{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_STOCK_STATUS_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}



WITH OPTION_SKU_MAPPING AS (
    SELECT T.OPTION_ID
        ,  ARRAY_AGG(IFNULL(T.SKU_ID, 'NOT MATCH') ORDER BY T.SKU_ID) AS SKU_ID
    FROM (
         SELECT S.OPTION_ID
              , S.SKU_ID_1 AS SKU_ID
          FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
          WHERE S.SKU_ID_1 IS NOT NULL

          UNION ALL

          SELECT S.OPTION_ID
               , S.SKU_ID_2 AS SKU_ID
          FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
          WHERE S.SKU_ID_2 IS NOT NULL

          UNION ALL

          SELECT S.OPTION_ID
               , S.SKU_ID_3 AS SKU_ID
          FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
          WHERE S.SKU_ID_3 IS NOT NULL

          UNION ALL

          SELECT S.OPTION_ID
               , S.SKU_ID_4 AS SKU_ID
          FROM {{ ref('FPNA_COMMERCE_OPTION_N_SKU') }} S
          WHERE S.SKU_ID_4 IS NOT NULL
    ) T
    GROUP BY T.OPTION_ID
),
SALES_DATA AS (
    SELECT T.OPTION_ID
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS TODAY_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS TODAY_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 2 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN ABS(T.QTY) ELSE 0 END) AS TODAY_CANCEL_CNT
         ,  SUM(CASE WHEN T.KIND = 2 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN ABS(T.SALES_PRICE) ELSE 0 END) AS TODAY_CANCEL_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 6 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS WEEK_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 6 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS WEEK_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS MONTH_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS MONTH_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 55 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 THEN T.SALES_PRICE ELSE 0 END) AS LAST_MONTH_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.BASIS_DATE BETWEEN CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 55 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 THEN T.QTY ELSE 0 END) AS LAST_MONTH_SALES_CNT
    FROM (
             SELECT S.BASIS_DATE
                  ,  S.KIND
                  ,  CAST(O.offer_price_id AS STRING) AS OPTION_ID
                  ,  S.SALES_KRW_PRICE AS SALES_PRICE
                  ,  O.quantity AS QTY
             FROM {{ ref('MART_SERVICE_SALE_D') }} S
             LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} O ON S.resve_id = CAST(O.reservation_id AS STRING)
             WHERE S.BASIS_DATE >= CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 56
               AND O.offer_price_id IS NOT NULL

             UNION ALL

             SELECT S.BASIS_DATE
                  , S.KIND
                  , oor.option_id AS OPTION_ID
                  , oor.sale_price AS SALES_PRICE
                  , oor.quantity AS QTY
             FROM {{ ref('MART_OFFER_SALE_D') }} S
             LEFT JOIN {{ source('orders', 'reservations') }} r ON S.RESVE_ID = CAST(r.reservation_no AS STRING)
             LEFT JOIN {{ source('orders', 'option_reservations') }} oor ON r.id = oor.reservation_id
             WHERE S.BASIS_DATE >= CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 56
               AND RESVE_ID LIKE 'TNA%'
               AND oor.option_id IS NOT NULL
         ) T
    GROUP BY T.OPTION_ID
)
SELECT CAST('{{ var("logical_start_date_kst") }}' AS DATE) AS BASIS_DATE
     ,  product.GID AS GID
     ,  product.GPID AS GPID
     ,  stock.PRODUCT_ID AS PRODUCT_ID
     ,  product.RECENT_STATUS AS PRODUCT_RECENT_STATUS
     ,  product.PRODUCT_NM AS PRODUCT_NM
     ,  stock.OPTION_ID AS OPTION_ID
     ,  stock.OPTION_NM AS OPTION_NM
     ,  sku.SKU_ID AS SKU_ID
     ,  stock.VOUCHER_TYPE AS VOUCHER_TYPE
     ,  stock.UPLOAD_STATUS_CNT + stock.RESTORE_STATUS_CNT AS AVAILABLE_STOCK_CNT
     ,  stock.UPLOAD_STATUS_CNT + stock.RESTORE_STATUS_CNT + stock.CANCEL_STATUS_CNT AS TOTAL_STOCK_CNT
     ,  IFNULL(ROUND(SAFE_DIVIDE(IFNULL(stock.UPLOAD_STATUS_STOCK_PRICE + stock.RESTORE_STATUS_STOCK_PRICE + stock.CANCEL_STATUS_STOCK_PRICE , 0), (stock.UPLOAD_STATUS_CNT + stock.RESTORE_STATUS_CNT + stock.CANCEL_STATUS_CNT)), 2), 0) AS AVG_STOCK_UNIT_PRICE
     ,  ROUND(stock.UPLOAD_STATUS_STOCK_PRICE + stock.RESTORE_STATUS_STOCK_PRICE + stock.CANCEL_STATUS_STOCK_PRICE, 2) AS TOTAL_STOCK_PRICE
     ,  stock.TODAY_UPLOAD_STATUS_CNT AS TODAY_UPLOAD_STATUS_CNT
     ,  stock.TODAY_SOLD_STATUS_CNT AS TODAY_SOLD_STATUS_CNT
     ,  IFNULL(sales.TODAY_SALES_CNT, 0) AS TODAY_SALES_CNT
     ,  stock.TODAY_SOLD_STATUS_CNT - IFNULL(sales.TODAY_SALES_CNT, 0) AS SOLD_DIFF_CNT
     ,  stock.TODAY_RESTORE_STATUS_CNT AS TODAY_RESTORE_STATUS_CNT
     ,  IFNULL(sales.TODAY_CANCEL_CNT, 0) AS TODAY_SALES_CANCEL_CNT
     ,  stock.TODAY_RESTORE_STATUS_CNT - IFNULL(sales.TODAY_CANCEL_CNT, 0) AS CANCEL_DIFF_CNT
     ,  stock.TODAY_END_STATUS_CNT AS TODAY_END_STATUS_CNT
     ,  stock.TODAY_DELETE_STATUS_CNT AS TODAY_DELETE_STATUS_CNT
     ,  stock.TODAY_CANCEL_STATUS_CNT AS TODAY_CANCEL_STATUS_CNT

     ,  stock.TODAY_UPLOAD_STATUS_STOCK_PRICE AS TODAY_UPLOAD_STATUS_STOCK_PRICE
     ,  stock.TODAY_SOLD_STATUS_STOCK_PRICE AS TODAY_SOLD_STATUS_STOCK_PRICE
     ,  stock.TODAY_RESTORE_STATUS_STOCK_PRICE AS TODAY_RESTORE_STATUS_STOCK_PRICE
     ,  stock.TODAY_END_STATUS_STOCK_PRICE AS TODAY_END_STATUS_STOCK_PRICE
     ,  stock.TODAY_DELETE_STATUS_STOCK_PRICE AS TODAY_DELETE_STATUS_STOCK_PRICE
     ,  stock.TODAY_CANCEL_STATUS_STOCK_PRICE AS TODAY_CANCEL_STATUS_STOCK_PRICE
