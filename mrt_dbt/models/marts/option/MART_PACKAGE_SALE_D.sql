{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PACKAGE_SALE_D'
    )
}}
    
WITH RESERVATION_TARGET AS (
    SELECT DISTINCT CAST(P.first_payment_date AS DATE) AS BASIS_DATE
        ,  R.id                      AS RESVE_ID
        ,  O.id                      AS RESVE_OPTION_ID
        ,  1                         AS kind
        ,  CAST(NULL AS TIMESTAMP)   AS canceled_at
        ,  P.id                      AS payment_id
        ,  O.sale_price              AS REFUND_PRICE -- KIND=1: 옵션 원가. KIND=2의 SUM(refund_amount)와 컬럼 수 일치용
    FROM {{ source('orders', 'order_payments') }} P
    LEFT JOIN {{ source('orders', 'reservations') }} R ON P.order_id = R.order_id AND R.deleted_at IS NULL
    LEFT JOIN {{ source('orders', 'option_reservations') }} O ON R.id = O.reservation_id
    LEFT JOIN {{ source('orders', 'reservations_histories') }} RH ON R.reservation_no = RH.reservation_no
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR ON R.reservation_no = PR.mrt_reservation_no
    WHERE RH.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH')
      AND P.deleted_at IS NULL
      AND P.pg_authorized_at IS NOT NULL
      AND (PR.id IS NOT NULL OR R.reservation_no LIKE '%PKG%')


    UNION ALL

    -- KIND=2 dedup: option_reservation_refunds 분할환불 N건 -> GROUP BY로 옵션당 1건 집약.
    -- 분할환불 합산 정책: BASIS_DATE=최초 환불일(MIN), REFUND_PRICE=전체 합산(SUM).
    -- 이후 환불 시점은 유실되며 전체 금액이 최초 환불일에 귀속됨. TNA/STAY(PR #215)와 동일 패턴.
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
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR ON R.reservation_no = PR.mrt_reservation_no
    WHERE (PR.id IS NOT NULL OR R.reservation_no LIKE '%PKG%')
      AND RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
    GROUP BY R.id, O.id
),
CITY_NODUP AS (
    SELECT t.offer_id
        ,  t.is_representative -- 신규 추가
        ,  t.city_key_name
    FROM (
    SELECT c.offer_id
        ,  c.is_representative  -- 추가
        ,  c.city_key_name
        ,  ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN # 로직 변경
    FROM {{ ref('city_to_region') }} c
    WHERE city_info_id IS NOT NULL
    ) t
    WHERE t.RN = 1
),
SETTLEMENT_DATA AS (
    SELECT option_reservation_id
         , sale_commission
         , sale_commission_rate
    FROM (
        SELECT P.option_reservation_id
             , P.sale_commission
             , P.sale_commission_rate
             , ROW_NUMBER() OVER (PARTITION BY P.option_reservation_id ORDER BY P.id DESC) AS RN
        FROM {{ source('settles', 'settlement_product_closing') }} P
        WHERE P.deleted_at IS NULL
          AND P.closing_type IN ('PAYMENT', 'PAYMENT_OF_REFUND')
    )
    WHERE RN = 1
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
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR
      ON R.reservation_no = PR.mrt_reservation_no
    WHERE (PR.id IS NOT NULL OR R.reservation_no LIKE '%PKG%')
      AND RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND O.deleted_at IS NULL
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
    WHERE O.deleted_at IS NULL
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
    ,  CAST(R.user_id AS STRING)          AS USER_ID
    ,  CAST(R.reservation_no AS STRING)   AS RESVE_ID
    ,  CAST(O.id AS STRING)               AS RESVE_OPTION_ID
    ,  CAST(OD.id AS STRING)              AS ORDER_ID
    ,  CAST(R.product_id AS STRING)       AS PRODUCT_ID
    ,  CAST(O.option_id AS STRING)        AS OPTION_ID
    ,  CAST(R.union_product_id AS STRING) AS PACKAGE_GID
    ,  CAST(R.sync_id AS STRING)          AS PACKAGE_SYNC_ID
    ,  CAST(O.union_product_id AS STRING) AS PAKAGE_OPTION_GID
    ,  RT.KIND                            AS KIND
    ,  R.product_title                    AS PACKAGE_TITLE
    ,  POR.title                          AS PACKAGE_SYNC_TITLE
    ,  CP.title                           AS PACKAGE_OPTION_TITLE
    ,  CP.product_type                    AS PACKAGE_OPTION_TYPE
    ,  O.canceled_at                      AS CANCEL_KST_DT
    ,  CASE WHEN PR.reservation_status IS NOT NULL THEN PR.reservation_status
            WHEN R.type = 'SURCHARGE' THEN R.status END AS RESVE_RECENT_STATUS
    ,  DATE(R.trip_started_at)            AS TRAVEL_START_KST_DATE
    ,  DATE(R.trip_ended_at)              AS TRAVEL_END_KST_DATE
    ,  LOWER(P.pg)                        AS PG_NM
    ,  LOWER(OD.ordered_platform)         AS PLATFORM
    ,  P.first_payment_date               AS RESVE_PAID_KST_DT
    ,  SC.LV_1_CD                         AS PACKAGE_STANDARD_CATEGORY_LV_1_CD
    ,  SC.LV_1_NM                         AS PACKAGE_STANDARD_CATEGORY_LV_1_NM
    ,  SC.LV_2_CD                         AS PACKAGE_STANDARD_CATEGORY_LV_2_CD
    ,  SC.LV_2_NM                         AS PACKAGE_STANDARD_CATEGORY_LV_2_NM
    ,  SC.LV_3_CD                         AS PACKAGE_STANDARD_CATEGORY_LV_3_CD
    ,  SC.LV_3_NM                         AS PACKAGE_STANDARD_CATEGORY_LV_3_NM
    ,  O.created_at                       AS CREATE_KST_DT
    ,  O.updated_at                       AS UPDATE_KST_DT
    ,  CAST(R.partner_id AS STRING)       AS PACKAGE_PARTNER_ID
    ,  CAST(O.partner_id AS STRING)       AS PACKAGE_OPTION_PARTNER_ID
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
    ,  P.payment_method                   AS PAYMENT_METHOD_VALUE
    ,  ROUND(SAFE_DIVIDE(O.sale_commission_rate, 100), 4) AS PAYMENT_COMMISSION_RATE
    ,  CAST(O.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS PAYMENT_COMMISSION_PRICE
    ,  ROUND(SAFE_DIVIDE(SD.sale_commission_rate, 100), 4) AS SETTLEMENT_COMMISSION_RATE
    ,  CAST(SD.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS SETTLEMENT_COMMISSION_PRICE
    ,  CT.CITY                            AS CITY_NM
    ,  CT.COUNTRY                         AS COUNTRY_NM
    ,  CT.REGION                          AS REGION_NM
    ,  LOWER(OD.trip_purpose)             AS RESVE_PURPOSE_TYPE
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET RT
LEFT JOIN {{ source('orders', 'order_payments') }} P ON RT.payment_id = P.id AND P.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations') }} R ON RT.RESVE_ID = R.id
LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RT.RESVE_OPTION_ID = O.id
LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR ON R.reservation_no = PR.mrt_reservation_no
LEFT JOIN {{ source('orders', 'orders') }} OD ON R.order_id = OD.id AND OD.deleted_at IS NULL
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.union_product_id = UPS.id
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC ON UPS.standard_category_code = SC.LV_3_CD
  --LEFT JOIN edw.DW_MRT_PACKAGE_SOLUTION_PACKAGE_PRODUCT_OPTION PO ON CAST(PO.id AS STRING) = R.sync_id -- 옵션 구조 변경
LEFT JOIN {{ source('package_solution', 'reservation_option') }} POR ON POR.id = PR.reservation_option_id AND POR.deleted_at IS NULL
LEFT JOIN {{ source('package_solution', 'component_product') }} CP ON O.union_product_id = CP.id AND CP.deleted_at IS NULL
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS STRING) = U.USER_ID
LEFT JOIN CITY_NODUP d ON R.product_id = d.offer_id
LEFT JOIN {{ ref("DIM_CITY") }} CT ON d.city_key_name = CT.CODE
LEFT JOIN SETTLEMENT_DATA SD ON RT.RESVE_OPTION_ID = SD.option_reservation_id
LEFT JOIN OPTION_COUPON_ALLOCATION OCA
  ON RT.RESVE_OPTION_ID = OCA.RESVE_OPTION_ID
 AND RT.KIND = OCA.KIND
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON CAST(R.union_product_id AS STRING) = TP.GID
WHERE R.product_title NOT LIKE '%테스트%'
  AND (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)
  AND TP.GID IS NULL
