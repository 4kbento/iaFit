-- =====================================================================
-- iaFit: demonstração guiada do banco, para apresentar ao professor
-- Rodar no Windows: DEMONSTRAR.bat   |   Em outro sistema: psql -d iafit -f sql/05_demonstracao.sql
--
-- Uma usuária nova (Ana) se cadastra, faz login, recebe plano alimentar
-- e de treino da IA, registra refeições e peso, conversa com o chatbot
-- e por fim exclui a conta. No caminho, o banco recusa o que viola as
-- regras. Cada etapa espera Enter. Tudo que a demonstração cria é
-- apagado no final, então ela pode ser repetida quantas vezes quiser.
-- =====================================================================

\set QUIET on
\set ON_ERROR_STOP on
\set VERBOSITY terse
\pset pager off
\pset null '-'
\pset format wrapped
\pset columns 120
SET search_path TO iafit, public, extensions;
SET client_min_messages TO warning;

-- limpa uma demonstração anterior que tenha sido interrompida
DELETE FROM usuario WHERE lower(email) = 'ana.demo@iafit.com';

\echo ''
\echo '================================================================'
\echo '  iaFit: demonstração do banco de dados PostgreSQL'
\echo '  Aperte Enter para avançar cada etapa.'
\echo '================================================================'

-- ---------------------------------------------------------------------
\echo '\n[1/10] O BANCO: tabelas e quantidade de registros de exemplo'
SELECT count(*) FILTER (WHERE table_type = 'BASE TABLE') AS tabelas,
       count(*) FILTER (WHERE table_type = 'VIEW')       AS views,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'iafit' AND p.proname LIKE 'fn\_%')  AS funcoes,
       (SELECT count(DISTINCT tgname) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'iafit' AND NOT t.tgisinternal)            AS triggers
FROM information_schema.tables WHERE table_schema = 'iafit';

SELECT table_name AS tabela,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM iafit.%I', table_name),
              false, true, '')))[1]::text::int AS registros
FROM information_schema.tables
WHERE table_schema = 'iafit' AND table_type = 'BASE TABLE'
ORDER BY table_name;
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[2/10] TELA CADASTRO: a Ana cria a conta'
\echo 'A senha é gravada só como hash bcrypt, nunca em texto puro.'
INSERT INTO usuario (nome, email, senha_hash, data_nascimento, sexo)
VALUES ('Ana Demonstração', 'ana.demo@iafit.com', crypt('Senha@123', gen_salt('bf', 8)), '2001-05-10', 'feminino')
RETURNING id, nome, email, left(senha_hash, 20) || '...' AS senha_guardada;

INSERT INTO perfil (usuario_id, altura_cm, peso_meta_kg, objetivo, nivel_atividade, experiencia,
                    dias_treino_semana, minutos_por_treino, local_treino, refeicoes_por_dia)
SELECT id, 165, 62, 'perder_gordura', 'moderado', 'iniciante', 3, 45, 'casa', 4
FROM usuario WHERE email = 'ana.demo@iafit.com';

INSERT INTO usuario_restricao (usuario_id, restricao_id)
SELECT u.id, r.id FROM usuario u, restricao_alimentar r
WHERE u.email = 'ana.demo@iafit.com' AND r.nome = 'Sem lactose';

INSERT INTO preferencia_notificacao (usuario_id)
SELECT id FROM usuario WHERE email = 'ana.demo@iafit.com';

INSERT INTO consentimento (usuario_id, tipo, versao, aceito)
SELECT u.id, t.tipo::tipo_consentimento, '1.0', t.aceito
FROM usuario u, (VALUES ('termos_uso', true), ('politica_privacidade', true), ('uso_anonimo_ia', true)) t(tipo, aceito)
WHERE u.email = 'ana.demo@iafit.com';

