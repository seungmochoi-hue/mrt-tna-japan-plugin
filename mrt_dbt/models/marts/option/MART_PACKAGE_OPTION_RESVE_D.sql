{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PACKAGE_OPTION_RESVE_D'
    )
}}

WITH MAP_HIST AS (
    SELECT
        M.reservation_id
      , M.mapping_reservation_id
      , M.id
      , LAG(M.id) OVER (PARTITION BY M.reservation_id ORDER BY M.id) AS PREV_ID
    FROM {{ source('orders', 'reservation_mapping') }} M
    WHERE M.deleted_at IS NULL
      AND M.created_at >= '2025-07-01'

),
MAP_LATEST AS (
    SELECT
        M.reservation_id
      , MAX(M.id) AS LATEST_ID
    FROM {{ source('orders', 'reservation_mapping') }} M
    WHERE M.deleted_at IS NULL
      AND M.created_at >= '2025-07-01'
    GROUP BY M.reservation_id
),
MAP_EXPANDED AS (
    -- 마이팩예약: reservation_id 당 1행(최신 id 부여)
    SELECT
        ML.reservation_id AS RESVE_ID
      , ML.LATEST_ID AS MAPPING_ID
      , '마이팩예약' AS RESVE_TYPE
      , CAST(NULL AS INT64) AS MAPPING_CHANGE_ID
    FROM MAP_LATEST ML

    UNION ALL

    -- 원예약: 각 매핑행(각 id)에 대해 직전 id 부여
    SELECT
        MH.mapping_reservation_id AS RESVE_ID
      , ML.LATEST_ID AS MAPPING_ID
      , '원예약' AS RESVE_TYPE
      , CAST(MH.PREV_ID AS INT64) AS MAPPING_CHANGE_ID
    FROM MAP_HIST MH
    JOIN MAP_LATEST ML
      ON ML.reservation_id = MH.reservation_id
),
RESERVATION_TARGET AS (
    SELECT DISTINCT
        CAST(P.first_payment_date AS DATE) AS BASIS_DATE
      , R.id AS RESVE_ID
      , O.id AS RESVE_OPTION_ID
      , 1 AS KIND
      , CAST(NULL AS TIMESTAMP) AS CANCELED_AT
      , CAST(NULL AS STRING) AS CANCEL_REASON_TYPE
      , P.id AS PAYMENT_ID
      , O.sale_price AS SALE_PRICE
    FROM {{ source('orders', 'order_payments') }} P
    LEFT JOIN {{ source('orders', 'reservations') }} R ON P.order_id = R.order_id AND R.deleted_at IS NULL
    LEFT JOIN {{ source('orders', 'option_reservations') }} O ON R.id = O.reservation_id
    LEFT JOIN {{ source('orders', 'reservations_histories') }} RH ON R.reservation_no = RH.reservation_no
    LEFT JOIN MAP_EXPANDED M ON M.RESVE_ID = R.id
    WHERE RH.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH')
      AND P.deleted_at IS NULL
      AND P.pg_authorized_at IS NOT NULL
      AND (((R.system_provider = 'PKG' OR M.RESVE_ID IS NOT NULL) AND R.created_at >= '2025-07-01' AND R.version = 2)
       OR ((R.reservation_no LIKE 'PKG%') AND R.created_at < '2025-07-01' AND R.version = 1))

    UNION ALL

    SELECT MIN(T.BASIS_DATE) AS BASIS_DATE
        ,  T.RESVE_ID
        ,  T.RESVE_OPTION_ID
        ,  T.KIND
        ,  MIN(T.CANCELED_AT) AS CANCELED_AT
        ,  MIN(T.CANCEL_REASON_TYPE) AS CANCEL_REASON_TYPE
        ,  MIN(T.PAYMENT_ID) AS PAYMENT_ID
        ,  SUM(T.SALE_PRICE) AS SALE_PRICE
      FROM (
        SELECT DISTINCT
            CAST(RF.canceled_at AS DATE) AS BASIS_DATE
          , R.id AS RESVE_ID
          , O.id AS RESVE_OPTION_ID
          , 2 AS KIND
          , MIN(CAST(RF.canceled_at AS TIMESTAMP)) AS CANCELED_AT
          , STRING_AGG(DISTINCT RF.cancel_reason_type, ', ' order by RF.cancel_reason_type) AS CANCEL_REASON_TYPE
          , P.id AS PAYMENT_ID
          , RF.refund_amount AS SALE_PRICE
        FROM {{ source('orders', 'option_reservation_refunds') }} RF
        LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RF.option_reservation_id = O.id
        LEFT JOIN {{ source('orders', 'reservations') }} R ON R.id = O.reservation_id
        LEFT JOIN {{ source('orders', 'order_payments') }} P ON R.order_id = P.order_id AND P.deleted_at IS NULL
        LEFT JOIN MAP_EXPANDED M ON M.RESVE_ID = R.id
        WHERE RF.deleted_at IS NULL
          AND RF.refund_status = 'COMPLETE'
          AND P.pg_authorized_at IS NOT NULL
          AND RF.canceled_at IS NOT NULL
          AND RF.refund_amount <> 0
          AND (((R.system_provider = 'PKG' OR M.RESVE_ID IS NOT NULL) AND R.created_at >= '2025-07-01' AND R.version = 2)
           OR ((R.reservation_no LIKE 'PKG%') AND R.created_at < '2025-07-01' AND R.version = 1))
        GROUP BY CAST(RF.canceled_at AS DATE), R.id, O.id, P.id, RF.refund_amount
    ) T
    GROUP BY T.RESVE_ID, T.RESVE_OPTION_ID, T.KIND
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
    LEFT JOIN MAP_EXPANDED M
      ON M.RESVE_ID = R.id
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND O.deleted_at IS NULL
      AND (((R.system_provider = 'PKG' OR M.RESVE_ID IS NOT NULL) AND R.created_at >= '2025-07-01' AND R.version = 2)
       OR ((R.reservation_no LIKE 'PKG%') AND R.created_at < '2025-07-01' AND R.version = 1))
    GROUP BY R.reservation_no
),
OPTION_COUPON_ALLOCATION_BASE AS (
    SELECT
        RT.RESVE_OPTION_ID
      , RT.KIND
      , CAST(R.reservation_no AS STRING) AS RESVE_ID
      , CAST(CASE WHEN RT.KIND = 1 THEN O.sale_price ELSE ABS(RT.SALE_PRICE) END AS INT64) AS OPTION_ALLOC_PRICE
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
SELECT DISTINCT
      RT.BASIS_DATE AS BASIS_DATE
    , CAST(OD.id AS STRING) AS ORDER_ID
    , R.reservation_no AS RESVE_ID
    , CAST(O.option_id AS STRING) AS OPTION_ID
    , CAST(RT.RESVE_OPTION_ID AS STRING) AS RESVE_OPTION_ID
    , RT.KIND AS KIND
    , CAST(ME.MAPPING_ID AS STRING) AS RESVE_MAPPING_ID
    , IFNULL(ME.RESVE_TYPE, '마이팩예약') AS RESVE_MAPPING_TYPE
    , CAST(ME.MAPPING_CHANGE_ID AS STRING) AS RESVE_MAPPING_CHANGE_ID
    , R.version AS RESVE_VERSION_VALUE
    , CAST(R.product_id AS STRING) AS PRODUCT_ID
    , CAST(O.product_id AS STRING) AS OPTION_PRODUCT_ID
    , CAST(R.union_product_id AS STRING) AS PACKAGE_GID
    , CAST(O.union_product_id AS STRING) AS PACKAGE_OPTION_GID
    , CAST(O.link_id AS STRING) AS LINK_ID
    , RT.CANCELED_AT AS CANCELED_AT
    , RT.cancel_reason_type AS CANCEL_REASON_TYPE
    , RT.PAYMENT_ID AS PAYMENT_ID
    , R.product_title AS RESVE_TITLE
    , O.option_title AS OPTION_RESVE_TITLE
    , R.type AS RESVE_TYPE
    , O.option_type AS OPTION_RESVE_TYPE
    , LOWER(R.status) AS RECENT_RESVE_STATUS
    , LOWER(O.status) AS RECENT_OPTION_RESVE_STATUS
    , DATE(R.trip_started_at) AS RESVE_TRAVEL_START_KST_DATE
    , DATE(O.trip_started_at) AS TRAVEL_START_KST_DATE
    , DATE(O.trip_ended_at) AS TRAVEL_END_KST_DATE
    , LOWER(P.pg) AS PG_NM
    , LOWER(OD.ordered_platform) AS PLATFORM
    , P.first_payment_date AS RESVE_PAID_KST_DT
    , SC.LV_1_CD AS PACKAGE_STANDARD_CATEGORY_LV_1_CD
    , SC.LV_1_NM AS PACKAGE_STANDARD_CATEGORY_LV_1_NM
    , SC.LV_2_CD AS PACKAGE_STANDARD_CATEGORY_LV_2_CD
    , SC.LV_2_NM AS PACKAGE_STANDARD_CATEGORY_LV_2_NM
    , SC.LV_3_CD AS PACKAGE_STANDARD_CATEGORY_LV_3_CD
    , SC.LV_3_NM AS PACKAGE_STANDARD_CATEGORY_LV_3_NM
    , RD.flight_reservation_no AS AIR_PNR_NO
    , O.created_at AS CREATE_KST_DT
    , O.updated_at AS UPDATE_KST_DT
    , CAST(R.partner_id AS STRING) AS PACKAGE_PARTNER_ID
    , CAST(O.partner_id AS STRING) AS PACKAGE_OPTION_PARTNER_ID
    , P.payment_method AS PAYMENT_METHOD_VALUE
    , RT.SALE_PRICE * IF(RT.KIND = 1, 1, -1) AS SALES_PRICE
    , CAST(
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
                      ABS(RT.SALE_PRICE)
                      - IFNULL(OCA.PRODUCT_COUPON_PRICE, 0)
                      - IFNULL(OCA.ORDER_COUPON_PRICE, 0)
                      - ROUND(SAFE_DIVIDE(O.sale_price, R.sale_price) * R.point_amount, 2),
                      0
                  )
          END * CASE WHEN RT.KIND = 1 THEN 1 ELSE -SIGN(RT.SALE_PRICE) END AS INT
      ) AS PAID_PRICE
    , CAST((IFNULL(OCA.PRODUCT_COUPON_PRICE, 0) + IFNULL(OCA.ORDER_COUPON_PRICE, 0)) * IF(RT.KIND = 1, 1, -1) AS INT) AS COUPON_PRICE
    , CAST(IFNULL(OCA.PRODUCT_COUPON_PRICE, 0) * IF(RT.KIND = 1, 1, -1) AS INT) AS PRODUCT_COUPON_PRICE
    , CAST(IFNULL(OCA.ORDER_COUPON_PRICE, 0) * IF(RT.KIND = 1, 1, -1) AS INT) AS ORDER_COUPON_PRICE
    , OCA.PRODUCT_COUPON_ID AS PRODUCT_COUPON_ID
    , OCA.ORDER_COUPON_ID AS ORDER_COUPON_ID
    , CAST(ROUND(SAFE_DIVIDE(O.sale_price, R.sale_price) * R.point_amount, 2) * IF(RT.KIND = 1, 1, -1) AS INT) AS POINT_PRICE
    , ROUND(SAFE_DIVIDE(O.sale_commission_rate, 100), 4) AS PAYMENT_COMMISSION_RATE
    , CAST(O.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS PAYMENT_COMMISSION_PRICE
    , ROUND(SAFE_DIVIDE(SD.sale_commission_rate, 100), 4) AS SETTLEMENT_COMMISSION_RATE
    , CAST(SD.sale_commission * IF(RT.KIND = 1, 1, -1) AS INT) AS SETTLEMENT_COMMISSION_PRICE
    , O.supply_price AS SUPPLY_PRICE
    , DC.CITY AS CITY_NM
    , DC.COUNTRY AS COUNTRY_NM
    , DC.REGION AS REGION_NM
    , LOWER(OD.trip_purpose) AS RESVE_PURPOSE_TYPE
    , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET RT
LEFT JOIN MAP_EXPANDED ME ON ME.RESVE_ID = RT.RESVE_ID
LEFT JOIN {{ source('orders', 'order_payments') }} P ON RT.payment_id = P.id AND P.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations') }} R ON RT.RESVE_ID = R.id
LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RT.RESVE_OPTION_ID = O.id
LEFT JOIN {{ source('orders', 'orders') }} OD ON R.order_id = OD.id AND OD.deleted_at IS NULL
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.union_product_id = UPS.id
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC ON UPS.standard_category_code = SC.LV_3_CD
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS STRING) = U.USER_ID
LEFT JOIN {{ ref('DIM_UPS_REP_CITY') }} D ON R.product_id = D.GID
LEFT JOIN {{ ref("DIM_CITY") }} DC ON D.CITY_NM = DC.CODE
LEFT JOIN {{ source('orders', 'option_reservation_details') }} RD ON RT.RESVE_OPTION_ID = RD.option_reservation_id
LEFT JOIN SETTLEMENT_DATA SD ON RT.RESVE_OPTION_ID = SD.option_reservation_id
LEFT JOIN OPTION_COUPON_ALLOCATION OCA
  ON RT.RESVE_OPTION_ID = OCA.RESVE_OPTION_ID
 AND RT.KIND = OCA.KIND
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON CAST(R.union_product_id AS STRING) = TP.GID
WHERE R.product_title NOT LIKE '%테스트%'
  AND (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)
  AND TP.GID IS NULL
