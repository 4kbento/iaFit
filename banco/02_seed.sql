-- =====================================================================
-- iaFit: dados de exemplo
-- Rodar depois do 01_schema.sql:  psql -d iafit -f sql/02_seed.sql
--
-- As datas são relativas a current_date, então o Dashboard, a sequência
-- de dias e o "treino de hoje" sempre aparecem preenchidos, em qualquer dia
-- em que o professor rodar o script.
-- Usuários fictícios. Senha de todos: Senha@123
-- Valores nutricionais aproximados (TACO/USDA), só para demonstração.
-- =====================================================================

BEGIN;
SET search_path TO iafit, public, extensions;

-- ---------------------------------------------------------------------
-- Catálogos
-- ---------------------------------------------------------------------
INSERT INTO restricao_alimentar (nome, descricao) VALUES
    ('Vegetariano',          'Não come carne, frango, peixe nem frutos do mar'),
    ('Vegano',               'Não consome nenhum produto de origem animal'),
    ('Sem lactose',          'Intolerância à lactose'),
    ('Sem glúten',           'Doença celíaca ou sensibilidade ao glúten'),
    ('Alergia a amendoim',   'Evitar amendoim e derivados'),
    ('Sem frutos do mar',    'Alergia a crustáceos e moluscos');

INSERT INTO alimento (nome, kcal_100g, proteina_100g, carboidrato_100g, gordura_100g, fibra_100g, fonte) VALUES
    ('Arroz branco cozido',          128,  2.5, 28.1,   0.2, 1.6, 'TACO, aproximado'),
    ('Arroz integral cozido',        124,  2.6, 25.8,   1.0, 2.7, 'TACO, aproximado'),
    ('Feijão carioca cozido',         76,  4.8, 13.6,   0.5, 8.5, 'TACO, aproximado'),
    ('Peito de frango grelhado',     159, 32.0,  0.0,   2.5, 0.0, 'TACO, aproximado'),
    ('Patinho moído refogado',       219, 35.9,  0.0,   7.3, 0.0, 'TACO, aproximado'),
    ('Filé de tilápia grelhado',     128, 26.2,  0.0,   2.7, 0.0, 'USDA, aproximado'),
    ('Camarão cozido',                90, 19.0,  0.0,   1.0, 0.0, 'TACO, aproximado'),
    ('Ovo de galinha cozido',        146, 13.3,  0.6,   9.5, 0.0, 'TACO, aproximado'),
    ('Pão francês',                  300,  8.0, 58.6,   3.1, 2.3, 'TACO, aproximado'),
    ('Pão integral',                 253,  9.4, 49.9,   3.7, 6.9, 'TACO, aproximado'),
    ('Aveia em flocos',              394, 13.9, 66.6,   8.5, 9.1, 'TACO, aproximado'),
    ('Banana prata',                  98,  1.3, 26.0,   0.1, 2.0, 'TACO, aproximado'),
    ('Maçã',                          56,  0.3, 15.2,   0.0, 1.3, 'TACO, aproximado'),
    ('Mamão papaia',                  40,  0.5, 10.4,   0.1, 1.0, 'TACO, aproximado'),
    ('Leite desnatado',               35,  3.4,  4.9,   0.1, 0.0, 'TACO, aproximado'),
    ('Iogurte natural desnatado',     41,  3.8,  5.8,   0.3, 0.0, 'TACO, aproximado'),
    ('Queijo minas frescal',         264, 17.4,  3.2,  20.2, 0.0, 'TACO, aproximado'),
    ('Whey protein concentrado',     400, 80.0,  8.0,   6.0, 0.0, 'rótulo médio'),
    ('Batata-doce cozida',            77,  0.6, 18.4,   0.1, 2.2, 'TACO, aproximado'),
    ('Mandioca cozida',              125,  0.6, 30.1,   0.3, 1.6, 'TACO, aproximado'),
    ('Cuscuz de milho cozido',       113,  2.2, 25.3,   0.7, 2.1, 'TACO, aproximado'),
    ('Grão-de-bico cozido',          164,  8.9, 27.4,   2.6, 7.6, 'USDA, aproximado'),
    ('Brócolis cozido',               25,  2.1,  4.4,   0.5, 3.4, 'TACO, aproximado'),
    ('Alface crespa',                 11,  1.3,  1.7,   0.2, 1.8, 'TACO, aproximado'),
    ('Tomate',                        15,  1.1,  3.1,   0.2, 1.2, 'TACO, aproximado'),
    ('Azeite de oliva',              884,  0.0,  0.0, 100.0, 0.0, 'TACO, aproximado'),
    ('Pasta de amendoim',            588, 25.0, 20.0,  50.0, 6.0, 'rótulo médio'),
    ('Castanha-do-pará',             643, 14.5, 15.1,  63.5, 7.9, 'TACO, aproximado');

