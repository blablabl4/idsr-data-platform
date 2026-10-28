-- Camada Gold (dbt Table Mart)
WITH orders AS (
    SELECT * FROM {{ ref('stg_ecommerce_orders') }}
    WHERE order_status = 'delivered'
),
items AS (
    SELECT
        order_id,
        COUNT(order_item_id) AS total_items,
        SUM(price) AS total_items_value,
        SUM(freight_value) AS total_freight_value
    FROM {{ source('bronze_lakehouse', 'raw_order_items') }}
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id AS customer_sk,
    i.total_items,
    i.total_items_value,
    i.total_freight_value,
    o.purchase_at,
    o.customer_delivered_at,
    o.estimated_delivery_at,
    
    -- Cálculos de Tempo e SLA
    EXTRACT(EPOCH FROM (o.customer_delivered_at - o.purchase_at)) / 86400.0 AS actual_lead_time_days,
    EXTRACT(EPOCH FROM (o.customer_delivered_at - o.estimated_delivery_at)) / 86400.0 AS delay_days,
    
    CASE 
        WHEN o.customer_delivered_at > o.estimated_delivery_at THEN TRUE 
        ELSE FALSE 
    END AS is_delayed,
    
    CURRENT_TIMESTAMP AS dbt_updated_at
FROM orders o
JOIN items i ON o.order_id = i.order_id;
