{{
    config(
        materialized = 'table',
        schema='edw_mart',
        alias='MART_ESIM_OPTION_SALE_D'
    )
}}


WITH
  RESERVATION_TARGET AS (
    SELECT DISTINCT
          CAST(P.first_payment_date AS DATE) AS basis_date
        ,  SR.mrt_reservation_no as reservation_no
        ,  1 AS kind
        ,  CAST(null AS timestamp) AS canceled_at
        ,  P.id AS payment_id
    FROM {{ source('orders', 'order_payments') }} P
    LEFT JOIN {{ source('orders', 'reservations') }} R on P.order_id = R.order_id AND R.deleted_at IS NULL
    LEFT JOIN {{ source('orders', 'reservations_histories') }} RH on R.reservation_no = RH.reservation_no AND RH.deleted_at IS NULL
    LEFT JOIN {{ source('mustang_esim','esim_reservation') }} SR ON R.reservation_no = SR.mrt_reservation_no AND SR.deleted_at IS NULL
    WHERE P.deleted_at IS NULL
      AND P.pg_authorized_at IS NOT NULL
      AND SR.mrt_reservation_no IS NOT NULL
      AND SR.confirmed_at IS NOT NULL
      AND SR.canceled_at IS NULL
      AND CASE WHEN R.is_pay_later = TRUE THEN RH.status IN ('CONFIRM', 'FINISH')
                  ELSE RH.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH') END

    UNION ALL

    SELECT CAST(MIN(IFNULL(RF.refunded_at, R.canceled_at)) AS DATE) AS basis_date
        ,  RS.reservation_no
        ,  2 AS kind
        ,  MIN(R.canceled_at) AS canceled_at
        ,  P.id AS payment_id
    FROM {{ source('orders', 'reservation_refunds') }} R
    LEFT JOIN {{ source('orders', 'order_refunds') }} RF ON R.order_refund_id = RF.id
    LEFT JOIN {{ source('orders', 'order_payments') }} P ON RF.order_id = P.order_id AND P.deleted_at IS NULL
    LEFT JOIN {{ source('orders', 'reservations') }} RS ON R.reservation_id = RS.id
    LEFT JOIN {{ source('mustang_esim','esim_reservation') }} SR ON RS.reservation_no = SR.mrt_reservation_no AND SR.deleted_at IS NULL
    WHERE R.deleted_at IS NULL
      AND R.refund_type IN ('FULL_CANCEL', 'PARTIAL_CANCELED')
      AND R.refund_status = 'COMPLETE'
      AND P.pg_authorized_at IS NOT NULL
      AND SR.mrt_reservation_no IS NOT NULL
      AND SR.confirmed_at IS NOT NULL
    GROUP BY RS.reservation_no, P.id
)

-- KIND=2 dedup: option_reservation_refunds 분할환불 N건 -> GROUP BY option_id로 1건 집약.
-- 분할환불 합산 정책: refund_amount=전체 합산(SUM). 전체 금액이 최초 환불일에 귀속됨.
-- TNA/STAY/PACKAGE와 동일 패턴.
, REFUND_DATA AS (
    SELECT RF.option_id
         , SUM(RF.refund_amount) AS refund_amount
    FROM {{ source('orders', 'option_reservation_refunds') }} RF
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND RF.refund_amount <> 0
    GROUP BY RF.option_id
)

, DW_MRT_UPS_UNION_PRODUCT_V3_PREPROCESS AS (
  SELECT
    *,
    JSON_VALUE(city_list, '$.country') AS REPRESENTATIVE_COUNTRY_CD,
    JSON_VALUE(city_list, '$.representative') AS REPRESENTATIVE
  FROM {{ source('ups', 'union_product_v3') }}
  LEFT JOIN UNNEST(JSON_EXTRACT_ARRAY(locations)) city_list
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY REPRESENTATIVE DESC) = 1
)

