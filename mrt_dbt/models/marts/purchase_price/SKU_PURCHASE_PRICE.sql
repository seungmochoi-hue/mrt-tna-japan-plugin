{{
    config(
        materialized='table',
        schema='temp',
        alias='SKU_PURCHASE_PRICE',
        enabled=false
    )
}}


SELECT t.BASIS_DATE AS BASIS_DATE
    ,  t.SKU_ID AS SKU_ID
    ,  t.TICKET_AMOUNT AS TICKET_AMOUNT
    ,  t.STOCK_UNIT_PRICE AS STOCK_UNIT_PRICE
FROM {{ ref('MART_SKU_STOCK_HISTORY_D') }} t
WHERE t.SNP_DATE = '{{ var("logical_start_date_kst") }}'


UNION ALL

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
TARGET AS (
    select H.historiable_id AS HISTORIABLE_ID
         , H.created_at_kst AS CREATED_AT_KST
         , replace(replace(H.after, "\'","\""),"None","\"None\"") AS CLEAR_AFTER
    from {{ source('mrt_20', 'update_histories') }} H
    where H.created_at_kst between '{{ var("logical_start_date_kst") }} 00:00:00'
          and '{{ var("logical_start_date_kst") }} 23:59:59'
      and H.historiable_type = 'BulkInvoice::RecordGroup'
      and H.before = '{}'
),
TEMP_PURCHASE_PRICE AS (
    SELECT  T.HISTORIABLE_ID
         ,  T.CREATED_AT_KST
         ,  CAST(CASE WHEN JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.offer_price_id') = 'None' OR JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.offer_price_id') IS NULL OR JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.offer_price_id') = '0' THEN NULL
                      ELSE JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.offer_price_id') END AS STRING) AS OFFER_PRICE_ID
         ,  CAST(CASE WHEN JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.unit_price_amount') = 'None' OR JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.unit_price_amount') IS NULL OR JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.unit_price_amount') = '0.0' THEN
                           CASE WHEN JSON_EXTRACT_SCALAR(H2.after, '$.unit_price_amount')  = 'None' OR JSON_EXTRACT_SCALAR(H2.after, '$.unit_price_amount') IS NULL OR JSON_EXTRACT_SCALAR(H2.after, '$.unit_price_amount') = '0.0' THEN NULL
                                ELSE JSON_EXTRACT_SCALAR(H2.after, '$.unit_price_amount') END
                      ELSE JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.unit_price_amount') END AS FLOAT64) AS STOCK_UNIT_PRICE
         ,  CAST(CASE WHEN JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.file_count') = 'None' OR JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.file_count') IS NULL THEN
                           CASE WHEN JSON_EXTRACT_SCALAR(H1.after, '$.file_count')  = 'None' OR JSON_EXTRACT_SCALAR(H1.after, '$.file_count') IS NULL THEN NULL
                                ELSE JSON_EXTRACT_SCALAR(H1.after, '$.file_count') END
                      ELSE JSON_EXTRACT_SCALAR(T.CLEAR_AFTER, '$.file_count') END AS FLOAT64) AS TICKET_AMOUNT
    FROM TARGET T
    LEFT JOIN (
        SELECT T.HISTORIABLE_ID
             , CASE WHEN (LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.file_count')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.file_count') = '0') AND JSON_EXTRACT_SCALAR(H.after, '$.file_count') IS NOT NULL THEN 'FILE_COUNT'
                    WHEN (LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount') = '0.0') AND JSON_EXTRACT_SCALAR(H.after, '$.unit_price_amount') IS NOT NULL THEN 'UNIT_PRICE'
                    END AS HITORIABLE_TYPE
             , MIN(H.created_at_kst) AS CREATED_AT_KST
        FROM TARGET T
        LEFT JOIN {{ source('mrt_20', 'update_histories') }} H ON T.HISTORIABLE_ID = H.historiable_id
        WHERE ((LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.file_count')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.file_count') = '0') AND JSON_EXTRACT_SCALAR(H.after, '$.file_count') IS NOT NULL)
           OR ((LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount') = '0.0') AND JSON_EXTRACT_SCALAR(H.after, '$.unit_price_amount') IS NOT NULL)
        GROUP BY T.HISTORIABLE_ID, CASE WHEN (LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.file_count')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.file_count') = '0') AND JSON_EXTRACT_SCALAR(H.after, '$.file_count') IS NOT NULL THEN 'FILE_COUNT'
                                        WHEN (LENGTH(JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount')) = 0 OR JSON_EXTRACT_SCALAR(H.before, '$.unit_price_amount') = '0.0') AND JSON_EXTRACT_SCALAR(H.after, '$.unit_price_amount') IS NOT NULL THEN 'UNIT_PRICE' END
    ) M ON T.HISTORIABLE_ID = M.HISTORIABLE_ID
    LEFT JOIN {{ source('mrt_20', 'update_histories') }} H1 ON H1.HISTORIABLE_ID = M.HISTORIABLE_ID AND H1.CREATED_AT_KST = M.CREATED_AT_KST AND M.HITORIABLE_TYPE = 'FILE_COUNT'
    LEFT JOIN {{ source('mrt_20', 'update_histories') }} H2 ON H2.HISTORIABLE_ID = M.HISTORIABLE_ID AND H2.CREATED_AT_KST = M.CREATED_AT_KST AND M.HITORIABLE_TYPE = 'UNIT_PRICE'
)
SELECT CAST(T.CREATED_AT_KST AS DATE) AS BASIS_DATE
    ,  O.SKU_ID AS SKU_ID
    ,  CAST(T.TICKET_AMOUNT AS INT) AS TICKET_AMOUNT
    ,  CAST(T.STOCK_UNIT_PRICE AS FLOAT64) AS STOCK_UNIT_PRICE
  FROM (
        SELECT T.HISTORIABLE_ID
             , T.CREATED_AT_KST
             , MAX(T.OFFER_PRICE_ID) AS OFFER_PRICE_ID
             , MAX(T.STOCK_UNIT_PRICE) AS STOCK_UNIT_PRICE
             , MAX(T.TICKET_AMOUNT) AS TICKET_AMOUNT
        FROM TEMP_PURCHASE_PRICE T
        GROUP BY T.HISTORIABLE_ID, T.CREATED_AT_KST
  ) T
LEFT JOIN OPTION_SKU_MAPPING O on T.OFFER_PRICE_ID = O.OPTION_ID
WHERE O.sku_id IS NOT NULL