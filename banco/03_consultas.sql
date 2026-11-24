-- =====================================================================
-- iaFit: consultas de cada tela do app
-- Rodar:  psql -d iafit -f sql/03_consultas.sql
--
-- :usuario_id e :email são variáveis do psql. No backend elas viram
-- parâmetros ($1, $2) da query, nunca texto concatenado.
-- =====================================================================

SET search_path TO iafit, public;
\set usuario_id 1
\set email 'lucas.andrade@exemplo.com'
\pset pager off

\echo '\n=== LOGIN: devolve o id se e-mail e senha conferem ==='
SELECT fn_autenticar(:'email', 'Senha@123') AS usuario_id_logado,
       fn_autenticar(:'email', 'senha-errada') AS senha_errada;

\echo '\n=== CADASTRO: cálculo mostrado na última etapa (IMC, TMB, gasto e meta sugerida) ==='
SELECT fn_imc(82.9, 178)                                                 AS imc,
       fn_tmb(82.9, 178, fn_idade('1999-03-14'), 'masculino')            AS tmb_kcal,
       round(fn_tmb(82.9, 178, fn_idade('1999-03-14'), 'masculino')
             * fn_fator_atividade('moderado'))::int                      AS gasto_diario_kcal,
       fn_meta_kcal_sugerida(round(fn_tmb(82.9, 178, fn_idade('1999-03-14'), 'masculino')
             * fn_fator_atividade('moderado'))::int, 'perder_gordura')    AS meta_kcal_sugerida;

\echo '\n=== DASHBOARD ==='
SELECT * FROM vw_dashboard WHERE usuario_id = :usuario_id;

\echo '\n=== PLANO ALIMENTAR: refeições do dia com macros e check de hoje ==='
SELECT m.ordem, to_char(m.horario, 'HH24:MI') AS horario, m.nome, m.kcal,
       m.proteina_g, m.carboidrato_g, m.gordura_g,
       (rc.refeicao_id IS NOT NULL) AS feita_hoje
FROM plano_alimentar p
JOIN vw_macros_refeicao m        ON m.plano_id = p.id
LEFT JOIN refeicao_consumida rc  ON rc.refeicao_id = m.refeicao_id AND rc.data = current_date
WHERE p.usuario_id = :usuario_id AND p.status = 'ativo'
ORDER BY m.ordem;

\echo '\n=== PLANO ALIMENTAR: itens de cada refeição ==='
SELECT r.nome AS refeicao, a.nome AS alimento, i.quantidade_g, i.medida_caseira,
       round(i.quantidade_g * a.kcal_100g / 100) AS kcal
FROM plano_alimentar p
JOIN refeicao r      ON r.plano_id = p.id
JOIN refeicao_item i ON i.refeicao_id = r.id
JOIN alimento a      ON a.id = i.alimento_id
WHERE p.usuario_id = :usuario_id AND p.status = 'ativo'
ORDER BY r.ordem, i.id;

\echo '\n=== PLANO ALIMENTAR: marcar refeição como feita (idempotente) ==='
INSERT INTO refeicao_consumida (refeicao_id, data)
SELECT r.id, current_date
FROM plano_alimentar p JOIN refeicao r ON r.plano_id = p.id
WHERE p.usuario_id = :usuario_id AND p.status = 'ativo' AND r.ordem = 3
ON CONFLICT (refeicao_id, data) DO NOTHING;

\echo '\n=== PLANO ALIMENTAR: total do plano x meta ==='
SELECT titulo, meta_kcal, total_kcal, pct_kcal,
       meta_proteina_g, total_proteina_g, meta_carboidrato_g, total_carboidrato_g,
       meta_gordura_g, total_gordura_g
FROM vw_macros_plano WHERE usuario_id = :usuario_id AND status = 'ativo';

\echo '\n=== TREINO: a semana do plano ativo ==='
SELECT td.dia_semana,
       (ARRAY['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'])[td.dia_semana + 1] AS dia,
       td.nome, td.descanso, count(te.id) AS exercicios
FROM plano_treino pt
JOIN treino_dia td            ON td.plano_treino_id = pt.id
LEFT JOIN treino_exercicio te ON te.treino_dia_id = td.id
WHERE pt.usuario_id = :usuario_id AND pt.status = 'ativo'
GROUP BY td.id
ORDER BY td.dia_semana;

\echo '\n=== TREINO: exercícios de um dia (segunda-feira) ==='
SELECT te.ordem, e.nome, e.grupo, te.series,
       CASE WHEN te.duracao_seg IS NOT NULL THEN te.duracao_seg || ' s'
            ELSE te.repeticoes_min || ' a ' || te.repeticoes_max || ' reps' END AS alvo,
       te.carga_sugerida_kg, te.descanso_seg
FROM plano_treino pt
JOIN treino_dia td       ON td.plano_treino_id = pt.id AND td.dia_semana = 1
JOIN treino_exercicio te ON te.treino_dia_id = td.id
JOIN exercicio e         ON e.id = te.exercicio_id
WHERE pt.usuario_id = :usuario_id AND pt.status = 'ativo'
ORDER BY te.ordem;

