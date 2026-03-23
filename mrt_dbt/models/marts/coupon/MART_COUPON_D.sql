{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_COUPON_D'
    )
}}

SELECT
  CAST(u.id AS STRING)                                                           AS COUPON_ID
  , CAST(u.template_id AS STRING)                                                AS TEMPLATE_ID
  , CAST(u.user_id AS STRING)                                                    AS ISSUED_USER_ID
  , u.use_status                                                                 AS RECENT_STATUS
  , t.name                                                                       AS TEMPLATE_NM
  , t.description                                                                AS TEMPLATE_DESCRIPTION
  , u.published_at                                                               AS PUBLISHED_KST_DT
  , u.start_use_date                                                             AS START_KST_DT
  , u.expire_date                                                                AS END_KST_DT
  , u.coupon_type                                                                AS COUPON_TYPE
  , u.discount_type                                                              AS DISCOUNT_TYPE
  , u.created_at                                                                 AS CREATED_KST_DT
  , u.updated_at                                                                 AS UPDATED_KST_DT
  , u.created_by                                                                 AS CREATED_BY_NM
  , u.updated_by                                                                 AS UPDATED_BY_NM
  , u.min_product_amount                                                         AS MIN_PAYMENT_PRICE
  , u.max_discount_amount                                                        AS MAX_DISCOUNT_PRICE
  , u.flat_amount                                                                AS COUPON_DICOUNT_PRICE
  , u.discount_rate                                                              AS COUPON_DISCOUNT_RATE
  , u.discount_amount                                                            AS ACTUAL_DISCOUNT_PRICE
  , u.reservation_no                                                             AS LAST_RESVE_ID
  , u.used_at                                                                    AS LAST_RESVE_DT
  , u.canceled_at                                                                AS LAST_CANCELED_AT
  , u.retrieve_reason                                                            AS LAST_CANCELED_REASON_VALUE
  , ROUND(COALESCE(u.partner_contribution_rate / NULLIF(100, 0), 0), 2)          AS PARTNER_CONTRIBUTION_RATE
  , ROUND(COALESCE(u.mrt_contribution_rate / NULLIF(100, 0), 0), 2)              AS MRT_CONTRIBUTION_RATE
  , tt.publish_team                                                              AS TEMPLATE_PUBLISH_TEAM_NM
  , tt.publish_purpose                                                           AS TEMPALTE_PUBLISH_PURPOSE
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                           AS DW_LOAD_DT
FROM {{ source('coupon', 'coupon_user_mapping') }} u
LEFT JOIN {{ source('coupon', 'coupon_templates') }} t ON u.template_id = t.id
LEFT JOIN {{ source('coupon', 'coupon_template_types')}} tt ON t.template_type_id = tt.id
WHERE u.deleted_at IS NULL
  AND u.reservation_no IS NOT NULL
