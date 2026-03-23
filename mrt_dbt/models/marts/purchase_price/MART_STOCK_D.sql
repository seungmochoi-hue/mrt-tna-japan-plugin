{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_STOCK_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        enabled=false
    )
}}

WITH STOCK_TARGET AS (
    SELECT H.file_record_id AS FILE_RECORD_ID
         ,  JSON_EXTRACT_SCALAR(H.after, '$.status') AS STATUS
    FROM {{ source('mrt_20' , 'bulk_invoice_file_record_histories') }} H
    JOIN (
        SELECT T.FILE_RECORD_ID
             , MAX(T.CREATED_AT_KST) AS CREATED_AT_KST
        FROM (
                 SELECT H.file_record_id AS FILE_RECORD_ID
                      , JSON_EXTRACT_SCALAR(H.after, '$.status') AS STATUS
                      , H.created_at_kst AS CREATED_AT_KST
                 FROM {{ source('mrt_20' , 'bulk_invoice_file_record_histories') }} H
                 WHERE H.created_at_kst <= '{{ var("logical_start_date_kst") }} 23:59:59'
             ) T
        WHERE T.STATUS IS NOT NULL
        GROUP BY T.FILE_RECORD_ID
    ) M ON H.file_record_id = M.FILE_RECORD_ID AND H.created_at_kst = M.CREATED_AT_KST
    JOIN {{ source('mrt_20' , 'bulk_invoice_file_records') }} R ON H.file_record_id = R.id
),
STOCK_ROW_DATA AS (
    SELECT R.id AS RECORD_ID
         ,  P.GID AS GID
         ,  P.GPID AS GPID
         ,  op.offer_id AS PRODUCT_ID
         ,  CAST(R.offer_price_id AS STRING) AS OPTION_ID
         ,  P.DOMAIN_NM AS DOMAIN_NM
         ,  P.PRODUCT_NM AS PRODUCT_NM
         ,  op.title AS OPTION_NM
         ,  P.RECENT_STATUS AS PRODUCT_RECENT_STATUS
         ,  T.status AS RECORD_RECENT_STATUS
         ,  P.FIRST_PUBLISHED_KST_DT AS FIRST_PUBLISHED_KST_DT
         ,  R.sold_at_kst AS SOLD_KST_AT
         ,  RG.voucher_type AS VOUCHER_TYPE
         ,  IFNULL(RG.unit_price_amount, 0) AS STOCK_UNIT_PRICE
         ,  R.created_at_kst AS CREATED_KST_AT
         ,  R.updated_at_kst AS UPDATED_KST_AT
    FROM STOCK_TARGET T
    LEFT JOIN {{ source('mrt_20' , 'bulk_invoice_file_records') }} R ON T.FILE_RECORD_ID = R.id
    LEFT JOIN {{ source('mrt_20' , 'offer_prices') }} op ON op.deleted_at is null AND op.id = R.offer_price_id
    LEFT JOIN {{ source('mrt_mart_view', 'MART_PRODUCT_D') }} P on P.PRODUCT_ID = CAST(op.offer_id AS STRING)
    LEFT JOIN {{ source('mrt_20' , 'bulk_invoice_record_groups') }} RG ON R.record_group_id = RG.id
    WHERE op.id IS NOT NULL
      AND R.status IS NOT NULL
),
OPTION_SKU_MAPPING AS (
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
STOCK_TODAY_FLAG AS (
    SELECT T.RECORD_ID AS RECORD_ID
         ,  MAX(CASE WHEN T.TODAY_UPLOAD_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_UPLOAD_FLAG
         ,  MAX(CASE WHEN T.TODAY_SOLD_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_SOLD_FLAG
         ,  MAX(CASE WHEN T.TODAY_RESTORE_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_RESTORE_FLAG
         ,  MAX(CASE WHEN T.TODAY_END_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_END_FLAG
         ,  MAX(CASE WHEN T.TODAY_DELETE_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_DELETE_FLAG
         ,  MAX(CASE WHEN T.TODAY_CANCEL_FLAG = 1 THEN 1 ELSE 0 END) AS TODAY_CANCEL_FLAG
    FROM (
             SELECT H.file_record_id AS RECORD_ID
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'upload' THEN 1 ELSE 0 END AS TODAY_UPLOAD_FLAG
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'sold' THEN 1 ELSE 0 END AS TODAY_SOLD_FLAG
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'restore' THEN 1 ELSE 0 END AS TODAY_RESTORE_FLAG
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'end' THEN 1 ELSE 0 END AS TODAY_END_FLAG
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'delete' THEN 1 ELSE 0 END AS TODAY_DELETE_FLAG
                 ,  CASE WHEN JSON_EXTRACT_SCALAR(H.after, '$.status') = 'cancel' THEN 1 ELSE 0 END AS TODAY_CANCEL_FLAG
             FROM {{ source('mrt_20' , 'bulk_invoice_file_record_histories') }} H
             WHERE CAST(H.created_at_kst AS DATE) = '{{ var("logical_start_date_kst") }}'
         ) T
    GROUP BY T.RECORD_ID
),
STOCK_DATA AS (
    SELECT D.GID AS GID
        ,  D.GPID AS GPID
        ,  D.PRODUCT_ID AS PRODUCT_ID
        ,  D.PRODUCT_RECENT_STATUS AS PRODUCT_RECENT_STATUS
        ,  D.PRODUCT_NM AS PRODUCT_NM
        ,  D.OPTION_ID AS OPTION_ID
        ,  D.OPTION_NM AS OPTION_NM
        ,  ARRAY_AGG(DISTINCT IFNULL(S.SKU_ID, 'NOT MATCH')) AS SKU_ID
        ,  D.VOUCHER_TYPE AS VOUCHER_TYPE
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'upload' THEN 1 ELSE NULL END), 0) AS UPLOAD_STATUS_CNT
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'sold' THEN 1 ELSE NULL END), 0) AS SOLD_STATUS_CNT
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'restore' THEN 1 ELSE NULL END), 0) AS RESTORE_STATUS_CNT
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'end' THEN 1 ELSE NULL END), 0) AS END_STATUS_CNT
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'delete' THEN 1 ELSE NULL END), 0) AS DELETE_STATUS_CNT
        ,  IFNULL(COUNT(CASE WHEN D.RECORD_RECENT_STATUS = 'cancel' THEN 1 ELSE NULL END), 0) AS CANCEL_STATUS_CNT
        ,  IFNULL(SUM(CASE WHEN D.RECORD_RECENT_STATUS IN ('upload', 'restore', 'cancel') THEN D.STOCK_UNIT_PRICE ELSE NULL END), 0) AS TOTAL_UNIT_PRICE
        ,  IFNULL(SUM(SF.TODAY_UPLOAD_FLAG), 0) AS TODAY_UPLOAD_STATUS_CNT
        ,  IFNULL(SUM(SF.TODAY_SOLD_FLAG), 0) AS TODAY_SOLD_STATUS_CNT
        ,  IFNULL(SUM(SF.TODAY_RESTORE_FLAG), 0) AS TODAY_RESTORE_STATUS_CNT
        ,  IFNULL(SUM(SF.TODAY_END_FLAG), 0) AS TODAY_END_STATUS_CNT
        ,  IFNULL(SUM(SF.TODAY_DELETE_FLAG), 0) AS TODAY_DELETE_STATUS_CNT
        ,  IFNULL(SUM(SF.TODAY_CANCEL_FLAG), 0) AS TODAY_CANCEL_STATUS_CNT
    FROM STOCK_ROW_DATA D
    LEFT JOIN OPTION_SKU_MAPPING S ON D.OPTION_ID = S.OPTION_ID
    LEFT JOIN STOCK_TODAY_FLAG SF ON D.RECORD_ID = SF.RECORD_ID
    GROUP BY D.GID, D.GPID, D.PRODUCT_ID, D.PRODUCT_RECENT_STATUS, D.PRODUCT_NM, D.OPTION_ID, D.OPTION_NM, D.VOUCHER_TYPE
),
SALES_DATA AS (
    SELECT T.OPTION_ID
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS TODAY_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS TODAY_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 2 AND T.BASIS_DATE = CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN ABS(T.QTY) ELSE 0 END) AS TODAY_CANCEL_CNT
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 6 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS WEEK_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 6 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS WEEK_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.SALES_PRICE ELSE 0 END) AS MONTH_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) THEN T.QTY ELSE 0 END) AS MONTH_SALES_CNT
         ,  SUM(CASE WHEN T.KIND = 1 AND T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 55 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 THEN T.SALES_PRICE ELSE 0 END) AS LAST_MONTH_SALES_KRW_PRICE
         ,  SUM(CASE WHEN T.BASIS_DATE between CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 55 AND CAST('{{ var("logical_start_date_kst") }}' AS DATE) - 27 THEN T.QTY ELSE 0 END) AS LAST_MONTH_SALES_CNT
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
               AND RESVE_ID like 'TNA%'
               AND oor.option_id IS NOT NULL
         ) T
    GROUP BY T.OPTION_ID
)
SELECT CAST('{{ var("logical_start_date_kst") }}' AS DATE) AS BASIS_DATE
     ,  STOCK.GID AS GID
     ,  STOCK.GPID AS GPID
     ,  STOCK.PRODUCT_ID AS PRODUCT_ID
     ,  STOCK.PRODUCT_RECENT_STATUS AS PRODUCT_RECENT_STATUS
     ,  STOCK.PRODUCT_NM AS PRODUCT_NM
     ,  STOCK.OPTION_ID AS OPTION_ID
     ,  STOCK.OPTION_NM AS OPTION_NM
     ,  STOCK.SKU_ID AS SKU_ID
     ,  STOCK.VOUCHER_TYPE AS VOUCHER_TYPE
     ,  STOCK.UPLOAD_STATUS_CNT + STOCK.RESTORE_STATUS_CNT AS AVAILABLE_STOCK_CNT
     ,  STOCK.UPLOAD_STATUS_CNT + STOCK.RESTORE_STATUS_CNT + STOCK.CANCEL_STATUS_CNT AS TOTAL_STOCK_CNT
     ,  IFNULL(ROUND(SAFE_DIVIDE(IFNULL(STOCK.TOTAL_UNIT_PRICE, 0), (STOCK.UPLOAD_STATUS_CNT + STOCK.RESTORE_STATUS_CNT + STOCK.CANCEL_STATUS_CNT)), 2), 0) AS AVG_STOCK_UNIT_PRICE
     ,  ROUND(STOCK.TOTAL_UNIT_PRICE, 2) AS TOTAL_STOCK_PRICE
     ,  STOCK.TODAY_UPLOAD_STATUS_CNT AS TODAY_UPLOAD_STATUS_CNT
     ,  STOCK.TODAY_SOLD_STATUS_CNT AS TODAY_SOLD_CNT
     ,  IFNULL(SALES.TODAY_SALES_CNT, 0) AS TODAY_SALES_CNT
     ,  STOCK.TODAY_SOLD_STATUS_CNT - IFNULL(SALES.TODAY_SALES_CNT, 0) AS SOLD_DIFF_CNT
     ,  STOCK.TODAY_RESTORE_STATUS_CNT AS TODAY_RESTORE_STATUS_CNT
     ,  IFNULL(SALES.TODAY_CANCEL_CNT, 0) AS TODAY_SALES_CANCEL_CNT
     ,  STOCK.TODAY_RESTORE_STATUS_CNT - IFNULL(SALES.TODAY_CANCEL_CNT, 0) AS CANCEL_DIFF_CNT
     ,  STOCK.TODAY_END_STATUS_CNT AS TODAY_END_STATUS_CNT
     ,  STOCK.TODAY_DELETE_STATUS_CNT AS TODAY_DELETE_STATUS_CNT
     ,  STOCK.TODAY_CANCEL_STATUS_CNT AS TODAY_CANCEL_STATUS_CNT
