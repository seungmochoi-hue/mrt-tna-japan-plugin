{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_COUPON_RESVE_D'
    )
}}

SELECT DISTINCT rh.reservation_no               AS RESVE_ID
             ,   cc.template_id                  AS COUPON_ID
             ,   cct.name                        AS COUPON_NM
             ,   CASE
                    WHEN ct.publish_type IS NULL THEN 'UNKNOWN'
                    ELSE ct.publish_type END      AS COUPON_PUBLISH_TYPE
             ,   CASE
                    WHEN ct.publish_team IS NULL THEN 'UNKNOWN'
                    ELSE ct.publish_team END      AS COUPON_PUBLISH_TEAM
             ,  CASE
                    WHEN ct.publish_purpose IS NULL THEN 'UNKNOWN'
                    ELSE ct.publish_purpose END   AS COUPON_PUBLISH_PURPOSE
             ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('coupon', 'coupon_user_mapping') }} cc
LEFT JOIN {{ source('coupon', 'coupon_reservation_history') }} rh ON cc.id = rh.coupon_user_mapping_id
LEFT JOIN {{ source('coupon', 'coupon_template_types') }} ct ON cc.template_id = ct.id
LEFT JOIN {{ source('coupon', 'coupon_templates') }} cct ON cc.template_id = cct.id /* 쿠폰 Title 맵핑 */
WHERE cc.deleted_at IS NULL
  AND rh.reservation_no IS NOT NULL
