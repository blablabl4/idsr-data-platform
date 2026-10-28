-- ==============================================================================
-- IDSR DATA LAKEHOUSE — Consultas Analíticas Avançadas (SQL Gold)
-- Fontes Auditáveis: Receita Federal do Brasil + IBGE (Demografia das Empresas)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Mortalidade de CNPJs por Faixa de Capital Social Inicial (Sebrae / RFB)
-- Responde: O impacto direto do capital inicial investido na sobrevivência em 24 meses.
-- ------------------------------------------------------------------------------
WITH base_cnpjs AS (
    SELECT
        f.cnpj_basico,
        CASE
            WHEN f.capital_social < 10000 THEN '1. Abaixo de R$ 10k (Crítico / MEI)'
            WHEN f.capital_social BETWEEN 10000 AND 50000 THEN '2. R$ 10k a R$ 50k (Microempresa Inicial)'
            WHEN f.capital_social BETWEEN 50001 AND 100000 THEN '3. R$ 50k a R$ 100k (Estruturação Média)'
            WHEN f.capital_social BETWEEN 100001 AND 300000 THEN '4. R$ 100k a R$ 300k (Pequeno Porte)'
            ELSE '5. Acima de R$ 300k (Consolidado / EPP)'
        END AS faixa_capital,
        f.situacao_cadastral,
        f.is_baixada,
        f.meses_atividade
    FROM gold.fct_empresas_brasil f
    WHERE f.data_inicio_atividade >= '2022-01-01'
)
SELECT
    faixa_capital,
    COUNT(*) AS total_empresas,
    SUM(CASE WHEN is_baixada = FALSE THEN 1 ELSE 0 END) AS empresas_ativas,
    SUM(CASE WHEN is_baixada = TRUE THEN 1 ELSE 0 END) AS empresas_baixadas,
    ROUND((SUM(CASE WHEN is_baixada = TRUE THEN 1 ELSE 0 END)::NUMERIC / COUNT(*)) * 100, 1) AS taxa_mortalidade_pct,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY meses_atividade)::NUMERIC, 1) AS mediana_meses_vida
FROM base_cnpjs
GROUP BY faixa_capital
ORDER BY faixa_capital;

-- ------------------------------------------------------------------------------
-- 2. Ranking Nacional de Aberturas e Curva ABC por CNAE (MDIC / Mapa de Empresas)
-- Responde: Quais setores da economia concentram 80% do volume de novos negócios.
-- ------------------------------------------------------------------------------
WITH cnae_agrupado AS (
    SELECT
        c.codigo_cnae,
        c.descricao_cnae,
        c.secao,
        COUNT(DISTINCT f.cnpj_basico) AS total_empresas_abertas,
        SUM(f.capital_social) AS capital_social_total,
        ROUND(AVG(f.capital_social), 2) AS capital_social_medio
    FROM gold.fct_empresas_brasil f
    JOIN gold.dim_cnae c ON f.cnae_sk = c.cnae_sk
    GROUP BY c.codigo_cnae, c.descricao_cnae, c.secao
),
ranking_abc AS (
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY total_empresas_abertas DESC) AS rank_aberturas,
        SUM(total_empresas_abertas) OVER (ORDER BY total_empresas_abertas DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) /
            SUM(total_empresas_abertas) OVER () AS pct_acumulado
    FROM cnae_agrupado
)
SELECT
    codigo_cnae,
    descricao_cnae,
    rank_aberturas,
    total_empresas_abertas,
    TO_CHAR(capital_social_medio, 'R$ 999,999.00') AS ticket_medio_capital,
    CASE 
        WHEN pct_acumulado <= 0.80 THEN 'Curva A (Top 80% do Volume Nacional)'
        WHEN pct_acumulado <= 0.95 THEN 'Curva B (15% Intermediário)'
        ELSE 'Curva C (Cauda Longa)'
    END AS classificacao_abc
FROM ranking_abc
WHERE rank_aberturas <= 10
ORDER BY rank_aberturas;

-- ------------------------------------------------------------------------------
-- 3. Dinâmica Temporal de Aberturas e Média Móvel de 7 Dias (IBGE CEMPRE)
-- Responde: Volume diário de novos registros, tendência de 7 dias e variação diária.
-- ------------------------------------------------------------------------------
WITH aberturas_diarias AS (
    SELECT
        t.data,
        COUNT(DISTINCT f.cnpj_basico) AS volume_aberturas,
        AVG(f.capital_social) AS capital_medio_dia
    FROM gold.fct_empresas_brasil f
    JOIN gold.dim_tempo t ON f.tempo_key = t.tempo_key
    GROUP BY t.data
)
SELECT
    data,
    volume_aberturas,
    ROUND(capital_medio_dia::NUMERIC, 2) AS capital_social_medio,
    ROUND(AVG(volume_aberturas) OVER (
        ORDER BY data 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )::NUMERIC, 1) AS media_movel_7d,
    ROUND(((volume_aberturas - LAG(volume_aberturas, 1) OVER (ORDER BY data)) / 
        NULLIF(LAG(volume_aberturas, 1) OVER (ORDER BY data), 0)) * 100, 2) AS var_dia_anterior_pct
FROM aberturas_diarias
ORDER BY data DESC
LIMIT 14;
