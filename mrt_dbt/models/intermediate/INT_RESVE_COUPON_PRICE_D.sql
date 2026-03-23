{{
    config(
        materialized='table',
        schema='edw_intermediate',
        alias='INT_RESVE_COUPON_PRICE_D'
    )
}}

WITH COUPON_HISTORY AS (
    SELECT
        reservation_no AS RESVE_ID
      , usable_type AS USABLE_TYPE
      , coupon_user_mapping_id AS COUPON_USER_MAPPING_ID
      , template_id AS COUPON_ID
      , CAST(SUM(IF(discount_amount > 0, discount_amount, 0)) AS INT64) AS PAYMENT_COUPON_PRICE
      , CAST(SUM(IF(discount_amount < 0, ABS(discount_amount), 0)) AS INT64) AS REFUND_COUPON_PRICE
    FROM {{ source('coupon', 'coupon_reservation_history') }}
    WHERE deleted_at IS NULL
      AND reservation_no IS NOT NULL
    GROUP BY reservation_no, usable_type, coupon_user_mapping_id, template_id
)

, PAYMENT_COUPON_REP AS (
    SELECT
        RESVE_ID
      , MAX(IF(USABLE_TYPE = 'PRODUCT', COUPON_ID, NULL)) AS PRODUCT_COUPON_ID
      , MAX(IF(USABLE_TYPE = 'ORDER', COUPON_ID, NULL)) AS ORDER_COUPON_ID
    FROM (
        SELECT
            *
          , ROW_NUMBER() OVER (
                PARTITION BY RESVE_ID, USABLE_TYPE
                ORDER BY PAYMENT_COUPON_PRICE DESC, COUPON_USER_MAPPING_ID DESC, COUPON_ID DESC
            ) AS RN
        FROM COUPON_HISTORY
        WHERE PAYMENT_COUPON_PRICE > 0
    )
    WHERE RN = 1
    GROUP BY RESVE_ID
)

, REFUND_COUPON_REP AS (
    SELECT
        RESVE_ID
      , MAX(IF(USABLE_TYPE = 'PRODUCT', COUPON_ID, NULL)) AS PRODUCT_COUPON_ID
      , MAX(IF(USABLE_TYPE = 'ORDER', COUPON_ID, NULL)) AS ORDER_COUPON_ID
    FROM (
        SELECT
            *
          , ROW_NUMBER() OVER (
                PARTITION BY RESVE_ID, USABLE_TYPE
                ORDER BY REFUND_COUPON_PRICE DESC, COUPON_USER_MAPPING_ID DESC, COUPON_ID DESC
            ) AS RN
        FROM COUPON_HISTORY
        WHERE REFUND_COUPON_PRICE > 0
    )
    WHERE RN = 1
    GROUP BY RESVE_ID
)

, PAYMENT_COUPON AS (
    SELECT
        r.reservation_no AS RESVE_ID
      , 1 AS KIND
      , CAST(GREATEST(IFNULL(r.coupon_discount_amount, 0), 0) AS INT64) AS PRODUCT_COUPON_PRICE
      , CAST(GREATEST(IFNULL(r.order_coupon_discount_amount, 0), 0) AS INT64) AS ORDER_COUPON_PRICE
      , pr.PRODUCT_COUPON_ID
      , pr.ORDER_COUPON_ID
    FROM {{ source('orders', 'reservations') }} r
    LEFT JOIN PAYMENT_COUPON_REP pr
      ON r.reservation_no = pr.RESVE_ID
    WHERE r.deleted_at IS NULL
)

, REFUND_BASE AS (
    SELECT
        rr.order_refund_id AS ORDER_REFUND_ID
      , r.reservation_no AS RESVE_ID
      , CAST(GREATEST(SUM(IFNULL(rr.coupon_discount_amount, 0)), 0) AS INT64) AS PRODUCT_COUPON_PRICE
      , CAST(GREATEST(MAX(IFNULL(r.order_coupon_discount_amount, 0)), 0) AS INT64) AS RESVE_ORDER_COUPON_PRICE
      , CAST(GREATEST(MAX(IFNULL(orf.refund_order_coupon_amount, 0)), 0) AS INT64) AS REFUND_ORDER_COUPON_PRICE
    FROM {{ source('orders', 'reservation_refunds') }} rr
    JOIN {{ source('orders', 'reservations') }} r
      ON rr.reservation_id = r.id
    LEFT JOIN {{ source('orders', 'order_refunds') }} orf
      ON rr.order_refund_id = orf.id
     AND orf.deleted_at IS NULL
    WHERE rr.deleted_at IS NULL
      AND rr.refund_status = 'COMPLETE'
      AND rr.refund_type IN ('FULL_CANCEL', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'OPTION_REFUND')
      AND r.deleted_at IS NULL
    GROUP BY rr.order_refund_id, r.reservation_no
)

