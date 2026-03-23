{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_STAY_OPTION_SALE_D'
    )
}}

WITH RESERVATION_TARGET AS (
    SELECT DISTINCT CAST(P.first_payment_date AS DATE) AS BASIS_DATE
                  ,  R.id                    AS RESVE_ID
                  ,  O.id                    AS RESVE_OPTION_ID
                  ,  1                       AS KIND
                  ,  CAST(NULL AS TIMESTAMP) AS canceled_at
                  ,  P.id                    AS payment_id
                  ,  O.sale_price            AS REFUND_PRICE -- KIND=1: 옵션 원가. KIND=2의 SUM(refund_amount)와 컬럼 수 일치용
    FROM {{ source('orders', 'order_payments') }} P
    LEFT JOIN {{ source('orders', 'reservations') }} R ON P.order_id = R.order_id AND R.deleted_at IS NULL
    LEFT JOIN {{ source('orders', 'option_reservations') }} O ON R.id = O.reservation_id
    LEFT JOIN {{ source('orders', 'reservations_histories') }} RH ON R.reservation_no = RH.reservation_no
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no
    WHERE RH.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH')
      AND P.deleted_at IS NULL
      AND P.pg_authorized_at IS NOT NULL
      AND SR.reservation_id IS NOT NULL

    UNION ALL

    -- 취소 건 dedup: option_reservation_refunds는 환불 분할 처리로 1건 취소에 N개 레코드 존재 가능.
    -- GROUP BY R.id, O.id로 RESVE_OPTION_ID당 1건으로 집약하고 SUM(refund_amount)로 환불 합산 금액 산출.
    SELECT MIN(CAST(RF.canceled_at AS DATE))      AS BASIS_DATE
         ,  R.id                                   AS RESVE_ID
         ,  O.id                                   AS RESVE_OPTION_ID
         ,  2                                      AS KIND
         ,  MIN(CAST(RF.canceled_at AS TIMESTAMP)) AS canceled_at
         ,  MIN(P.id)                              AS payment_id
         ,  SUM(RF.refund_amount)                  AS REFUND_PRICE
    FROM {{ source('orders', 'option_reservation_refunds') }} RF
    LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RF.option_reservation_id = O.id
    LEFT JOIN {{ source('orders', 'reservations') }} R ON R.id = O.reservation_id
    LEFT JOIN {{ source('orders', 'order_payments') }} P ON R.order_id = P.order_id AND P.deleted_at IS NULL
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND SR.reservation_id IS NOT NULL
    GROUP BY R.id, O.id
),
CITY_NODUP AS (
    SELECT DISTINCT
        CAST(property_id AS STRING) AS offer_id
                  , city_key_name AS mrt_city
    FROM {{ source('unionstay', 'property_represent_mrt_region') }}
    WHERE city_key_name IS NOT NULL
),
SETTLEMENT_DATA AS (
    SELECT DISTINCT P.option_reservation_id
                  , P.sale_commission
                  , P.sale_commission_rate
    FROM {{ source('settles', 'settlement_product_closing') }} P
    WHERE P.deleted_at IS NULL
      AND P.closing_type IN ('PAYMENT', 'PAYMENT_OF_REFUND')
),
REFUND_RESVE_TOTAL AS (
    SELECT
        R.reservation_no AS RESVE_ID
      , CAST(SUM(RF.refund_amount) AS INT64) AS REFUND_SALES_PRICE
    FROM {{ source('orders', 'option_reservation_refunds') }} RF
    LEFT JOIN {{ source('orders', 'option_reservations') }} O
      ON RF.option_reservation_id = O.id
    LEFT JOIN {{ source('orders', 'reservations') }} R
      ON R.id = O.reservation_id
    LEFT JOIN {{ source('orders', 'order_payments') }} P
      ON R.order_id = P.order_id
     AND P.deleted_at IS NULL
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR
      ON R.reservation_no = SR.mrt_reservation_no
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND SR.reservation_id IS NOT NULL
    GROUP BY R.reservation_no
),
OPTION_COUPON_ALLOCATION_BASE AS (
    SELECT
        RT.RESVE_OPTION_ID
      , RT.KIND
      , CAST(R.reservation_no AS STRING) AS RESVE_ID
      , CAST(CASE WHEN RT.KIND = 1 THEN O.sale_price ELSE RT.REFUND_PRICE END AS INT64) AS OPTION_ALLOC_PRICE
      , CAST(CASE WHEN RT.KIND = 1 THEN R.sale_price ELSE IFNULL(RT2.REFUND_SALES_PRICE, 0) END AS INT64) AS RESVE_ALLOC_PRICE
      , CAST(IFNULL(RCP.PRODUCT_COUPON_PRICE, 0) AS INT64) AS TOTAL_PRODUCT_COUPON_PRICE
      , CAST(IFNULL(RCP.ORDER_COUPON_PRICE, 0) AS INT64) AS TOTAL_ORDER_COUPON_PRICE
      , CAST(RCP.PRODUCT_COUPON_ID AS INT64) AS PRODUCT_COUPON_ID
      , CAST(RCP.ORDER_COUPON_ID AS INT64) AS ORDER_COUPON_ID
    FROM RESERVATION_TARGET RT
    LEFT JOIN {{ source('orders', 'reservations') }} R
      ON RT.RESVE_ID = R.id
    LEFT JOIN {{ source('orders', 'option_reservations') }} O
      ON RT.RESVE_OPTION_ID = O.id
    LEFT JOIN {{ ref('INT_RESVE_COUPON_PRICE_D') }} RCP
      ON R.reservation_no = RCP.RESVE_ID
     AND RT.KIND = RCP.KIND
    LEFT JOIN REFUND_RESVE_TOTAL RT2
      ON R.reservation_no = RT2.RESVE_ID
),
OPTION_COUPON_ALLOCATION_RANKED AS (
    SELECT
        *
      , CAST(
            CASE
                WHEN RESVE_ALLOC_PRICE > 0 AND TOTAL_PRODUCT_COUPON_PRICE > 0
                    THEN FLOOR(SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_PRODUCT_COUPON_PRICE)
                ELSE 0
            END AS INT64
        ) AS PRODUCT_COUPON_FLOOR
      , CASE
            WHEN RESVE_ALLOC_PRICE > 0 AND TOTAL_PRODUCT_COUPON_PRICE > 0
                THEN SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_PRODUCT_COUPON_PRICE
                   - FLOOR(SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_PRODUCT_COUPON_PRICE)
            ELSE 0
        END AS PRODUCT_COUPON_FRAC
      , CAST(
            CASE
                WHEN RESVE_ALLOC_PRICE > 0 AND TOTAL_ORDER_COUPON_PRICE > 0
                    THEN FLOOR(SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_ORDER_COUPON_PRICE)
                ELSE 0
            END AS INT64
        ) AS ORDER_COUPON_FLOOR
      , CASE
            WHEN RESVE_ALLOC_PRICE > 0 AND TOTAL_ORDER_COUPON_PRICE > 0
                THEN SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_ORDER_COUPON_PRICE
                   - FLOOR(SAFE_DIVIDE(OPTION_ALLOC_PRICE, RESVE_ALLOC_PRICE) * TOTAL_ORDER_COUPON_PRICE)
            ELSE 0
        END AS ORDER_COUPON_FRAC
    FROM OPTION_COUPON_ALLOCATION_BASE
),
OPTION_COUPON_ALLOCATION AS (
    SELECT
        RESVE_OPTION_ID
      , KIND
      , PRODUCT_COUPON_ID
      , ORDER_COUPON_ID
      , PRODUCT_COUPON_FLOOR
        + IF(
            ROW_NUMBER() OVER (PARTITION BY RESVE_ID, KIND ORDER BY PRODUCT_COUPON_FRAC DESC, RESVE_OPTION_ID) <= GREATEST(
                TOTAL_PRODUCT_COUPON_PRICE - SUM(PRODUCT_COUPON_FLOOR) OVER (PARTITION BY RESVE_ID, KIND),
                0
            ),
            1,
            0
        ) AS PRODUCT_COUPON_PRICE
      , ORDER_COUPON_FLOOR
        + IF(
            ROW_NUMBER() OVER (PARTITION BY RESVE_ID, KIND ORDER BY ORDER_COUPON_FRAC DESC, RESVE_OPTION_ID) <= GREATEST(
                TOTAL_ORDER_COUPON_PRICE - SUM(ORDER_COUPON_FLOOR) OVER (PARTITION BY RESVE_ID, KIND),
                0
            ),
            1,
            0
        ) AS ORDER_COUPON_PRICE
    FROM OPTION_COUPON_ALLOCATION_RANKED
)
SELECT RT.BASIS_DATE AS BASIS_DATE
     ,  CAST(R.user_id AS STRING) AS USER_ID
     ,  CAST(R.reservation_no AS STRING) AS RESVE_ID
     ,  CAST(O.id AS STRING) AS RESVE_OPTION_ID
     ,  REGEXP_EXTRACT(O.option_id, r':-:\d+:-:(\d+):-:\d+:-:\d+') AS ROOM_ID
     ,  CAST(OD.id AS STRING) AS ORDER_ID
     ,  CAST(R.product_id AS STRING) AS PRODUCT_ID
     ,  CAST(R.union_product_id AS STRING) AS GID
     ,  CAST(O.option_id AS STRING) AS OPTION_ID
     ,  CAST(OT.option_id AS STRING) AS ROOM_OPTION_ID
     ,  SR.provider_type AS PROVIDER_TYPE
     ,  SR.provider_code AS PROVIDER_CD
     ,  CAST(PT.property_id AS STRING) AS PROPERTY_ID
     ,  RT.KIND AS KIND
     ,  R.product_title AS PRODUCT_TITLE
     ,  PT.property_name AS PROPERTY_NM
     ,  SRR.room_name AS ROOM_NM
     ,  OT.option_name AS ROOM_OPTION_NM
     ,  O.canceled_at AS CANCEL_KST_DT
     ,  LOWER(R.status) AS RECENT_STATUS
     ,  SRR.check_in_date AS TRAVEL_START_KST_DATE
     ,  SRR.check_out_date AS TRAVEL_END_KST_DATE
     ,  LOWER(P.pg) AS PG_NM
     ,  LOWER(OD.ordered_platform) AS PLATFORM
     ,  P.first_payment_date AS RESVE_PAID_KST_DT
     ,  SC.LV_1_CD AS STANDARD_CATEGORY_LV_1_CD
     ,  SC.LV_1_NM AS STANDARD_CATEGORY_LV_1_NM
     ,  SC.LV_2_CD AS STANDARD_CATEGORY_LV_2_CD
     ,  SC.LV_2_NM AS STANDARD_CATEGORY_LV_2_NM
     ,  SC.LV_3_CD AS STANDARD_CATEGORY_LV_3_CD
     ,  SC.LV_3_NM AS STANDARD_CATEGORY_LV_3_NM
     ,  O.created_at AS CREATE_KST_DT
     ,  O.updated_at AS UPDATE_KST_DT
     ,  CAST(R.partner_id AS STRING) AS PARTNER_ID
     ,  IF(RT.KIND = 1, O.sale_price, RT.REFUND_PRICE) * IF(RT.KIND = 1, 1, -1) AS SALES_PRICE
     ,  CAST(
            CASE
                WHEN RT.KIND = 1
                    THEN ROUND(
                        O.sale_price
                        - IFNULL(OCA.PRODUCT_COUPON_PRICE, 0)
                        - IFNULL(OCA.ORDER_COUPON_PRICE, 0)
                        - ROUND(SAFE_DIVIDE(O.sale_price, R.sale_price) * R.point_amount, 2),
                        0
                    )
                ELSE
                    GREATEST(
                        ABS(RT.REFUND_PRICE)
                        - IFNULL(OCA.PRODUCT_COUPON_PRICE, 0)
                        - IFNULL(OCA.ORDER_COUPON_PRICE, 0)
                        - ROUND(SAFE_DIVIDE(O.sale_price, R.sale_price) * R.point_amount, 2),
                        0
                    )
            END * CASE WHEN RT.KIND = 1 THEN 1 ELSE -SIGN(RT.REFUND_PRICE) END AS INT
        ) AS PAID_PRICE
     ,  CAST((IFNULL(OCA.PRODUCT_COUPON_PRICE, 0) + IFNULL(OCA.ORDER_COUPON_PRICE, 0)) * IF(RT.KIND = 1, 1, -1) AS INT) AS COUPON_PRICE
     ,  CAST(IFNULL(OCA.PRODUCT_COUPON_PRICE, 0) * IF(RT.KIND = 1, 1, -1) AS INT) AS PRODUCT_COUPON_PRICE
     ,  CAST(IFNULL(OCA.ORDER_COUPON_PRICE, 0) * IF(RT.KIND = 1, 1, -1) AS INT) AS ORDER_COUPON_PRICE
     ,  OCA.PRODUCT_COUPON_ID AS PRODUCT_COUPON_ID
     ,  OCA.ORDER_COUPON_ID AS ORDER_COUPON_ID
     ,  CAST(ROUND(SAFE_DIVIDE(O.sale_price, R.sale_price) * R.point_amount, 2) * IF(RT.KIND = 1, 1, -1) AS INT) AS POINT_PRICE
     ,  P.payment_method AS PAYMENT_METHOD_VALUE
     ,  ROUND(SAFE_DIVIDE(O.sale_commission_rate, 100), 4) AS PAYMENT_COMMISSION_RATE
     ,  CAST(O.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS PAYMENT_COMMISSION_PRICE
     ,  ROUND(SAFE_DIVIDE(SD.sale_commission_rate, 100), 4) AS SETTLEMENT_COMMISSION_RATE
     ,  CAST(SD.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS SETTLEMENT_COMMISSION_PRICE
     ,  CT.CITY AS CITY_NM
     ,  CT.COUNTRY AS COUNTRY_NM
     ,  CT.REGION AS REGION_NM
     ,  LOWER(OD.trip_purpose) AS RESVE_PURPOSE_TYPE
     ,  SRR.number_of_children AS CHILD_RESVE_PRSNL_CNT
     ,  SRR.number_of_adults AS ADULT_RESVE_PRSNL_CNT
     ,  SRR.number_of_children + SRR.number_of_adults AS RESVE_PRSNL_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET RT
LEFT JOIN {{ source('orders', 'order_payments') }} P ON RT.payment_id = P.id AND P.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations') }} R ON RT.RESVE_ID = R.id
LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RT.RESVE_OPTION_ID = O.id
LEFT JOIN {{ source('orders', 'orders') }} OD ON R.order_id = OD.id AND OD.deleted_at IS NULL
LEFT JOIN {{ source('unionstay', 'reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no
LEFT JOIN {{ source('unionstay', 'reservation_room') }} SRR ON SRR.reservation_id = SR.reservation_id
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.union_product_id = UPS.id
LEFT JOIN {{ source('hotel', 'property') }} PT ON R.union_product_id = PT.gid AND PT.deleted_at IS NULL
LEFT JOIN {{ source('hotel', 'rate') }} SRT ON REGEXP_EXTRACT(O.option_id, r':-:\d+:-:\d+:-:(\d+):-:\d+') = CAST(SRT.rate_id AS STRING)
LEFT JOIN {{ source('hotel', 'stay_option') }} OT ON SRT.option_id = OT.option_id
LEFT JOIN CITY_NODUP cr ON R.product_id = cr.offer_id
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS STRING) = U.USER_ID
LEFT JOIN {{ ref("DIM_CITY") }} CT ON cr.mrt_city = CT.CODE
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC ON UPS.standard_category_code = SC.LV_3_CD
LEFT JOIN SETTLEMENT_DATA SD ON RT.RESVE_OPTION_ID = SD.option_reservation_id
LEFT JOIN OPTION_COUPON_ALLOCATION OCA
  ON RT.RESVE_OPTION_ID = OCA.RESVE_OPTION_ID
 AND RT.KIND = OCA.KIND
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON CAST(R.union_product_id AS STRING) = TP.GID
WHERE (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)
  AND TP.GID IS NULL
