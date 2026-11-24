'use strict';
/*
 * Conector mínimo para o PostgreSQL, sem dependências (só módulos do Node).
 * Fala o protocolo do PostgreSQL 3.0: login com SCRAM-SHA-256, MD5 ou senha simples,
 * consultas com parâmetros ($1, $2...) pelo protocolo estendido, e um pool pequeno de conexões.
 * Lê a senha de PGPASSWORD ou do arquivo pgpass (%APPDATA%\postgresql\pgpass.conf no Windows).
 */
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

// ---------------------------------------------------------------- pgpass
function lerPgpass(host, port, database, user) {
  const arquivo = process.env.PGPASSFILE || (process.platform === 'win32'
    ? path.join(process.env.APPDATA || '', 'postgresql', 'pgpass.conf')
    : path.join(os.homedir(), '.pgpass'));
  let texto;
  try { texto = fs.readFileSync(arquivo, 'utf8'); } catch (_) { return undefined; }
  for (const linha of texto.split(/\r?\n/)) {
    if (!linha || linha.startsWith('#')) continue;
    const campos = [];
    let atual = '';
    for (let i = 0; i < linha.length; i++) {
      const c = linha[i];
      if (c === '\\' && i + 1 < linha.length) { atual += linha[++i]; continue; }
      if (c === ':' && campos.length < 4) { campos.push(atual); atual = ''; continue; }
      atual += c;
    }
    campos.push(atual);
    if (campos.length !== 5) continue;
    const [h, p, d, u, senha] = campos;
    const bate = (padrao, valor) => padrao === '*' || padrao === String(valor);
    const hostOk = bate(h, host) || (h === 'localhost' && (host === '127.0.0.1' || host === '::1'));
    if (hostOk && bate(p, port) && bate(d, database) && bate(u, user)) return senha;
  }
  return undefined;
}

