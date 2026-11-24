-- =====================================================================
-- iaFit: banco de dados PostgreSQL (versão 14 ou superior)
-- Disciplina PMI II, Modelagem Computacional, turma ADS21
--
-- Cobre as 9 telas do protótipo: Login, Cadastro, Dashboard,
-- Plano Alimentar, Treino, Chatbot, Registrar Progresso, Evolução e Perfil.
--
-- Rodar:  psql -d iafit -f sql/01_schema.sql
-- O script recria o schema "iafit" do zero (apaga o que existir nele).
-- =====================================================================

BEGIN;

SET client_min_messages TO warning;
DROP SCHEMA IF EXISTS iafit CASCADE;
CREATE SCHEMA iafit;
SET search_path TO iafit, public;

-- pgcrypto: hash de senha (crypt + bcrypt). Disponível no Postgres padrão e no Supabase.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- ---------------------------------------------------------------------
-- 1. Tipos enumerados
-- ---------------------------------------------------------------------
CREATE TYPE sexo_biologico    AS ENUM ('feminino', 'masculino');
CREATE TYPE nivel_atividade   AS ENUM ('sedentario', 'leve', 'moderado', 'intenso', 'muito_intenso');
CREATE TYPE objetivo_fit      AS ENUM ('perder_gordura', 'ganhar_massa', 'manter_peso', 'condicionamento');
CREATE TYPE nivel_experiencia AS ENUM ('iniciante', 'intermediario', 'avancado');
CREATE TYPE local_treino      AS ENUM ('academia', 'casa', 'ar_livre');
CREATE TYPE status_plano      AS ENUM ('ativo', 'encerrado');
CREATE TYPE grupo_muscular    AS ENUM ('peito', 'costas', 'ombros', 'biceps', 'triceps',
                                       'pernas', 'gluteos', 'abdomen', 'cardio', 'corpo_todo');
CREATE TYPE papel_mensagem    AS ENUM ('usuario', 'assistente', 'sistema');
CREATE TYPE tipo_consentimento AS ENUM ('termos_uso', 'politica_privacidade', 'uso_anonimo_ia');

-- ---------------------------------------------------------------------
-- 2. Usuário e perfil (telas Login, Cadastro e Perfil)
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome             varchar(120) NOT NULL CHECK (length(trim(nome)) >= 2),
    email            varchar(254) NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    senha_hash       text         NOT NULL,   -- nunca a senha em texto puro
    data_nascimento  date         NOT NULL CHECK (data_nascimento > DATE '1900-01-01'),
    sexo             sexo_biologico NOT NULL, -- entra na fórmula da TMB
    criado_em        timestamptz  NOT NULL DEFAULT now(),
    atualizado_em    timestamptz  NOT NULL DEFAULT now(),
    ultimo_login_em  timestamptz
);
-- e-mail único sem diferenciar maiúsculas
CREATE UNIQUE INDEX usuario_email_uk ON usuario (lower(email));

