-- Camada Silver (dbt Staging View)
WITH source_data AS (
    SELECT
        order_id::VARCHAR(64) AS order_id,
        customer_id::VARCHAR(64) AS customer_id,
        LOWER(TRIM(order_status))::VARCHAR(32) AS order_status,
        order_purchase_timestamp::TIMESTAMP WITH TIME ZONE AS purchase_at,
        order_approved_at::TIMESTAMP WITH TIME ZONE AS approved_at,
        order_delivered_carrier_date::TIMESTAMP WITH TIME ZONE AS carrier_dispatched_at,
        order_delivered_customer_date::TIMESTAMP WITH TIME ZONE AS customer_delivered_at,
        order_estimated_delivery_date::TIMESTAMP WITH TIME ZONE AS estimated_delivery_at,
        ROW_NUMBER() OVER (
            PARTITION BY order_id 
            ORDER BY order_purchase_timestamp DESC
        ) AS dedup_rank
    FROM {{ source('bronze_lakehouse', 'raw_orders') }}
)
SELECT
    order_id,
    customer_id,
    order_status,
    purchase_at,
    approved_at,
    carrier_dispatched_at,
    customer_delivered_at,
    estimated_delivery_at
FROM source_data
WHERE dedup_rank = 1;