// ---------------------------------------------------------------- tipos
const OID = { bool: 16, int8: 20, int2: 21, int4: 23, json: 114, float4: 700, float8: 701, numeric: 1700, jsonb: 3802 };
function converter(valor, tipo) {
  if (valor === null) return null;
  switch (tipo) {
    case OID.bool: return valor === 't';
    case OID.int2: case OID.int4: return parseInt(valor, 10);
    case OID.int8: { const n = Number(valor); return Number.isSafeInteger(n) ? n : valor; }
    case OID.float4: case OID.float8: case OID.numeric: return parseFloat(valor);
    case OID.json: case OID.jsonb: return JSON.parse(valor);
    default: return valor; // date, time, timestamp, text, enums: ficam como texto
  }
}
function paramTexto(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

class ErroPg extends Error {
  constructor(campos) {
    super(campos.M || 'Erro no PostgreSQL');
    this.code = campos.C;
    this.severity = campos.S;
    this.detail = campos.D;
    this.hint = campos.H;
    this.constraint = campos.n;
    this.table = campos.t;
    this.column = campos.c;
  }
}

// ---------------------------------------------------------------- mensagens
function msg(tipo, corpo) {
  const cab = Buffer.alloc(tipo ? 5 : 4);
  let o = 0;
  if (tipo) { cab.write(tipo, 0, 'ascii'); o = 1; }
  cab.writeInt32BE(corpo.length + 4, o);
  return Buffer.concat([cab, corpo]);
}
const cstr = s => Buffer.from(String(s) + '\0', 'utf8');
function int16(n) { const b = Buffer.alloc(2); b.writeInt16BE(n); return b; }
function int32(n) { const b = Buffer.alloc(4); b.writeInt32BE(n); return b; }

class Leitor {
  constructor(buf) { this.buf = buf; this.o = 0; }
  int16() { const v = this.buf.readInt16BE(this.o); this.o += 2; return v; }
  int32() { const v = this.buf.readInt32BE(this.o); this.o += 4; return v; }
  byte() { return this.buf[this.o++]; }
  cstr() { const fim = this.buf.indexOf(0, this.o); const s = this.buf.toString('utf8', this.o, fim); this.o = fim + 1; return s; }
  bytes(n) { const b = this.buf.subarray(this.o, this.o + n); this.o += n; return b; }
  resto() { return this.buf.subarray(this.o); }
}

// ---------------------------------------------------------------- conexão
class Conexao {
  constructor(cfg) {
    this.cfg = cfg;
    this.socket = null;
    this.buffer = Buffer.alloc(0);
    this.pendente = null;
    this.morta = false;
  }

  conectar() {
    return new Promise((resolve, reject) => {
      const { host, port, user, database, options } = this.cfg;
      const sock = net.createConnection({ host, port });
      this.socket = sock;
      let pronto = false;
      const falhar = e => {
        this.morta = true;
        if (!pronto) reject(e);
        else if (this.pendente) { const p = this.pendente; this.pendente = null; p.reject(e); }
      };
      sock.on('error', falhar);
      sock.on('close', () => { this.morta = true; if (this.pendente) falhar(new Error('A conexão com o PostgreSQL foi fechada.')); });
      sock.on('data', dados => {
        this.buffer = this.buffer.length ? Buffer.concat([this.buffer, dados]) : dados;
        while (this.buffer.length >= 5) {
          const tamanho = this.buffer.readInt32BE(1);
          if (this.buffer.length < tamanho + 1) break;
          const tipo = String.fromCharCode(this.buffer[0]);
          const corpo = this.buffer.subarray(5, tamanho + 1);
          this.buffer = this.buffer.subarray(tamanho + 1);
          try { this.receber(tipo, corpo); } catch (e) { falhar(e); sock.destroy(); return; }
        }
      });
      sock.on('connect', () => {
        const params = ['user', user, 'database', database, 'client_encoding', 'UTF8', 'application_name', 'iafit-app'];
        if (options) params.push('options', options);
        const corpo = Buffer.concat([int32(196608), ...params.map(cstr), Buffer.from([0])]);
        sock.write(msg(null, corpo));
      });
      this.pendente = {
        login: true,
        resolve: () => { pronto = true; resolve(this); },
        reject: e => { this.morta = true; sock.destroy(); reject(e); }
      };
    });
  }

  senha() {
    const { password, host, port, database, user } = this.cfg;
    const s = password !== undefined ? password : lerPgpass(host, port, database, user);
    if (s === undefined) throw new Error('O PostgreSQL pediu senha e ela não foi encontrada (rode o INSTALAR.bat para salvá-la).');
    return s;
  }

  receber(tipo, corpo) {
    const p = this.pendente;
    const r = new Leitor(corpo);
    switch (tipo) {
      case 'R': return this.autenticar(r);
      case 'S': case 'K': case 'N': case 'A': return; // parâmetros, chave, avisos, notificações
      case 'E': {
        const campos = {};
        for (let t = r.byte(); t; t = r.byte()) campos[String.fromCharCode(t)] = r.cstr();
        const erro = new ErroPg(campos);
        if (p && p.login) { this.pendente = null; return p.reject(erro); }
        if (p) p.erro = erro;
        return;
      }
      case '1': case '2': case 'n': case 's': case 'I': return;
      case 'T': {
        const n = r.int16(), campos = [];
        for (let i = 0; i < n; i++) {
          const nome = r.cstr(); r.int32(); r.int16();
          const tipoOid = r.int32(); r.int16(); r.int32(); r.int16();
          campos.push({ nome, tipo: tipoOid });
        }
        if (p) p.campos = campos;
        return;
      }
      case 'D': {
        const n = r.int16(), linha = {};
        for (let i = 0; i < n; i++) {
          const len = r.int32();
          const bruto = len === -1 ? null : r.bytes(len).toString('utf8');
          const c = p.campos[i];
          linha[c.nome] = converter(bruto, c.tipo);
        }
        p.linhas.push(linha);
        return;
      }
      case 'C': {
        const tag = r.cstr();
        const m = tag.match(/(\d+)$/);
        if (p) p.rowCount = m ? parseInt(m[1], 10) : null;
        return;
      }
      case 'Z': {
        if (!p) return;
        this.pendente = null;
        if (p.login) return p.resolve();
        return p.erro ? p.reject(p.erro) : p.resolve({ rows: p.linhas, rowCount: p.rowCount, fields: p.campos });
      }
      default: return;
    }
  }

  autenticar(r) {
    const codigo = r.int32();
    const { user } = this.cfg;
    if (codigo === 0) return; // AuthenticationOk
    if (codigo === 3) return this.socket.write(msg('p', cstr(this.senha())));
    if (codigo === 5) {
      const sal = r.bytes(4);
      const interno = crypto.createHash('md5').update(this.senha() + user).digest('hex');
      const externo = crypto.createHash('md5').update(Buffer.concat([Buffer.from(interno), sal])).digest('hex');
      return this.socket.write(msg('p', cstr('md5' + externo)));
    }
    if (codigo === 10) {
      const mecanismos = [];
      for (let m = r.cstr(); m; m = r.cstr()) mecanismos.push(m);
      if (!mecanismos.includes('SCRAM-SHA-256')) throw new Error('Método de login não suportado: ' + mecanismos.join(', '));
      this.scram = { nonce: crypto.randomBytes(18).toString('base64') };
      this.scram.primeiraNua = 'n=,r=' + this.scram.nonce;
      const primeira = Buffer.from('n,,' + this.scram.primeiraNua, 'utf8');
      return this.socket.write(msg('p', Buffer.concat([cstr('SCRAM-SHA-256'), int32(primeira.length), primeira])));
    }
    if (codigo === 11) {
      const servidorPrimeira = r.resto().toString('utf8');
      const attr = Object.fromEntries(servidorPrimeira.split(',').map(x => [x[0], x.slice(2)]));
      if (!attr.r || !attr.r.startsWith(this.scram.nonce)) throw new Error('Resposta SCRAM inválida do servidor.');
      const salgada = crypto.pbkdf2Sync(this.senha().normalize('NFKC'), Buffer.from(attr.s, 'base64'), parseInt(attr.i, 10), 32, 'sha256');
      const hmac = (k, d) => crypto.createHmac('sha256', k).update(d).digest();
      const chaveCliente = hmac(salgada, 'Client Key');
      const chaveGuardada = crypto.createHash('sha256').update(chaveCliente).digest();
      const semProva = 'c=biws,r=' + attr.r;
      const authMsg = this.scram.primeiraNua + ',' + servidorPrimeira + ',' + semProva;
      const assinatura = hmac(chaveGuardada, authMsg);
      const prova = Buffer.from(chaveCliente.map((b, i) => b ^ assinatura[i]));
      this.scram.assinaturaServidor = hmac(hmac(salgada, 'Server Key'), authMsg).toString('base64');
      return this.socket.write(msg('p', Buffer.from(semProva + ',p=' + prova.toString('base64'), 'utf8')));
    }
    if (codigo === 12) {
      const final = r.resto().toString('utf8');
      if (final !== 'v=' + this.scram.assinaturaServidor) throw new Error('O servidor não confirmou a assinatura SCRAM.');
      return;
    }
    throw new Error('Método de login do PostgreSQL não suportado (código ' + codigo + ').');
  }

  query(sql, params = []) {
    if (this.morta) return Promise.reject(new Error('Conexão encerrada.'));
    return new Promise((resolve, reject) => {
      this.pendente = { resolve, reject, linhas: [], campos: [], rowCount: null };
      const vals = params.map(paramTexto);
      const bind = [cstr(''), cstr(''), int16(0), int16(vals.length)];
      for (const v of vals) {
        if (v === null) bind.push(int32(-1));
        else { const b = Buffer.from(v, 'utf8'); bind.push(int32(b.length), b); }
      }
      bind.push(int16(0));
      this.socket.write(Buffer.concat([
        msg('P', Buffer.concat([cstr(''), cstr(sql), int16(0)])),
        msg('B', Buffer.concat(bind)),
        msg('D', Buffer.concat([Buffer.from('P'), cstr('')])),
        msg('E', Buffer.concat([cstr(''), int32(0)])),
        msg('S', Buffer.alloc(0))
      ]));
    });
  }

  fechar() {
    if (this.socket && !this.morta) {
      try { this.socket.end(msg('X', Buffer.alloc(0))); } catch (_) { }
    }
    this.morta = true;
  }
}

// ---------------------------------------------------------------- pool
class Pool {
  constructor(cfg = {}) {
    this.cfg = {
      host: cfg.host || process.env.PGHOST || 'localhost',
      port: Number(cfg.port || process.env.PGPORT || 5432),
      user: cfg.user || process.env.PGUSER || 'postgres',
      database: cfg.database || process.env.PGDATABASE || 'postgres',
      password: cfg.password !== undefined ? cfg.password : process.env.PGPASSWORD,
      options: cfg.options
    };
    this.max = cfg.max || 5;
    this.livres = [];
    this.total = 0;
    this.fila = [];
  }

  async connect() {
    while (this.livres.length) {
      const c = this.livres.pop();
      if (!c.morta) return this.embrulhar(c);
      this.total--;
    }
    if (this.total < this.max) {
      this.total++;
      try { return this.embrulhar(await new Conexao(this.cfg).conectar()); }
      catch (e) { this.total--; throw e; }
    }
    return new Promise((resolve, reject) => this.fila.push({ resolve, reject }));
  }

  embrulhar(c) {
    let solto = false;
    return {
      query: (sql, params) => c.query(sql, params),
      release: () => {
        if (solto) return;
        solto = true;
        if (c.morta) { this.total--; return; }
        const prox = this.fila.shift();
        if (prox) prox.resolve(this.embrulhar(c));
        else this.livres.push(c);
      }
    };
  }

  async query(sql, params) {
    const c = await this.connect();
    try { return await c.query(sql, params); } finally { c.release(); }
  }

  end() { this.livres.forEach(c => c.fechar()); this.livres = []; }
}

module.exports = { Pool, ErroPg, lerPgpass };
