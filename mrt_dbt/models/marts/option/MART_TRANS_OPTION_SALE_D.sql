{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_TRANS_OPTION_SALE_D'
    )
}}

-- 현재는 유로레일만
WITH RESERVATION_TARGET AS (
SELECT DISTINCT
       CAST(P.first_payment_date AS DATE) AS basis_date
    ,  TR.reservation_no
    ,  1 AS kind
    ,  CAST(null AS timestamp) AS canceled_at
    ,  P.id AS payment_id
FROM {{ source('orders', 'order_payments') }} P
LEFT JOIN {{ source('orders', 'reservations') }} R ON P.order_id = R.order_id AND R.deleted_at IS NULL
LEFT JOIN {{ source('orders', 'reservations_histories') }} RH ON R.reservation_no = RH.reservation_no AND RH.deleted_at IS NULL
LEFT JOIN {{ source('mustang_transport', 'transportation_reservation') }} TR ON R.reservation_no = TR.reservation_no AND TR.deleted_at IS NULL
WHERE P.deleted_at IS NULL
  AND P.pg_authorized_at IS NOT NULL
  AND TR.reservation_no IS NOT NULL
  AND TR.confirmed_at IS NOT NULL
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
LEFT JOIN {{ source('mustang_transport', 'transportation_reservation') }} TR ON RS.reservation_no = TR.reservation_no AND TR.deleted_at IS NULL
WHERE R.deleted_at IS NULL
  AND R.refund_type IN ('FULL_CANCEL', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'OPTION_REFUND')
  AND R.refund_status = 'COMPLETE'
  AND P.pg_authorized_at IS NOT NULL
  AND TR.reservation_no IS NOT NULL
  AND TR.confirmed_at IS NOT NULL
GROUP BY RS.reservation_no, P.id
),
FEE_ROWS AS (
SELECT RI.id AS RESVE_ITEM_ID
     , RI.transportation_reservation_id AS TRANS_RESVE_ID
     , RI.foreign_currency_margin_price AS FOREIGN_CUR_MARGIN_PRICE
     , RI.foreign_currency_partner_commission AS FOREIGN_CUR_PARTNER_COMMISSION
     , RI.foreign_currency_sale_price AS FOREIGN_CUR_SALES_PRICE
     , RI.foreign_currency_supply_price AS FOREIGN_CUR_SUPPLY_PRICE
     , RI.foreign_currency_type AS CUR_TYPE
     , RI.sale_price AS SALES_PRICE
     , RI.supply_price AS SUPPLY_PRICE
FROM {{ source('mustang_transport', 'transportation_reservation_item') }} RI
WHERE RI.reservation_item_type = 'FIXED_FEE'
),
NON_FEE_CNT AS (
SELECT RI.transportation_reservation_id AS TRANS_RESVE_ID
    ,  COUNT(1) AS NON_FEE_CNT
FROM {{ source('mustang_transport', 'transportation_reservation_item') }} RI
WHERE RI.reservation_item_type <> 'FIXED_FEE'
GROUP BY RI.transportation_reservation_id
),
FEE_INFO AS (
SELECT RI.id AS RESVE_ITEM_ID
    ,  r.TRANS_RESVE_ID AS TRANS_RESVE_ID
    ,  c.NON_FEE_CNT AS NON_FEE_CNT
    ,  SAFE_DIVIDE(r.FOREIGN_CUR_MARGIN_PRICE, c.NON_FEE_CNT) AS CUR_MARGIN_PRICE
    ,  SAFE_DIVIDE(r.FOREIGN_CUR_PARTNER_COMMISSION, c.NON_FEE_CNT) AS CUR_PARTNER_COMMISSION
    ,  SAFE_DIVIDE(r.FOREIGN_CUR_SALES_PRICE, c.NON_FEE_CNT) AS CUR_SALES_PRICE
    ,  SAFE_DIVIDE(r.FOREIGN_CUR_SUPPLY_PRICE, c.NON_FEE_CNT) AS CUR_SUPPLY_PRICE
    ,  r.CUR_TYPE AS CUR_TYPE
    ,  SAFE_DIVIDE(r.SALES_PRICE, c.NON_FEE_CNT) AS SALES_PRICE
    ,  SAFE_DIVIDE(r.SUPPLY_PRICE, c.NON_FEE_CNT) AS SUPPLY_PRICE
  FROM {{ source('mustang_transport', 'transportation_reservation_item') }} RI
LEFT JOIN FEE_ROWS r ON RI.transportation_reservation_id = r.TRANS_RESVE_ID
LEFT JOIN NON_FEE_CNT c ON r.TRANS_RESVE_ID = c.TRANS_RESVE_ID
WHERE RI.deleted_at IS NULL
  AND RI.reservation_item_type <> 'FIXED_FEE'
),
-- KIND=2 dedup: option_reservation_refunds 분할환불 N건 -> GROUP BY option_id로 1건 집약.
-- 분할환불 합산 정책: refund_amount=전체 합산(SUM). 전체 금액이 최초 환불일에 귀속됨.
-- TNA/STAY/PACKAGE와 동일 패턴.
REFUND_DATA AS (
    SELECT RF.option_id
         , SUM(RF.refund_amount) AS refund_amount
    FROM {{ source('orders', 'option_reservation_refunds') }} RF
    WHERE RF.deleted_at IS NULL
      AND RF.refund_status = 'COMPLETE'
      AND RF.refund_amount <> 0
    GROUP BY RF.option_id
)
SELECT T.BASIS_DATE AS BASIS_DATE
     ,  CAST(R.USER_ID AS STRING) AS USER_ID
     ,  R.reservation_no AS RESVE_ID
     ,  CAST(RI.transportation_item_id AS STRING) AS RESVE_OPTION_ID
     ,  CAST(R.id AS STRING) AS TRANS_RESVE_ID
     ,  CAST(P.order_id AS STRING) AS ORDER_ID
     ,  CAST(R.trp_order_id AS STRING) AS TRIP_ORDER_ID
     ,  CAST(RI.id AS STRING) AS RESVE_ITEM_ID
     ,  'EURO_RAIL' AS DOMAIN_NM
     ,  CAST(R.gid AS STRING) AS GID
     ,  CAST(UPS.gpid AS STRING) AS GPID
     ,  T.kind AS KIND
     ,  R.status AS RECENT_STATUS
     ,  CAST(R.provider_id AS STRING) AS PROVIDER_ID
     ,  CAST(UPS.partner_id AS STRING) AS PARTNER_ID
     ,  T.canceled_at AS CANCEL_KST_DT
     ,  TR.name AS ROUTE_NM
     ,  R.confirmed_at AS CONFIRM_KST_DT
     ,  RI.zoned_trip_started_at AS TRAVEL_START_TIMEZONE_DT
     ,  RI.origin_time_zone AS TRAVEL_START_TIMEZONE_NM
     ,  RI.zoned_trip_ended_at AS TRAVEL_END_TIMEZONE_DT
     ,  RI.destination_time_zone AS TRAVEL_END_TIMEZONE_NM
     ,  RI.start_at AS TRAVEL_START_KST_DT
     ,  RI.end_at AS TRAVEL_END_KST_DT
     ,  CAST(RI.start_at AS DATE) AS TRAVEL_START_KST_DATE
     ,  CAST(RI.end_at AS DATE) AS TRAVEL_END_KST_DATE
     ,  LOWER(UPS.product_type) AS PRODUCT_TYPE
     ,  LOWER(RES.type) AS ORDER_RESVE_TYPE
     ,  RI.reservation_item_type AS RESVE_ITEM_TYPE
     ,  REGEXP_EXTRACT(UPS.product_urls, r'[?&]journey=([^&]+)') AS TRAVEL_TYPE
     ,  C.LV_1_CD AS STANDARD_CATEGORY_LV_1_CD
     ,  C.Lv_1_NM AS STANDARD_CATEGORY_LV_1_NM
     ,  C.LV_2_CD AS STANDARD_CATEGORY_LV_2_CD
     ,  C.Lv_2_NM AS STANDARD_CATEGORY_LV_2_NM
     ,  C.LV_3_CD AS STANDARD_CATEGORY_LV_3_CD
     ,  C.Lv_3_NM AS STANDARD_CATEGORY_LV_3_NM
     ,  CASE WHEN URC.REPRESENTATIVE_FLAG = 'true' THEN 'Y' ELSE 'N' END AS UPS_REPRESENTATIVE_FLAG
     ,  URC.CITY_NM AS UPS_START_CITY_CD
     ,  RP1.country_code AS START_COUNTRY_CD
     ,  RP2.country_code AS END_COUNTRY_CD
     ,  RP1.country_label AS START_COUNTRY_NM
     ,  RP2.country_label AS END_COUNTRY_NM
     ,  TR.origin_code AS START_CITY_CD
     ,  TR.destination_code AS END_CITY_CD
     ,  RP1.label AS START_CITY_NM
     ,  RP2.label AS END_CITY_NM
     ,  RI.created_at AS CREATE_KST_DATE
     ,  RI.updated_at AS UPDATE_KST_DATE
     ,  O.ordered_platform AS PLATFORM
     ,  P.first_payment_date AS RESVE_PAID_KST_DT
     ,  RES.partnership_code AS PARTNERSHIP_CD
     ,  RES.partnership_type AS PARTNERSHIP_TYPE
     ,  RES.marketing_partnership_code AS MARKETING_PARTNERSHIP_CD
     ,  CAST(PP.partner_id AS STRING) AS PARTNERSHIP_PARTNER_ID
     ,  CAST(RES.marketing_link_id AS STRING) AS MARKETING_LINK_ID
     ,  LOWER(P.pg) AS PG_NM
     ,  P.payment_method AS PAYMENT_METHOD_VALUE
     ,  F.CUR_SUPPLY_PRICE AS FIXED_FEE_SUPPLY_PRICE
     ,  RI.foreign_currency_supply_price AS TICKET_SUPPLY_PRICE
     ,  F.CUR_SUPPLY_PRICE + RI.foreign_currency_supply_price AS SUPPLY_PRICE
     ,  IF(T.KIND = 1, ROUND(F.CUR_SALES_PRICE, 2), NULL) AS FIXED_FEE_SALES_PRICE
     ,  IF(T.KIND = 1, RI.foreign_currency_sale_price, NULL) AS TICKET_SALES_PRICE
     ,  IF(T.KIND = 1, ROUND(F.CUR_SALES_PRICE + RI.foreign_currency_sale_price, 2), NULL) AS SALES_PRICE
     ,  RI.foreign_currency_type AS SALES_PRICE_CUR_TYPE
     ,  F.SUPPLY_PRICE AS FIXED_FEE_SUPPLY_KRW_PRICE
     ,  RI.supply_price AS TICKET_SUPPLY_KRW_PRICE
     ,  F.SUPPLY_PRICE + RI.supply_price AS SUPPLY_KRW_PRICE
     ,  IF(T.KIND = 1, F.SALES_PRICE, 0) AS FIXED_FEE_SALES_KRW_PRICE
     ,  IF(T.KIND = 1, RI.sale_price, RF.refund_amount * -1) AS TICKET_SALES_KRW_PRICE
     ,  IF(T.KIND = 1, F.SALES_PRICE + RI.sale_price, RF.refund_amount * -1) AS SALES_KRW_PRICE
     ,  IF(T.KIND = 1, (F.SALES_PRICE + RI.sale_price) - SAFE_DIVIDE(RES.coupon_discount_amount, F.NON_FEE_CNT) - SAFE_DIVIDE(RES.point_amount, F.NON_FEE_CNT),
          (RF.refund_amount - SAFE_DIVIDE(RES.coupon_discount_amount, F.NON_FEE_CNT) - SAFE_DIVIDE(RES.point_amount, F.NON_FEE_CNT))* -1) AS PAID_KRW_PRICE
     ,  SAFE_DIVIDE(RES.coupon_discount_amount, F.NON_FEE_CNT) * IF(KIND = 1, 1, -1) AS COUPON_KRW_PRICE
     ,  SAFE_DIVIDE(RES.point_amount, F.NON_FEE_CNT) * IF(KIND = 1, 1, -1) AS POINT_KRW_PRICE
     ,  IF(T.KIND = 1, RI.foreign_currency_margin_price, NULL) AS MARGIN_PRICE
     ,  IF(T.KIND = 1, RI.foreign_currency_partner_commission, NULL) AS COMMISSION_PRICE
     ,  RI.mrt_margin_price * IF(T.KIND = 1, 1, -1) AS MARGIN_KRW_PRICE
     ,  RI.partner_commission * IF(T.KIND = 1, 1, -1) AS COMMISSION_KRW_PRICE
     ,  RI.mrt_margin_rate AS MARGIN_RATE
     ,  ROUND(SAFE_DIVIDE(RI.foreign_currency_partner_commission, RI.foreign_currency_sale_price), 2) AS COMMISSION_RATE
     ,  RESA.children AS CHILD_RESVE_PRSNL_CNT
     ,  RESA.adults AS ADULT_RESVE_PRSNL_CNT
     ,  RESA.children + RESA.adults AS RESVE_PRSNL_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVATION_TARGET T
         LEFT JOIN {{ source('orders', 'order_payments') }} P ON T.payment_id = P.id AND P.deleted_at IS NULL
         LEFT JOIN {{ source('mustang_transport', 'transportation_reservation') }} R ON T.reservation_no = R.reservation_no AND R.deleted_at IS NULL
         LEFT JOIN {{ source('mustang_transport', 'transportation_reservation_item') }} RI ON R.id = RI.transportation_reservation_id AND RI.deleted_at IS NULL
         LEFT JOIN REFUND_DATA RF ON RI.transportation_item_id = RF.option_id
         LEFT JOIN {{ source('orders', 'orders') }} O ON P.order_id = O.id AND O.deleted_at IS NULL
         LEFT JOIN {{ source('orders', 'reservations') }} RES ON T.reservation_no = RES.reservation_no AND RES.deleted_at IS NULL
         LEFT JOIN {{ source('partners', 'partnership') }} PP ON RES.partnership_code = PP.code
         LEFT JOIN {{ source('orders', 'reservation_additions') }} RESA ON RES.id = RESA.reservation_id AND RESA.deleted_at IS NULL
         LEFT JOIN FEE_INFO F ON RI.id = F.RESVE_ITEM_ID
         LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON R.gid = UPS.id AND UPS.deleted_at IS NULL
         LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} C ON UPS.standard_category_code = C.LV_3_CD
         LEFT JOIN {{ source('mustang_transport', 'train_raileurope_route') }} TR ON R.gid = TR.gid AND TR.deleted_at IS NULL
         LEFT JOIN {{ ref('DIM_UPS_REP_CITY') }} URC ON CAST(R.gid AS STRING) = URC.GID
         LEFT JOIN {{ source('mustang_transport', 'train_raileurope_place') }} RP1 ON TR.origin_code = RP1.code AND TR.destination_type = RP1.type AND RP1.deleted_at IS NULL
         LEFT JOIN {{ source('mustang_transport', 'train_raileurope_place') }} RP2 ON TR.destination_code = RP2.code AND TR.destination_type = RP2.type AND RP2.deleted_at IS NULL
         LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(R.user_id AS STRING) = U.USER_ID
WHERE RI.reservation_item_type <> 'FIXED_FEE'
  AND (U.TEST_FLAG <> TRUE OR U.USER_ID IS NULL)