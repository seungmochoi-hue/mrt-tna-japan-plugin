{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_SERVICE_SALE_D'
    )
}}



WITH SERVICE_PAYMENTS_TARGET AS (
SELECT SP.reservation_id
     , SP.payment_method
     , SP.vendor
     , SP.paid_at_kst
     , SP.price_currency_code
     , SP.price_amount
FROM {{ source('mrt_20', 'payments') }} SP
WHERE SP.status = 'paid'
  AND SP.deleted_at_kst IS NULL
),
PAYMENT_RESERVATION_INFO AS (
SELECT T.reservation_id
    ,  T.payment_method
    ,  T.vendor
    ,  T.paid_at_kst
    ,  T.price_currency_code
    ,  T.price_amount
  FROM SERVICE_PAYMENTS_TARGET T
  WHERE T.reservation_id NOT IN (5380137, 6275892)

UNION ALL

SELECT IH.reservation_id
    ,  CASE WHEN IH.coupon_price_amount IS NULL THEN 'point'
            WHEN IH.point_amount IS NULL THEN 'coupon'
            ELSE 'point/coupon' END AS payment_method
    ,  '' AS vendor
    ,  IH.created_at_kst AS paid_at_kst
    ,  'KRW' AS price_currency_code
    ,  0 AS price_amount
FROM {{ source('mrt_20', 'accounting_integration_histories') }} IH
LEFT JOIN SERVICE_PAYMENTS_TARGET P ON IH.reservation_id = P.reservation_id
WHERE IH.event_type = 'payment'
  AND IH.paid_price_amount IS NULL
  AND IH.deleted_at_kst IS NULL
  AND IH.reservation_id NOT IN (5380137, 6275892) -- test 데이터
  AND P.reservation_id IS NULL
 ),
