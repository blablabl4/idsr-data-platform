-- ==============================================================================
-- IDSR DATA LAKEHOUSE — Modelagem Dimensional (Star Schema / Medallion Gold)
-- Fonte Oficial: Receita Federal do Brasil (Dados Abertos CNPJ) + IBGE (CEMPRE)
-- Target: PostgreSQL / BigQuery / Snowflake compatible DDL
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS gold;

-- 1. Dimensão Tempo (Calendário Corporativo de Aberturas e Baixas)
CREATE TABLE IF NOT EXISTS gold.dim_tempo (
    tempo_key INT PRIMARY KEY,
    data DATE NOT NULL,
    ano SMALLINT NOT NULL,
    trimestre SMALLINT NOT NULL,
    mes SMALLINT NOT NULL,
    nome_mes VARCHAR(20) NOT NULL,
    dia SMALLINT NOT NULL,
    dia_semana SMALLINT NOT NULL,
    nome_dia_semana VARCHAR(20) NOT NULL,
    is_fim_de_semana BOOLEAN NOT NULL
);

-- 2. Dimensão Atividade Econômica (CNAE 2.0 Oficial - IBGE / CONCLA)
CREATE TABLE IF NOT EXISTS gold.dim_cnae (
    cnae_sk SERIAL PRIMARY KEY,
    codigo_cnae VARCHAR(10) UNIQUE NOT NULL,
    descricao_cnae VARCHAR(255) NOT NULL,
    secao CHAR(1) NOT NULL,              -- Ex: G (Comércio), J (Informação/Comunicação)
    divisao VARCHAR(100) NOT NULL,
    grau_risco_fiscal SMALLINT DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_dim_cnae_codigo ON gold.dim_cnae(codigo_cnae);

-- 3. Dimensão Município & Território (IBGE - Tabela de Códigos Municipais)
CREATE TABLE IF NOT EXISTS gold.dim_municipio (
    municipio_sk SERIAL PRIMARY KEY,
    codigo_ibge INT UNIQUE NOT NULL,      -- Código de 7 dígitos do IBGE
    codigo_tom VARCHAR(4),                -- Código TOM da Receita Federal
    nome_municipio VARCHAR(100) NOT NULL,
    uf CHAR(2) NOT NULL,
    regiao VARCHAR(20) NOT NULL,          -- Sudeste, Sul, Nordeste, Centro-Oeste, Norte
    populacao_censo INT,
    pib_per_capita NUMERIC(12,2),
    distancia_polo_economico_km NUMERIC(8,2) NOT NULL DEFAULT 0.0
);
CREATE INDEX IF NOT EXISTS idx_dim_municipio_uf ON gold.dim_municipio(uf);

-- 4. Dimensão Natureza Jurídica (CONCLA / Receita Federal)
CREATE TABLE IF NOT EXISTS gold.dim_natureza_juridica (
    natureza_juridica_sk SERIAL PRIMARY KEY,
    codigo_natureza VARCHAR(5) UNIQUE NOT NULL, -- Ex: 206-2 (LTDA), 213-5 (Empresário Individual)
    descricao_natureza VARCHAR(150) NOT NULL,
    categoria_societaria VARCHAR(50) NOT NULL    -- Sociedade, Individual, Cooperativa
);

-- 5. Fato Empresas do Brasil (Métricas Reais de Sobrevivência e Dinâmica Cadastral)
CREATE TABLE IF NOT EXISTS gold.fct_empresas_brasil (
    cnpj_basico VARCHAR(8) NOT NULL,             -- 8 primeiros dígitos oficiais do CNPJ
    cnpj_ordem VARCHAR(4) NOT NULL,              -- 0001 (Matriz), 0002+ (Filiais)
    cnpj_dv VARCHAR(2) NOT NULL,                 -- Dígito verificador
    tempo_key INT REFERENCES gold.dim_tempo(tempo_key),
    cnae_sk INT REFERENCES gold.dim_cnae(cnae_sk),
    municipio_sk INT REFERENCES gold.dim_municipio(municipio_sk),
    natureza_juridica_sk INT REFERENCES gold.dim_natureza_juridica(natureza_juridica_sk),
    capital_social NUMERIC(15,2) NOT NULL,       -- Capital social declarado na RFB
    porte_empresa CHAR(2) NOT NULL,              -- 01: Não Inf, 02: ME, 03: EPP, 05: Demais
    quantidade_socios SMALLINT NOT NULL DEFAULT 1,
    data_inicio_atividade DATE NOT NULL,
    situacao_cadastral CHAR(2) NOT NULL,         -- 01: Nula, 02: Ativa, 03: Suspensa, 04: Inapta, 08: Baixada
    data_situacao_cadastral DATE,
    motivo_situacao_cadastral VARCHAR(100),
    is_baixada BOOLEAN GENERATED ALWAYS AS (situacao_cadastral = '08') STORED,
    meses_atividade INT GENERATED ALWAYS AS (
        EXTRACT(YEAR FROM AGE(COALESCE(data_situacao_cadastral, CURRENT_DATE), data_inicio_atividade)) * 12 +
        EXTRACT(MONTH FROM AGE(COALESCE(data_situacao_cadastral, CURRENT_DATE), data_inicio_atividade))
    ) STORED,
    PRIMARY KEY (cnpj_basico, cnpj_ordem)
);

CREATE INDEX IF NOT EXISTS idx_fct_empresas_situacao ON gold.fct_empresas_brasil(situacao_cadastral);
CREATE INDEX IF NOT EXISTS idx_fct_empresas_porte ON gold.fct_empresas_brasil(porte_empresa);
CREATE INDEX IF NOT EXISTS idx_fct_empresas_capital ON gold.fct_empresas_brasil(capital_social);
