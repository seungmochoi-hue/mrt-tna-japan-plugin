{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_PACKAGE_OPTION'
    )
}}


WITH CITY_NODUP AS (
    SELECT T.offer_id
         ,  T.is_representative -- 신규 추가
         ,  T.city_key_name
    FROM (
             SELECT c.offer_id
                  ,  c.is_representative  -- 추가
                  ,  c.city_key_name
                  ,  ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN # 로직 변경
             FROM {{ ref('city_to_region') }} c
             WHERE city_info_id IS NOT NULL
         ) t
    WHERE t.RN = 1
)
SELECT CAST(PP.offer_id AS STRING) AS PACKAGE_GID
    ,  CAST(PO.id AS STRING) AS SYNC_ID
    ,  CAST(CP.id AS STRING) AS PACKAGE_OPTION_GID
    ,  PP.title AS PACKAGE_TITLE
    ,  PO.title AS PACKAGE_SYNC_TITLE
    ,  CP.title AS PACKAGE_OPTION_TITLE
    ,  CP.product_status AS PRODUCT_STATUS
    ,  CP.product_type AS PRODUCT_TYPE
    ,  CP.supply_start_date AS SUPPLY_START_DATE
    ,  CP.supply_end_date AS SUPPLY_END_DATE
    ,  CP.supplier_id AS SUPPLIER_ID
    ,  S.supplier_name AS SUPPLIER_NM
    ,  S.partner_id AS PARTNER_ID
    ,  CT.CITY AS CITY_NM
    ,  CT.COUNTRY AS COUNTRY_NM
    ,  CT.REGION AS REGION_NM
    ,  CP.created_at AS CREATED_KST_DT
    ,  CP.updated_at AS UPDATED_KST_DT
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('package_solution', 'package_product') }} PP
LEFT JOIN {{ source('package_solution', 'package_product_option') }} PO ON PO.package_product_id = PP.id AND PO.deleted_at IS NULL
LEFT JOIN {{ source('package_solution', 'package_product_option_component_product') }} CO ON CO.package_product_option_id = PO.id AND CO.deleted_at IS NULL
LEFT JOIN {{ source('package_solution', 'component_product') }} CP ON CO.component_product_id = CP.id AND CP.deleted_at IS NULL
LEFT JOIN {{ source('package_solution', 'supplier') }} S ON CP.supplier_id = S.id AND S.deleted_at IS NULL
LEFT JOIN CITY_NODUP d ON CAST(PP.offer_id AS STRING) = d.offer_id
LEFT JOIN {{ ref("DIM_CITY") }} CT ON d.city_key_name = CT.CODE
WHERE PP.deleted_at IS NULL