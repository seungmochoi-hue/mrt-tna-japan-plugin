{{
    config(
        materialized='ephemeral'
    )
}}

WITH BASE AS (
    SELECT
        CAST(R.partner_id AS STRING) AS PARTNER_ID
      , COUNT(DISTINCT IF(H.event = 'confirm', R.reservation_no, NULL)) AS CONFIRM_CNT
      , COUNT(DISTINCT IF(
            H.event LIKE '%cancel_after_confirm%'
            AND R.cancel_reason_type IN ('OVER_TRAVELER', 'PARTNER_NO_RESPONSE', 'PARTNER_SCHEDULE'),
            R.reservation_no,
            NULL
        )) AS CANCEL_CNT
    FROM {{ source('settles', 'accounting_event_histories') }} H
    LEFT JOIN {{ source('orders', 'reservations') }} R
      ON R.reservation_no = H.reservation_id
    WHERE R.partner_id IS NOT NULL
    GROUP BY CAST(R.partner_id AS STRING)
)
SELECT
    B.PARTNER_ID AS PARTNER_ID
  , CAST(NULL AS INT64) AS RESVE_CNT
  , CAST(NULL AS INT64) AS SALES_KRW_PRICE
  , CAST(NULL AS INT64) AS USER_CNT
  , CAST(NULL AS INT64) AS CURRENT_RESVE_CNT
  , CAST(NULL AS INT64) AS ONSALE_CNT
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_CITY_CD
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_COUNTRY_NM
  , CAST(NULL AS STRING) AS MAIN_ACTIVITY_MRT_TYPE
  , CAST(NULL AS INT64) AS REVIEW_CNT
  , CAST(NULL AS FLOAT64) AS REVIEW_SCORE_AVG
  , FLOOR(IF(B.CONFIRM_CNT <> 0, (B.CONFIRM_CNT - B.CANCEL_CNT) / B.CONFIRM_CNT, 1) * 100) / 100 AS CONFIRM_RATE
FROM BASE B
