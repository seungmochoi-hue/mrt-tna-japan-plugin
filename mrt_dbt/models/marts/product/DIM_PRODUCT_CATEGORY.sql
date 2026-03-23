{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_PRODUCT_CATEGORY',
        cluster_by=['DOMAIN_NM']
    )
}}


SELECT CAST(CO.OFFER_ID AS STRING) AS PRODUCT_ID
    ,  '2.0 PRODUCT' AS DOMAIN_NM
    ,  NULL AS CATEGORY_NM
    ,  CO.CATEGORY_ID AS CATEGORY_ID
    ,  C.CODE AS CATEGORY_CD
    ,  CO2.SUB_CATEGORY_ID AS SUB_CATEGORY_ID
    ,  SC.CODE AS SUB_CATEGORY_CD
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM
(SELECT DISTINCT C.offer_id
      , FIRST_VALUE(C.category_id) OVER(PARTITION BY C.offer_id ORDER BY C.created_at DESC) AS CATEGORY_ID
 FROM {{ source('mrt_20', 'offers_offer_categories') }} C
 WHERE C.deleted_at IS NULL) CO
LEFT JOIN
(SELECT DISTINCT C.offer_id
      , FIRST_VALUE(C.sub_category_id) OVER(PARTITION BY C.offer_id ORDER BY C.created_at DESC) AS SUB_CATEGORY_ID
   FROM {{ source('mrt_20', 'offers_offer_sub_categories') }} C
   WHERE C.deleted_at IS NULL) CO2 ON CO.offer_id = CO2.offer_Id
LEFT JOIN {{ source('mrt_20', 'offer_categories') }} C ON CO.CATEGORY_ID = C.id
LEFT JOIN {{ source('mrt_20', 'offer_sub_categories') }} SC ON CO2.SUB_CATEGORY_ID = SC.id

UNION ALL

SELECT CAST(T.PRODUCT_ID AS STRING) AS PRODUCT_ID
     ,  '3.0 PRODUCT' AS DOMAIN_NM
     ,  NULL AS CATEGORY_NM
     , T.first_category_id AS CATEGORY_ID
     , T.first_category_code AS CATEGORY_CD
     , T.second_category_id AS SUB_CATEGORY_ID
     , T.second_category_code AS SUB_CATEGORY_CD
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT c.PRODUCT_ID
              , c.first_category_id
              , c.first_category_code
              , c.second_category_id
              , c.second_category_code
              , ROW_NUMBER() OVER(PARTITION BY c.PRODUCT_ID ORDER BY c.created_at DESC) AS rnk
         FROM {{ source('experiences', 'product_display_categories') }} c
         WHERE c.deleted_at IS NULL
) t
WHERE t.rnk = 1