-- Quais alimentos violam quais restrições
INSERT INTO alimento_conflito (alimento_id, restricao_id)
SELECT a.id, r.id
FROM (VALUES
    ('Peito de frango grelhado',  'Vegetariano'), ('Patinho moído refogado',   'Vegetariano'),
    ('Filé de tilápia grelhado',  'Vegetariano'), ('Camarão cozido',           'Vegetariano'),
    ('Peito de frango grelhado',  'Vegano'),      ('Patinho moído refogado',   'Vegano'),
    ('Filé de tilápia grelhado',  'Vegano'),      ('Camarão cozido',           'Vegano'),
    ('Ovo de galinha cozido',     'Vegano'),      ('Leite desnatado',          'Vegano'),
    ('Iogurte natural desnatado', 'Vegano'),      ('Queijo minas frescal',     'Vegano'),
    ('Whey protein concentrado',  'Vegano'),
    ('Leite desnatado',           'Sem lactose'), ('Iogurte natural desnatado','Sem lactose'),
    ('Queijo minas frescal',      'Sem lactose'), ('Whey protein concentrado', 'Sem lactose'),
    ('Pão francês',               'Sem glúten'),  ('Pão integral',             'Sem glúten'),
    ('Aveia em flocos',           'Sem glúten'),
    ('Pasta de amendoim',         'Alergia a amendoim'),
    ('Camarão cozido',            'Sem frutos do mar')
) v(alimento, restricao)
JOIN alimento a ON a.nome = v.alimento
JOIN restricao_alimentar r ON r.nome = v.restricao;

INSERT INTO exercicio (nome, grupo, equipamento, pode_em_casa, instrucoes) VALUES
    ('Supino reto com barra',         'peito',      'barra',          false, 'Desça a barra até o meio do peito, cotovelos a 45 graus.'),
    ('Supino inclinado com halteres', 'peito',      'halteres',       false, 'Banco a 30 graus; empurre sem bater os halteres no topo.'),
    ('Crucifixo com halteres',        'peito',      'halteres',       false, 'Braços levemente flexionados durante todo o movimento.'),
    ('Flexão de braço',               'peito',      'peso corporal',  true,  'Corpo alinhado da cabeça ao calcanhar; joelhos no chão se precisar.'),
    ('Puxada frontal',                'costas',     'máquina',        false, 'Puxe a barra até o queixo levando os cotovelos para baixo.'),
    ('Remada curvada com barra',      'costas',     'barra',          false, 'Tronco inclinado, coluna neutra, barra em direção ao umbigo.'),
    ('Remada unilateral com halter',  'costas',     'halteres',       false, 'Apoie joelho e mão no banco; puxe o halter rente ao corpo.'),
    ('Desenvolvimento com halteres',  'ombros',     'halteres',       false, 'Sentado, empurre os halteres acima da cabeça sem travar os cotovelos.'),
    ('Elevação lateral',              'ombros',     'halteres',       false, 'Suba até a altura dos ombros, cotovelos levemente flexionados.'),
    ('Rosca direta com barra',        'biceps',     'barra',          false, 'Cotovelos colados ao corpo, sem balançar o tronco.'),
    ('Rosca martelo',                 'biceps',     'halteres',       false, 'Pegada neutra, palmas viradas uma para a outra.'),
    ('Tríceps na polia',              'triceps',    'polia',          false, 'Cotovelos parados ao lado do corpo; estenda até o fim.'),
    ('Tríceps francês',               'triceps',    'halteres',       false, 'Halter atrás da cabeça, cotovelos apontando para cima.'),
    ('Agachamento livre',             'pernas',     'barra',          false, 'Desça até as coxas ficarem paralelas ao chão, joelhos alinhados aos pés.'),
    ('Agachamento com peso corporal', 'pernas',     'peso corporal',  true,  'Quadril para trás como se fosse sentar, calcanhares no chão.'),
    ('Leg press 45',                  'pernas',     'máquina',        false, 'Não deixe o quadril sair do banco na descida.'),
    ('Cadeira extensora',             'pernas',     'máquina',        false, 'Segure 1 segundo com as pernas estendidas.'),
    ('Mesa flexora',                  'pernas',     'máquina',        false, 'Quadril colado ao banco durante todo o movimento.'),
    ('Elevação pélvica',              'gluteos',    'peso corporal ou barra', true, 'Costas apoiadas no banco ou no chão; suba o quadril contraindo o glúteo.'),
    ('Prancha',                       'abdomen',    'peso corporal',  true,  'Apoio nos antebraços, corpo reto, abdômen contraído.'),
    ('Abdominal crunch',              'abdomen',    'peso corporal',  true,  'Tire só as escápulas do chão; não puxe o pescoço.'),
    ('Esteira caminhada inclinada',   'cardio',     'esteira',        false, 'Inclinação entre 8 e 12 por cento, ritmo em que ainda dá para conversar.'),
    ('Polichinelo',                   'cardio',     'peso corporal',  true,  'Ritmo constante, aterrissando na ponta dos pés.'),
    ('Burpee',                        'corpo_todo', 'peso corporal',  true,  'Agacha, prancha, volta e salta; adapte sem o salto se precisar.');