\echo '\nCálculos da última etapa do cadastro (peso informado: 68 kg):'
SELECT fn_idade(u.data_nascimento)                                      AS idade,
       fn_imc(68, p.altura_cm)                                          AS imc,
       fn_tmb(68, p.altura_cm, fn_idade(u.data_nascimento), u.sexo)     AS tmb_kcal,
       round(fn_tmb(68, p.altura_cm, fn_idade(u.data_nascimento), u.sexo)
             * fn_fator_atividade(p.nivel_atividade))::int              AS gasto_diario_kcal,
       fn_meta_kcal_sugerida(round(fn_tmb(68, p.altura_cm, fn_idade(u.data_nascimento), u.sexo)
             * fn_fator_atividade(p.nivel_atividade))::int, p.objetivo) AS meta_kcal_sugerida
FROM usuario u JOIN perfil p ON p.usuario_id = u.id
WHERE u.email = 'ana.demo@iafit.com';
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[3/10] TELA LOGIN: senha certa devolve o id; senha errada devolve vazio'
SELECT fn_autenticar('ana.demo@iafit.com', 'Senha@123')    AS senha_certa,
       fn_autenticar('ANA.DEMO@iafit.com', 'Senha@123')    AS email_em_maiusculas,
       fn_autenticar('ana.demo@iafit.com', 'senha-errada') AS senha_errada;
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[4/10] TELA PLANO ALIMENTAR: a IA gera o plano da Ana (sem lactose)'
INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g, modelo_ia)
SELECT u.id, 'Déficit sem lactose',
       fn_meta_kcal_sugerida(round(fn_tmb(68, p.altura_cm, fn_idade(u.data_nascimento), u.sexo)
                             * fn_fator_atividade(p.nivel_atividade))::int, p.objetivo),
       120, 190, 55, 'iafit-llm-v1'
FROM usuario u JOIN perfil p ON p.usuario_id = u.id
WHERE u.email = 'ana.demo@iafit.com';

INSERT INTO refeicao (plano_id, nome, horario, ordem)
SELECT p.id, v.nome, v.horario::time, v.ordem
FROM plano_alimentar p JOIN usuario u ON u.id = p.usuario_id,
     (VALUES ('Café da manhã', '07:00', 1), ('Almoço', '12:30', 2),
             ('Lanche da tarde', '16:00', 3), ('Jantar', '20:00', 4)) v(nome, horario, ordem)
WHERE u.email = 'ana.demo@iafit.com' AND p.status = 'ativo';

INSERT INTO refeicao_item (refeicao_id, alimento_id, quantidade_g, medida_caseira)
SELECT r.id, a.id, v.qtd, v.medida
FROM (VALUES
    ('Café da manhã',   'Pão integral',             50, '2 fatias'),
    ('Café da manhã',   'Ovo de galinha cozido',   100, '2 ovos'),
    ('Café da manhã',   'Aveia em flocos',          30, '3 colheres de sopa'),
    ('Café da manhã',   'Mamão papaia',            150, '1/2 mamão'),
    ('Almoço',          'Arroz integral cozido',   180, '6 colheres de sopa'),
    ('Almoço',          'Feijão carioca cozido',   100, '1 concha'),
    ('Almoço',          'Peito de frango grelhado',130, '1 filé médio'),
    ('Almoço',          'Brócolis cozido',         100, '1 xícara'),
    ('Almoço',          'Azeite de oliva',          10, '1 colher de sobremesa'),
    ('Lanche da tarde', 'Banana prata',            100, '1 unidade'),
    ('Lanche da tarde', 'Castanha-do-pará',         15, '3 unidades'),
    ('Lanche da tarde', 'Maçã',                    130, '1 unidade'),
    ('Jantar',          'Batata-doce cozida',      150, '1 unidade média'),
    ('Jantar',          'Filé de tilápia grelhado',150, '1 filé grande'),
    ('Jantar',          'Alface crespa',            50, '1 prato de sobremesa'),
    ('Jantar',          'Tomate',                   80, '1 unidade média'),
    ('Jantar',          'Azeite de oliva',          10, '1 colher de sobremesa')
) v(refeicao, alimento, qtd, medida)
JOIN usuario u         ON u.email = 'ana.demo@iafit.com'
JOIN plano_alimentar p ON p.usuario_id = u.id AND p.status = 'ativo'
JOIN refeicao r        ON r.plano_id = p.id AND r.nome = v.refeicao
JOIN alimento a        ON a.nome = v.alimento;