CREATE TABLE perfil (
    usuario_id          bigint PRIMARY KEY REFERENCES usuario(id) ON DELETE CASCADE,
    altura_cm           numeric(5,1) NOT NULL CHECK (altura_cm BETWEEN 100 AND 250),
    peso_meta_kg        numeric(5,1) CHECK (peso_meta_kg BETWEEN 30 AND 300),
    objetivo            objetivo_fit      NOT NULL,
    nivel_atividade     nivel_atividade   NOT NULL,
    experiencia         nivel_experiencia NOT NULL DEFAULT 'iniciante',
    dias_treino_semana  smallint NOT NULL CHECK (dias_treino_semana BETWEEN 1 AND 7),
    minutos_por_treino  smallint CHECK (minutos_por_treino BETWEEN 15 AND 180),
    local_treino        local_treino NOT NULL DEFAULT 'academia',
    refeicoes_por_dia   smallint NOT NULL DEFAULT 4 CHECK (refeicoes_por_dia BETWEEN 2 AND 8),
    observacoes_saude   text,  -- lesões e limitações informadas no cadastro; a IA lê ao montar o treino
    atualizado_em       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE restricao_alimentar (
    id         smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome       varchar(60) NOT NULL UNIQUE,
    descricao  text
);

CREATE TABLE usuario_restricao (
    usuario_id    bigint   NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    restricao_id  smallint NOT NULL REFERENCES restricao_alimentar(id),
    PRIMARY KEY (usuario_id, restricao_id)
);

CREATE TABLE preferencia_notificacao (
    usuario_id              bigint PRIMARY KEY REFERENCES usuario(id) ON DELETE CASCADE,
    lembrete_refeicao       boolean  NOT NULL DEFAULT true,
    minutos_antes_refeicao  smallint NOT NULL DEFAULT 10 CHECK (minutos_antes_refeicao BETWEEN 0 AND 120),
    lembrete_treino         boolean  NOT NULL DEFAULT true,
    horario_treino          time     NOT NULL DEFAULT '08:00',
    lembrete_progresso      boolean  NOT NULL DEFAULT true,
    horario_progresso       time     NOT NULL DEFAULT '21:00',
    dicas_ia                boolean  NOT NULL DEFAULT true
);

-- LGPD: cada aceite ou revogação vira uma linha nova (histórico auditável)
CREATE TABLE consentimento (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id     bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    tipo           tipo_consentimento NOT NULL,
    versao         varchar(10) NOT NULL,
    aceito         boolean NOT NULL,
    registrado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX consentimento_usuario_tipo_idx ON consentimento (usuario_id, tipo, registrado_em DESC);

-- ---------------------------------------------------------------------
-- 3. Progresso (telas Registrar Progresso e Evolução)
-- ---------------------------------------------------------------------
CREATE TABLE registro_progresso (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id   bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    data         date   NOT NULL DEFAULT current_date,
    peso_kg      numeric(5,1) NOT NULL CHECK (peso_kg BETWEEN 30 AND 300),
    gordura_pct  numeric(4,1) CHECK (gordura_pct BETWEEN 3 AND 70),
    cintura_cm   numeric(5,1) CHECK (cintura_cm BETWEEN 40 AND 200),
    quadril_cm   numeric(5,1) CHECK (quadril_cm BETWEEN 40 AND 200),
    braco_cm     numeric(4,1) CHECK (braco_cm BETWEEN 15 AND 70),
    humor        smallint CHECK (humor BETWEEN 1 AND 5),
    treinou      boolean,                                                   -- "Treinou hoje?"
    seguiu_dieta varchar(10) CHECK (seguiu_dieta IN ('completa', 'parcial', 'nao')), -- "Seguiu a dieta?"
    observacao   text,
    criado_em    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (usuario_id, data)   -- um registro por dia; o app faz upsert
);

-- ---------------------------------------------------------------------
-- 4. Alimentação (tela Plano Alimentar)
-- ---------------------------------------------------------------------
CREATE TABLE alimento (
    id                int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome              varchar(120) NOT NULL UNIQUE,
    kcal_100g         numeric(6,1) NOT NULL CHECK (kcal_100g >= 0),
    proteina_100g     numeric(5,1) NOT NULL CHECK (proteina_100g >= 0),
    carboidrato_100g  numeric(5,1) NOT NULL CHECK (carboidrato_100g >= 0),
    gordura_100g      numeric(5,1) NOT NULL CHECK (gordura_100g >= 0),
    fibra_100g        numeric(5,1) NOT NULL DEFAULT 0 CHECK (fibra_100g >= 0),
    fonte             varchar(40)  NOT NULL DEFAULT 'TACO, aproximado'
);

-- Alimentos que violam uma restrição (ex.: frango x vegetariano)
CREATE TABLE alimento_conflito (
    alimento_id   int      NOT NULL REFERENCES alimento(id) ON DELETE CASCADE,
    restricao_id  smallint NOT NULL REFERENCES restricao_alimentar(id) ON DELETE CASCADE,
    PRIMARY KEY (alimento_id, restricao_id)
);

CREATE TABLE plano_alimentar (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id          bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    titulo              varchar(80) NOT NULL,
    meta_kcal           int NOT NULL CHECK (meta_kcal BETWEEN 1000 AND 6000),
    meta_proteina_g     int NOT NULL CHECK (meta_proteina_g > 0),
    meta_carboidrato_g  int NOT NULL CHECK (meta_carboidrato_g >= 0),
    meta_gordura_g      int NOT NULL CHECK (meta_gordura_g > 0),
    status              status_plano NOT NULL DEFAULT 'ativo',
    inicio              date NOT NULL DEFAULT current_date,
    fim                 date,
    gerado_por_ia       boolean NOT NULL DEFAULT true,
    modelo_ia           varchar(60),
    criado_em           timestamptz NOT NULL DEFAULT now(),
    CHECK (fim IS NULL OR fim >= inicio),
    CHECK (status = 'ativo' OR fim IS NOT NULL)
);
-- no máximo um plano alimentar ativo por usuário
CREATE UNIQUE INDEX plano_alimentar_um_ativo_uk ON plano_alimentar (usuario_id) WHERE status = 'ativo';

CREATE TABLE refeicao (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plano_id  bigint NOT NULL REFERENCES plano_alimentar(id) ON DELETE CASCADE,
    nome      varchar(40) NOT NULL,
    horario   time NOT NULL,
    ordem     smallint NOT NULL CHECK (ordem BETWEEN 1 AND 8),
    UNIQUE (plano_id, ordem)
);

CREATE TABLE refeicao_item (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    refeicao_id     bigint NOT NULL REFERENCES refeicao(id) ON DELETE CASCADE,
    alimento_id     int    NOT NULL REFERENCES alimento(id),
    quantidade_g    numeric(6,1) NOT NULL CHECK (quantidade_g > 0 AND quantidade_g <= 2000),
    medida_caseira  varchar(40),  -- "2 colheres de sopa", mostrado no app
    UNIQUE (refeicao_id, alimento_id)
);

-- check de refeição feita (um por refeição por dia)
CREATE TABLE refeicao_consumida (
    refeicao_id   bigint NOT NULL REFERENCES refeicao(id) ON DELETE CASCADE,
    data          date   NOT NULL DEFAULT current_date,
    consumida_em  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (refeicao_id, data)
);

-- ---------------------------------------------------------------------
-- 5. Treino (tela Treino)
-- ---------------------------------------------------------------------
CREATE TABLE exercicio (
    id            int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome          varchar(80) NOT NULL UNIQUE,
    grupo         grupo_muscular NOT NULL,
    equipamento   varchar(40) NOT NULL DEFAULT 'peso corporal',
    pode_em_casa  boolean NOT NULL DEFAULT false,
    instrucoes    text,
    video_url     text
);

CREATE TABLE plano_treino (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id     bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    titulo         varchar(80) NOT NULL,
    divisao        varchar(20) NOT NULL,  -- ABCD, AB, Full body...
    status         status_plano NOT NULL DEFAULT 'ativo',
    inicio         date NOT NULL DEFAULT current_date,
    fim            date,
    gerado_por_ia  boolean NOT NULL DEFAULT true,
    modelo_ia      varchar(60),
    criado_em      timestamptz NOT NULL DEFAULT now(),
    CHECK (fim IS NULL OR fim >= inicio),
    CHECK (status = 'ativo' OR fim IS NOT NULL)
);
CREATE UNIQUE INDEX plano_treino_um_ativo_uk ON plano_treino (usuario_id) WHERE status = 'ativo';

CREATE TABLE treino_dia (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plano_treino_id  bigint NOT NULL REFERENCES plano_treino(id) ON DELETE CASCADE,
    dia_semana       smallint NOT NULL CHECK (dia_semana BETWEEN 0 AND 6), -- 0 = domingo, igual a EXTRACT(DOW)
    nome             varchar(60) NOT NULL,
    descanso         boolean NOT NULL DEFAULT false,
    UNIQUE (plano_treino_id, dia_semana)
);

CREATE TABLE treino_exercicio (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    treino_dia_id      bigint NOT NULL REFERENCES treino_dia(id) ON DELETE CASCADE,
    exercicio_id       int    NOT NULL REFERENCES exercicio(id),
    ordem              smallint NOT NULL CHECK (ordem BETWEEN 1 AND 20),
    series             smallint NOT NULL CHECK (series BETWEEN 1 AND 10),
    repeticoes_min     smallint CHECK (repeticoes_min BETWEEN 1 AND 100),
    repeticoes_max     smallint CHECK (repeticoes_max BETWEEN 1 AND 100),
    duracao_seg        smallint CHECK (duracao_seg BETWEEN 5 AND 3600),  -- prancha, cardio
    carga_sugerida_kg  numeric(5,1) CHECK (carga_sugerida_kg >= 0),
    descanso_seg       smallint NOT NULL DEFAULT 60 CHECK (descanso_seg BETWEEN 0 AND 600),
    CHECK (repeticoes_max >= repeticoes_min),
    -- ou é por repetição (faixa completa) ou é por tempo
    CHECK ((repeticoes_min IS NOT NULL AND repeticoes_max IS NOT NULL AND duracao_seg IS NULL)
        OR (repeticoes_min IS NULL AND repeticoes_max IS NULL AND duracao_seg IS NOT NULL)),
    UNIQUE (treino_dia_id, ordem)
);

-- histórico de execução: sobrevive à troca de plano
CREATE TABLE sessao_treino (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id         bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    treino_dia_id      bigint REFERENCES treino_dia(id) ON DELETE SET NULL,
    data               date NOT NULL DEFAULT current_date,
    iniciada_em        timestamptz NOT NULL DEFAULT now(),
    concluida_em       timestamptz,
    esforco_percebido  smallint CHECK (esforco_percebido BETWEEN 1 AND 10),
    CHECK (concluida_em IS NULL OR concluida_em >= iniciada_em)
);
CREATE INDEX sessao_treino_usuario_data_idx ON sessao_treino (usuario_id, data);

CREATE TABLE serie_executada (
    sessao_id     bigint   NOT NULL REFERENCES sessao_treino(id) ON DELETE CASCADE,
    exercicio_id  int      NOT NULL REFERENCES exercicio(id),
    numero        smallint NOT NULL CHECK (numero BETWEEN 1 AND 10),
    repeticoes    smallint CHECK (repeticoes BETWEEN 0 AND 100),
    duracao_seg   smallint CHECK (duracao_seg BETWEEN 1 AND 3600),
    carga_kg      numeric(5,1) CHECK (carga_kg >= 0),
    CHECK (repeticoes IS NOT NULL OR duracao_seg IS NOT NULL),
    PRIMARY KEY (sessao_id, exercicio_id, numero)
);

-- ---------------------------------------------------------------------
-- 6. Chatbot (tela Chatbot)
-- ---------------------------------------------------------------------
CREATE TABLE conversa (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id     bigint NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    titulo         varchar(120),
    criada_em      timestamptz NOT NULL DEFAULT now(),
    atualizada_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX conversa_usuario_idx ON conversa (usuario_id, atualizada_em DESC);

CREATE TABLE mensagem (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversa_id  bigint NOT NULL REFERENCES conversa(id) ON DELETE CASCADE,
    papel        papel_mensagem NOT NULL,
    conteudo     text NOT NULL CHECK (length(conteudo) BETWEEN 1 AND 20000),
    tokens       int CHECK (tokens >= 0),
    modelo_ia    varchar(60),
    criada_em    timestamptz NOT NULL DEFAULT now(),
    CHECK (papel <> 'assistente' OR modelo_ia IS NOT NULL)
);
CREATE INDEX mensagem_conversa_idx ON mensagem (conversa_id, criada_em);

-- ---------------------------------------------------------------------
-- 7. Funções de cálculo (Cadastro, Dashboard, Evolução)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_idade(p_nascimento date, p_ref date DEFAULT current_date)
RETURNS int LANGUAGE sql STABLE AS $$
    SELECT date_part('year', age(p_ref, p_nascimento))::int;
$$;

CREATE FUNCTION fn_imc(p_peso_kg numeric, p_altura_cm numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT round(p_peso_kg / power(p_altura_cm / 100.0, 2), 1);
$$;

-- Taxa metabólica basal, fórmula de Mifflin-St Jeor (kcal/dia)
CREATE FUNCTION fn_tmb(p_peso_kg numeric, p_altura_cm numeric, p_idade int, p_sexo sexo_biologico)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT round(10 * p_peso_kg + 6.25 * p_altura_cm - 5 * p_idade
                 + CASE p_sexo WHEN 'masculino' THEN 5 ELSE -161 END)::int;
$$;

CREATE FUNCTION fn_fator_atividade(p_nivel nivel_atividade)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_nivel
        WHEN 'sedentario'    THEN 1.2
        WHEN 'leve'          THEN 1.375
        WHEN 'moderado'      THEN 1.55
        WHEN 'intenso'       THEN 1.725
        WHEN 'muito_intenso' THEN 1.9
    END;
$$;

-- Meta calórica sugerida para o MVP: gasto diário ajustado pelo objetivo
CREATE FUNCTION fn_meta_kcal_sugerida(p_gasto_diario int, p_objetivo objetivo_fit)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT (round(p_gasto_diario * CASE p_objetivo
        WHEN 'perder_gordura' THEN 0.80
        WHEN 'ganhar_massa'   THEN 1.10
        ELSE 1.00 END / 50.0) * 50)::int;   -- arredonda para múltiplos de 50
$$;

-- Dias seguidos com alguma atividade (progresso, treino concluído ou refeição marcada),
-- contando até hoje; se hoje ainda não teve atividade, conta até ontem.
CREATE FUNCTION fn_sequencia_dias(p_usuario_id bigint)
RETURNS int LANGUAGE sql STABLE AS $$
    WITH dias AS (
        SELECT data FROM registro_progresso WHERE usuario_id = p_usuario_id
        UNION
        SELECT data FROM sessao_treino WHERE usuario_id = p_usuario_id AND concluida_em IS NOT NULL
        UNION
        SELECT rc.data
        FROM refeicao_consumida rc
        JOIN refeicao r        ON r.id = rc.refeicao_id
        JOIN plano_alimentar p ON p.id = r.plano_id
        WHERE p.usuario_id = p_usuario_id
    ),
    ilhas AS (
        SELECT data, data - (row_number() OVER (ORDER BY data))::int AS grupo
        FROM dias
        WHERE data <= current_date
    )
    SELECT COALESCE((
        SELECT count(*)::int
        FROM ilhas
        WHERE grupo = (SELECT grupo FROM ilhas ORDER BY data DESC LIMIT 1)
          AND (SELECT max(data) FROM ilhas) >= current_date - 1
    ), 0);
$$;

-- Login: devolve o id se e-mail e senha conferem (senha comparada pelo hash bcrypt)
CREATE FUNCTION fn_autenticar(p_email text, p_senha text)
RETURNS bigint LANGUAGE plpgsql
SET search_path = iafit, public, extensions   -- "extensions" é onde o Supabase instala o pgcrypto
AS $$
DECLARE
    v_id bigint;
BEGIN
    SELECT id INTO v_id
    FROM usuario
    WHERE lower(email) = lower(p_email)
      AND senha_hash = crypt(p_senha, senha_hash);

    IF v_id IS NOT NULL THEN
        UPDATE usuario SET ultimo_login_em = now() WHERE id = v_id;
    END IF;
    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 8. Regras de negócio em triggers
-- ---------------------------------------------------------------------

-- 8.1 atualizado_em automático
CREATE FUNCTION trg_set_atualizado_em() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.atualizado_em := now();
    RETURN NEW;
END;
$$;
CREATE TRIGGER usuario_atualizado_em BEFORE UPDATE ON usuario
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER perfil_atualizado_em BEFORE UPDATE ON perfil
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();

-- 8.2 Plano novo encerra o plano ativo anterior (alimentar e treino)
CREATE FUNCTION trg_encerrar_plano_anterior() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'ativo' THEN
        EXECUTE format(
            'UPDATE %I.%I SET status = ''encerrado'', fim = GREATEST(inicio, $1 - 1)
              WHERE usuario_id = $2 AND status = ''ativo''',
            TG_TABLE_SCHEMA, TG_TABLE_NAME)
        USING NEW.inicio, NEW.usuario_id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER plano_alimentar_encerra_anterior BEFORE INSERT ON plano_alimentar
    FOR EACH ROW EXECUTE FUNCTION trg_encerrar_plano_anterior();
CREATE TRIGGER plano_treino_encerra_anterior BEFORE INSERT ON plano_treino
    FOR EACH ROW EXECUTE FUNCTION trg_encerrar_plano_anterior();

-- 8.3 Item de refeição não pode violar restrição alimentar do dono do plano
--     (protege contra a IA sugerir frango para quem é vegetariano)
CREATE FUNCTION trg_item_respeita_restricao() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_restricao text;
    v_alimento  text;
BEGIN
    SELECT ra.nome, a.nome INTO v_restricao, v_alimento
    FROM refeicao r
    JOIN plano_alimentar p     ON p.id = r.plano_id
    JOIN usuario_restricao ur  ON ur.usuario_id = p.usuario_id
    JOIN alimento_conflito ac  ON ac.restricao_id = ur.restricao_id AND ac.alimento_id = NEW.alimento_id
    JOIN restricao_alimentar ra ON ra.id = ur.restricao_id
    JOIN alimento a            ON a.id = NEW.alimento_id
    WHERE r.id = NEW.refeicao_id
    LIMIT 1;

    IF v_restricao IS NOT NULL THEN
        RAISE EXCEPTION 'O alimento "%" viola a restrição "%" do usuário', v_alimento, v_restricao
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER refeicao_item_restricao BEFORE INSERT OR UPDATE OF alimento_id, refeicao_id ON refeicao_item
    FOR EACH ROW EXECUTE FUNCTION trg_item_respeita_restricao();

-- 8.4 Dia de descanso não recebe exercício
CREATE FUNCTION trg_exercicio_fora_do_descanso() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM treino_dia WHERE id = NEW.treino_dia_id AND descanso) THEN
        RAISE EXCEPTION 'Dia de descanso não recebe exercícios (treino_dia %)', NEW.treino_dia_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER treino_exercicio_descanso BEFORE INSERT OR UPDATE OF treino_dia_id ON treino_exercicio
    FOR EACH ROW EXECUTE FUNCTION trg_exercicio_fora_do_descanso();

-- 8.5 Mensagem nova atualiza a conversa (lista do chat ordena pela última)
CREATE FUNCTION trg_conversa_atualizada() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE conversa SET atualizada_em = NEW.criada_em WHERE id = NEW.conversa_id;
    RETURN NEW;
END;
$$;
CREATE TRIGGER mensagem_atualiza_conversa AFTER INSERT ON mensagem
    FOR EACH ROW EXECUTE FUNCTION trg_conversa_atualizada();

-- ---------------------------------------------------------------------
-- 9. Views usadas pelas telas
-- ---------------------------------------------------------------------

-- Peso mais recente de cada usuário
CREATE VIEW vw_peso_atual AS
SELECT DISTINCT ON (usuario_id)
       usuario_id, data, peso_kg, gordura_pct, cintura_cm
FROM registro_progresso
ORDER BY usuario_id, data DESC;

-- Calorias e macros de cada refeição (somando os itens)
CREATE VIEW vw_macros_refeicao AS
SELECT r.id AS refeicao_id, r.plano_id, r.nome, r.horario, r.ordem,
       round(sum(i.quantidade_g * a.kcal_100g        / 100))    AS kcal,
       round(sum(i.quantidade_g * a.proteina_100g    / 100), 1) AS proteina_g,
       round(sum(i.quantidade_g * a.carboidrato_100g / 100), 1) AS carboidrato_g,
       round(sum(i.quantidade_g * a.gordura_100g     / 100), 1) AS gordura_g
FROM refeicao r
JOIN refeicao_item i ON i.refeicao_id = r.id
JOIN alimento a      ON a.id = i.alimento_id
GROUP BY r.id;

-- Total do plano x meta: confere se o plano gerado pela IA bate com o que prometeu
CREATE VIEW vw_macros_plano AS
SELECT p.id AS plano_id, p.usuario_id, p.titulo, p.status,
       p.meta_kcal, sum(m.kcal)::int AS total_kcal,
       round(100.0 * sum(m.kcal) / p.meta_kcal, 1) AS pct_kcal,
       p.meta_proteina_g,    sum(m.proteina_g)    AS total_proteina_g,
       p.meta_carboidrato_g, sum(m.carboidrato_g) AS total_carboidrato_g,
       p.meta_gordura_g,     sum(m.gordura_g)     AS total_gordura_g
FROM plano_alimentar p
JOIN vw_macros_refeicao m ON m.plano_id = p.id
GROUP BY p.id;

-- Consentimento vigente (último registro de cada tipo)
CREATE VIEW vw_consentimento_atual AS
SELECT DISTINCT ON (usuario_id, tipo)
       usuario_id, tipo, versao, aceito, registrado_em
FROM consentimento
ORDER BY usuario_id, tipo, registrado_em DESC, id DESC;

-- Tudo que o Dashboard mostra, numa linha por usuário
CREATE VIEW vw_dashboard AS
SELECT u.id AS usuario_id,
       u.nome,
       fn_idade(u.data_nascimento)                                      AS idade,
       pa.peso_kg                                                       AS peso_atual_kg,
       pf.peso_meta_kg,
       abs(round(pa.peso_kg - pf.peso_meta_kg, 1))                      AS falta_kg,
       fn_imc(pa.peso_kg, pf.altura_cm)                                 AS imc,
       fn_tmb(pa.peso_kg, pf.altura_cm, fn_idade(u.data_nascimento), u.sexo) AS tmb_kcal,
       round(fn_tmb(pa.peso_kg, pf.altura_cm, fn_idade(u.data_nascimento), u.sexo)
             * fn_fator_atividade(pf.nivel_atividade))::int             AS gasto_diario_kcal,
       pl.meta_kcal,
       COALESCE((SELECT sum(m.kcal)
                 FROM refeicao_consumida rc
                 JOIN vw_macros_refeicao m ON m.refeicao_id = rc.refeicao_id
                 WHERE m.plano_id = pl.id AND rc.data = current_date), 0)::int AS kcal_hoje,
       td.nome                                                          AS treino_hoje,
       COALESCE(td.descanso, true)                                      AS descanso_hoje,
       fn_sequencia_dias(u.id)                                          AS sequencia_dias
FROM usuario u
JOIN perfil pf               ON pf.usuario_id = u.id
LEFT JOIN vw_peso_atual pa   ON pa.usuario_id = u.id
LEFT JOIN plano_alimentar pl ON pl.usuario_id = u.id AND pl.status = 'ativo'
LEFT JOIN plano_treino pt    ON pt.usuario_id = u.id AND pt.status = 'ativo'
LEFT JOIN treino_dia td      ON td.plano_treino_id = pt.id
                            AND td.dia_semana = EXTRACT(DOW FROM current_date);

-- Peso médio por semana (gráfico da tela Evolução)
CREATE VIEW vw_evolucao_semanal AS
SELECT usuario_id,
       date_trunc('week', data)::date AS semana,
       round(avg(peso_kg), 1)         AS peso_medio_kg,
       round(avg(cintura_cm), 1)      AS cintura_media_cm,
       count(*)                       AS registros
FROM registro_progresso
GROUP BY usuario_id, date_trunc('week', data);

-- ---------------------------------------------------------------------
-- 10. LGPD e contexto da IA
-- ---------------------------------------------------------------------

-- Exportação completa dos dados do titular (Perfil > Baixar meus dados)
CREATE FUNCTION fn_exportar_dados(p_usuario_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
    'usuario', (SELECT to_jsonb(u) - 'senha_hash' FROM usuario u WHERE u.id = p_usuario_id),
    'perfil', (SELECT to_jsonb(p) FROM perfil p WHERE p.usuario_id = p_usuario_id),
    'restricoes', (SELECT COALESCE(jsonb_agg(ra.nome ORDER BY ra.nome), '[]')
                   FROM usuario_restricao ur JOIN restricao_alimentar ra ON ra.id = ur.restricao_id
                   WHERE ur.usuario_id = p_usuario_id),
    'notificacoes', (SELECT to_jsonb(n) FROM preferencia_notificacao n WHERE n.usuario_id = p_usuario_id),
    'consentimentos', (SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.registrado_em), '[]')
                       FROM consentimento c WHERE c.usuario_id = p_usuario_id),
    'progresso', (SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.data), '[]')
                  FROM registro_progresso r WHERE r.usuario_id = p_usuario_id),
    'planos_alimentares', (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.inicio), '[]')
                           FROM plano_alimentar p WHERE p.usuario_id = p_usuario_id),
    'planos_treino', (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.inicio), '[]')
                      FROM plano_treino p WHERE p.usuario_id = p_usuario_id),
    'sessoes_treino', (SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.data), '[]')
                       FROM sessao_treino s WHERE s.usuario_id = p_usuario_id),
    'conversas', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'titulo', c.titulo,
                        'criada_em', c.criada_em,
                        'mensagens', (SELECT jsonb_agg(jsonb_build_object(
                                          'papel', m.papel, 'conteudo', m.conteudo, 'criada_em', m.criada_em)
                                          ORDER BY m.criada_em)
                                      FROM mensagem m WHERE m.conversa_id = c.id))
                        ORDER BY c.criada_em), '[]')
                  FROM conversa c WHERE c.usuario_id = p_usuario_id),
    'exportado_em', now()
);
$$;

-- Resumo do usuário que o backend envia junto com a pergunta para a IA do chatbot
CREATE FUNCTION fn_contexto_ia(p_usuario_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
    'nome', d.nome,
    'idade', d.idade,
    'sexo', u.sexo,
    'altura_cm', pf.altura_cm,
    'peso_atual_kg', d.peso_atual_kg,
    'peso_meta_kg', d.peso_meta_kg,
    'objetivo', pf.objetivo,
    'nivel_atividade', pf.nivel_atividade,
    'experiencia', pf.experiencia,
    'local_treino', pf.local_treino,
    'observacoes_saude', pf.observacoes_saude,
    'restricoes', (SELECT COALESCE(jsonb_agg(ra.nome), '[]')
                   FROM usuario_restricao ur JOIN restricao_alimentar ra ON ra.id = ur.restricao_id
                   WHERE ur.usuario_id = u.id),
    'meta_kcal', d.meta_kcal,
    'gasto_diario_kcal', d.gasto_diario_kcal,
    'treino_hoje', d.treino_hoje,
    'usa_dados_para_treinar_ia', COALESCE((SELECT aceito FROM vw_consentimento_atual
                                           WHERE usuario_id = u.id AND tipo = 'uso_anonimo_ia'), false)
)
FROM usuario u
JOIN perfil pf      ON pf.usuario_id = u.id
JOIN vw_dashboard d ON d.usuario_id = u.id
WHERE u.id = p_usuario_id;
$$;

COMMIT;