\echo '\n=== TREINO: carga máxima por exercício nas últimas 4 semanas (progressão) ==='
SELECT e.nome, max(se.carga_kg) AS carga_max_kg, count(DISTINCT s.id) AS sessoes
FROM sessao_treino s
JOIN serie_executada se ON se.sessao_id = s.id
JOIN exercicio e        ON e.id = se.exercicio_id
WHERE s.usuario_id = :usuario_id AND s.data >= current_date - 28 AND se.carga_kg IS NOT NULL
GROUP BY e.nome
ORDER BY carga_max_kg DESC
LIMIT 5;

\echo '\n=== REGISTRAR PROGRESSO: upsert do dia (salvar duas vezes só atualiza) ==='
INSERT INTO registro_progresso (usuario_id, data, peso_kg, cintura_cm, humor)
VALUES (:usuario_id, current_date, 82.8, 90.1, 5)
ON CONFLICT (usuario_id, data) DO UPDATE
   SET peso_kg = EXCLUDED.peso_kg, cintura_cm = EXCLUDED.cintura_cm, humor = EXCLUDED.humor
RETURNING data, peso_kg, cintura_cm;

\echo '\n=== EVOLUÇÃO: peso por semana e variação ==='
SELECT semana, peso_medio_kg,
       peso_medio_kg - lag(peso_medio_kg) OVER (ORDER BY semana) AS variacao_kg
FROM vw_evolucao_semanal
WHERE usuario_id = :usuario_id
ORDER BY semana;

\echo '\n=== EVOLUÇÃO: resumo do período ==='
SELECT min(data) AS desde, max(data) AS ate,
       (array_agg(peso_kg ORDER BY data))[1]      AS peso_inicial,
       (array_agg(peso_kg ORDER BY data DESC))[1] AS peso_atual,
       (array_agg(peso_kg ORDER BY data DESC))[1] - (array_agg(peso_kg ORDER BY data))[1] AS diferenca_kg,
       fn_sequencia_dias(:usuario_id) AS sequencia_dias
FROM registro_progresso WHERE usuario_id = :usuario_id;

\echo '\n=== CHATBOT: conversas do usuário, mais recente primeiro ==='
SELECT c.id, c.titulo, c.atualizada_em, count(m.id) AS mensagens
FROM conversa c LEFT JOIN mensagem m ON m.conversa_id = c.id
WHERE c.usuario_id = :usuario_id
GROUP BY c.id ORDER BY c.atualizada_em DESC;

\echo '\n=== CHATBOT: últimas mensagens (histórico enviado à IA) ==='
SELECT papel, left(conteudo, 90) AS conteudo, criada_em
FROM (SELECT m.* FROM mensagem m JOIN conversa c ON c.id = m.conversa_id
      WHERE c.usuario_id = :usuario_id
      ORDER BY m.criada_em DESC LIMIT 20) ultimas
ORDER BY criada_em;

\echo '\n=== CHATBOT: contexto do usuário que vai junto no prompt ==='
SELECT jsonb_pretty(fn_contexto_ia(:usuario_id));

\echo '\n=== PERFIL: dados, restrições e notificações ==='
SELECT u.nome, u.email, pf.altura_cm, pf.objetivo, pf.nivel_atividade, pf.local_treino,
       COALESCE(string_agg(ra.nome, ', '), 'nenhuma') AS restricoes,
       n.horario_treino, n.horario_progresso, n.dicas_ia
FROM usuario u
JOIN perfil pf                    ON pf.usuario_id = u.id
JOIN preferencia_notificacao n    ON n.usuario_id = u.id
LEFT JOIN usuario_restricao ur    ON ur.usuario_id = u.id
LEFT JOIN restricao_alimentar ra  ON ra.id = ur.restricao_id
WHERE u.id = :usuario_id
GROUP BY u.id, pf.usuario_id, n.usuario_id;

\echo '\n=== PERFIL: planos ativos e encerrados ==='
SELECT 'alimentar' AS tipo, titulo, status, inicio, fim FROM plano_alimentar WHERE usuario_id = :usuario_id
UNION ALL
SELECT 'treino', titulo, status, inicio, fim FROM plano_treino WHERE usuario_id = :usuario_id
ORDER BY inicio;

\echo '\n=== LGPD: consentimento vigente ==='
SELECT tipo, versao, aceito, registrado_em::date FROM vw_consentimento_atual WHERE usuario_id = :usuario_id;

\echo '\n=== LGPD: revogar o uso anônimo dos dados (vira uma linha nova no histórico) ==='
INSERT INTO consentimento (usuario_id, tipo, versao, aceito)
VALUES (:usuario_id, 'uso_anonimo_ia', '1.0', false)
RETURNING tipo, aceito, registrado_em;

\echo '\n=== LGPD: baixar meus dados (chaves do JSON exportado) ==='
SELECT jsonb_object_keys(fn_exportar_dados(:usuario_id)) AS secoes_exportadas;

\echo '\n=== LGPD: excluir minha conta (apaga tudo em cascata) ==='
\echo 'DELETE FROM usuario WHERE id = :usuario_id;   -- não executado aqui; veja 04_testes.sql'