\echo '\nRefeições do dia, com calorias e macros somadas pelo banco:'
SELECT m.ordem, to_char(m.horario, 'HH24:MI') AS horario, m.nome AS refeicao,
       m.kcal, m.proteina_g, m.carboidrato_g, m.gordura_g
FROM vw_macros_refeicao m
JOIN plano_alimentar p ON p.id = m.plano_id
JOIN usuario u         ON u.id = p.usuario_id
WHERE u.email = 'ana.demo@iafit.com'
ORDER BY m.ordem;

\echo '\nO plano bate com a meta que a IA prometeu?'
SELECT v.titulo, v.meta_kcal, v.total_kcal, v.pct_kcal AS "% da meta"
FROM vw_macros_plano v JOIN usuario u ON u.id = v.usuario_id
WHERE u.email = 'ana.demo@iafit.com';
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[5/10] REGRA: a IA tenta colocar iogurte (tem lactose) no lanche da Ana'
\echo 'O banco deve RECUSAR:'
\set ON_ERROR_STOP off
INSERT INTO refeicao_item (refeicao_id, alimento_id, quantidade_g)
SELECT r.id, (SELECT id FROM alimento WHERE nome = 'Iogurte natural desnatado'), 170
FROM refeicao r
JOIN plano_alimentar p ON p.id = r.plano_id
JOIN usuario u         ON u.id = p.usuario_id
WHERE u.email = 'ana.demo@iafit.com' AND r.nome = 'Lanche da tarde';
\set ON_ERROR_STOP on
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[6/10] TELA TREINO: a IA monta o treino; o plano novo encerra o anterior'
INSERT INTO plano_treino (usuario_id, titulo, divisao, inicio, modelo_ia)
SELECT id, 'Adaptação', 'Full body', current_date - 14, 'iafit-llm-v1'
FROM usuario WHERE email = 'ana.demo@iafit.com';

INSERT INTO plano_treino (usuario_id, titulo, divisao, inicio, modelo_ia)
SELECT id, 'Full body 3x em casa', 'Full body', current_date, 'iafit-llm-v1'
FROM usuario WHERE email = 'ana.demo@iafit.com';

\echo 'Inserimos dois planos; o trigger encerrou o primeiro sozinho:'
SELECT pt.titulo, pt.status, pt.inicio, pt.fim
FROM plano_treino pt JOIN usuario u ON u.id = pt.usuario_id
WHERE u.email = 'ana.demo@iafit.com'
ORDER BY pt.inicio;

INSERT INTO treino_dia (plano_treino_id, dia_semana, nome, descanso)
SELECT pt.id, d, CASE WHEN d IN (1, 3, 5) THEN 'Full body' ELSE 'Descanso' END, d NOT IN (1, 3, 5)
FROM plano_treino pt JOIN usuario u ON u.id = pt.usuario_id
CROSS JOIN generate_series(0, 6) d
WHERE u.email = 'ana.demo@iafit.com' AND pt.status = 'ativo';

INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max, duracao_seg, descanso_seg)
SELECT td.id, e.id, v.ordem, v.series, v.rmin, v.rmax, v.seg, 60
FROM (VALUES ('Agachamento com peso corporal', 1, 3, 12, 15, NULL),
             ('Flexão de braço',               2, 3,  8, 10, NULL),
             ('Elevação pélvica',              3, 3, 12, 15, NULL),
             ('Prancha',                       4, 3, NULL, NULL, 30)) v(exercicio, ordem, series, rmin, rmax, seg)
JOIN exercicio e       ON e.nome = v.exercicio
JOIN usuario u         ON u.email = 'ana.demo@iafit.com'
JOIN plano_treino pt   ON pt.usuario_id = u.id AND pt.status = 'ativo'
JOIN treino_dia td     ON td.plano_treino_id = pt.id AND NOT td.descanso;

