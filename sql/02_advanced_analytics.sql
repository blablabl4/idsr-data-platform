-- ==============================================================================
-- IDSR DATA LAKEHOUSE — Consultas Analíticas Avançadas & Window Functions
-- Demonstração de domínio em SQL para auditorias e KPIs de alta performance
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Elasticidade do Prazo de Entrega sobre o NPS (Impacto Estatístico de Atraso)
-- Calcula a queda na nota média e a probabilidade de detrator (score 1-2)
-- ------------------------------------------------------------------------------
WITH metricas_atraso AS (
    SELECT
        f.pedido_id,
        CASE
            WHEN f.dias_atraso_estimado <= 0 THEN 'No Prazo / Antecipado'
            WHEN f.dias_atraso_estimado BETWEEN 0.01 AND 2.00 THEN 'Atraso Leve (1-2d)'
            WHEN f.dias_atraso_estimado BETWEEN 2.01 AND 5.00 THEN 'Atraso Moderado (3-5d)'
            ELSE 'Atraso Crítico (>5d)'
        END AS faixa_atraso,
        f.dias_atraso_estimado,
        f.review_score,
        CASE WHEN f.review_score <= 2 THEN 1 ELSE 0 END AS is_detrator
    FROM gold.fct_pedidos_logistica f
    WHERE f.review_score IS NOT NULL
)
SELECT
    faixa_atraso,
    COUNT(*) AS total_pedidos,
    ROUND(AVG(review_score), 2) AS nps_medio,
    ROUND((SUM(is_detrator)::NUMERIC / COUNT(*)) * 100, 2) AS pct_detratores,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dias_atraso_estimado)::NUMERIC, 1) AS mediana_dias_atraso
FROM metricas_atraso
GROUP BY faixa_atraso
ORDER BY nps_medio DESC;

-- ------------------------------------------------------------------------------
-- 2. Ranking Dinâmico de Vendedores e Curva ABC com Window Functions (NTILE / DENSE_RANK)
-- ------------------------------------------------------------------------------
WITH vendas_vendedor AS (
    SELECT
        v.vendedor_id,
        v.estado AS uf_vendedor,
        COUNT(DISTINCT f.pedido_id) AS total_pedidos,
        SUM(f.valor_produto) AS receita_total,
        ROUND(AVG(f.review_score), 2) AS rating_medio,
        SUM(CASE WHEN f.is_atrasado THEN 1 ELSE 0 END)::NUMERIC / COUNT(DISTINCT f.pedido_id) AS taxa_atraso
    FROM gold.fct_pedidos_logistica f
    JOIN gold.dim_vendedor v ON f.vendedor_sk = v.vendedor_sk
    GROUP BY v.vendedor_id, v.estado
),
ranking_e_decis AS (
    SELECT
        *,
        DENSE_RANK() OVER (ORDER BY receita_total DESC) AS rank_nacional,
        DENSE_RANK() OVER (PARTITION BY uf_vendedor ORDER BY receita_total DESC) AS rank_estadual,
        NTILE(10) OVER (ORDER BY receita_total DESC) AS decil_receita,
        SUM(receita_total) OVER (ORDER BY receita_total DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) /
            SUM(receita_total) OVER () AS pct_acumulado_receita
    FROM vendas_vendedor
)
SELECT
    vendedor_id,
    uf_vendedor,
    rank_nacional,
    rank_estadual,
    total_pedidos,
    receita_total,
    rating_medio,
    ROUND(taxa_atraso * 100, 1) AS pct_atraso,
    CASE
        WHEN pct_acumulado_receita <= 0.80 THEN 'Classe A (80% receita)'
        WHEN pct_acumulado_receita <= 0.95 THEN 'Classe B (15% receita)'
        ELSE 'Classe C (5% receita)'
    END AS classificacao_abc
FROM ranking_e_decis
WHERE rank_nacional <= 50;

-- ------------------------------------------------------------------------------
-- 3. Lead Time MoM e Média Móvel de 7 dias com LAG e ROWS BETWEEN
-- ------------------------------------------------------------------------------
WITH pedidos_diarios AS (
    SELECT
        t.data,
        COUNT(DISTINCT f.pedido_id) AS volume_pedidos,
        SUM(f.valor_total) AS faturamento_dia,
        AVG(f.dias_para_entrega) AS lead_time_medio_dia
    FROM gold.fct_pedidos_logistica f
    JOIN gold.dim_tempo t ON f.tempo_key = t.tempo_key
    GROUP BY t.data
)
SELECT
    data,
    volume_pedidos,
    faturamento_dia,
    ROUND(lead_time_medio_dia::NUMERIC, 2) AS lead_time_dia,
    -- Média móvel dos últimos 7 dias
    ROUND(AVG(lead_time_medio_dia) OVER (
        ORDER BY data 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )::NUMERIC, 2) AS lead_time_mm7d,
    -- Variação dia anterior via LAG
    ROUND(((faturamento_dia - LAG(faturamento_dia, 1) OVER (ORDER BY data)) / 
        NULLIF(LAG(faturamento_dia, 1) OVER (ORDER BY data), 0)) * 100, 2) AS variacao_faturamento_pct
FROM pedidos_diarios
ORDER BY data DESC
LIMIT 30;
