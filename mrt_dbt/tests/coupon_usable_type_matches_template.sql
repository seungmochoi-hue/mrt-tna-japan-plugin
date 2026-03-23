{{ config(severity='warn') }}

WITH coupon_history AS (
    SELECT
        reservation_no AS resve_id
      , coupon_user_mapping_id
      , template_id AS coupon_id
      , usable_type AS history_usable_type
    FROM {{ source('coupon', 'coupon_reservation_history') }}
    WHERE deleted_at IS NULL
      AND reservation_no IS NOT NULL
)

SELECT
    h.resve_id
  , h.coupon_user_mapping_id
  , h.coupon_id
  , h.history_usable_type
  , t.usable_type AS template_usable_type
FROM coupon_history h
LEFT JOIN {{ source('coupon', 'coupon_templates') }} t
  ON h.coupon_id = t.id
WHERE h.history_usable_type IS DISTINCT FROM t.usable_type
