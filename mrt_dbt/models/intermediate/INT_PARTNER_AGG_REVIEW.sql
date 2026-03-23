{{
    config(
        materialized='ephemeral'
    )
}}

SELECT
    CAST(T.PARTNER_ID AS STRING) AS PARTNER_ID
  , CAST(NULL AS INT64) AS RESVE_CNT
  , CAST(NULL AS INT64) AS SALES_KRW_PRICE
  , CAST(NULL AS INT64) AS USER_CNT
  , CAST(NULL AS INT64) AS CURRENT_RESVE_CNT
  , CAST(NULL AS INT64) AS ONSALE_CNT
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_CITY_CD
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_COUNTRY_NM
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_MRT_TYPE
  , COUNT(DISTINCT T.REVIEW_ID) AS REVIEW_CNT
  , FLOOR(AVG(T.SCORE) * 100) / 100 AS REVIEW_SCORE_AVG
  , CAST(NULL AS FLOAT64) AS CONFIRM_RATE
FROM (
    SELECT
        O.guide_id AS PARTNER_ID
      , R.id AS REVIEW_ID
      , R.score AS SCORE
    FROM {{ source('mrt_20', 'reviews') }} R
    LEFT JOIN {{ source('mrt_20', 'offers') }} O
      ON R.offer_id = O.id
    WHERE R.deleted_at IS NULL
      AND R.type = 'TravelerReview'

    UNION ALL

    SELECT
        R.product_partner_id AS PARTNER_ID
      , R.ID + 1000000 AS REVIEW_ID
      , R.score AS SCORE
    FROM {{ source('reviews', 'reviews') }} R
    LEFT JOIN {{ source('mrt_mart_view', 'MART_PRODUCT_D') }} P
      ON R.product_id = P.PRODUCT_ID
     AND P.DOMAIN_NM = '3.0 PRODUCT'
    WHERE P.MRT_TYPE <> 'rentalcar'
) T
GROUP BY CAST(T.PARTNER_ID AS STRING)
