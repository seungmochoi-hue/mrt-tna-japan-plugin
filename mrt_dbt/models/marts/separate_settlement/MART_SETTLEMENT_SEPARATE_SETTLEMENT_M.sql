{{
    config(
        materialized='table',
        schema='settlement',
        alias='MART_SETTLEMENT_SEPARATE_SETTLEMENT_M'
    )
}}

WITH RESERVATION_STATUS AS (
    SELECT * EXCEPT(rn) FROM (
        SELECT
            DATE(DATE_TRUNC(created_at_kst, MONTH)) AS basis_month
             , CAST(reservation_id AS STRING) AS reservation_id
             , status
             , ROW_NUMBER() OVER(PARTITION BY DATE_TRUNC(created_at_kst, MONTH), reservation_id ORDER BY created_at DESC) AS rn
        FROM {{ source('mrt_20', 'reservation_status_logs') }}
    ) WHERE rn = 1
),
NET_PRICES AS (
    SELECT o.reservation_id, SUM(n.price_amount) AS net_price
    FROM {{ source('mrt_20', 'reservation_orders') }} o
        JOIN {{ source('mrt_20', 'reservation_order_net_prices') }} n ON o.id = reservation_order_id
    GROUP BY o.reservation_id
)
SELECT
    DATE_TRUNC(m.BASIS_DATE, MONTH) AS BASIS_MONTH
     , m.GUIDE_ID
     , m.RESVE_ID
     , m.OFFER_ID
     , o.title AS OFFER_NAME
     , m.KIND
     , m.CREATE_KST_DT
     , m.RESVE_PAID_KST_DT
     , m.RESVE_CONFIRM_KST_DT
     , m.CANCEL_KST_DT
     , m.TRAVEL_END_KST_DATE
     , m.SALES_PRICE
     , m.PAID_KRW_PRICE
     , m.COUPON_PRICE
     , m.POINT_PRICE
     , m.COMMISSION_RATE
     , m.COMMISSION_PRICE
     , r.istanbul_reservation_key AS ISTANBUL_RESERVATION_KEY
     , r.number_of_people AS PERSON_CNT
     , CASE WHEN m.KIND=2 THEN n.net_price * -1 ELSE n.net_price END AS NET_PRICE
     , s.status AS STATUS
     , CURRENT_DATETIME('Asia/Seoul') AS DW_LOAD_DT
FROM {{ ref('MART_SERVICE_SALE_D') }} m
         JOIN {{ ref('DIM_SETTLEMENT_SEPARATE_SETTLEMENT_PARTNER') }} p ON m.guide_id = p.guide_id
         JOIN {{ source('mrt_20', 'reservations') }} r ON m.RESVE_ID = CAST(r.id AS STRING) AND r.istanbul_reservation_key IS NOT NULL
         JOIN {{ source('mrt_20', 'offers') }} o ON r.offer_id = o.id
         LEFT JOIN NET_PRICES n ON r.id = n.reservation_id
         LEFT JOIN RESERVATION_STATUS s ON DATE_TRUNC(m.BASIS_DATE, MONTH) = s.basis_month AND m.RESVE_ID = s.reservation_id
UNION ALL
SELECT
    DATE_TRUNC(m.BASIS_DATE, MONTH) AS BASIS_MONTH
     , m.PARTNER_ID AS GUIDE_ID
     , m.RESVE_ID
     , m.PRODUCT_ID AS OFFER_ID
     , r.PRODUCT_TITLE AS OFFER_NAME
     , m.KIND
     , m.CREATE_KST_DT
     , m.RESVE_PAID_KST_DT
     , m.RESVE_CONFIRM_KST_DT
     , m.CANCEL_KST_DT
     , m.TRAVEL_END_KST_DATE
     , m.SALES_PRICE
     , m.PAID_PRICE
     , m.COUPON_PRICE
     , m.POINT_PRICE
     , m.COMMISSION_RATE
     , m.COMMISSION_PRICE
     , r.merchant_uid AS ISTANBUL_RESERVATION_KEY
     , 1 AS PERSON_CNT
     , CASE WHEN m.KIND=2 THEN r.total_sale_commission * -1 ELSE r.total_sale_commission END AS NET_PRICE
     , r.status AS STATUS
     , CURRENT_DATETIME('Asia/Seoul') AS DW_LOAD_DT
FROM {{ ref('MART_OFFER_SALE_D') }} m
    JOIN {{ ref('DIM_SETTLEMENT_SEPARATE_SETTLEMENT_PARTNER') }} p ON m.partner_id = p.guide_id
    JOIN {{ source('orders', 'reservations') }} r ON m.RESVE_ID = CAST(r.reservation_no AS STRING) AND r.merchant_uid IS NOT NULL