-- ---------------------------------------------------------------------
-- Usuários (Cadastro)
-- ---------------------------------------------------------------------
INSERT INTO usuario (nome, email, senha_hash, data_nascimento, sexo) VALUES
    ('Lucas Andrade',  'lucas.andrade@exemplo.com',  crypt('Senha@123', gen_salt('bf', 8)), '1999-03-14', 'masculino'),
    ('Mariana Costa',  'mariana.costa@exemplo.com',  crypt('Senha@123', gen_salt('bf', 8)), '2002-08-22', 'feminino'),
    ('Rafael Souza',   'rafael.souza@exemplo.com',   crypt('Senha@123', gen_salt('bf', 8)), '1995-11-02', 'masculino');

INSERT INTO perfil (usuario_id, altura_cm, peso_meta_kg, objetivo, nivel_atividade, experiencia,
                    dias_treino_semana, minutos_por_treino, local_treino, refeicoes_por_dia, observacoes_saude)
SELECT u.id, v.altura, v.meta, v.objetivo::objetivo_fit, v.atividade::nivel_atividade, v.exp::nivel_experiencia,
       v.dias, v.minutos, v.local::local_treino, v.refeicoes, v.obs
FROM (VALUES
    ('lucas.andrade@exemplo.com',  178.0, 78.0, 'perder_gordura', 'moderado',   'intermediario', 4, 60, 'academia', 5,
        'Desconforto leve no ombro direito com supino muito pesado'),
    ('mariana.costa@exemplo.com',  163.0, 58.0, 'ganhar_massa',   'leve',       'iniciante',     3, 40, 'casa',     4, NULL),
    ('rafael.souza@exemplo.com',   172.0, 72.0, 'manter_peso',    'sedentario', 'iniciante',     3, 45, 'academia', 4,
        'Cirurgia de menisco no joelho esquerdo em 2021')
) v(email, altura, meta, objetivo, atividade, exp, dias, minutos, local, refeicoes, obs)
JOIN usuario u ON u.email = v.email;

INSERT INTO usuario_restricao (usuario_id, restricao_id)
SELECT u.id, r.id
FROM (VALUES ('mariana.costa@exemplo.com', 'Vegetariano'),
             ('rafael.souza@exemplo.com',  'Sem lactose')) v(email, restricao)
JOIN usuario u ON u.email = v.email
JOIN restricao_alimentar r ON r.nome = v.restricao;

INSERT INTO preferencia_notificacao (usuario_id, lembrete_refeicao, horario_treino, dicas_ia)
SELECT u.id, v.lembrete_refeicao, v.horario_treino::time, v.dicas
FROM (VALUES ('lucas.andrade@exemplo.com', true,  '06:30', true),
             ('mariana.costa@exemplo.com', true,  '18:30', false),
             ('rafael.souza@exemplo.com',  false, '08:00', true)) v(email, lembrete_refeicao, horario_treino, dicas)
JOIN usuario u ON u.email = v.email;

-- Consentimentos LGPD (Lucas aceitou e depois revogou o uso anônimo para a IA)
INSERT INTO consentimento (usuario_id, tipo, versao, aceito, registrado_em)
SELECT u.id, v.tipo::tipo_consentimento, '1.0', v.aceito, now() - (v.dias_atras || ' days')::interval
FROM (VALUES
    ('lucas.andrade@exemplo.com',  'termos_uso',           true,  60),
    ('lucas.andrade@exemplo.com',  'politica_privacidade', true,  60),
    ('lucas.andrade@exemplo.com',  'uso_anonimo_ia',       true,  60),
    ('lucas.andrade@exemplo.com',  'uso_anonimo_ia',       false, 12),
    ('mariana.costa@exemplo.com',  'termos_uso',           true,  35),
    ('mariana.costa@exemplo.com',  'politica_privacidade', true,  35),
    ('mariana.costa@exemplo.com',  'uso_anonimo_ia',       true,  35),
    ('rafael.souza@exemplo.com',   'termos_uso',           true,   3),
    ('rafael.souza@exemplo.com',   'politica_privacidade', true,   3),
    ('rafael.souza@exemplo.com',   'uso_anonimo_ia',       false,  3)
) v(email, tipo, aceito, dias_atras)
JOIN usuario u ON u.email = v.email;

