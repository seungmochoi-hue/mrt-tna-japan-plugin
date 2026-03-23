{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_TNA_OPTION_SALE_D'
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
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR ON R.reservation_no = PR.mrt_reservation_no
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no
    WHERE CASE WHEN R.is_pay_later = TRUE THEN RH.status IN ('CONFIRM', 'FINISH')
               ELSE RH.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH') END
      AND P.deleted_at IS NULL
      AND P.pg_authorized_at IS NOT NULL
      -- 옵션 데이터가 없는 예약 제외: option_reservations 매칭 실패 시 NULL row 방어
      AND O.id IS NOT NULL
      AND PR.id IS NULL AND SR.reservation_id IS NULL
      -- package_reservation 누락 매핑 방어: PKG 예약번호는 TNA 마트에서 제외
      AND NOT STARTS_WITH(UPPER(COALESCE(R.reservation_no, '')), 'PKG')

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
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR ON R.reservation_no = PR.mrt_reservation_no
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND PR.id IS NULL AND SR.reservation_id IS NULL
      -- package_reservation 누락 매핑 방어: PKG 예약번호는 TNA 마트에서 제외
      AND NOT STARTS_WITH(UPPER(COALESCE(R.reservation_no, '')), 'PKG')
    GROUP BY R.id, O.id
),
CITY_NODUP AS (
    SELECT t.offer_id
         ,  t.is_representative
         ,  t.city_key_name
    FROM (
             SELECT c.offer_id
                  ,  c.is_representative
                  ,  c.city_key_name
                  ,  ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN
             FROM {{ ref('city_to_region') }} c
             WHERE city_info_id IS NOT NULL
         ) t
    WHERE t.RN = 1
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
    LEFT JOIN {{ source('package_solution', 'package_reservation') }} PR
      ON R.reservation_no = PR.mrt_reservation_no
    LEFT JOIN {{ source('unionstay', 'reservation') }} SR
      ON R.reservation_no = SR.mrt_reservation_no
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND RF.canceled_at IS NOT NULL
      AND RF.refund_amount <> 0
      AND PR.id IS NULL
      AND SR.reservation_id IS NULL
      AND NOT STARTS_WITH(UPPER(COALESCE(R.reservation_no, '')), 'PKG')
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
     ,  CAST(OD.id AS STRING) AS ORDER_ID
     ,  CAST(R.product_id AS STRING) AS PRODUCT_ID
     ,  CAST(O.option_id AS STRING) AS OPTION_ID
     ,  IFNULL(CAST(R.union_product_id AS STRING), N.PRODUCT_ID) AS GID
     ,  CAST(O.union_product_id AS STRING) AS OPTION_GID
     ,  CASE WHEN SC.LV_1_CD = 'TRANSPORTATION_V2' THEN 'RENTALCAR' ELSE 'TNA' END AS RESVE_TYPE
     ,  RT.KIND AS KIND
     ,  R.product_title AS PRODUCT_TITLE
     ,  O.option_title AS OPTION_TITLE
     ,  O.canceled_at AS CANCEL_KST_DT
     ,  LOWER(O.status) AS RECENT_STATUS
     ,  DATE(R.trip_started_at) AS TRAVEL_START_KST_DATE
     ,  DATE(R.trip_ended_at) AS TRAVEL_END_KST_DATE
     ,  LOWER(P.pg) AS PG_NM
     ,  LOWER(OD.ordered_platform) AS PLATFORM
     ,  P.first_payment_date AS RESVE_PAID_KST_DT
     ,  IFNULL(SC.LV_1_CD, SC2.LV_1_CD) AS STANDARD_CATEGORY_LV_1_CD
     ,  IFNULL(SC.LV_1_NM, SC2.LV_1_NM) AS STANDARD_CATEGORY_LV_1_NM
     ,  IFNULL(SC.LV_2_CD, SC2.LV_2_CD) AS STANDARD_CATEGORY_LV_2_CD
     ,  IFNULL(SC.LV_2_NM, SC2.LV_2_NM) AS STANDARD_CATEGORY_LV_2_NM
     ,  IFNULL(SC.LV_3_CD, SC2.LV_3_CD) AS STANDARD_CATEGORY_LV_3_CD
     ,  IFNULL(SC.LV_3_NM, SC2.LV_3_NM) AS STANDARD_CATEGORY_LV_3_NM
     ,  O.created_at AS CREATE_KST_DT
     ,  O.updated_at AS UPDATE_KST_DT
     ,  CAST(O.partner_id AS STRING) AS OPTION_PARTNER_ID
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
     ,  IFNULL(CT.CITY, VCT.CITY) AS CITY_NM
     ,  IFNULL(CT.COUNTRY, VCT.COUNTRY) AS COUNTRY_NM
     ,  IFNULL(CT.REGION, VCT.REGION) AS REGION_NM
     ,  LOWER(OD.trip_purpose) AS RESVE_PURPOSE_TYPE
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET RT
LEFT JOIN {{ source('orders', 'order_payments') }} P ON RT.payment_id = P.id AND P.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations') }} R ON RT.RESVE_ID = R.id
LEFT JOIN {{ source('orders', 'option_reservations') }} O ON RT.RESVE_OPTION_ID = O.id
LEFT JOIN {{ source('orders', 'orders') }} OD ON R.order_id = OD.id AND OD.deleted_at IS NULL
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.union_product_id = UPS.id
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC ON UPS.standard_category_code = SC.LV_3_CD
LEFT JOIN {{ ref('DW_MRT_UPS_UNION_PRODUCT_NODUP') }} N ON R.product_id = N.PRODUCT_NO
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS2 ON N.PRODUCT_ID = CAST(UPS2.id AS STRING)
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC2 ON UPS2.standard_category_code = SC2.LV_3_CD
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS STRING) = U.USER_ID
LEFT JOIN CITY_NODUP D ON R.product_id = D.offer_id
LEFT JOIN {{ ref("DIM_CITY") }} CT ON D.city_key_name = CT.CODE
LEFT JOIN SETTLEMENT_DATA SD ON RT.RESVE_OPTION_ID = SD.option_reservation_id
LEFT JOIN OPTION_COUPON_ALLOCATION OCA
  ON RT.RESVE_OPTION_ID = OCA.RESVE_OPTION_ID
 AND RT.KIND = OCA.KIND
LEFT JOIN {{ source('mustang', 'mst_vehicle') }} vh ON O.product_id = CAST(vh.id AS STRING)
LEFT JOIN {{ source('mustang', 'mst_agency') }} ag ON vh.agency_id = ag.id
LEFT JOIN {{ ref("DIM_CITY") }} VCT ON ag.mrt_city = VCT.CODE
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON CAST(R.union_product_id AS STRING) = TP.GID
WHERE R.product_title NOT LIKE '%테스트%'
  AND (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)
  AND TP.GID IS NULL