RESERVATION_TARGET AS (
SELECT MIN(CAST(IF(RSL.status <> 'cancel', PRI.paid_at_kst, RSL.created_at_kst) AS DATE)) AS basis_date
    ,  PRI.reservation_id AS reservation_id
    ,  IF(RSL.status <> 'cancel', 1, 2) AS kind
    ,  MIN(IF(RSL.status <> 'cancel', null, RSL.created_at_kst)) AS canceled_at_kst
    ,  PRI.payment_method
    ,  PRI.vendor
    ,  PRI.paid_at_kst
    ,  PRI.price_currency_code
    ,  PRI.price_amount
    ,  CM.confirmed_at
FROM PAYMENT_RESERVATION_INFO PRI
LEFT JOIN {{ source('mrt_20', 'reservation_status_logs') }} RSL ON PRI.reservation_id = RSL.reservation_id
LEFT JOIN (
    SELECT PRI.reservation_id
        ,  MAX(IF(RSL.status = 'confirm', RSL.created_at_kst, null)) AS confirmed_at
    FROM PAYMENT_RESERVATION_INFO PRI
    LEFT JOIN {{ source('mrt_20', 'reservation_status_logs') }} RSL ON PRI.reservation_id = RSL.reservation_id
    GROUP BY PRI.reservation_id
) CM ON PRI.reservation_id = CM.reservation_id
GROUP BY PRI.reservation_id, IF(RSL.status <> 'cancel', 1, 2), PRI.payment_method, PRI.vendor, PRI.paid_at_kst,  PRI.price_currency_code,  PRI.price_amount, CM.confirmed_at
),
RESERVATION_PRICE AS (
SELECT RT.reservation_id
    ,  RT.kind
    ,  IH.guide_settle_type
    ,  MAX(IF(event_type = 'payment', IH.reservation_price_amount, null)) AS reservation_price_amount
    ,  MAX(IF(event_type = 'payment', IH.reservation_price_currency_code, null)) AS reservation_price_currency_code
    ,  MAX(IF(event_type = 'payment', IH.reservation_price_amount_krw, null)) AS reservation_price_amount_krw
    ,  MAX(IF(event_type = 'payment', IH.reservation_commission_rate, null)) AS reservation_commission_rate
    ,  SUM(IF(RT.kind = 1, IF(event_type = 'payment', IH.coupon_price_amount, null), IF(event_type in ('coupon_cancel_before_confirm', 'coupon_cancel_after_confirm'), IH.coupon_price_amount, null))) AS coupon_price_amount
    ,  MAX(IF(RT.kind = 1, IF(event_type = 'payment', IH.coupon_price_currency_code, null), IF(event_type in ('coupon_cancel_before_confirm', 'coupon_cancel_after_confirm'), IH.coupon_price_currency_code, null))) AS coupon_price_currency_code
    ,  SUM(IF(RT.kind = 1, IF(event_type = 'payment', IH.paid_price_amount, null), IF(event_type in ('payment_cancel_before_confirm', 'payment_cancel_after_confirm'), IH.paid_price_amount, null))) AS paid_price_amount
    ,  MAX(IF(RT.kind = 1, IF(event_type = 'payment', IH.paid_price_currency_code, null), IF(event_type in ('payment_cancel_before_confirm', 'payment_cancel_after_confirm'), IH.paid_price_currency_code, null))) AS paid_price_currency_code
    ,  SUM(IF(RT.kind = 1, IF(event_type = 'payment', ABS(IH.point_amount), null), IF(event_type in ('point_cancel_before_confirm', 'point_cancel_after_confirm'), ABS(IH.point_amount), null))) AS point_amount
    ,  SUM(IF(RT.kind = 1, IF(event_type = 'payment', IH.guide_profit_amount_krw, null), IF(event_type in ('payment_cancel_before_confirm', 'point_cancel_before_confirm', 'coupon_cancel_before_confirm',
    'payment_cancel_after_confirm', 'point_cancel_after_confirm', 'coupon_cancel_after_confirm'), IH.guide_profit_amount_krw, 0))) AS guide_profit_amount_krw
    ,  SUM(IF(RT.kind = 1, IF(event_type = 'payment', IH.mrt_profit_amount_krw, null), IF(event_type in ('payment_cancel_before_confirm', 'point_cancel_before_confirm', 'coupon_cancel_before_confirm',
    'payment_cancel_after_confirm', 'point_cancel_after_confirm', 'coupon_cancel_after_confirm'), IH.mrt_profit_amount_krw, 0))) AS mrt_profit_amount_krw
 FROM RESERVATION_TARGET RT
 LEFT JOIN {{ source('mrt_20', 'accounting_integration_histories') }} IH ON RT.reservation_id = IH.reservation_id
 WHERE IH.deleted_at_kst IS NULL
GROUP BY RT.reservation_id, RT.kind, IH.guide_settle_type
),
CITY_NODUP AS (
SELECT T.offer_id
     , T.is_representative -- 신규 추가
     , T.city_key_name
FROM (
         SELECT c.offer_id
              , c.is_representative  -- 추가
              , c.city_key_name
              , ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN # 로직 변경
         FROM {{ ref('city_to_region') }} c
         WHERE city_info_id IS NOT NULL
     ) T
WHERE T.RN = 1

UNION ALL

-- 22.04.14 입점숙소 gid 기준 추가
SELECT p.union_product_id AS offer_id
     , CAST(NULL AS BOOL) AS is_representative -- BNB는 대표 도시 개념이 없으니 NULL로
     , MAX(lc.key_name) AS city_key_name
FROM {{ source('products', 'products') }} p
LEFT JOIN {{ source('products', 'product_city_mappings') }} cp ON p.id = cp.product_id
LEFT JOIN {{ source('products', 'location_cities') }} lc ON cp.location_city_id = lc.id
GROUP BY p.union_product_id
)
SELECT RT.basis_date AS BASIS_DATE
    ,  CAST(R.user_id AS string) AS USER_ID
    ,  CAST(RT.reservation_id AS string) AS RESVE_ID
    ,  CAST(O.id AS string) AS OFFER_ID
    ,  CAST(R.offer_id AS string) AS GID
    ,  CONCAT('OFF', CAST(R.offer_id AS string)) AS GPID
    ,  RT.kind AS KIND
    ,  LOWER(R.status) AS RECENT_STATUS
    ,  RT.canceled_at_kst AS CANCEL_KST_DT
    ,  RCR.reason_item AS CANCEL_REASON
    ,  RCR.actor AS CANCEL_SUBJECT
    ,  LOWER(O.type) AS OFFER_TYPE
    ,  R.created_at_kst AS CREATE_KST_DT
    ,  RT.paid_at_kst AS RESVE_PAID_KST_DT
    ,  RT.confirmed_at AS RESVE_CONFIRM_KST_DT
    ,  R.updated_at_kst AS UPDATE_KST_DT
    ,  CASE WHEN C.LV_1_CD = 'PACKAGE' OR (C.LV_1_CD = 'ORDER_MADE' AND C.LV_2_CD NOT IN ('KIDS_ORDER_MADE')) THEN 'B2B'
            WHEN C.LV_3_CD IN ('B2B_ACCOMMODATION_V2') THEN 'B2B'
            ELSE 'B2C' END AS SALE_FORM_CD
    ,  LOWER(R.created_platform) AS PLATFORM
    ,  R.begin_at AS TRAVEL_START_KST_DATE
    ,  R.duration_size AS TRAVEL_DURATION_VALUE
    ,  DATE_ADD(R.begin_at, INTERVAL R.duration_size day) AS TRAVEL_END_KST_DATE
    ,  IF(O.type IS NULL, IF(O.scale = 'private_tour', 'tour', NULL), LOWER(O.type)) AS RESVE_TYPE
    ,  OOC.category_id AS CATEGORY_ID
    ,  C.LV_1_CD AS STANDARD_CATEGORY_LV_1_CD
    ,  C.LV_2_CD AS STANDARD_CATEGORY_LV_2_CD
    ,  C.LV_3_CD AS STANDARD_CATEGORY_LV_3_CD
    ,  CAST(O.guide_id AS STRING) AS GUIDE_ID
    ,  cr.city_key_name AS CITY_CD
    ,  CASE WHEN cr.is_representative = true THEN 'Y' WHEN cr.is_representative = false THEN 'N' ELSE NULL END AS CITY_REPRESENTATIVE_FLAG
    ,  RT.payment_method AS PAYMENT_METHOD_VALUE
    ,  LOWER(R.created_country) AS PAYMENT_COUNTRY_CD
    ,  IF(RP.reservation_price_amount IS NULL, R.price_amount, RP.reservation_price_amount) * IF(RT.kind = 1, 1, -1) AS SALES_PRICE
    ,  IF(RP.reservation_price_amount IS NULL, R.price_currency_code, RP.reservation_price_currency_code) AS SALES_PRICE_CUR_TYPE
    ,  FLOOR(IF(RP.reservation_price_amount IS NULL, R.price_amount * COALESCE(IFNULL(CASE WHEN ce.to_currency = 'JPY' THEN SAFE_DIVIDE(ce.standard_exchange_rate, 100) ELSE ce.standard_exchange_rate END
                                                                                   , mc.krw_rate), 1), RP.reservation_price_amount_krw) * 100) / 100 * IF(RT.kind = 1, 1, -1) AS SALES_KRW_PRICE
    ,  FLOOR(IF(RP.reservation_price_amount IS NULL, COALESCE(R.offer_commission_rate, R.guide_commission_rate) / 100, RP.reservation_commission_rate) * 10000) / 10000 AS COMMISSION_RATE
    ,  LOWER(RT.vendor) AS PG_NM
    ,  COALESCE(IF(RP.reservation_price_amount IS NULL, RT.price_amount * IF(RT.kind = 1, 1, -1), RP.paid_price_amount), 0) AS PAID_PRICE
    ,  IF(RP.reservation_price_amount IS NULL, RT.price_currency_code, RP.paid_price_currency_code) AS PAID_PRICE_CUR_TYPE
    ,  COALESCE(IF(RP.reservation_price_amount IS NULL, FLOOR(RT.price_amount * COALESCE(IFNULL(CASE WHEN ce2.to_currency = 'JPY' THEN SAFE_DIVIDE(ce2.standard_exchange_rate, 100) ELSE ce2.standard_exchange_rate END
                                                                                             , mc2.krw_rate), 1) * 100) / 100 * IF(RT.kind = 1, 1, -1), RP.paid_price_amount), 0) AS PAID_KRW_PRICE
    ,  CAST(COALESCE(IF(RP.reservation_price_amount IS NULL, PC.price_amount * IF(RT.kind = 1, 1, -1), RP.coupon_price_amount), 0) AS NUMERIC) AS COUPON_PRICE
    ,  COALESCE(IF(RP.reservation_price_amount IS NULL, ABS(UP.point) * IF(RT.kind = 1, 1, -1), ABS(RP.point_amount) * IF(RT.kind = 1, 1, -1)), 0) AS POINT_PRICE
    ,  COALESCE(FLOOR(IF(RP.reservation_price_amount IS NULL, R.commission_price_amount * IF(RT.kind = 1, 1, -1), RP.mrt_profit_amount_krw) * 100) / 100, 0) AS COMMISSION_PRICE
    ,  LOWER(R.purpose) AS RESVE_PURPOSE_TYPE
    ,  0 AS CHILD_RESVE_PRSNL_CNT
    ,  R.number_of_people AS ADULT_RESVE_PRSNL_CNT
    ,  R.number_of_people AS RESVE_PRSNL_CNT
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET RT
LEFT JOIN {{ source('mrt_20', 'reservations') }} R ON RT.reservation_id = R.id
LEFT JOIN {{ source('mrt_20', 'offers') }} O ON R.offer_id = O.id
LEFT JOIN {{ source('mrt_20', 'reservation_cancel_reasons') }} RCR ON R.id = RCR.reservation_id AND RT.kind = 2
LEFT JOIN (
	SELECT OOC.offer_id
	     , ARRAY_AGG(DISTINCT OOC.category_id IGNORE NULLS ORDER BY OOC.category_id) AS category_id
	  FROM {{ source('mrt_20', 'offers_offer_categories') }} OOC
	  WHERE OOC.deleted_at IS NULL
	  GROUP BY OOC.offer_id
	  ) OOC ON O.id = OOC.offer_id