-- ---------------------------------------------------------------------
-- Progresso (Registrar Progresso e Evolução)
-- ---------------------------------------------------------------------
INSERT INTO registro_progresso (usuario_id, data, peso_kg, cintura_cm, gordura_pct, humor, treinou, seguiu_dieta)
SELECT u.id, current_date - v.dias_atras, v.peso, v.cintura, v.gordura, v.humor,
       v.dias_atras % 2 = 0, CASE WHEN v.humor >= 4 THEN 'completa' ELSE 'parcial' END
FROM (VALUES
    ('lucas.andrade@exemplo.com', 56, 86.4, 94.0, 22.5, 3),
    ('lucas.andrade@exemplo.com', 49, 85.9, 93.5, 22.1, 4),
    ('lucas.andrade@exemplo.com', 42, 85.6, 93.0, 21.8, 3),
    ('lucas.andrade@exemplo.com', 35, 85.0, 92.4, 21.4, 4),
    ('lucas.andrade@exemplo.com', 28, 84.6, 92.0, 21.0, 4),
    ('lucas.andrade@exemplo.com', 21, 84.1, 91.5, 20.6, 5),
    ('lucas.andrade@exemplo.com', 14, 83.8, 91.0, 20.3, 4),
    ('lucas.andrade@exemplo.com',  7, 83.3, 90.6, 19.9, 4),
    ('lucas.andrade@exemplo.com',  0, 82.9, 90.2, 19.6, 5),
    ('mariana.costa@exemplo.com', 28, 52.8, 66.0, NULL, 3),
    ('mariana.costa@exemplo.com', 21, 53.2, 66.2, NULL, 4),
    ('mariana.costa@exemplo.com', 14, 53.6, 66.3, NULL, 4),
    ('mariana.costa@exemplo.com',  7, 54.0, 66.5, NULL, 5),
    ('mariana.costa@exemplo.com',  1, 54.3, 66.6, NULL, 4),
    ('rafael.souza@exemplo.com',   2, 74.0, 86.0, NULL, 3)
) v(email, dias_atras, peso, cintura, gordura, humor)
JOIN usuario u ON u.email = v.email;

-- ---------------------------------------------------------------------
-- Planos alimentares (gerados pela IA)
-- ---------------------------------------------------------------------

-- Plano antigo do Lucas: o trigger encerra este quando o novo entra
INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g,
                             inicio, modelo_ia)
SELECT id, 'Adaptação', 2400, 150, 280, 75, current_date - 58, 'iafit-llm-v1'
FROM usuario WHERE email = 'lucas.andrade@exemplo.com';

-- Lucas: TMB 1812 kcal x 1,55 (moderado) = 2809; déficit de 20% = 2250 kcal
INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g,
                             inicio, modelo_ia)
SELECT id, 'Déficit para perder gordura', 2250, 165, 240, 70, current_date - 30, 'iafit-llm-v1'
FROM usuario WHERE email = 'lucas.andrade@exemplo.com';

-- Mariana: TMB 1283 kcal x 1,375 (leve) = 1764; superávit de 10% = 1950 kcal
INSERT INTO plano_alimentar (usuario_id, titulo, meta_kcal, meta_proteina_g, meta_carboidrato_g, meta_gordura_g,
                             inicio, modelo_ia)
SELECT id, 'Ganho de massa vegetariano', 1950, 100, 252, 60, current_date - 21, 'iafit-llm-v1'
FROM usuario WHERE email = 'mariana.costa@exemplo.com';

INSERT INTO refeicao (plano_id, nome, horario, ordem)
SELECT p.id, v.nome, v.horario::time, v.ordem
FROM (VALUES
    ('lucas.andrade@exemplo.com', 'Café da manhã',    '07:00', 1),
    ('lucas.andrade@exemplo.com', 'Lanche da manhã',  '10:00', 2),
    ('lucas.andrade@exemplo.com', 'Almoço',           '12:30', 3),
    ('lucas.andrade@exemplo.com', 'Lanche da tarde',  '16:00', 4),
    ('lucas.andrade@exemplo.com', 'Jantar',           '20:00', 5),
    ('mariana.costa@exemplo.com', 'Café da manhã',    '07:30', 1),
    ('mariana.costa@exemplo.com', 'Almoço',           '12:30', 2),
    ('mariana.costa@exemplo.com', 'Lanche da tarde',  '16:00', 3),
    ('mariana.costa@exemplo.com', 'Jantar',           '20:00', 4)
) v(email, nome, horario, ordem)
JOIN usuario u ON u.email = v.email
JOIN plano_alimentar p ON p.usuario_id = u.id AND p.status = 'ativo';

