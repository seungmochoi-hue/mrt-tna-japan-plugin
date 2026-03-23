{{
    config(
        materialized='table',
        schema='temp',
        alias='SALES_SKU_PURCHASE',
        enabled=false
    )
}}


WITH OPTION_SKU_MAPPING AS (
  SELECT S.OPTION_ID
      ,  S.SKU_ID_1 AS SKU_ID
    FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
  WHERE S.SKU_ID_1 IS NOT NULL

  UNION ALL

  SELECT S.OPTION_ID
      ,  S.SKU_ID_2 AS SKU_ID
    FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
  WHERE S.SKU_ID_2 IS NOT NULL

  UNION ALL

  SELECT S.OPTION_ID
      ,  S.SKU_ID_3 AS SKU_ID
    FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
  WHERE S.SKU_ID_3 IS NOT NULL

  UNION ALL

  SELECT S.OPTION_ID
      ,  S.SKU_ID_4 AS SKU_ID
    FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
  WHERE S.SKU_ID_4 IS NOT NULL
),
SALES_DATA AS (
    SELECT T.BASIS_DATE
         , T.SALES_TYPE
         , T.SKU_ID
         , SUM(T.SALE_AMOUNT) AS SALE_AMOUNT
    FROM (
        SELECT M.BASIS_DATE
             , CASE WHEN M.KIND = 1 THEN 'SALES' WHEN M.KIND = 2 THEN 'CANCEL' END AS SALES_TYPE
             , C.SKU_ID AS SKU_ID
             , SUM(O.quantity) AS SALE_AMOUNT
        FROM {{ ref('MART_SALE_D') }} M
        LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} O ON M.RESVE_ID = CAST(O.reservation_id AS STRING)
        LEFT JOIN OPTION_SKU_MAPPING C ON CAST(O.offer_price_id AS STRING) = C.OPTION_ID
        WHERE M.BASIS_DATE = '{{ var("logical_start_date_kst") }}'
          AND M.DOMAIN_NM = '2.0 PRODUCT'
          AND O.deleted_at IS NULL
          AND C.OPTION_ID IS NOT NULL
        GROUP BY M.BASIS_DATE, M.KIND, C.SKU_ID

        UNION ALL

        SELECT M.BASIS_DATE
             , CASE WHEN M.KIND = 1 THEN 'SALES' WHEN M.KIND = 2 THEN 'CANCEL' END AS SALES_TYPE
             , C.SKU_ID AS SKU_ID
             , SUM(RO.quantity)  AS SALE_AMOUNT
        FROM {{ ref('MART_SALE_D') }} M
        LEFT JOIN {{ source('orders', 'reservations') }} R ON M.RESVE_ID = R.RESERVATION_NO
        LEFT JOIN {{ source('orders', 'option_reservations') }} RO ON R.ID = RO.RESERVATION_ID
        LEFT JOIN OPTION_SKU_MAPPING C ON CAST(RO.option_id AS STRING) = C.OPTION_ID
        WHERE M.BASIS_DATE = '{{ var("logical_start_date_kst") }}'
          AND M.DOMAIN_NM = '3.0 PRODUCT'
          AND R.DELETED_AT IS NULL AND RO.DELETED_AT IS NULL
          AND C.OPTION_ID IS NOT NULL
        GROUP BY M.BASIS_DATE, M.KIND, C.SKU_ID
    ) T
    GROUP BY T.BASIS_DATE, T.SALES_TYPE, T.SKU_ID
)
SELECT S.BASIS_DATE
     ,  S.SALES_TYPE
     ,  S.SKU_ID
     ,  S.SALE_AMOUNT
FROM SALES_DATA S