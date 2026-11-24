'use strict';
/*
 * iaFit: servidor do app. Serve as telas (public/index.html) e a API que lê e grava no PostgreSQL.
 * Rodar: node server.js   (o ABRIR_APP.bat faz isso e abre o navegador)
 * Conexão: localhost:5432, banco iafit, usuário postgres; senha de PGPASSWORD ou do pgpass.conf.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { exec } = require('child_process');
const { Pool } = require('./pg-mini');

const PORTA_INICIAL = Number(process.env.PORTA) || 3000;
const MODELO = 'iafit-regras-v1';

const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: Number(process.env.PGPORT) || 5432,
  user: process.env.PGUSER || 'postgres',
  database: process.env.PGDATABASE || 'iafit',
  options: '-c search_path=iafit,public,extensions',
  max: 6
});

const sessoes = new Map(); // token -> usuario_id

// =====================================================================
// Banco com rastreio: toda consulta fica registrada para o painel "Banco ao vivo"
// =====================================================================
class HttpErro extends Error {
  constructor(status, mensagem) { super(mensagem); this.status = status; }
}

function resumirSql(sql, params, mascarar) {
  let s = sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').trim();
  s = s.replace(/\$(\d+)/g, (m, n) => {
    const i = Number(n) - 1;
    if (mascarar && mascarar.includes(i)) return "'••••••'";
    const v = params[i];
    if (v === null || v === undefined) return 'NULL';
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    const t = String(v);
    return "'" + (t.length > 48 ? t.slice(0, 45) + '...' : t).replace(/'/g, "''") + "'";
  });
  return s.length > 600 ? s.slice(0, 597) + '...' : s;
}

async function comBanco(fn) {
  const trace = [];
  let cliente;
  try {
    cliente = await pool.connect();
  } catch (e) {
    e.trace = trace;
    throw e;
  }
  const q = async (sql, params = [], opt = {}) => {
    const t0 = process.hrtime.bigint();
    const reg = { sql: resumirSql(sql, params, opt.mascarar) };
    trace.push(reg);
    try {
      const r = await cliente.query(sql, params);
      reg.linhas = r.rowCount;
      return r;
    } catch (e) {
      reg.erro = e.message;
      throw e;
    } finally {
      reg.ms = Math.round(Number(process.hrtime.bigint() - t0) / 1e5) / 10;
    }
  };
  try {
    return { dados: await fn(q), trace };
  } catch (e) {
    e.trace = trace;
    throw e;
  } finally {
    cliente.release();
  }
}

async function transacao(q, fn) {
  await q('BEGIN');
  try {
    const r = await fn();
    await q('COMMIT');
    return r;
  } catch (e) {
    try { await q('ROLLBACK'); } catch (_) { }
    throw e;
  }
}

function traduzirErro(e) {
  if (e instanceof HttpErro) return [e.status, e.message];
  if (e.code === '23505') return [409, 'Já existe uma conta com esse e-mail.'];
  if (e.code === '23514') {
    if (!e.constraint) return [400, e.message]; // mensagem dos triggers do banco
    return [400, `O banco recusou o valor: fora da faixa permitida (${e.constraint}).`];
  }
  if (e.code === '23502') return [400, `Campo obrigatório vazio (${e.column || 'desconhecido'}).`];
  if (e.code === '22P02' || e.code === '22003' || e.code === '22007') return [400, 'Valor em formato inválido: ' + e.message];
  if (e.code === 'ECONNREFUSED') return [503, 'O PostgreSQL não está respondendo em localhost:5432. Ligue o serviço do PostgreSQL e tente de novo.'];
  if (e.code === '28P01') return [503, 'A senha do PostgreSQL não confere. Rode o INSTALAR.bat de novo para salvar a senha.'];
  if (e.code === '3D000') return [503, 'O banco iafit não existe. Rode o INSTALAR.bat.'];
  if (e.code === '42P01' || e.code === '42883') return [503, 'O banco está desatualizado. Rode o INSTALAR.bat para recriá-lo.'];
  return [500, e.message];
}

// =====================================================================
// Estado completo do usuário: tudo que as telas mostram
// =====================================================================
async function estado(q, uid) {
  const u = (await q(
    `SELECT u.id, u.nome, u.email, u.sexo, fn_idade(u.data_nascimento) AS idade,
            p.altura_cm, p.peso_meta_kg, p.objetivo, p.nivel_atividade, p.experiencia,
            p.dias_treino_semana, p.local_treino, p.refeicoes_por_dia
       FROM usuario u JOIN perfil p ON p.usuario_id = u.id
      WHERE u.id = $1`, [uid])).rows[0];
  if (!u) throw new HttpErro(401, 'Sua sessão terminou. Entre de novo.');

  const restricoes = (await q(
    `SELECT ra.nome FROM usuario_restricao ur
       JOIN restricao_alimentar ra ON ra.id = ur.restricao_id
      WHERE ur.usuario_id = $1 ORDER BY ra.nome`, [uid])).rows.map(r => r.nome);

  const dashboard = (await q(
    `SELECT d.*, current_date::text AS hoje, EXTRACT(DOW FROM current_date)::int AS dow,
            to_char(now(), 'HH24:MI') AS hora
       FROM vw_dashboard d WHERE d.usuario_id = $1`, [uid])).rows[0];

  const plano = (await q(
    `SELECT id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g,
            inicio::text, modelo_ia
       FROM plano_alimentar WHERE usuario_id = $1 AND status = 'ativo'`, [uid])).rows[0] || null;

  let refeicoes = [];
  if (plano) {
    refeicoes = (await q(
      `SELECT m.refeicao_id AS id, m.ordem, to_char(m.horario, 'HH24:MI') AS horario, m.nome,
              m.kcal, m.proteina_g, m.carboidrato_g, m.gordura_g,
              EXISTS (SELECT 1 FROM refeicao_consumida rc
                       WHERE rc.refeicao_id = m.refeicao_id AND rc.data = current_date) AS feita
         FROM vw_macros_refeicao m WHERE m.plano_id = $1 ORDER BY m.ordem`, [plano.id])).rows;
    const itens = (await q(
      `SELECT i.refeicao_id, a.nome, i.quantidade_g, i.medida_caseira
         FROM refeicao_item i
         JOIN refeicao r ON r.id = i.refeicao_id
         JOIN alimento a ON a.id = i.alimento_id
        WHERE r.plano_id = $1 ORDER BY r.ordem, i.id`, [plano.id])).rows;
    for (const r of refeicoes) r.itens = itens.filter(i => i.refeicao_id === r.id);
  }

  const linhasTreino = (await q(
    `SELECT pt.id AS plano_id, pt.titulo, pt.divisao, td.id AS dia_id, td.dia_semana, td.nome AS dia_nome,
            td.descanso, te.id AS te_id, te.ordem, e.nome AS exercicio, e.grupo, e.equipamento,
            te.series, te.repeticoes_min, te.repeticoes_max, te.duracao_seg, te.carga_sugerida_kg,
            te.descanso_seg,
            EXISTS (SELECT 1 FROM sessao_treino s
                      JOIN serie_executada se ON se.sessao_id = s.id
                     WHERE s.usuario_id = pt.usuario_id AND s.data = current_date
                       AND s.treino_dia_id = td.id AND se.exercicio_id = te.exercicio_id) AS feito
       FROM plano_treino pt
       JOIN treino_dia td ON td.plano_treino_id = pt.id
       LEFT JOIN treino_exercicio te ON te.treino_dia_id = td.id
       LEFT JOIN exercicio e ON e.id = te.exercicio_id
      WHERE pt.usuario_id = $1 AND pt.status = 'ativo'
      ORDER BY td.dia_semana, te.ordem`, [uid])).rows;
  let treino = null;
  if (linhasTreino.length) {
    treino = { id: linhasTreino[0].plano_id, titulo: linhasTreino[0].titulo, divisao: linhasTreino[0].divisao, dias: {} };
    for (const l of linhasTreino) {
      const d = treino.dias[l.dia_semana] || (treino.dias[l.dia_semana] = { id: l.dia_id, nome: l.dia_nome, descanso: l.descanso, exs: [] });
      if (l.te_id) d.exs.push({
        id: l.te_id, nome: l.exercicio, grupo: l.grupo, equipamento: l.equipamento, series: l.series,
        rmin: l.repeticoes_min, rmax: l.repeticoes_max, seg: l.duracao_seg, carga: l.carga_sugerida_kg,
        descanso: l.descanso_seg, feito: l.feito
      });
    }
  }

  const registros = (await q(
    `SELECT data::text, peso_kg, cintura_cm, braco_cm, treinou, seguiu_dieta
       FROM registro_progresso
      WHERE usuario_id = $1 AND data >= current_date - 120
      ORDER BY data`, [uid])).rows;

  const chat = (await q(
    `SELECT m.id, m.papel, m.conteudo
       FROM mensagem m JOIN conversa c ON c.id = m.conversa_id
      WHERE c.usuario_id = $1 AND m.papel <> 'sistema'
      ORDER BY m.criada_em, m.id`, [uid])).rows.map(m => ({ ...m, acao: m.papel === 'assistente' ? acaoDaResposta(m.conteudo) : null }));

  const notif = (await q(
    `SELECT lembrete_refeicao, lembrete_treino, lembrete_progresso, dicas_ia, minutos_antes_refeicao,
            to_char(horario_treino, 'HH24:MI') AS horario_treino,
            to_char(horario_progresso, 'HH24:MI') AS horario_progresso
       FROM preferencia_notificacao WHERE usuario_id = $1`, [uid])).rows[0] || null;

  const consent = (await q(
    `SELECT tipo, aceito FROM vw_consentimento_atual WHERE usuario_id = $1`, [uid])).rows;

  const historico = (await q(
    `SELECT * FROM (
       SELECT 'Plano alimentar' AS tipo, titulo, status, inicio::text AS inicio, fim::text AS fim,
              meta_kcal || ' kcal' AS detalhe, criado_em
         FROM plano_alimentar WHERE usuario_id = $1
       UNION ALL
       SELECT 'Plano de treino', titulo, status, inicio::text, fim::text, 'divisão ' || divisao, criado_em
         FROM plano_treino WHERE usuario_id = $1
     ) h
     ORDER BY (status = 'ativo') DESC, inicio DESC, criado_em DESC`, [uid])).rows;

  return {
    usuario: { ...u, restricoes },
    dashboard, plano, refeicoes, treino, registros, chat, notif,
    consentimentoIa: (consent.find(c => c.tipo === 'uso_anonimo_ia') || {}).aceito === true,
    historico
  };
}

// =====================================================================
// Geração dos planos (regras do MVP, no lugar do modelo de IA)
// =====================================================================
const CARDAPIOS = [
  [
    ['Café da manhã', '07:00', [['Pão integral', 50], ['Ovo de galinha cozido', 100], ['Banana prata', 100], ['Leite desnatado', 200]]],
    ['Almoço', '12:30', [['Arroz integral cozido', 150], ['Feijão carioca cozido', 100], ['Peito de frango grelhado', 150], ['Brócolis cozido', 100], ['Azeite de oliva', 10]]],
    ['Lanche da tarde', '16:00', [['Iogurte natural desnatado', 170], ['Aveia em flocos', 30], ['Maçã', 130]]],
    ['Jantar', '20:00', [['Batata-doce cozida', 150], ['Filé de tilápia grelhado', 150], ['Alface crespa', 50], ['Tomate', 80], ['Azeite de oliva', 10]]]
  ],
  [
    ['Café da manhã', '07:00', [['Cuscuz de milho cozido', 150], ['Ovo de galinha cozido', 100], ['Mamão papaia', 150], ['Queijo minas frescal', 30]]],
    ['Almoço', '12:30', [['Arroz branco cozido', 150], ['Feijão carioca cozido', 120], ['Patinho moído refogado', 120], ['Brócolis cozido', 80], ['Azeite de oliva', 10]]],
    ['Lanche da tarde', '16:00', [['Pão integral', 50], ['Pasta de amendoim', 15], ['Banana prata', 100], ['Whey protein concentrado', 30]]],
    ['Jantar', '20:00', [['Mandioca cozida', 150], ['Peito de frango grelhado', 130], ['Alface crespa', 50], ['Tomate', 80], ['Azeite de oliva', 10]]]
  ]
];
// substitutos em ordem de preferência: [alimento, fator de quantidade]; lista vazia = tira o item
const SUBSTITUTOS = {
  'Peito de frango grelhado': [['Filé de tilápia grelhado', 1], ['Grão-de-bico cozido', 1.4], ['Ovo de galinha cozido', 1]],
  'Patinho moído refogado': [['Peito de frango grelhado', 1], ['Ovo de galinha cozido', 1], ['Grão-de-bico cozido', 1.4]],
  'Filé de tilápia grelhado': [['Peito de frango grelhado', 1], ['Ovo de galinha cozido', 1], ['Grão-de-bico cozido', 1.4]],
  'Ovo de galinha cozido': [['Grão-de-bico cozido', 1]],
  'Leite desnatado': [],
  'Iogurte natural desnatado': [['Mamão papaia', 1]],
  'Queijo minas frescal': [['Castanha-do-pará', 0.5]],
  'Whey protein concentrado': [['Castanha-do-pará', 0.5], ['Pasta de amendoim', 0.7]],
  'Pão integral': [['Cuscuz de milho cozido', 2], ['Mandioca cozida', 2]],
  'Aveia em flocos': [['Banana prata', 2]],
  'Pasta de amendoim': [['Castanha-do-pará', 1]]
};

async function metaCalorica(q, uid) {
  const r = (await q(
    `SELECT GREATEST(1200, fn_meta_kcal_sugerida(
              round(fn_tmb(pa.peso_kg, p.altura_cm, fn_idade(u.data_nascimento), u.sexo)
                    * fn_fator_atividade(p.nivel_atividade))::int, p.objetivo)) AS meta
       FROM usuario u
       JOIN perfil p ON p.usuario_id = u.id
       JOIN vw_peso_atual pa ON pa.usuario_id = u.id
      WHERE u.id = $1`, [uid])).rows[0];
  if (!r) throw new HttpErro(400, 'Registre o peso antes de gerar o plano.');
  return r.meta;
}

async function gerarPlanoAlimentar(q, uid, variante) {
  const meta = await metaCalorica(q, uid);
  const alimentos = (await q(
    `SELECT a.id, a.nome, a.kcal_100g, a.proteina_100g, a.carboidrato_100g, a.gordura_100g,
            EXISTS (SELECT 1 FROM alimento_conflito ac
                      JOIN usuario_restricao ur ON ur.restricao_id = ac.restricao_id
                     WHERE ac.alimento_id = a.id AND ur.usuario_id = $1) AS proibido
       FROM alimento a`, [uid])).rows;
  const porNome = Object.fromEntries(alimentos.map(a => [a.nome, a]));
  const permitido = n => porNome[n] && !porNome[n].proibido;

  // 1. troca o que a pessoa não pode comer
  const cardapio = CARDAPIOS[variante % CARDAPIOS.length].map(([nome, horario, itens]) => {
    const lista = [];
    for (const [alimento, g] of itens) {
      let escolhido = permitido(alimento) ? [alimento, g] : null;
      if (!escolhido) for (const [sub, f] of (SUBSTITUTOS[alimento] || [])) if (permitido(sub)) { escolhido = [sub, g * f]; break; }
      if (!escolhido) continue;
      const ja = lista.find(x => x[0] === escolhido[0]);
      if (ja) ja[1] += escolhido[1]; else lista.push(escolhido);
    }
    return [nome, horario, lista];
  });

  // 2. ajusta as quantidades para bater a meta de calorias
  const kcal = c => c.reduce((t, [, , l]) => t + l.reduce((s, [n, g]) => s + g * porNome[n].kcal_100g / 100, 0), 0);
  const fator = Math.min(2.2, Math.max(0.5, meta / kcal(cardapio)));
  for (const [, , lista] of cardapio) for (const item of lista) item[1] = Math.max(5, Math.round(item[1] * fator / 5) * 5);
  const soma = campo => Math.round(cardapio.reduce((t, [, , l]) => t + l.reduce((s, [n, g]) => s + g * porNome[n][campo] / 100, 0), 0));

  // 3. grava: o trigger do banco encerra o plano anterior sozinho
  const titulo = ['Cardápio A', 'Cardápio B'][variante % 2];
  const plano = (await q(
    `INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g, modelo_ia)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
    [uid, titulo, meta, soma('proteina_100g'), soma('carboidrato_100g'), soma('gordura_100g'), MODELO])).rows[0];

  for (let i = 0; i < cardapio.length; i++) {
    const [nome, horario, lista] = cardapio[i];
    const ref = (await q(
      `INSERT INTO refeicao (plano_id, nome, horario, ordem) VALUES ($1, $2, $3, $4) RETURNING id`,
      [plano.id, nome, horario, i + 1])).rows[0];
    const valores = [], params = [ref.id];
    lista.forEach(([n, g]) => { params.push(porNome[n].id, g); valores.push(`($1, $${params.length - 1}, $${params.length})`); });
    await q(`INSERT INTO refeicao_item (refeicao_id, alimento_id, quantidade_g) VALUES ${valores.join(', ')}`, params);
  }
  return plano.id;
}

const DIVISOES = {
  academia: [
    ['Treino A: peito e tríceps', ['Supino reto com barra', 'Supino inclinado com halteres', 'Crucifixo com halteres', 'Tríceps na polia', 'Tríceps francês']],
    ['Treino B: costas e bíceps', ['Puxada frontal', 'Remada curvada com barra', 'Remada unilateral com halter', 'Rosca direta com barra', 'Rosca martelo']],
    ['Treino C: pernas', ['Agachamento livre', 'Leg press 45', 'Cadeira extensora', 'Mesa flexora', 'Elevação pélvica']],
    ['Treino D: ombros e abdômen', ['Desenvolvimento com halteres', 'Elevação lateral', 'Abdominal crunch', 'Prancha', 'Esteira caminhada inclinada']]
  ],
  casa: [
    ['Circuito 1: corpo todo', ['Agachamento com peso corporal', 'Flexão de braço', 'Elevação pélvica', 'Prancha', 'Polichinelo']],
    ['Circuito 2: corpo todo', ['Agachamento com peso corporal', 'Flexão de braço', 'Burpee', 'Abdominal crunch', 'Prancha']]
  ]
};
const DIAS_DE_TREINO = { 1: [3], 2: [2, 4], 3: [1, 3, 5], 4: [1, 2, 4, 5], 5: [1, 2, 3, 4, 5], 6: [1, 2, 3, 4, 5, 6], 7: [1, 2, 3, 4, 5, 6] };
const DOSE = {
  perder_gordura: { series: 3, rmin: 12, rmax: 15, descanso: 45, seg: 45 },
  ganhar_massa: { series: 4, rmin: 8, rmax: 10, descanso: 90, seg: 40 },
  manter_peso: { series: 3, rmin: 10, rmax: 12, descanso: 60, seg: 40 },
  condicionamento: { series: 3, rmin: 12, rmax: 15, descanso: 45, seg: 45 }
};

async function gerarPlanoTreino(q, uid) {
  const p = (await q(`SELECT objetivo, dias_treino_semana, local_treino FROM perfil WHERE usuario_id = $1`, [uid])).rows[0];
  const local = p.local_treino === 'academia' ? 'academia' : 'casa';
  const divisao = DIVISOES[local];
  const dias = DIAS_DE_TREINO[p.dias_treino_semana] || [1, 3, 5];
  const dose = DOSE[p.objetivo];
  // academia com 3 dias: A, B e C; com 4 ou mais: A, B, C e D em sequência
  const usados = local === 'academia' && dias.length === 3 ? divisao.slice(0, 3) : divisao;
  const letras = local === 'academia' ? ['A', 'B', 'C', 'D'].slice(0, Math.min(usados.length, dias.length)).join('') : 'Circuito';
  const titulo = local === 'academia' ? `Academia ${dias.length}x por semana` : `Em casa ${dias.length}x por semana`;

  const plano = (await q(
    `INSERT INTO plano_treino (usuario_id, titulo, divisao, modelo_ia) VALUES ($1, $2, $3, $4) RETURNING id`,
    [uid, titulo, letras, MODELO])).rows[0];

  const ex = Object.fromEntries((await q(`SELECT id, nome FROM exercicio`)).rows.map(e => [e.nome, e.id]));
  let k = 0;
  for (let dia = 0; dia < 7; dia++) {
    const treina = dias.includes(dia);
    const [nome, lista] = treina ? usados[k++ % usados.length] : ['Descanso', []];
    const td = (await q(
      `INSERT INTO treino_dia (plano_treino_id, dia_semana, nome, descanso) VALUES ($1, $2, $3, $4) RETURNING id`,
      [plano.id, dia, nome, !treina])).rows[0];
    if (!treina) continue;
    const valores = [], params = [td.id];
    lista.forEach((nomeEx, i) => {
      const porTempo = nomeEx === 'Prancha' || nomeEx === 'Polichinelo' || nomeEx.startsWith('Esteira');
      const esteira = nomeEx.startsWith('Esteira');
      params.push(ex[nomeEx], i + 1, esteira ? 1 : dose.series,
        porTempo ? null : dose.rmin, porTempo ? null : dose.rmax,
        porTempo ? (esteira ? 1200 : dose.seg) : null, esteira ? 0 : dose.descanso);
      const n = params.length;
      valores.push(`($1, $${n - 6}, $${n - 5}, $${n - 4}, $${n - 3}, $${n - 2}, $${n - 1}, $${n})`);
    });
    await q(`INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max, duracao_seg, descanso_seg)
             VALUES ${valores.join(', ')}`, params);
  }
  return plano.id;
}

// =====================================================================
// Chatbot (respostas por regras com os dados do banco; um modelo de IA entra aqui depois)
// =====================================================================
const norm = s => String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const num = (n, d = 1) => Number(n).toFixed(d).replace('.', ',');
const OBJETIVO_TXT = { perder_gordura: 'perder gordura', ganhar_massa: 'ganhar massa', manter_peso: 'manter o peso', condicionamento: 'melhorar o condicionamento' };
const DIA_TXT = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

function acaoDaResposta(texto) {
  if (/kcal por dia/.test(texto)) return { label: 'Abrir plano alimentar', go: 'dieta' };
  if (/dia de descanso|exercícios, começando/.test(texto)) return { label: 'Abrir plano de treino', go: 'treino' };
  if (/Nos últimos \d+ dias você/.test(texto)) return { label: 'Ver minha evolução', go: 'evolucao' };
  return null;
}

function responder(pergunta, e) {
  const t = norm(pergunta);
  const u = e.usuario, d = e.dashboard || {};
  const peso = d.peso_atual_kg;
  const obj = OBJETIVO_TXT[u.objetivo];
  const tot = e.refeicoes.reduce((a, r) => ({ kcal: a.kcal + r.kcal, p: a.p + r.proteina_g, c: a.c + r.carboidrato_g, g: a.g + r.gordura_g }), { kcal: 0, p: 0, c: 0, g: 0 });
  const hojeTreino = e.treino && e.treino.dias[d.dow];
  const restr = u.restricoes.length ? ` Levei em conta: ${u.restricoes.join(', ').toLowerCase()}.` : '';

  if (/protein/.test(t)) {
    const alvo = Math.round(peso * (u.objetivo === 'ganhar_massa' ? 1.8 : u.objetivo === 'perder_gordura' ? 1.6 : 1.4));
    return `Para o seu objetivo de ${obj} e ${num(peso)} kg, a referência é cerca de ${alvo} g de proteína por dia.` +
      (e.plano ? ` Seu plano atual tem ${Math.round(tot.p)} g.` : '') + restr;
  }
  if (/creatin/.test(t)) return `A creatina monohidratada é um dos suplementos mais estudados. A dose comum é de 3 a 5 g por dia, em qualquer horário. Converse com seu médico ou nutricionista antes de começar.`;
  if (/agua|hidrat|beber/.test(t)) return `Uma boa referência é 35 ml por kg de peso. Para você, cerca de ${num(peso * 0.035)} litros por dia, um pouco mais nos dias de treino.`;
  if (/troc|substitu/.test(t)) return `Pode trocar mantendo as calorias: 150 g de arroz equivalem a cerca de 200 g de batata-doce ou 170 g de cuscuz de milho. A proteína da refeição continua a mesma.` + restr;
  if (/diet|calori|kcal|refei|comer|almoc|jant|cafe|cardapio/.test(t)) {
    if (!e.plano) return 'Você ainda não tem plano alimentar. Abra a tela Dieta e toque em Gerar plano.';
    const prox = e.refeicoes.find(r => r.horario > d.hora && !r.feita);
    return `Seu plano tem ${Math.round(tot.kcal)} kcal por dia: ${Math.round(tot.p)} g de proteína, ${Math.round(tot.c)} g de carboidratos e ${Math.round(tot.g)} g de gordura, em ${e.refeicoes.length} refeições. ` +
      `Hoje você já consumiu ${d.kcal_hoje} kcal. ` + (prox ? `A próxima é ${prox.nome.toLowerCase()}, às ${prox.horario}.` : 'As refeições de hoje já passaram.');
  }
  if (/trein|exercic|academia|hoje/.test(t)) {
    if (!hojeTreino) return 'Você ainda não tem plano de treino. Abra a tela Treino e toque em Gerar plano.';
    if (hojeTreino.descanso || !hojeTreino.exs.length) return `Hoje (${DIA_TXT[d.dow]}) é dia de descanso. Uma caminhada leve de 20 a 30 minutos e alongamento ajudam na recuperação.`;
    const x = hojeTreino.exs[0];
    const dose = x.seg ? `${x.series}×${x.seg}s` : `${x.series}×${x.rmin}-${x.rmax}`;
    return `Hoje (${DIA_TXT[d.dow]}) é ${hojeTreino.nome}: ${hojeTreino.exs.length} exercícios, começando por ${x.nome.toLowerCase()} (${dose}).`;
  }
  if (/peso|evolu|progress|resultad/.test(t)) {
    const regs = e.registros;
    if (regs.length < 2) return 'Ainda há poucos registros para mostrar evolução. Registre o peso por alguns dias e pergunte de novo.';
    const ult = regs[regs.length - 1];
    const ref = [...regs].reverse().find(r => Date.parse(r.data) <= Date.parse(ult.data) - 6 * 864e5) || regs[0];
    const dias = Math.round((Date.parse(ult.data) - Date.parse(ref.data)) / 864e5);
    const dif = ult.peso_kg - ref.peso_kg;
    const bom = u.objetivo === 'ganhar_massa' ? dif >= 0 : u.objetivo === 'perder_gordura' ? dif <= 0 : Math.abs(dif) < 1;
    return `Nos últimos ${dias} dias você foi de ${num(ref.peso_kg)} kg para ${num(ult.peso_kg)} kg (${dif > 0 ? '+' : ''}${num(dif)} kg). ` +
      (bom ? `Está no ritmo para ${obj}.` : 'Vale revisar a dieta desta semana; posso te ajudar com isso.');
  }
  if (/sono|dormi/.test(t)) return 'Tente dormir de 7 a 9 horas por noite. Boa parte da recuperação muscular acontece no sono, e noites curtas aumentam a fome no dia seguinte.';
  if (/whey|suplement/.test(t)) return 'O whey ajuda a bater a meta de proteína, mas não é obrigatório. Se preferir comida, 100 g de frango grelhado têm cerca de 32 g de proteína.';
  if (/obrigad|valeu/.test(t)) return 'Por nada! Estou por aqui sempre que precisar.';
  if (/^(oi|ola|opa|bom dia|boa tarde|boa noite|e ai)\b/.test(t)) return `Olá, ${u.nome.split(' ')[0]}! Em que posso ajudar hoje?`;
  return 'Ainda não sei responder isso. Posso ajudar com dieta, treino, proteína, hidratação, sono e evolução. Tente, por exemplo: "qual meu treino de hoje?"';
}

// =====================================================================
// Rotas
// =====================================================================
const OBJETIVOS = ['perder_gordura', 'ganhar_massa', 'manter_peso', 'condicionamento'];
const ATIVIDADES = ['sedentario', 'leve', 'moderado', 'intenso', 'muito_intenso'];
const LOCAIS = ['academia', 'casa', 'ar_livre'];
const RESTRICOES_APP = ['Vegetariano', 'Vegano', 'Sem lactose', 'Sem glúten', 'Alergia a amendoim'];

function numero(v, nome, min, max, opcional = false) {
  if ((v === '' || v === null || v === undefined) && opcional) return null;
  const n = typeof v === 'number' ? v : parseFloat(String(v).replace(',', '.'));
  if (!Number.isFinite(n) || n < min || n > max) throw new HttpErro(400, `Informe ${nome} entre ${min} e ${max}.`);
  return n;
}
const texto = (v, nome, min = 1, max = 200) => {
  const s = String(v || '').trim();
  if (s.length < min || s.length > max) throw new HttpErro(400, `Informe ${nome}.`);
  return s;
};

const rotas = [];
const rota = (metodo, padrao, publica, fn) => rotas.push({ metodo, padrao, publica, fn });

rota('GET', /^\/api\/status$/, true, async (q) => {
  const r = (await q(`SELECT current_database() AS banco, split_part(version(), ' ', 2) AS versao,
                             (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'iafit' AND table_type = 'BASE TABLE')::int AS tabelas`)).rows[0];
  return { ok: true, ...r };
});

rota('POST', /^\/api\/login$/, true, async (q, { corpo }) => {
  const email = texto(corpo.email, 'o e-mail');
  const uid = (await q(`SELECT fn_autenticar($1, $2) AS id`, [email, String(corpo.senha || '')], { mascarar: [1] })).rows[0].id;
  if (!uid) throw new HttpErro(401, 'E-mail ou senha incorretos.');
  const token = crypto.randomBytes(24).toString('hex');
  sessoes.set(token, uid);
  return { token, estado: await estado(q, uid) };
});

rota('POST', /^\/api\/cadastro$/, true, async (q, { corpo: c }) => {
  const nome = texto(c.nome, 'seu nome', 2, 120);
  const email = texto(c.email, 'um e-mail válido', 5, 254);
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new HttpErro(400, 'Digite um e-mail válido, por exemplo bento@email.com.');
  const senha = String(c.senha || '');
  if (senha.length < 8) throw new HttpErro(400, 'A senha precisa ter pelo menos 8 caracteres.');
  const idade = Math.round(numero(c.idade, 'a idade', 14, 100));
  const peso = numero(c.peso, 'o peso em kg', 30, 250);
  const altura = numero(c.altura, 'a altura em cm', 120, 230);
  const meta = numero(c.meta, 'o peso desejado em kg', 30, 250, true);
  const sexo = c.sexo === 'F' ? 'feminino' : 'masculino';
  if (!OBJETIVOS.includes(c.objetivo)) throw new HttpErro(400, 'Escolha um objetivo.');
  if (!ATIVIDADES.includes(c.atividade)) throw new HttpErro(400, 'Escolha o nível de atividade.');
  const local = LOCAIS.includes(c.local) ? c.local : 'academia';
  const dias = Math.round(numero(c.dias || 3, 'os dias de treino', 1, 7));
  const restricoes = (Array.isArray(c.restricoes) ? c.restricoes : []).filter(r => RESTRICOES_APP.includes(r));

  const uid = await transacao(q, async () => {
    const id = (await q(
      `INSERT INTO usuario (nome, email, senha_hash, data_nascimento, sexo)
       VALUES ($1, $2, crypt($3, gen_salt('bf', 8)), current_date - make_interval(years => $4), $5)
       RETURNING id`, [nome, email, senha, idade, sexo], { mascarar: [2] })).rows[0].id;
    await q(
      `INSERT INTO perfil (usuario_id, altura_cm, peso_meta_kg, objetivo, nivel_atividade, dias_treino_semana, local_treino)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`, [id, altura, meta, c.objetivo, c.atividade, dias, local]);
    if (restricoes.length) await q(
      `INSERT INTO usuario_restricao (usuario_id, restricao_id)
       SELECT $1, id FROM restricao_alimentar WHERE nome = ANY (string_to_array($2, '|'))`, [id, restricoes.join('|')]);
    await q(`INSERT INTO preferencia_notificacao (usuario_id) VALUES ($1)`, [id]);
    await q(
      `INSERT INTO consentimento (usuario_id, tipo, versao, aceito)
       VALUES ($1, 'termos_uso', '1.0', true), ($1, 'politica_privacidade', '1.0', true), ($1, 'uso_anonimo_ia', '1.0', $2)`,
      [id, c.usoAnonimo !== false]);
    await q(`INSERT INTO registro_progresso (usuario_id, data, peso_kg) VALUES ($1, current_date, $2)`, [id, peso]);
    await gerarPlanoAlimentar(q, id, 0);
    await gerarPlanoTreino(q, id);
    return id;
  });
  const token = crypto.randomBytes(24).toString('hex');
  sessoes.set(token, uid);
  return { token, estado: await estado(q, uid) };
});

rota('POST', /^\/api\/esqueci$/, true, async (q, { corpo }) => {
  await q(`SELECT EXISTS (SELECT 1 FROM usuario WHERE lower(email) = lower($1)) AS existe`, [String(corpo.email || '')]);
  return { mensagem: 'Se o e-mail estiver cadastrado, o link chega em instantes. (O envio de e-mail fica para a próxima fase do projeto.)' };
});

rota('POST', /^\/api\/logout$/, false, async (q, { token }) => { sessoes.delete(token); return { ok: true }; });

rota('GET', /^\/api\/estado$/, false, async (q, { uid }) => ({ estado: await estado(q, uid) }));

rota('POST', /^\/api\/refeicoes\/(\d+)\/feita$/, false, async (q, { uid, m }) => {
  const id = Number(m[1]);
  const dono = (await q(
    `SELECT 1 FROM refeicao r JOIN plano_alimentar p ON p.id = r.plano_id
      WHERE r.id = $1 AND p.usuario_id = $2 AND p.status = 'ativo'`, [id, uid])).rowCount;
  if (!dono) throw new HttpErro(404, 'Refeição não encontrada.');
  const apagou = (await q(`DELETE FROM refeicao_consumida WHERE refeicao_id = $1 AND data = current_date`, [id])).rowCount;
  if (!apagou) await q(`INSERT INTO refeicao_consumida (refeicao_id, data) VALUES ($1, current_date)`, [id]);
  return { feita: !apagou, estado: await estado(q, uid) };
});

rota('POST', /^\/api\/planos\/alimentar$/, false, async (q, { uid }) => {
  const n = (await q(`SELECT count(*)::int AS n FROM plano_alimentar WHERE usuario_id = $1`, [uid])).rows[0].n;
  await transacao(q, () => gerarPlanoAlimentar(q, uid, n));
  return { estado: await estado(q, uid) };
});

rota('POST', /^\/api\/planos\/treino$/, false, async (q, { uid }) => {
  await transacao(q, () => gerarPlanoTreino(q, uid));
  return { estado: await estado(q, uid) };
});

rota('POST', /^\/api\/exercicios\/(\d+)\/feito$/, false, async (q, { uid, m }) => {
  const te = (await q(
    `SELECT te.exercicio_id, te.series, te.repeticoes_max, te.duracao_seg, te.carga_sugerida_kg,
            td.id AS dia_id, td.dia_semana, EXTRACT(DOW FROM current_date)::int AS hoje
       FROM treino_exercicio te
       JOIN treino_dia td ON td.id = te.treino_dia_id
       JOIN plano_treino pt ON pt.id = td.plano_treino_id
      WHERE te.id = $1 AND pt.usuario_id = $2 AND pt.status = 'ativo'`, [Number(m[1]), uid])).rows[0];
  if (!te) throw new HttpErro(404, 'Exercício não encontrado.');
  if (te.dia_semana !== te.hoje) throw new HttpErro(400, 'Só dá para marcar os exercícios do treino de hoje.');
  const concluido = await transacao(q, async () => {
    let s = (await q(`SELECT id FROM sessao_treino WHERE usuario_id = $1 AND data = current_date AND treino_dia_id = $2`, [uid, te.dia_id])).rows[0];
    if (!s) s = (await q(`INSERT INTO sessao_treino (usuario_id, treino_dia_id) VALUES ($1, $2) RETURNING id`, [uid, te.dia_id])).rows[0];
    const apagou = (await q(`DELETE FROM serie_executada WHERE sessao_id = $1 AND exercicio_id = $2`, [s.id, te.exercicio_id])).rowCount;
    if (!apagou) await q(
      `INSERT INTO serie_executada (sessao_id, exercicio_id, numero, repeticoes, duracao_seg, carga_kg)
       SELECT $1, $2, n, $3, $4, $5 FROM generate_series(1, $6::int) n`,
      [s.id, te.exercicio_id, te.repeticoes_max, te.duracao_seg, te.carga_sugerida_kg, te.series]);
    return (await q(
      `UPDATE sessao_treino s SET concluida_em = CASE
          WHEN (SELECT count(*) FROM treino_exercicio WHERE treino_dia_id = s.treino_dia_id)
             = (SELECT count(DISTINCT exercicio_id) FROM serie_executada WHERE sessao_id = s.id)
          THEN now() END
        WHERE s.id = $1 RETURNING concluida_em IS NOT NULL AS concluido`, [s.id])).rows[0].concluido;
  });
  return { concluido, estado: await estado(q, uid) };
});

rota('POST', /^\/api\/progresso$/, false, async (q, { uid, corpo: c }) => {
  const peso = numero(c.peso, 'o peso em kg', 30, 300);
  const cintura = numero(c.cintura, 'a cintura em cm', 40, 200, true);
  const braco = numero(c.braco, 'o braço em cm', 15, 70, true);
  const treinou = c.treinou === 'sim' ? true : c.treinou === 'nao' ? false : null;
  const dieta = ['completa', 'parcial', 'nao'].includes(c.dieta) ? c.dieta : null;
  const r = (await q(
    `INSERT INTO registro_progresso (usuario_id, data, peso_kg, cintura_cm, braco_cm, treinou, seguiu_dieta)
     VALUES ($1, current_date, $2, $3, $4, $5, $6)
     ON CONFLICT (usuario_id, data) DO UPDATE
        SET peso_kg = EXCLUDED.peso_kg, cintura_cm = EXCLUDED.cintura_cm, braco_cm = EXCLUDED.braco_cm,
            treinou = EXCLUDED.treinou, seguiu_dieta = EXCLUDED.seguiu_dieta
     RETURNING (xmax = 0) AS novo`, [uid, peso, cintura, braco, treinou, dieta])).rows[0];
  return { novo: r.novo, estado: await estado(q, uid) };
});

rota('POST', /^\/api\/chat$/, false, async (q, { uid, corpo }) => {
  const pergunta = texto(corpo.texto, 'a mensagem', 1, 2000);
  const e = await estado(q, uid);
  const resposta = responder(pergunta, e);
  await transacao(q, async () => {
    let c = (await q(`SELECT id FROM conversa WHERE usuario_id = $1 ORDER BY atualizada_em DESC LIMIT 1`, [uid])).rows[0];
    if (!c) c = (await q(`INSERT INTO conversa (usuario_id, titulo) VALUES ($1, $2) RETURNING id`, [uid, pergunta.slice(0, 120)])).rows[0];
    await q(`INSERT INTO mensagem (conversa_id, papel, conteudo, tokens) VALUES ($1, 'usuario', $2, $3)`,
      [c.id, pergunta, Math.ceil(pergunta.length / 4)]);
    await q(`INSERT INTO mensagem (conversa_id, papel, conteudo, tokens, modelo_ia, criada_em) VALUES ($1, 'assistente', $2, $3, $4, now() + interval '1 millisecond')`,
      [c.id, resposta, Math.ceil(resposta.length / 4), MODELO]);
  });
  return { estado: await estado(q, uid) };
});

rota('PUT', /^\/api\/perfil$/, false, async (q, { uid, corpo: c }) => {
  const nome = texto(c.nome, 'seu nome', 2, 120);
  const idade = Math.round(numero(c.idade, 'a idade', 14, 100));
  const altura = numero(c.altura, 'a altura em cm', 120, 230);
  const peso = numero(c.peso, 'o peso em kg', 30, 250);
  const meta = numero(c.meta, 'o peso desejado em kg', 30, 250, true);
  if (!ATIVIDADES.includes(c.atividade)) throw new HttpErro(400, 'Escolha o nível de atividade.');
  await transacao(q, async () => {
    await q(
      `UPDATE usuario SET nome = $2, sexo = $3,
              data_nascimento = CASE WHEN fn_idade(data_nascimento) = $4 THEN data_nascimento
                                     ELSE current_date - make_interval(years => $4) END
        WHERE id = $1`, [uid, nome, c.sexo === 'F' ? 'feminino' : 'masculino', idade]);
    await q(`UPDATE perfil SET altura_cm = $2, nivel_atividade = $3, peso_meta_kg = $4 WHERE usuario_id = $1`, [uid, altura, c.atividade, meta]);
    const atual = (await q(`SELECT peso_kg FROM vw_peso_atual WHERE usuario_id = $1`, [uid])).rows[0];
    if (!atual || Math.abs(atual.peso_kg - peso) > 0.04) await q(
      `INSERT INTO registro_progresso (usuario_id, data, peso_kg) VALUES ($1, current_date, $2)
       ON CONFLICT (usuario_id, data) DO UPDATE SET peso_kg = EXCLUDED.peso_kg`, [uid, peso]);
  });
  return { estado: await estado(q, uid) };
});

rota('PUT', /^\/api\/objetivo$/, false, async (q, { uid, corpo }) => {
  if (!OBJETIVOS.includes(corpo.objetivo)) throw new HttpErro(400, 'Escolha um objetivo.');
  await transacao(q, async () => {
    await q(`UPDATE perfil SET objetivo = $2 WHERE usuario_id = $1`, [uid, corpo.objetivo]);
    const n = (await q(`SELECT count(*)::int AS n FROM plano_alimentar WHERE usuario_id = $1`, [uid])).rows[0].n;
    await gerarPlanoAlimentar(q, uid, n);
    await gerarPlanoTreino(q, uid);
  });
  return { estado: await estado(q, uid) };
});

const CAMPOS_NOTIF = ['lembrete_refeicao', 'lembrete_treino', 'lembrete_progresso', 'dicas_ia'];
rota('PUT', /^\/api\/notificacoes$/, false, async (q, { uid, corpo }) => {
  if (!CAMPOS_NOTIF.includes(corpo.campo)) throw new HttpErro(400, 'Campo inválido.');
  await q(`UPDATE preferencia_notificacao SET ${corpo.campo} = $2 WHERE usuario_id = $1`, [uid, corpo.valor === true]);
  return { estado: await estado(q, uid) };
});

rota('PUT', /^\/api\/consentimento$/, false, async (q, { uid, corpo }) => {
  await q(`INSERT INTO consentimento (usuario_id, tipo, versao, aceito) VALUES ($1, 'uso_anonimo_ia', '1.0', $2)`, [uid, corpo.aceito === true]);
  return { estado: await estado(q, uid) };
});

rota('GET', /^\/api\/exportar$/, false, async (q, { uid }) => {
  const dados = (await q(`SELECT fn_exportar_dados($1) AS dados`, [uid])).rows[0].dados;
  return { arquivo: dados };
});

rota('DELETE', /^\/api\/conta$/, false, async (q, { uid, token }) => {
  const r = await q(`DELETE FROM usuario WHERE id = $1`, [uid]);
  for (const [t, id] of sessoes) if (id === uid) sessoes.delete(t);
  sessoes.delete(token);
  return { excluida: r.rowCount === 1 };
});

// =====================================================================
// Servidor HTTP
// =====================================================================
function enviar(res, status, corpo, extra = {}) {
  const dados = Buffer.from(JSON.stringify(corpo));
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extra });
  res.end(dados);
}

function lerCorpo(req) {
  return new Promise((resolve, reject) => {
    let tamanho = 0;
    const partes = [];
    req.on('data', p => { tamanho += p.length; if (tamanho > 1e6) { reject(new HttpErro(413, 'Requisição grande demais.')); req.destroy(); } else partes.push(p); });
    req.on('end', () => {
      if (!partes.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(partes).toString('utf8'))); } catch (_) { reject(new HttpErro(400, 'JSON inválido.')); }
    });
    req.on('error', reject);
  });
}

const PUBLICO = path.join(__dirname, 'public');
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

const servidor = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith('/api/')) {
    const alvo = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    const arquivo = path.join(PUBLICO, path.normalize(alvo).replace(/^(\.\.[\\/])+/, ''));
    if (!arquivo.startsWith(PUBLICO)) { res.writeHead(403); return res.end(); }
    fs.readFile(arquivo, (err, dados) => {
      if (err) { res.writeHead(404); return res.end('Não encontrado'); }
      res.writeHead(200, { 'Content-Type': TIPOS[path.extname(arquivo)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(dados);
    });
    return;
  }

  const r = rotas.find(x => x.metodo === req.method && x.padrao.test(url.pathname));
  if (!r) return enviar(res, 404, { erro: 'Rota não encontrada.' });
  const inicio = Date.now();
  let trace = [];
  try {
    const token = (req.headers.authorization || '').replace(/^Bearer /, '');
    const uid = sessoes.get(token);
    if (!r.publica && !uid) throw new HttpErro(401, 'Sua sessão terminou. Entre de novo.');
    const corpo = req.method === 'GET' ? {} : await lerCorpo(req);
    const m = url.pathname.match(r.padrao);
    const { dados, trace: t } = await comBanco(q => r.fn(q, { uid, corpo, m, token }));
    trace = t;
    enviar(res, 200, { ...dados, _sql: trace, _ms: Date.now() - inicio });
  } catch (e) {
    trace = e.trace || trace;
    const [status, mensagem] = traduzirErro(e);
    if (status >= 500) console.error(`[${req.method} ${url.pathname}]`, e.message);
    enviar(res, status, { erro: mensagem, _sql: trace, _ms: Date.now() - inicio });
  }
  const linhas = trace.filter(x => /^(INSERT|UPDATE|DELETE)/.test(x.sql)).length;
  console.log(`${new Date().toLocaleTimeString('pt-BR')}  ${req.method.padEnd(6)} ${url.pathname.padEnd(28)} ${String(trace.length).padStart(2)} consultas${linhas ? `, ${linhas} gravações` : ''}`);
});

function iniciar(porta, tentativas = 10) {
  servidor.once('error', e => {
    if (e.code === 'EADDRINUSE' && tentativas > 0) return iniciar(porta + 1, tentativas - 1);
    console.error('Não consegui abrir o servidor:', e.message);
    process.exit(1);
  });
  servidor.listen(porta, '127.0.0.1', async () => {
    const endereco = `http://localhost:${porta}`;
    try {
      const s = (await pool.query(`SELECT split_part(version(), ' ', 2) AS v, count(*)::int AS n FROM information_schema.tables WHERE table_schema = 'iafit'`)).rows[0];
      console.log(`\n  Conectado ao PostgreSQL ${s.v}, banco iafit (${s.n} tabelas e views).`);
    } catch (e) {
      console.log('\n  ATENÇÃO: ' + traduzirErro(e)[1]);
    }
    console.log(`  iaFit rodando em ${endereco}`);
    console.log('  Deixe esta janela aberta enquanto usa o app. Para parar, feche a janela.\n');
    if (!process.argv.includes('--sem-navegador')) {
      const cmd = process.platform === 'win32' ? `start "" "${endereco}"` : process.platform === 'darwin' ? `open "${endereco}"` : `xdg-open "${endereco}"`;
      exec(cmd, () => { });
    }
  });
}
iniciar(PORTA_INICIAL);