SELECT T.BASIS_DATE AS BASIS_DATE
     ,  CAST(P.USER_ID AS STRING) AS USER_ID
     ,  T.reservation_no AS RESVE_ID
     ,  CAST(RO.esim_reservation_option_no AS STRING) AS RESVE_OPTION_ID
     ,  CAST(P.order_id AS STRING) AS ORDER_ID
     ,  CAST(R.id AS STRING) AS ESIM_RESVE_ID
     ,  CAST(RO.id AS STRING) AS ESIM_RESVE_OPTION_ID
     ,  'ESIM' AS DOMAIN_NM
     ,  CAST(R.gid AS STRING) AS GID
     ,  CAST(UPS.gpid AS STRING) AS GPID
     ,  T.kind AS KIND
     ,  R.status AS RECENT_STATUS
     ,  CAST(UPS.partner_id AS STRING) AS PARTNER_ID
     ,  R.confirmed_at AS CONFIRM_KST_DT
     ,  T.canceled_at AS CANCEL_KST_DT
     ,  RO.days AS PRODUCT_DT_CNT -- 기간
     ,  M.esim_status AS ESIM_STATUS
     ,  M.usage_type AS USAGE_TYPE
     ,  M.receive_status AS RECEIVE_STATUS
     ,  M.issued_at_kst AS ISSUED_KST_DT
     ,  M.valid_until_kst AS VALID_UNTIL_KST_DT
     ,  M.activated_at_kst AS ACTIVATED_KST_DT
     ,  M.expired_at_kst AS EXPIRED_KST_DT
     ,  RES.kst_trip_started_at AS TRAVEL_START_KST_DT
     ,  RES.kst_trip_ended_at AS TRAVEL_END_KST_DT
     -- 이심 크로스셀 플래그 추가
     -- edw.dim_cross_sell 참고
     ,  D.INCLUDE_FLIGHT_FLAG
     ,  D.CROSS_SELL_FLAG
     ,  LOWER(UPS.product_type) AS PRODUCT_TYPE
     ,  LOWER(RES.type) AS ORDER_RESVE_TYPE
     ,  RO.esim_option_type AS RESVE_ITEM_TYPE
    --  ,  REGEXP_EXTRACT(UPS.product_urls, r'[?&]journey=([^&]+)') AS TRAVEL_TYPE
     ,  C.LV_1_CD AS STANDARD_CATEGORY_LV_1_CD
     ,  C.Lv_1_NM AS STANDARD_CATEGORY_LV_1_NM
     ,  C.LV_2_CD AS STANDARD_CATEGORY_LV_2_CD
     ,  C.Lv_2_NM AS STANDARD_CATEGORY_LV_2_NM
     ,  C.LV_3_CD AS STANDARD_CATEGORY_LV_3_CD
     ,  C.Lv_3_NM AS STANDARD_CATEGORY_LV_3_NM
     ,  R.product_code AS PRODUCT_CD
     -- 도시 코드 추가 UPS참조
     ,  REPRESENTATIVE_COUNTRY_CD
     ,  MCO.country_name AS REPRESENTATIVE_COUNTRY_NM
     ,  MCO.english_name AS REPRESENTATIVE_COUNTRY_EN_NM
     ,  MCO.korean_name AS REPRESENTATIVE_COUNTRY_KR_NM
     ,  MCI.city_name AS REPRESENTATIVE_CITY_NM
     ,  MCI.english_name AS REPRESENTATIVE_CITY_EN_NM
     ,  MCI.korean_name AS REPRESENTATIVE_CITY_KR_NM
     ,  RO.created_at AS CREATE_KST_DATE
     ,  RO.updated_at AS UPDATE_KST_DATE
     ,  O.ordered_platform AS PLATFORM
     ,  P.first_payment_date AS RESVE_PAID_KST_DT
     ,  RES.partnership_code AS PARTNERSHIP_CD
     ,  RES.partnership_type AS PARTNERSHIP_TYPE
     ,  RES.marketing_partnership_code AS MARKETING_PARTNERSHIP_CD
     ,  CAST(PP.partner_id AS STRING) AS PARTNERSHIP_PARTNER_ID
     ,  CAST(RES.marketing_link_id AS STRING) AS MARKETING_LINK_ID
     ,  LOWER(P.pg) AS PG_NM
     ,  P.payment_method AS PAYMENT_METHOD_VALUE
     ,  RO.supply_price AS SUPPLY_PRICE
     ,  IF(T.KIND = 1, ROUND(RO.price, 2), NULL) AS SALES_PRICE
     ,  P.foreign_currency AS SALES_PRICE_CUR_TYPE
     ,  RO.supply_price AS SUPPLY_KRW_PRICE
     ,  IF(T.KIND = 1, RO.price, RF.refund_amount * -1) AS SALES_KRW_PRICE
     -- 옵션 reserv 갯수 1/n
     -- reservation 과 reservation_option이 1:1 이라 적용하지 않음
     ,  IF(T.KIND = 1, RO.price - RES.coupon_discount_amount - RES.point_amount,
          (RF.refund_amount - RES.coupon_discount_amount - RES.point_amount)* -1) AS PAID_KRW_PRICE
     ,  RES.coupon_discount_amount * IF(KIND = 1, 1, -1) AS COUPON_KRW_PRICE
     ,  RES.point_amount * IF(KIND = 1, 1, -1) AS POINT_KRW_PRICE
     ,  IF(T.KIND = 1, RO.mrt_margin_price, NULL) AS MARGIN_PRICE
     ,  IF(T.KIND = 1, RO.partner_commission, NULL) AS COMMISSION_PRICE
     ,  RO.mrt_margin_price * IF(T.KIND = 1, 1, -1) AS MARGIN_KRW_PRICE
     ,  RO.partner_commission * IF(T.KIND = 1, 1, -1) AS COMMISSION_KRW_PRICE
     ,  ROUND(SAFE_DIVIDE(RO.mrt_margin_price, RO.price), 2) AS MARGIN_RATE
     ,  ROUND(SAFE_DIVIDE(RO.partner_commission, RO.price), 2) AS COMMISSION_RATE
     ,  1 AS RESVE_PRSNL_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET T
