-- ==============================================================================
-- IDSR DATA LAKEHOUSE — Modelagem Dimensional (Star Schema / Medallion Gold)
-- Target: PostgreSQL / BigQuery / Snowflake compatible DDL
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS gold;

-- 1. Dimensão Tempo
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

-- 2. Dimensão Cliente (SCD Tipo 2 Ready)
CREATE TABLE IF NOT EXISTS gold.dim_cliente (
    cliente_sk BIGSERIAL PRIMARY KEY,
    cliente_id VARCHAR(64) NOT NULL,
    cidade VARCHAR(100),
    estado CHAR(2) NOT NULL,
    regiao VARCHAR(20) NOT NULL,
    cep_prefixo INT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_dim_cliente_id ON gold.dim_cliente(cliente_id);

-- 3. Dimensão Produto
CREATE TABLE IF NOT EXISTS gold.dim_produto (
    produto_sk BIGSERIAL PRIMARY KEY,
    produto_id VARCHAR(64) NOT NULL,
    categoria VARCHAR(100) NOT NULL,
    peso_gramas NUMERIC(10,2),
    comprimento_cm NUMERIC(6,2),
    altura_cm NUMERIC(6,2),
    largura_cm NUMERIC(6,2),
    volume_cm3 NUMERIC(12,2) GENERATED ALWAYS AS (comprimento_cm * altura_cm * largura_cm) STORED
);
CREATE INDEX IF NOT EXISTS idx_dim_produto_id ON gold.dim_produto(produto_id);

-- 4. Dimensão Vendedor
CREATE TABLE IF NOT EXISTS gold.dim_vendedor (
    vendedor_sk BIGSERIAL PRIMARY KEY,
    vendedor_id VARCHAR(64) NOT NULL,
    cidade VARCHAR(100),
    estado CHAR(2) NOT NULL,
    regiao VARCHAR(20) NOT NULL
);

-- 5. Fato Vendas & Logística
CREATE TABLE IF NOT EXISTS gold.fct_pedidos_logistica (
    pedido_id VARCHAR(64) NOT NULL,
    item_numero INT NOT NULL,
    tempo_key INT REFERENCES gold.dim_tempo(tempo_key),
    cliente_sk BIGINT REFERENCES gold.dim_cliente(cliente_sk),
    produto_sk BIGINT REFERENCES gold.dim_produto(produto_sk),
    vendedor_sk BIGINT REFERENCES gold.dim_vendedor(vendedor_sk),
    
    -- Métricas e Degenerados
    valor_produto NUMERIC(10,2) NOT NULL,
    valor_frete NUMERIC(10,2) NOT NULL,
    valor_total NUMERIC(10,2) GENERATED ALWAYS AS (valor_produto + valor_frete) STORED,
    
    data_compra TIMESTAMP WITH TIME ZONE NOT NULL,
    data_estimada_entrega TIMESTAMP WITH TIME ZONE NOT NULL,
    data_real_entrega TIMESTAMP WITH TIME ZONE,
    
    -- SLA e Indicadores
    dias_para_entrega NUMERIC(6,2),
    dias_atraso_estimado NUMERIC(6,2),
    is_atrasado BOOLEAN NOT NULL DEFAULT FALSE,
    distancia_geografica_km NUMERIC(10,2),
    
    -- Feedback do Cliente
    review_score SMALLINT CHECK (review_score BETWEEN 1 AND 5),
    
    PRIMARY KEY (pedido_id, item_numero)
);
CREATE INDEX IF NOT EXISTS idx_fct_tempo ON gold.fct_pedidos_logistica(tempo_key);
CREATE INDEX IF NOT EXISTS idx_fct_atraso ON gold.fct_pedidos_logistica(is_atrasado);