\echo '\nSemana de treino da Ana:'
SELECT (ARRAY['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'])[td.dia_semana + 1] AS dia,
       td.nome, count(te.id) AS exercicios
FROM treino_dia td
JOIN plano_treino pt          ON pt.id = td.plano_treino_id AND pt.status = 'ativo'
JOIN usuario u                ON u.id = pt.usuario_id
LEFT JOIN treino_exercicio te ON te.treino_dia_id = td.id
WHERE u.email = 'ana.demo@iafit.com'
GROUP BY td.id ORDER BY td.dia_semana;

\echo '\nTentativa de colocar exercício no domingo (descanso). O banco deve RECUSAR:'
\set ON_ERROR_STOP off
INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max)
SELECT td.id, (SELECT id FROM exercicio WHERE nome = 'Burpee'), 1, 3, 10, 12
FROM treino_dia td
JOIN plano_treino pt ON pt.id = td.plano_treino_id AND pt.status = 'ativo'
JOIN usuario u       ON u.id = pt.usuario_id
WHERE u.email = 'ana.demo@iafit.com' AND td.dia_semana = 0;
\set ON_ERROR_STOP on
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[7/10] TELAS REGISTRAR PROGRESSO E EVOLUÇÃO'
\echo 'A Ana marca o café e o almoço de hoje como feitos:'
INSERT INTO refeicao_consumida (refeicao_id, data)
SELECT r.id, current_date
FROM refeicao r
JOIN plano_alimentar p ON p.id = r.plano_id AND p.status = 'ativo'
JOIN usuario u         ON u.id = p.usuario_id
WHERE u.email = 'ana.demo@iafit.com' AND r.ordem <= 2;

\echo 'Ela registrou o peso nas últimas 3 semanas e hoje registra 68,0 kg:'
INSERT INTO registro_progresso (usuario_id, data, peso_kg, cintura_cm)
SELECT u.id, current_date - v.dias, v.peso, v.cintura
FROM usuario u, (VALUES (21, 69.4, 82.0), (14, 69.0, 81.4), (7, 68.5, 81.0), (0, 68.0, 80.6)) v(dias, peso, cintura)
WHERE u.email = 'ana.demo@iafit.com';

\echo 'Ela percebe que errou e corrige para 67,8 kg. Mesmo dia = atualiza, não duplica:'
INSERT INTO registro_progresso (usuario_id, data, peso_kg)
SELECT id, current_date, 67.8 FROM usuario WHERE email = 'ana.demo@iafit.com'
ON CONFLICT (usuario_id, data) DO UPDATE SET peso_kg = EXCLUDED.peso_kg;

SELECT r.data, r.peso_kg, r.cintura_cm
FROM registro_progresso r JOIN usuario u ON u.id = r.usuario_id
WHERE u.email = 'ana.demo@iafit.com'
ORDER BY r.data;

\echo '\nGráfico da tela Evolução (média por semana):'
SELECT e.semana, e.peso_medio_kg,
       e.peso_medio_kg - lag(e.peso_medio_kg) OVER (ORDER BY e.semana) AS variacao_kg
FROM vw_evolucao_semanal e JOIN usuario u ON u.id = e.usuario_id
WHERE u.email = 'ana.demo@iafit.com'
ORDER BY e.semana;
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[8/10] TELA DASHBOARD: tudo que a tela inicial mostra, calculado pelo banco'
\x on
SELECT d.nome, d.idade, d.peso_atual_kg, d.peso_meta_kg, d.falta_kg, d.imc, d.tmb_kcal,
       d.gasto_diario_kcal, d.meta_kcal, d.kcal_hoje, d.treino_hoje, d.descanso_hoje, d.sequencia_dias