, REFUND_RANKED AS (
    SELECT
        b.ORDER_REFUND_ID
      , b.RESVE_ID
      , b.PRODUCT_COUPON_PRICE
      , b.RESVE_ORDER_COUPON_PRICE
      , b.REFUND_ORDER_COUPON_PRICE
      , CAST(
            CASE
                WHEN SUM(b.RESVE_ORDER_COUPON_PRICE) OVER (PARTITION BY b.ORDER_REFUND_ID) > 0
                 AND b.REFUND_ORDER_COUPON_PRICE > 0
                    THEN FLOOR(
                        SAFE_DIVIDE(
                            b.RESVE_ORDER_COUPON_PRICE,
                            SUM(b.RESVE_ORDER_COUPON_PRICE) OVER (PARTITION BY b.ORDER_REFUND_ID)
                        ) * b.REFUND_ORDER_COUPON_PRICE
                    )
                ELSE 0
            END AS INT64
        ) AS ORDER_COUPON_FLOOR
      , CASE
            WHEN SUM(b.RESVE_ORDER_COUPON_PRICE) OVER (PARTITION BY b.ORDER_REFUND_ID) > 0
             AND b.REFUND_ORDER_COUPON_PRICE > 0
                THEN SAFE_DIVIDE(
                    b.RESVE_ORDER_COUPON_PRICE,
                    SUM(b.RESVE_ORDER_COUPON_PRICE) OVER (PARTITION BY b.ORDER_REFUND_ID)
                ) * b.REFUND_ORDER_COUPON_PRICE
                   - FLOOR(
                        SAFE_DIVIDE(
                            b.RESVE_ORDER_COUPON_PRICE,
                            SUM(b.RESVE_ORDER_COUPON_PRICE) OVER (PARTITION BY b.ORDER_REFUND_ID)
                        ) * b.REFUND_ORDER_COUPON_PRICE
                    )
            ELSE 0
        END AS ORDER_COUPON_FRAC
    FROM REFUND_BASE b
)

, REFUND_ALLOCATED AS (
    SELECT
        ORDER_REFUND_ID
      , RESVE_ID
      , PRODUCT_COUPON_PRICE
      , ORDER_COUPON_FLOOR
        + IF(
            ROW_NUMBER() OVER (
                PARTITION BY ORDER_REFUND_ID
                ORDER BY ORDER_COUPON_FRAC DESC, RESVE_ID
            ) <= GREATEST(
                REFUND_ORDER_COUPON_PRICE
                - SUM(ORDER_COUPON_FLOOR) OVER (PARTITION BY ORDER_REFUND_ID),
                0
            ),
            1,
            0
        ) AS ORDER_COUPON_PRICE
    FROM REFUND_RANKED
)

, REFUND_COUPON AS (
    SELECT
        a.RESVE_ID
      , 2 AS KIND
      , CAST(SUM(a.PRODUCT_COUPON_PRICE) AS INT64) AS PRODUCT_COUPON_PRICE
      , CAST(SUM(a.ORDER_COUPON_PRICE) AS INT64) AS ORDER_COUPON_PRICE
      , rr.PRODUCT_COUPON_ID
      , rr.ORDER_COUPON_ID
    FROM REFUND_ALLOCATED a
    LEFT JOIN REFUND_COUPON_REP rr
      ON a.RESVE_ID = rr.RESVE_ID
    GROUP BY a.RESVE_ID, rr.PRODUCT_COUPON_ID, rr.ORDER_COUPON_ID
)

SELECT
    RESVE_ID
  , KIND
  , PRODUCT_COUPON_PRICE
  , ORDER_COUPON_PRICE
  , PRODUCT_COUPON_PRICE + ORDER_COUPON_PRICE AS COUPON_PRICE
  , PRODUCT_COUPON_ID
  , ORDER_COUPON_ID
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM PAYMENT_COUPON

UNION ALL

SELECT
    RESVE_ID
  , KIND
  , PRODUCT_COUPON_PRICE
  , ORDER_COUPON_PRICE
  , PRODUCT_COUPON_PRICE + ORDER_COUPON_PRICE AS COUPON_PRICE
  , PRODUCT_COUPON_ID
  , ORDER_COUPON_ID
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM REFUND_COUPON
