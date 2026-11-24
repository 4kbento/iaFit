-- =====================================================================
-- iaFit: testes automáticos das regras do banco
-- Rodar depois do schema e do seed:  psql -d iafit -f sql/04_testes.sql
-- Tudo roda dentro de uma transação desfeita no final (ROLLBACK),
-- então os dados de exemplo continuam intactos.
-- Cada teste imprime "OK"; o primeiro que falhar interrompe o script.
-- =====================================================================

\set QUIET on
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET search_path TO iafit, public, extensions;
SET client_min_messages TO warning;

CREATE TEMP TABLE resultado (n int PRIMARY KEY, teste text, detalhe text) ON COMMIT DROP;

-- 1. Cálculos ---------------------------------------------------------
DO $$
BEGIN
    ASSERT fn_imc(82.9, 178) = 26.2, 'IMC errado';
    ASSERT fn_tmb(82.9, 178, 27, 'masculino') = 1812, 'TMB masculina errada';
    ASSERT fn_tmb(54.3, 163, 24, 'feminino') = 1281, 'TMB feminina errada';
    ASSERT fn_meta_kcal_sugerida(2809, 'perder_gordura') = 2250, 'meta de déficit errada';
    ASSERT fn_meta_kcal_sugerida(1761, 'ganhar_massa') = 1950, 'meta de superávit errada';
    INSERT INTO resultado VALUES (1, 'IMC, TMB e meta calórica', NULL);
END $$;

-- 2. Login ------------------------------------------------------------
DO $$
BEGIN
    ASSERT fn_autenticar('LUCAS.ANDRADE@exemplo.com', 'Senha@123') IS NOT NULL, 'login válido falhou';
    ASSERT fn_autenticar('lucas.andrade@exemplo.com', 'errada') IS NULL, 'senha errada passou';
    ASSERT (SELECT ultimo_login_em IS NOT NULL FROM usuario WHERE email = 'lucas.andrade@exemplo.com'),
           'último login não registrado';
    INSERT INTO resultado VALUES (2, 'Login confere o hash e ignora maiúsculas no e-mail', NULL);
END $$;

-- 3. E-mail único sem diferenciar maiúsculas -------------------------
DO $$
BEGIN
    INSERT INTO usuario (nome, email, senha_hash, data_nascimento, sexo)
    VALUES ('Cópia', 'Lucas.Andrade@Exemplo.com', 'x', '2000-01-01', 'masculino');
    RAISE EXCEPTION 'e-mail duplicado foi aceito';
EXCEPTION WHEN unique_violation THEN
    INSERT INTO resultado VALUES (3, 'E-mail duplicado é recusado', NULL);
END $$;

-- 4. Validações de faixa ---------------------------------------------
DO $$
BEGIN
    INSERT INTO registro_progresso (usuario_id, data, peso_kg)
    VALUES ((SELECT id FROM usuario WHERE email = 'rafael.souza@exemplo.com'), current_date, 900);
    RAISE EXCEPTION 'peso de 900 kg foi aceito';
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES (4, 'Peso fora da faixa é recusado', NULL);
END $$;

-- 5. Um registro de progresso por dia --------------------------------
DO $$
DECLARE v_uid bigint := (SELECT id FROM usuario WHERE email = 'rafael.souza@exemplo.com');
BEGIN
    INSERT INTO registro_progresso (usuario_id, data, peso_kg) VALUES (v_uid, current_date, 73.8);
    BEGIN
        INSERT INTO registro_progresso (usuario_id, data, peso_kg) VALUES (v_uid, current_date, 73.6);
        RAISE EXCEPTION 'dois registros no mesmo dia foram aceitos';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    INSERT INTO registro_progresso (usuario_id, data, peso_kg) VALUES (v_uid, current_date, 73.6)
    ON CONFLICT (usuario_id, data) DO UPDATE SET peso_kg = EXCLUDED.peso_kg;
    ASSERT (SELECT peso_kg FROM registro_progresso WHERE usuario_id = v_uid AND data = current_date) = 73.6,
           'upsert não atualizou';
    INSERT INTO resultado VALUES (5, 'Um registro por dia, com upsert', NULL);