INSERT INTO refeicao_item (refeicao_id, alimento_id, quantidade_g, medida_caseira)
SELECT r.id, a.id, v.qtd, v.medida
FROM (VALUES
    -- Lucas
    ('lucas.andrade@exemplo.com', 'Café da manhã',   'Pão integral',              50, '2 fatias'),
    ('lucas.andrade@exemplo.com', 'Café da manhã',   'Ovo de galinha cozido',    100, '2 ovos'),
    ('lucas.andrade@exemplo.com', 'Café da manhã',   'Banana prata',             100, '1 unidade'),
    ('lucas.andrade@exemplo.com', 'Café da manhã',   'Leite desnatado',          200, '1 copo'),
    ('lucas.andrade@exemplo.com', 'Lanche da manhã', 'Iogurte natural desnatado',170, '1 pote'),
    ('lucas.andrade@exemplo.com', 'Lanche da manhã', 'Aveia em flocos',           30, '3 colheres de sopa'),
    ('lucas.andrade@exemplo.com', 'Lanche da manhã', 'Castanha-do-pará',          10, '2 unidades'),
    ('lucas.andrade@exemplo.com', 'Almoço',          'Arroz integral cozido',    170, '5 colheres de sopa'),
    ('lucas.andrade@exemplo.com', 'Almoço',          'Feijão carioca cozido',    100, '1 concha'),
    ('lucas.andrade@exemplo.com', 'Almoço',          'Peito de frango grelhado', 150, '1 filé grande'),
    ('lucas.andrade@exemplo.com', 'Almoço',          'Brócolis cozido',          100, '1 xícara'),
    ('lucas.andrade@exemplo.com', 'Almoço',          'Azeite de oliva',           15, '1 colher de sopa cheia'),
    ('lucas.andrade@exemplo.com', 'Lanche da tarde', 'Whey protein concentrado',  30, '1 scoop'),
    ('lucas.andrade@exemplo.com', 'Lanche da tarde', 'Banana prata',             100, '1 unidade'),
    ('lucas.andrade@exemplo.com', 'Lanche da tarde', 'Pasta de amendoim',         15, '1 colher de sopa'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Arroz branco cozido',      120, '4 colheres de sopa'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Patinho moído refogado',   100, '4 colheres de sopa'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Feijão carioca cozido',     80, '1 concha pequena'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Alface crespa',             50, '1 prato de sobremesa'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Tomate',                    80, '1 unidade média'),
    ('lucas.andrade@exemplo.com', 'Jantar',          'Azeite de oliva',           10, '1 colher de sobremesa'),
    -- Mariana (vegetariana: nenhum item pode violar a restrição, o trigger confere)
    ('mariana.costa@exemplo.com', 'Café da manhã',   'Aveia em flocos',           40, '4 colheres de sopa'),
    ('mariana.costa@exemplo.com', 'Café da manhã',   'Banana prata',             100, '1 unidade'),
    ('mariana.costa@exemplo.com', 'Café da manhã',   'Iogurte natural desnatado',200, '1 pote grande'),
    ('mariana.costa@exemplo.com', 'Café da manhã',   'Pasta de amendoim',         20, '1 colher de sopa cheia'),
    ('mariana.costa@exemplo.com', 'Almoço',          'Arroz integral cozido',    190, '6 colheres de sopa'),
    ('mariana.costa@exemplo.com', 'Almoço',          'Feijão carioca cozido',    150, '1 concha e meia'),
    ('mariana.costa@exemplo.com', 'Almoço',          'Ovo de galinha cozido',    100, '2 ovos'),
    ('mariana.costa@exemplo.com', 'Almoço',          'Brócolis cozido',           80, '3/4 de xícara'),
    ('mariana.costa@exemplo.com', 'Almoço',          'Azeite de oliva',           10, '1 colher de sobremesa'),
    ('mariana.costa@exemplo.com', 'Lanche da tarde', 'Whey protein concentrado',  30, '1 scoop'),
    ('mariana.costa@exemplo.com', 'Lanche da tarde', 'Pão integral',              50, '2 fatias'),
    ('mariana.costa@exemplo.com', 'Lanche da tarde', 'Queijo minas frescal',      30, '1 fatia'),
    ('mariana.costa@exemplo.com', 'Lanche da tarde', 'Mamão papaia',             150, '1/2 mamão'),
    ('mariana.costa@exemplo.com', 'Jantar',          'Grão-de-bico cozido',      150, '1 xícara'),
    ('mariana.costa@exemplo.com', 'Jantar',          'Batata-doce cozida',       150, '1 unidade média'),
    ('mariana.costa@exemplo.com', 'Jantar',          'Tomate',                    80, '1 unidade média'),
    ('mariana.costa@exemplo.com', 'Jantar',          'Alface crespa',             40, '1 prato de sobremesa'),
    ('mariana.costa@exemplo.com', 'Jantar',          'Azeite de oliva',           10, '1 colher de sobremesa')
) v(email, refeicao, alimento, qtd, medida)
JOIN usuario u          ON u.email = v.email
JOIN plano_alimentar p  ON p.usuario_id = u.id AND p.status = 'ativo'
JOIN refeicao r         ON r.plano_id = p.id AND r.nome = v.refeicao
JOIN alimento a         ON a.nome = v.alimento;

-- Checks de refeição: Lucas marcou tudo nos últimos 6 dias e as duas primeiras de hoje
INSERT INTO refeicao_consumida (refeicao_id, data, consumida_em)
SELECT r.id, d::date, d::date + r.horario + interval '15 minutes'
FROM usuario u
JOIN plano_alimentar p ON p.usuario_id = u.id AND p.status = 'ativo'
JOIN refeicao r        ON r.plano_id = p.id
CROSS JOIN generate_series(current_date - 6, current_date - 1, interval '1 day') d
WHERE u.email = 'lucas.andrade@exemplo.com';

INSERT INTO refeicao_consumida (refeicao_id, data)
SELECT r.id, current_date
FROM usuario u
JOIN plano_alimentar p ON p.usuario_id = u.id AND p.status = 'ativo'
JOIN refeicao r        ON r.plano_id = p.id AND r.ordem <= 2
WHERE u.email = 'lucas.andrade@exemplo.com';

-- Mariana: últimos 3 dias, pulou o jantar de ontem
INSERT INTO refeicao_consumida (refeicao_id, data, consumida_em)
SELECT r.id, d::date, d::date + r.horario + interval '20 minutes'
FROM usuario u
JOIN plano_alimentar p ON p.usuario_id = u.id AND p.status = 'ativo'
JOIN refeicao r        ON r.plano_id = p.id
CROSS JOIN generate_series(current_date - 3, current_date - 1, interval '1 day') d
WHERE u.email = 'mariana.costa@exemplo.com'
  AND NOT (d::date = current_date - 1 AND r.nome = 'Jantar');

-- ---------------------------------------------------------------------
-- Planos de treino
-- ---------------------------------------------------------------------
INSERT INTO plano_treino (usuario_id, titulo, divisao, inicio, modelo_ia)
SELECT u.id, v.titulo, v.divisao, current_date - v.dias_atras, 'iafit-llm-v1'
FROM (VALUES ('lucas.andrade@exemplo.com', 'Hipertrofia em déficit', 'ABCD',      30),
             ('mariana.costa@exemplo.com', 'Full body em casa',      'Full body', 21)) v(email, titulo, divisao, dias_atras)
JOIN usuario u ON u.email = v.email;

INSERT INTO treino_dia (plano_treino_id, dia_semana, nome, descanso)
SELECT pt.id, v.dia, v.nome, v.descanso
FROM (VALUES
    ('lucas.andrade@exemplo.com', 0, 'Descanso',                          true),
    ('lucas.andrade@exemplo.com', 1, 'Treino A: peito e tríceps',         false),
    ('lucas.andrade@exemplo.com', 2, 'Treino B: costas e bíceps',         false),
    ('lucas.andrade@exemplo.com', 3, 'Descanso ativo: caminhada de 30 min', true),
    ('lucas.andrade@exemplo.com', 4, 'Treino C: pernas',                  false),
    ('lucas.andrade@exemplo.com', 5, 'Treino D: ombros e abdômen',        false),
    ('lucas.andrade@exemplo.com', 6, 'Descanso',                          true),
    ('mariana.costa@exemplo.com', 0, 'Descanso',                          true),
    ('mariana.costa@exemplo.com', 1, 'Full body 1',                       false),
    ('mariana.costa@exemplo.com', 2, 'Descanso',                          true),
    ('mariana.costa@exemplo.com', 3, 'Full body 2',                       false),
    ('mariana.costa@exemplo.com', 4, 'Descanso',                          true),
    ('mariana.costa@exemplo.com', 5, 'Full body 3',                       false),
    ('mariana.costa@exemplo.com', 6, 'Descanso',                          true)
) v(email, dia, nome, descanso)
JOIN usuario u      ON u.email = v.email
JOIN plano_treino pt ON pt.usuario_id = u.id AND pt.status = 'ativo';

INSERT INTO treino_exercicio (treino_dia_id, exercicio_id, ordem, series, repeticoes_min, repeticoes_max,
                              duracao_seg, carga_sugerida_kg, descanso_seg)
SELECT td.id, e.id, v.ordem, v.series, v.rep_min, v.rep_max, v.duracao, v.carga, v.descanso
FROM (VALUES
    -- Lucas, Treino A
    ('lucas.andrade@exemplo.com', 1, 'Supino reto com barra',         1, 4,  8, 10, NULL, 60.0,  90),
    ('lucas.andrade@exemplo.com', 1, 'Supino inclinado com halteres', 2, 3, 10, 12, NULL, 22.0,  75),
    ('lucas.andrade@exemplo.com', 1, 'Crucifixo com halteres',        3, 3, 12, 15, NULL, 12.0,  60),
    ('lucas.andrade@exemplo.com', 1, 'Tríceps na polia',              4, 3, 10, 12, NULL, 25.0,  60),
    ('lucas.andrade@exemplo.com', 1, 'Tríceps francês',               5, 3, 10, 12, NULL, 14.0,  60),
    -- Lucas, Treino B
    ('lucas.andrade@exemplo.com', 2, 'Puxada frontal',                1, 4,  8, 10, NULL, 55.0,  90),
    ('lucas.andrade@exemplo.com', 2, 'Remada curvada com barra',      2, 4,  8, 10, NULL, 50.0,  90),
    ('lucas.andrade@exemplo.com', 2, 'Remada unilateral com halter',  3, 3, 10, 12, NULL, 24.0,  60),
    ('lucas.andrade@exemplo.com', 2, 'Rosca direta com barra',        4, 3, 10, 12, NULL, 25.0,  60),
    ('lucas.andrade@exemplo.com', 2, 'Rosca martelo',                 5, 3, 10, 12, NULL, 12.0,  60),
    -- Lucas, Treino C
    ('lucas.andrade@exemplo.com', 4, 'Agachamento livre',             1, 4,  8, 10, NULL, 70.0, 120),
    ('lucas.andrade@exemplo.com', 4, 'Leg press 45',                  2, 4, 10, 12, NULL, 160.0, 90),
    ('lucas.andrade@exemplo.com', 4, 'Cadeira extensora',             3, 3, 12, 15, NULL, 45.0,  60),
    ('lucas.andrade@exemplo.com', 4, 'Mesa flexora',                  4, 3, 12, 15, NULL, 35.0,  60),
    ('lucas.andrade@exemplo.com', 4, 'Elevação pélvica',              5, 3, 10, 12, NULL, 60.0,  75),
    -- Lucas, Treino D
    ('lucas.andrade@exemplo.com', 5, 'Desenvolvimento com halteres',  1, 4,  8, 10, NULL, 20.0,  90),
    ('lucas.andrade@exemplo.com', 5, 'Elevação lateral',              2, 3, 12, 15, NULL,  8.0,  60),
    ('lucas.andrade@exemplo.com', 5, 'Abdominal crunch',              3, 3, 15, 20, NULL, NULL,  45),
    ('lucas.andrade@exemplo.com', 5, 'Prancha',                       4, 3, NULL, NULL, 45, NULL, 45),
    ('lucas.andrade@exemplo.com', 5, 'Esteira caminhada inclinada',   5, 1, NULL, NULL, 1200, NULL, 0),
    -- Mariana, mesmo circuito nos três dias
    ('mariana.costa@exemplo.com', 1, 'Agachamento com peso corporal', 1, 4, 15, 20, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 1, 'Flexão de braço',               2, 3,  8, 12, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 1, 'Elevação pélvica',              3, 4, 12, 15, NULL, NULL, 45),
    ('mariana.costa@exemplo.com', 1, 'Prancha',                       4, 3, NULL, NULL, 40, NULL, 45),
    ('mariana.costa@exemplo.com', 1, 'Polichinelo',                   5, 3, NULL, NULL, 45, NULL, 30),
    ('mariana.costa@exemplo.com', 3, 'Agachamento com peso corporal', 1, 4, 15, 20, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 3, 'Flexão de braço',               2, 3,  8, 12, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 3, 'Elevação pélvica',              3, 4, 12, 15, NULL, NULL, 45),
    ('mariana.costa@exemplo.com', 3, 'Burpee',                        4, 3,  8, 10, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 3, 'Prancha',                       5, 3, NULL, NULL, 40, NULL, 45),
    ('mariana.costa@exemplo.com', 5, 'Agachamento com peso corporal', 1, 4, 15, 20, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 5, 'Flexão de braço',               2, 3,  8, 12, NULL, NULL, 60),
    ('mariana.costa@exemplo.com', 5, 'Elevação pélvica',              3, 4, 12, 15, NULL, NULL, 45),
    ('mariana.costa@exemplo.com', 5, 'Abdominal crunch',              4, 3, 15, 20, NULL, NULL, 45),
    ('mariana.costa@exemplo.com', 5, 'Polichinelo',                   5, 3, NULL, NULL, 45, NULL, 30)
) v(email, dia, exercicio, ordem, series, rep_min, rep_max, duracao, carga, descanso)
JOIN usuario u       ON u.email = v.email
JOIN plano_treino pt ON pt.usuario_id = u.id AND pt.status = 'ativo'
JOIN treino_dia td   ON td.plano_treino_id = pt.id AND td.dia_semana = v.dia
JOIN exercicio e     ON e.nome = v.exercicio;

-- Sessões das últimas duas semanas nos dias de treino de cada um
INSERT INTO sessao_treino (usuario_id, treino_dia_id, data, iniciada_em, concluida_em, esforco_percebido)
SELECT pt.usuario_id, td.id, d::date,
       d::date + time '18:00', d::date + time '18:00' + interval '55 minutes',
       7 + (EXTRACT(DOY FROM d)::int % 3)
FROM plano_treino pt
JOIN treino_dia td ON td.plano_treino_id = pt.id AND NOT td.descanso
CROSS JOIN generate_series(current_date - 14, current_date - 1, interval '1 day') d
WHERE pt.status = 'ativo'
  AND td.dia_semana = EXTRACT(DOW FROM d);

-- Séries executadas: todas as séries de cada exercício, no topo da faixa de repetições
INSERT INTO serie_executada (sessao_id, exercicio_id, numero, repeticoes, duracao_seg, carga_kg)
SELECT s.id, te.exercicio_id, n, te.repeticoes_max, te.duracao_seg, te.carga_sugerida_kg
FROM sessao_treino s
JOIN treino_exercicio te ON te.treino_dia_id = s.treino_dia_id
CROSS JOIN LATERAL generate_series(1, te.series) n;

-- ---------------------------------------------------------------------
-- Chatbot
-- ---------------------------------------------------------------------
WITH c AS (
    INSERT INTO conversa (usuario_id, titulo, criada_em)
    SELECT id, 'Trocar o patinho do jantar', now() - interval '2 days'
    FROM usuario WHERE email = 'lucas.andrade@exemplo.com'
    RETURNING id
)
INSERT INTO mensagem (conversa_id, papel, conteudo, tokens, modelo_ia, criada_em)
SELECT c.id, v.papel::papel_mensagem, v.conteudo, v.tokens, v.modelo, now() - interval '2 days' + v.offset_min * interval '1 minute'
FROM c, (VALUES
    ('usuario',    'Posso trocar o patinho do jantar por peixe?', 12, NULL, 0),
    ('assistente', 'Pode sim. Troque os 100 g de patinho moído por 130 g de filé de tilápia grelhado: a proteína fica praticamente igual (34 g) e a gordura cai, então o dia fecha com umas 50 kcal a menos.', 58, 'iafit-llm-v1', 1),
    ('usuario',    'Quero fazer isso só às terças e quintas.', 11, NULL, 3),
    ('assistente', 'Combinado. Seu plano tem um cardápio único para a semana, então nas terças e quintas é só usar a tilápia na quantidade que te passei; nos outros dias segue o patinho.', 45, 'iafit-llm-v1', 4)
) v(papel, conteudo, tokens, modelo, offset_min);

WITH c AS (
    INSERT INTO conversa (usuario_id, titulo, criada_em)
    SELECT id, 'Proteína sem carne', now() - interval '5 hours'
    FROM usuario WHERE email = 'mariana.costa@exemplo.com'
    RETURNING id
)
INSERT INTO mensagem (conversa_id, papel, conteudo, tokens, modelo_ia, criada_em)
SELECT c.id, v.papel::papel_mensagem, v.conteudo, v.tokens, v.modelo, now() - interval '5 hours' + v.offset_min * interval '1 minute'
FROM c, (VALUES
    ('usuario',    'Sou vegetariana. Consigo chegar nos 100 g de proteína por dia?', 16, NULL, 0),
    ('assistente', 'Consegue. No seu plano a proteína vem de ovos, iogurte, whey, queijo e grão-de-bico, e o dia fecha perto de 97 g. Para passar dos 100 g, acrescente 1 ovo no almoço.', 52, 'iafit-llm-v1', 1)
) v(papel, conteudo, tokens, modelo, offset_min);

COMMIT;
