{{
    config(
        materialized='table',
        schema='edw',
        alias='DW_MRT_UPS_UNION_PRODUCT_NODUP'
    )
}}

SELECT t.id         AS ID
    ,  t.product_id AS PRODUCT_ID
    ,  t.product_no AS PRODUCT_NO
    ,  t.domain_nm  AS DOMAIN_NM
FROM (
SELECT U.id, U.product_id, U.product_no, IF(SAFE_CAST(U.product_no AS INT64) IS NOT NULL, '2.0 PRODUCT', '3.0 PRODUCT') AS DOMAIN_NM
, ROW_NUMBER() OVER(PARTITION BY U.product_id, IF(SAFE_CAST(U.product_no AS INT64) IS NOT NULL, '2.0 PRODUCT', '3.0 PRODUCT') ORDER BY created_at DESC) AS row_number
FROM {{ source('ups', 'union_products') }} U
WHERE description <> 'dummy'
AND U.deleted_at IS NULL
) t
WHERE t.row_number = 1