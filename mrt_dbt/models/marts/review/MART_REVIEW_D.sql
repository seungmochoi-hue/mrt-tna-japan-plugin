{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_REVIEW_D'
    )
}}


SELECT CAST(R.product_id AS STRING) AS GID
     , MAX(CAST(R.product_partner_id AS STRING)) AS PARTNER_ID
     , COUNT(DISTINCT R.id) AS REVIEW_CNT
     , FLOOR(AVG(R.SCORE) * 100) / 100 AS AVG_SCORE
     , COUNT(CASE WHEN R.score = 1.0 THEN R.id END) AS SCORE1_REVIEW_CNT
     , COUNT(CASE WHEN R.score = 2.0 THEN R.id END) AS SCORE2_REVIEW_CNT
     , COUNT(CASE WHEN R.score = 3.0 THEN R.id END) AS SCORE3_REVIEW_CNT
     , COUNT(CASE WHEN R.score = 4.0 THEN R.id END) AS SCORE4_REVIEW_CNT
     , COUNT(CASE WHEN R.score = 5.0 THEN R.id END) AS SCORE5_REVIEW_CNT
     , MIN(R.created_at) AS FIRST_REVIEW_CREATE_DT
     , MAX(R.created_at) AS LAST_REVIEW_CREATE_DT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source("reviews", "reviews") }} R
WHERE R.blocked = FALSE
  AND R.deleted_at IS NULL
GROUP BY R.product_id