END $$;

-- 6. Plano novo encerra o anterior -----------------------------------
DO $$
DECLARE v_uid bigint := (SELECT id FROM usuario WHERE email = 'mariana.costa@exemplo.com');
        v_antigo bigint;
BEGIN
    SELECT id INTO v_antigo FROM plano_alimentar WHERE usuario_id = v_uid AND status = 'ativo';
    INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g)
    VALUES (v_uid, 'Novo plano', 2000, 105, 260, 62);
    ASSERT (SELECT status FROM plano_alimentar WHERE id = v_antigo) = 'encerrado', 'plano antigo continuou ativo';
    ASSERT (SELECT fim FROM plano_alimentar WHERE id = v_antigo) = current_date - 1, 'data de fim errada';
    ASSERT (SELECT count(*) FROM plano_alimentar WHERE usuario_id = v_uid AND status = 'ativo') = 1,
           'mais de um plano ativo';
    INSERT INTO resultado VALUES (6, 'Plano novo encerra o anterior e só um fica ativo', NULL);
END $$;

-- 7. Restrição alimentar é respeitada --------------------------------
DO $$
DECLARE v_refeicao bigint;
BEGIN
    SELECT r.id INTO v_refeicao
    FROM refeicao r JOIN plano_alimentar p ON p.id = r.plano_id
    JOIN usuario u ON u.id = p.usuario_id
    WHERE u.email = 'mariana.costa@exemplo.com' AND r.nome = 'Jantar'
    LIMIT 1;

    INSERT INTO refeicao_item (refeicao_id, alimento_id, quantidade_g)
    VALUES (v_refeicao, (SELECT id FROM alimento WHERE nome = 'Peito de frango grelhado'), 120);
    RAISE EXCEPTION 'frango entrou no plano de quem é vegetariana';
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES (7, 'Alimento que viola restrição é bloqueado', SQLERRM);
END $$;

-- 8. Dia de descanso sem exercício -----------------------------------
DO $$
BEGIN
    INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max)
    SELECT td.id, (SELECT id FROM exercicio WHERE nome = 'Burpee'), 1, 3, 10, 12
    FROM treino_dia td JOIN plano_treino pt ON pt.id = td.plano_treino_id
    JOIN usuario u ON u.id = pt.usuario_id
    WHERE u.email = 'lucas.andrade@exemplo.com' AND td.descanso
    LIMIT 1;
    RAISE EXCEPTION 'exercício entrou em dia de descanso';
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES (8, 'Dia de descanso não recebe exercício', NULL);
END $$;

-- 9. Exercício é por repetição ou por tempo, nunca os dois -----------
DO $$
BEGIN
    INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max, duracao_seg)
    SELECT td.id, (SELECT id FROM exercicio WHERE nome = 'Prancha'), 19, 3, 10, 12, 30
    FROM treino_dia td JOIN plano_treino pt ON pt.id = td.plano_treino_id
    JOIN usuario u ON u.id = pt.usuario_id
    WHERE u.email = 'lucas.andrade@exemplo.com' AND NOT td.descanso
    LIMIT 1;
    RAISE EXCEPTION 'exercício com repetição e tempo foi aceito';
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES (9, 'Exercício é por repetição ou por tempo', NULL);
END $$;

-- 10. Plano gerado bate com a meta (tolerância de 5% nas calorias) ---
DO $$
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM vw_macros_plano WHERE status = 'ativo' AND abs(pct_kcal - 100) > 5),
           'algum plano ativo foge mais de 5% da meta calórica';
    INSERT INTO resultado VALUES (10, 'Planos ativos ficam a menos de 5% da meta calórica', NULL);
END $$;

