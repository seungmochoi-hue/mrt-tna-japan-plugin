{{ config(
    materialized='table',
    schema='edw_intermediate'
) }}

/*
  [INT_FPNA_PG_FEE] 예약별 PG 수수료 정보
  - 3.0 결제(order_payments + payments_completed)와 2.0 결제(mrt_20.payments)를 UNION하여
    예약별 PG사, PG 수수료율, 결제일을 산출
  - payments_completed는 ORDER(주문) 시스템 데이터만 사용 (client_type = 'ORDER')
    FLIGHT(항공) 시스템과 ORDER_PAYMENT_ID 범위가 겹쳐 row explosion 발생 가능
  - FPNA_PG_INFO에서 PG사/기간별 수수료율 매핑
  - Grain: RESVE_ID (예약당 1행)
  - Downstream: MART_FPNA_TNA_PROFIT_D, MART_FPNA_RENTALCAR_PROFIT_D,
                MART_FPNA_PACKAGE_PROFIT_D, MART_FPNA_LODGMENT_PROFIT_D
*/

-- 3.0 결제 데이터
WITH PAYMENT_30 AS (
    SELECT DISTINCT
        odr.RESERVATION_NO                                                                   AS RESVE_ID
      , CASE WHEN p.PG = 'TOSSPAYMENTS' AND c.PAYMENT_METHOD = 'OVERSEA_CREDIT_CARD'
                  THEN 'TOSSPAYMENTS_해외'
             WHEN p.PG = 'KCP' AND c.COMPANY LIKE '%해외%'
                  THEN 'KCP_해외'
             ELSE p.PG END                                                                   AS PG
      , DATE(DATE_TRUNC(p.CREATED_AT, DAY))                                                  AS BASIS_DATE
    FROM {{ source('orders', 'order_payments') }} p
    LEFT JOIN {{ source('orders', 'reservations') }} odr
        ON p.ORDER_ID = odr.ORDER_ID
    LEFT JOIN {{ source('payments', 'payments_completed') }} c
        ON CAST(p.ID AS STRING) = c.ORDER_PAYMENT_ID
    WHERE p.PAYMENT_STATUS = 'PAID'
      AND c.PAYMENT_TYPE = 'PAYMENT'
      AND c.client_type = 'ORDER'
      AND odr.RESERVATION_NO IS NOT NULL
)

-- 2.0 결제 데이터
, PAYMENT_20 AS (
    SELECT DISTINCT
        CAST(r.ID AS STRING)                                                                 AS RESVE_ID
      , p.PAYMENT_METHOD                                                                     AS PG
      , DATE(DATE_TRUNC(p.CREATED_AT_KST, DAY))                                             AS BASIS_DATE
    FROM {{ source('mrt_20', 'payments') }} p
    LEFT JOIN {{ source('mrt_20', 'reservations') }} r
        ON r.ID = p.RESERVATION_ID
    WHERE p.STATUS = 'paid'
      AND r.ID IS NOT NULL
)

-- 3.0 + 2.0 UNION
, PRE_RESULT AS (
    SELECT * FROM PAYMENT_30
    UNION ALL
    SELECT * FROM PAYMENT_20
)

-- PG 수수료율 매핑
SELECT
    r.RESVE_ID
  , r.PG
  , p.PG_COM_RATE
  , r.BASIS_DATE
FROM PRE_RESULT r
LEFT JOIN {{ ref('FPNA_PG_INFO') }} p
    ON p.PAYMENT_METHOD = r.PG
   AND r.BASIS_DATE >= p.START_DATE
   AND r.BASIS_DATE <= p.END_DATE