LEFT JOIN {{ source('orders', 'order_payments') }} P ON T.payment_id = P.id AND P.deleted_at IS NULL
LEFT JOIN {{ source('mustang_esim','esim_reservation') }} R ON T.reservation_no = R.mrt_reservation_no AND R.deleted_at IS NULL
LEFT JOIN {{ source('mustang_esim','esim_reservation_option') }} RO ON R.id = RO.esim_reservation_id AND RO.deleted_at IS NULL
LEFT JOIN {{ source('mustang_esim','esim_management') }} M ON M.id = RO.id AND M.deleted_at IS NULL
LEFT JOIN REFUND_DATA RF ON RO.esim_reservation_option_no = RF.option_id
LEFT JOIN {{ source('orders', 'orders') }} O ON P.order_id = O.id AND O.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations') }} RES ON T.reservation_no = RES.reservation_no AND RES.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservation_additions') }} RESA ON RES.id = RESA.reservation_id AND RESA.deleted_at IS NULL
LEFT JOIN {{ source('partners', 'partnership') }} PP ON RES.partnership_code = PP.code
LEFT JOIN DW_MRT_UPS_UNION_PRODUCT_V3_PREPROCESS UPS ON R.gid = UPS.id AND UPS.deleted_at IS NULL
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} C ON UPS.standard_category_code = C.LV_3_CD
LEFT JOIN {{ source('mustang_esim','usimsa_product') }} UP ON UP.product_code = R.product_code
LEFT JOIN {{ source('mustang_esim','mcc_country') }} MCO ON MCO.id = UP.representative_country_id
LEFT JOIN {{ source('mustang_esim','mcc_city') }} MCI ON MCI.id = UP.representative_city_id
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(P.user_id AS STRING) = U.USER_ID
LEFT JOIN {{ ref('DIM_CROSS_SELL') }} D ON D.RESVE_ID = T.reservation_no
WHERE (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)