FROM vw_dashboard d JOIN usuario u ON u.id = d.usuario_id
WHERE u.email = 'ana.demo@iafit.com';
\x off
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[9/10] TELA CHATBOT: pergunta, resposta e o contexto que vai para a IA'
WITH c AS (
    INSERT INTO conversa (usuario_id, titulo)
    SELECT id, 'Substituir o leite' FROM usuario WHERE email = 'ana.demo@iafit.com'
    RETURNING id
)
INSERT INTO mensagem (conversa_id, papel, conteudo, modelo_ia, criada_em)
SELECT c.id, v.papel::papel_mensagem, v.conteudo, v.modelo, now() + v.seg * interval '1 second'
FROM c, (VALUES
    ('usuario',    'Não posso tomar leite. O que uso no café da manhã?', NULL, 0),
    ('assistente', 'Seu plano já não tem leite: o café tem pão integral, 2 ovos, aveia e mamão. Se quiser algo para beber, café sem açúcar ou chá não alteram as calorias.', 'iafit-llm-v1', 2)
) v(papel, conteudo, modelo, seg);

SELECT m.papel, m.conteudo
FROM mensagem m JOIN conversa c ON c.id = m.conversa_id
JOIN usuario u ON u.id = c.usuario_id
WHERE u.email = 'ana.demo@iafit.com'
ORDER BY m.criada_em;

\echo '\nResumo da Ana que o backend envia junto com cada pergunta para a IA:'
\pset format unaligned
\pset tuples_only on
SELECT jsonb_pretty(fn_contexto_ia(id)) FROM usuario WHERE email = 'ana.demo@iafit.com';
\pset tuples_only off
\pset format wrapped
\prompt '\nEnter para continuar...' pausa

-- ---------------------------------------------------------------------
\echo '\n[10/10] VALIDAÇÕES E LGPD'
\echo 'Peso de 900 kg. O banco deve RECUSAR:'
\set ON_ERROR_STOP off
INSERT INTO registro_progresso (usuario_id, data, peso_kg)
SELECT id, current_date - 1, 900 FROM usuario WHERE email = 'ana.demo@iafit.com';

\echo '\nOutra conta com o mesmo e-mail, em maiúsculas. O banco deve RECUSAR:'
INSERT INTO usuario (nome, email, senha_hash, data_nascimento, sexo)
VALUES ('Cópia', 'ANA.DEMO@IAFIT.COM', 'x', '2001-05-10', 'feminino');
\set ON_ERROR_STOP on

\echo '\nPerfil > Baixar meus dados: o JSON exportado tem estas seções (e não leva a senha):'
SELECT jsonb_object_keys(fn_exportar_dados(id)) AS secao FROM usuario WHERE email = 'ana.demo@iafit.com';
SELECT (fn_exportar_dados(id) -> 'usuario') ? 'senha_hash' AS exportou_a_senha
FROM usuario WHERE email = 'ana.demo@iafit.com';

\prompt '\nEnter para EXCLUIR a conta da Ana...' pausa
CREATE TEMP TABLE ana AS SELECT id FROM usuario WHERE email = 'ana.demo@iafit.com';
DELETE FROM usuario WHERE email = 'ana.demo@iafit.com';

\echo 'Conta excluída. O que sobrou dela em cada tabela:'
SELECT 'perfil' AS tabela, count(*) AS registros FROM perfil WHERE usuario_id IN (SELECT id FROM ana)
UNION ALL SELECT 'consentimento',      count(*) FROM consentimento      WHERE usuario_id IN (SELECT id FROM ana)
UNION ALL SELECT 'registro_progresso', count(*) FROM registro_progresso WHERE usuario_id IN (SELECT id FROM ana)
UNION ALL SELECT 'plano_alimentar',    count(*) FROM plano_alimentar    WHERE usuario_id IN (SELECT id FROM ana)
UNION ALL SELECT 'plano_treino',       count(*) FROM plano_treino       WHERE usuario_id IN (SELECT id FROM ana)
UNION ALL SELECT 'conversa',           count(*) FROM conversa           WHERE usuario_id IN (SELECT id FROM ana);
DROP TABLE ana;

\echo ''
\echo '================================================================'
\echo '  Demonstração concluída. Os dados de exemplo continuam no banco.'
\echo '================================================================'
