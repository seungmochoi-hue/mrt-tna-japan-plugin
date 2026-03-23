{{
    config(
        materialized='table',
        schema='edw_intermediate',
        alias='INT_COUPON_APPLIED_RESVE_D'
    )
}}

WITH COUPON_HISTORY AS (
    SELECT
        reservation_no AS RESVE_ID
      , MAX(order_no) AS ORDER_NO
      , coupon_user_mapping_id AS COUPON_USER_MAPPING_ID
      , template_id AS COUPON_ID
      , usable_type AS USABLE_TYPE
      , CAST(SUM(IF(discount_amount > 0, discount_amount, 0)) AS INT64) AS PAYMENT_COUPON_PRICE
      , CAST(SUM(IF(discount_amount < 0, ABS(discount_amount), 0)) AS INT64) AS REFUND_COUPON_PRICE
    FROM {{ source('coupon', 'coupon_reservation_history') }}
    WHERE deleted_at IS NULL
      AND reservation_no IS NOT NULL
    GROUP BY reservation_no, coupon_user_mapping_id, template_id, usable_type
)

SELECT
    h.RESVE_ID
  , h.ORDER_NO
  , h.COUPON_USER_MAPPING_ID
  , h.COUPON_ID
  , ct.name AS COUPON_NM
  , h.USABLE_TYPE
  , h.PAYMENT_COUPON_PRICE
  , h.REFUND_COUPON_PRICE
  , h.PAYMENT_COUPON_PRICE - h.REFUND_COUPON_PRICE AS NET_COUPON_PRICE
  , CASE
        WHEN ctt.publish_type IS NULL THEN 'UNKNOWN'
        ELSE ctt.publish_type
    END AS COUPON_PUBLISH_TYPE
  , CASE
        WHEN ctt.publish_team IS NULL THEN 'UNKNOWN'
        ELSE ctt.publish_team
    END AS COUPON_PUBLISH_TEAM
  , CASE
        WHEN ctt.publish_purpose IS NULL THEN 'UNKNOWN'
        ELSE ctt.publish_purpose
    END AS COUPON_PUBLISH_PURPOSE
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM COUPON_HISTORY h
LEFT JOIN {{ source('coupon', 'coupon_templates') }} ct
  ON h.COUPON_ID = ct.id
LEFT JOIN {{ source('coupon', 'coupon_template_types') }} ctt
  ON ct.template_type_id = ctt.id