-- 검증용
     ,  STOCK.UPLOAD_STATUS_CNT AS UPLOAD_STATUS_CNT
     ,  STOCK.SOLD_STATUS_CNT AS SOLD_STATUS_CNT
     ,  STOCK.RESTORE_STATUS_CNT AS RESTORE_STATUS_CNT
     ,  STOCK.END_STATUS_CNT AS END_STATUS_CNT
     ,  STOCK.DELETE_STATUS_CNT AS DELETE_STATUS_CNT
     ,  STOCK.CANCEL_STATUS_CNT AS CANCEL_STATUS_CNT

     ,  ROUND(IFNULL(SAFE_DIVIDE(STOCK.UPLOAD_STATUS_CNT + STOCK.RESTORE_STATUS_CNT + STOCK.CANCEL_STATUS_CNT, SAFE_DIVIDE(WEEK_SALES_CNT, 7)), 0), 2) as STOCK_OOS_DAY
     ,  IFNULL(SALES.WEEK_SALES_KRW_PRICE, 0) AS WEEK_SALES_KRW_PRICE
     ,  IFNULL(SALES.WEEK_SALES_CNT, 0) AS WEEK_SALES_CNT
     ,  IFNULL(ROUND(safe_divide(SALES.WEEK_SALES_KRW_PRICE, SALES.WEEK_SALES_CNT), 2), 0) AS WEEK_SALES_AVG_UNIT_PRICE
     ,  IFNULL(SALES.MONTH_SALES_KRW_PRICE, 0) AS MONTH_SALES_KRW_PRICE
     ,  IFNULL(SALES.MONTH_SALES_CNT, 0) AS MONTH_SALES_CNT
     ,  IFNULL(ROUND(safe_divide(SALES.MONTH_SALES_KRW_PRICE, SALES.MONTH_SALES_CNT), 2), 0) AS MONTH_SALES_AVG_UNIT_PRICE
     ,  IFNULL(SALES.LAST_MONTH_SALES_CNT, 0) AS LAST_MONTH_SALES_CNT
     ,  ROUND(IFNULL(SAFE_DIVIDE(SAFE_DIVIDE(SALES.WEEK_SALES_CNT, 7), SAFE_DIVIDE(SALES.MONTH_SALES_CNT, 28)), 0), 2) AS SALES_CHANGE_RATE
     ,  ROUND(IFNULL(SALES.MONTH_SALES_CNT * SAFE_DIVIDE(SAFE_DIVIDE(SALES.WEEK_SALES_CNT, 7), SAFE_DIVIDE(SALES.MONTH_SALES_CNT, 28)), 0), 2) as REQUIRED_STOCK_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM STOCK_DATA STOCK
LEFT JOIN SALES_DATA SALES ON STOCK.OPTION_ID = SALES.OPTION_ID