-- 검증용
     ,  stock.UPLOAD_STATUS_CNT AS UPLOAD_STATUS_CNT
     ,  stock.SOLD_STATUS_CNT AS SOLD_STATUS_CNT
     ,  stock.RESTORE_STATUS_CNT AS RESTORE_STATUS_CNT
     ,  stock.END_STATUS_CNT AS END_STATUS_CNT
     ,  stock.DELETE_STATUS_CNT AS DELETE_STATUS_CNT
     ,  stock.CANCEL_STATUS_CNT AS CANCEL_STATUS_CNT

     ,  stock.UPLOAD_STATUS_STOCK_PRICE AS UPLOAD_STATUS_STOCK_PRICE
     ,  stock.SOLD_STATUS_STOCK_PRICE AS SOLD_STATUS_STOCK_PRICE
     ,  stock.RESTORE_STATUS_STOCK_PRICE AS RESTORE_STATUS_STOCK_PRICE
     ,  stock.END_STATUS_STOCK_PRICE AS END_STATUS_STOCK_PRICE
     ,  stock.DELETE_STATUS_STOCK_PRICE AS DELETE_STATUS_STOCK_PRICE
     ,  stock.CANCEL_STATUS_STOCK_PRICE AS CANCEL_STATUS_STOCK_PRICE

     ,  IFNULL(sales.TODAY_SALES_KRW_PRICE, 0) AS TODAY_SALES_KRW_PRICE
     ,  IFNULL(sales.TODAY_CANCEL_KRW_PRICE, 0) AS TODAY_CANCEL_KRW_PRICE

     ,  ROUND(IFNULL(SAFE_DIVIDE(stock.UPLOAD_STATUS_CNT + stock.RESTORE_STATUS_CNT + stock.CANCEL_STATUS_CNT, SAFE_DIVIDE(WEEK_SALES_CNT, 7)), 0), 2) AS STOCK_OOS_DAY
     ,  IFNULL(sales.WEEK_SALES_KRW_PRICE, 0) AS WEEK_SALES_KRW_PRICE
     ,  IFNULL(sales.WEEK_SALES_CNT, 0) AS WEEK_SALES_CNT
     ,  IFNULL(ROUND(SAFE_DIVIDE(sales.WEEK_SALES_KRW_PRICE, sales.WEEK_SALES_CNT), 2), 0) AS WEEK_SALES_AVG_UNIT_PRICE
     ,  IFNULL(sales.MONTH_SALES_KRW_PRICE, 0) AS MONTH_SALES_KRW_PRICE
     ,  IFNULL(sales.MONTH_SALES_CNT, 0) AS MONTH_SALES_CNT
     ,  IFNULL(ROUND(SAFE_DIVIDE(sales.MONTH_SALES_KRW_PRICE, sales.MONTH_SALES_CNT), 2), 0) AS MONTH_SALES_AVG_UNIT_PRICE
     ,  IFNULL(sales.LAST_MONTH_SALES_CNT, 0) AS LAST_MONTH_SALES_CNT
     ,  ROUND(IFNULL(SAFE_DIVIDE(SAFE_DIVIDE(sales.WEEK_SALES_CNT, 7), SAFE_DIVIDE(sales.MONTH_SALES_CNT, 28)), 0), 2) AS SALES_CHANGE_RATE
     ,  ROUND(IFNULL(sales.MONTH_SALES_CNT * SAFE_DIVIDE(SAFE_DIVIDE(sales.WEEK_SALES_CNT, 7), SAFE_DIVIDE(sales.MONTH_SALES_CNT, 28)), 0), 2) AS REQUIRED_STOCK_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('SNP_STOCK_D') }} stock
LEFT JOIN OPTION_SKU_MAPPING sku ON stock.OPTION_ID = sku.OPTION_ID
LEFT JOIN SALES_DATA sales ON stock.OPTION_ID = sales.OPTION_ID
LEFT JOIN {{ source ('mrt_mart_view', 'MART_PRODUCT_D') }} product ON product.PRODUCT_ID = stock.PRODUCT_ID
WHERE stock.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE)
