"""Gera o DER do iaFit (der.svg e der.png) lendo o catálogo do PostgreSQL.

Como o diagrama sai do banco criado, ele nunca fica diferente do schema.
Requer: psql no PATH, Graphviz (comando dot) e o banco já criado.
Uso:  python3 gerar_der.py "host=localhost dbname=iafit user=postgres"
"""
import subprocess
import sys
from collections import defaultdict

CONN = sys.argv[1] if len(sys.argv) > 1 else "dbname=iafit"

AREAS = {
    "Usuário e LGPD": ("#EEF2FF", ["usuario", "perfil", "restricao_alimentar", "usuario_restricao",
                                     "preferencia_notificacao", "consentimento"]),
    "Progresso": ("#ECFDF5", ["registro_progresso"]),
    "Alimentação": ("#FFF7ED", ["alimento", "alimento_conflito", "plano_alimentar", "refeicao",
                                 "refeicao_item", "refeicao_consumida"]),
    "Treino": ("#F0F9FF", ["exercicio", "plano_treino", "treino_dia", "treino_exercicio",
                            "sessao_treino", "serie_executada"]),
    "Chatbot": ("#FDF2F8", ["conversa", "mensagem"]),
}

COLS_SQL = """
SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
       EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p'
               AND a.attnum = ANY (k.conkey)) AS pk,
       EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
               AND a.attnum = ANY (k.conkey)) AS fk
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'iafit'
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE c.relkind = 'r'
ORDER BY c.relname, a.attnum;
"""

FKS_SQL = """
SELECT c.relname, r.relname, a.attname, ra.attname,
       EXISTS (SELECT 1 FROM pg_constraint u WHERE u.conrelid = c.oid AND u.contype IN ('p','u')
               AND u.conkey = k.conkey) AS um_para_um
FROM pg_constraint k
JOIN pg_class c ON c.oid = k.conrelid
JOIN pg_class r ON r.oid = k.confrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'iafit'
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.conkey[1]
JOIN pg_attribute ra ON ra.attrelid = r.oid AND ra.attnum = k.confkey[1]
WHERE k.contype = 'f';
"""


def query(sql):
    out = subprocess.run(["psql", CONN, "-At", "-F", "\t", "-c", sql],
                         check=True, capture_output=True, text=True).stdout
    return [line.split("\t") for line in out.strip().splitlines()]


def short_type(t):
    return (t.replace("character varying", "varchar").replace("timestamp with time zone", "timestamptz")
             .replace("time without time zone", "time").replace("iafit.", ""))


cols = defaultdict(list)
for tabela, coluna, tipo, notnull, pk, fk in query(COLS_SQL):
    cols[tabela].append((coluna, short_type(tipo), notnull == "t", pk == "t", fk == "t"))

linhas = ['digraph der {',
          '  graph [rankdir=LR, splines=true, nodesep=0.3, ranksep=1.1, newrank=true, fontname="Helvetica", '
          'label="iaFit · Diagrama Entidade-Relacionamento (gerado do PostgreSQL)", labelloc=t, fontsize=20, pad=0.4];',
          '  node [shape=plain, fontname="Helvetica", fontsize=10];',
          '  edge [color="#64748B", arrowsize=0.7, fontname="Helvetica"];']

for i, (area, (cor, tabelas)) in enumerate(AREAS.items()):
    linhas.append(f'  subgraph cluster_{i} {{ label="{area}"; fontsize=13; style="rounded,filled"; '
                  f'fillcolor="{cor}"; color="#CBD5E1";')
    for t in tabelas:
        rows = [f'<TR><TD BGCOLOR="#1E293B" COLSPAN="2"><FONT COLOR="white"><B>{t}</B></FONT></TD></TR>']
        for coluna, tipo, notnull, pk, fk in cols[t]:
            marca = "PK " if pk else ""
            marca += "FK " if fk else ""
            nome = f"<B>{coluna}</B>" if pk else coluna
            nome = f"<U>{nome}</U>" if pk else nome
            rows.append(f'<TR><TD ALIGN="LEFT" PORT="{coluna}">{marca}{nome}</TD>'
                        f'<TD ALIGN="LEFT" PORT="{coluna}_tipo"><FONT COLOR="#475569">{tipo}{"" if notnull else " ?"}</FONT></TD></TR>')
        tabela_html = ('<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4" BGCOLOR="white">'
                       + "".join(rows) + "</TABLE>>")
        linhas.append(f'    {t} [label={tabela_html}];')
    linhas.append('  }')

for origem, destino, coluna, coluna_destino, um_para_um in query(FKS_SQL):
    # pé de galinha do lado N; traço duplo do lado 1
    cauda = "teetee" if um_para_um == "t" else "crow"
    linhas.append(f'  {destino}:{coluna_destino}_tipo:e -> {origem}:{coluna}:w '
                  f'[dir=both, arrowtail=teetee, arrowhead={cauda}];')

linhas.append('}')

with open("der.dot", "w", encoding="utf-8") as f:
    f.write("\n".join(linhas))

subprocess.run(["dot", "-Tsvg", "der.dot", "-o", "der.svg"], check=True)
subprocess.run(["dot", "-Tpng", "-Gdpi=150", "der.dot", "-o", "der.png"], check=True)
print(f"DER gerado: {len(cols)} tabelas -> der.svg, der.png")