-- 11. Mensagem nova atualiza a conversa ------------------------------
DO $$
DECLARE v_conversa bigint; v_antes timestamptz;
BEGIN
    SELECT c.id, c.atualizada_em INTO v_conversa, v_antes
    FROM conversa c JOIN usuario u ON u.id = c.usuario_id
    WHERE u.email = 'lucas.andrade@exemplo.com' LIMIT 1;
    INSERT INTO mensagem (conversa_id, papel, conteudo) VALUES (v_conversa, 'usuario', 'Obrigado!');
    ASSERT (SELECT atualizada_em FROM conversa WHERE id = v_conversa) > v_antes, 'conversa não foi atualizada';
    INSERT INTO resultado VALUES (11, 'Mensagem nova atualiza a conversa', NULL);
END $$;

-- 12. Resposta da IA sem modelo registrado é recusada ----------------
DO $$
BEGIN
    INSERT INTO mensagem (conversa_id, papel, conteudo)
    VALUES ((SELECT min(id) FROM conversa), 'assistente', 'resposta sem modelo');
    RAISE EXCEPTION 'resposta da IA sem modelo foi aceita';
EXCEPTION WHEN check_violation THEN
    INSERT INTO resultado VALUES (12, 'Resposta da IA guarda qual modelo respondeu', NULL);
END $$;

-- 13. Sequência de dias ----------------------------------------------
DO $$
BEGIN
    ASSERT fn_sequencia_dias((SELECT id FROM usuario WHERE email = 'lucas.andrade@exemplo.com')) >= 7,
           'sequência do Lucas deveria passar de 7 dias';
    ASSERT fn_sequencia_dias((SELECT id FROM usuario WHERE email = 'rafael.souza@exemplo.com')) >= 1,
           'Rafael registrou hoje no teste 5, a sequência deveria ser pelo menos 1';
    INSERT INTO resultado VALUES (13, 'Sequência de dias', NULL);
END $$;

-- 14. LGPD: exportar não leva a senha e excluir apaga tudo -----------
DO $$
DECLARE v_uid bigint := (SELECT id FROM usuario WHERE email = 'lucas.andrade@exemplo.com');
        v_json jsonb;
BEGIN
    v_json := fn_exportar_dados(v_uid);
    ASSERT NOT (v_json -> 'usuario') ? 'senha_hash', 'exportação vazou o hash da senha';
    ASSERT jsonb_array_length(v_json -> 'progresso') >= 9, 'exportação sem o histórico de progresso';

    DELETE FROM usuario WHERE id = v_uid;

    ASSERT NOT EXISTS (SELECT 1 FROM perfil WHERE usuario_id = v_uid), 'perfil sobrou';
    ASSERT NOT EXISTS (SELECT 1 FROM registro_progresso WHERE usuario_id = v_uid), 'progresso sobrou';
    ASSERT NOT EXISTS (SELECT 1 FROM plano_alimentar WHERE usuario_id = v_uid), 'plano alimentar sobrou';
    ASSERT NOT EXISTS (SELECT 1 FROM sessao_treino WHERE usuario_id = v_uid), 'sessões sobraram';
    ASSERT NOT EXISTS (SELECT 1 FROM conversa WHERE usuario_id = v_uid), 'conversas sobraram';
    ASSERT NOT EXISTS (SELECT 1 FROM consentimento WHERE usuario_id = v_uid), 'consentimentos sobraram';
    ASSERT (SELECT count(*) FROM alimento) = 28, 'exclusão apagou o catálogo de alimentos';
    INSERT INTO resultado VALUES (14, 'LGPD: exportação sem senha e exclusão em cascata', NULL);
END $$;

\echo ''
\echo 'Resultado dos testes:'
SELECT n AS "#", teste AS "Regra testada", 'OK' AS status, COALESCE(detalhe, '') AS "Mensagem do banco"
FROM resultado ORDER BY n;

ROLLBACK;
\echo 'Todos os 14 testes passaram. Nada foi gravado (ROLLBACK).'