LEFT JOIN RESERVATION_PRICE RP ON RT.reservation_id = RP.reservation_id AND RT.kind = RP.kind
LEFT JOIN {{ source('mrt_20', 'promotion_coupon_codes') }} PCC ON RT.reservation_id = PCC.reservation_id AND PCC.deleted_at IS NULL
LEFT JOIN {{ source('mrt_20', 'promotion_coupons') }} PC ON PC.id = PCC.coupon_id
LEFT JOIN {{ source('mrt_20', 'user_points') }} UP ON RT.reservation_id = UP.reservation_id AND UP.deleted_at IS NULL
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS string) = U.USER_ID
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.offer_id = UPS.id
LEFT JOIN {{ source('mrt_mart_view', 'dim_standard_category') }} C ON UPS.standard_category_code = C.LV_3_CD
LEFT JOIN {{ ref('mart_currency') }} MC ON DATE(MC.day) = DATE(RT.paid_at_kst) AND MC.code = R.price_currency_code
LEFT JOIN {{ ref('mart_currency') }} MC2 ON DATE(MC2.day) = DATE(RT.paid_at_kst) AND MC2.code = RT.price_currency_code
LEFT JOIN {{ source('settles', 'currency_exchanges') }} ce ON ce.standard_date = DATE(RT.paid_at_kst) AND ce.to_currency = R.price_currency_code AND ce.from_currency = 'KRW' AND ce.deleted_at IS NULL
LEFT JOIN {{ source('settles', 'currency_exchanges') }} ce2 ON ce2.standard_date = DATE(RT.paid_at_kst) AND ce2.to_currency = RT.price_currency_code AND ce2.from_currency = 'KRW' AND ce2.deleted_at IS NULL
LEFT JOIN {{ ref('mrt_type') }} MT ON MT.guide_id = O.guide_id
LEFT JOIN CITY_NODUP cr ON CAST(O.id AS STRING) = cr.offer_id
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON CAST(R.offer_id AS string) = TP.GID
WHERE O.id NOT IN (70200)
  AND (U.TEST_FLAG <> true OR U.USER_ID IS NULL)
  AND RT.basis_date IS NOT NULL
  AND TP.GID IS NULL