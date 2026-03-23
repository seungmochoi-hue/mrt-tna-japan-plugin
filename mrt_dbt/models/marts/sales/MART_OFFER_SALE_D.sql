{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_OFFER_SALE_D'
    )
}}


WITH RESERVATION_TARGET AS (
    SELECT DISTINCT
           CAST(p.first_payment_date AS DATE)                                    AS BASIS_DATE
         , rh.reservation_no                                                     AS RESERVATION_NO
         , 1                                                                     AS KIND
         , CAST(NULL AS TIMESTAMP)                                               AS CANCELED_AT
         , p.id                                                                  AS PAYMENT_ID
      FROM {{ source('orders', 'order_payments') }} p
      LEFT JOIN {{ source('orders', 'reservations') }} r
        ON p.order_id = r.order_id
       AND r.deleted_at IS NULL
      LEFT JOIN {{ source('orders', 'reservations_histories') }} rh
        ON r.reservation_no = rh.reservation_no
       AND p.deleted_at IS NULL
     WHERE CASE WHEN r.is_pay_later = TRUE THEN rh.status IN ('CONFIRM', 'FINISH')
                ELSE rh.status IN ('WAIT_CONFIRM', 'CONFIRM', 'FINISH') END
       AND p.pg_authorized_at IS NOT NULL

    UNION ALL

    SELECT CAST(MIN(IFNULL(rf.refunded_at, r.canceled_at)) AS DATE)              AS BASIS_DATE
         , rs.reservation_no                                                     AS RESERVATION_NO
         , 2                                                                     AS KIND
         , MIN(r.canceled_at)                                                    AS CANCELED_AT
         , p.id                                                                  AS PAYMENT_ID
      FROM {{ source('orders', 'reservation_refunds') }} r
      LEFT JOIN {{ source('orders', 'order_refunds') }} rf
        ON r.order_refund_id = rf.id
      LEFT JOIN {{ source('orders', 'order_payments') }} p
        ON rf.order_id = p.order_id
       AND p.deleted_at IS NULL
      LEFT JOIN {{ source('orders', 'reservations') }} rs
        ON r.reservation_id = rs.id
     WHERE r.deleted_at IS NULL
       AND r.refund_type IN ('FULL_CANCEL', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'OPTION_REFUND')
       AND r.refund_status = 'COMPLETE'
       AND p.pg_authorized_at IS NOT NULL
     GROUP BY rs.reservation_no, p.id
),

CITY_NODUP AS (
    SELECT t.offer_id                                                            AS OFFER_ID
         , t.is_representative                                                   AS IS_REPRESENTATIVE
         , t.city_key_name                                                       AS CITY_KEY_NAME
      FROM (
          SELECT c.offer_id                                                      AS OFFER_ID
               , c.is_representative                                             AS IS_REPRESENTATIVE
               , c.city_key_name                                                 AS CITY_KEY_NAME
               , ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN
            FROM {{ ref('city_to_region') }} c
           WHERE city_info_id IS NOT NULL
      ) t
     WHERE t.rn = 1

    UNION ALL

    -- 입점숙소 gid 기준 추가
    SELECT p.union_product_id                                                    AS OFFER_ID
         , CAST(NULL AS BOOL)                                                    AS IS_REPRESENTATIVE -- BNB는 대표 도시 개념이 없으니 NULL로
         , MAX(lc.key_name)                                                      AS CITY_KEY_NAME
      FROM {{ source('products', 'products') }} p
      LEFT JOIN {{ source('products', 'product_city_mappings') }} cp
        ON p.id = cp.product_id
      LEFT JOIN {{ source('products', 'location_cities') }} lc
        ON cp.location_city_id = lc.id
     GROUP BY p.union_product_id
),

-- ORDER_ID 기준 취소 사유 추출을 위해
CANCEL_NODUP AS (
    SELECT t.order_id                                                            AS ORDER_ID
         , STRING_AGG(DISTINCT t.cancel_reason_type, ',')                        AS CANCEL_REASON_TYPE
         , STRING_AGG(DISTINCT t.refunded_by_user_type, ',')                     AS REFUNDED_BY_USER_TYPE
         , STRING_AGG(t.refund_type, ',')                                        AS REFUND_TYPE
         , SUM(ABS(t.refund_pg_amount))                                          AS REFUND_PG_AMOUNT
         , SUM(ABS(t.coupon_discount_amount))                                    AS COUPON_DISCOUNT_AMOUNT
         , SUM(ABS(t.refund_point_amount))                                       AS REFUND_POINT_AMOUNT
      FROM (
          SELECT rf.order_id                                                     AS ORDER_ID
               , rf.cancel_reason_type                                           AS CANCEL_REASON_TYPE
               , rf.refund_type                                                  AS REFUND_TYPE
               , rf.refunded_by_user_type                                        AS REFUNDED_BY_USER_TYPE
               , rf.refund_pg_amount                                             AS REFUND_PG_AMOUNT
               , rf.coupon_discount_amount                                       AS COUPON_DISCOUNT_AMOUNT
               , rf.refund_point_amount                                          AS REFUND_POINT_AMOUNT
               , rf.updated_at                                                   AS UPDATED_AT
            FROM {{ source('orders', 'order_refunds') }} rf
           WHERE rf.deleted_at IS NULL
             AND rf.refund_type IN ('FULL_CANCEL', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'OPTION_REFUND')
             AND rf.refund_status = 'COMPLETE'
           ORDER BY rf.updated_at, ROW_NUMBER() OVER (PARTITION BY rf.order_id ORDER BY rf.updated_at)
      ) t
     GROUP BY t.order_id
),

-- 정산 기준 수수료 계산을 위해
SETTLEMENT_COMMISSION AS (
    SELECT p.reservation_no                                                          AS RESERVATION_NO
         , SUM(p.sale_commission)                                                    AS SETTLEMENT_COMMISSION_PRICE
         , ROUND(SAFE_DIVIDE(SUM(p.sale_commission), SUM(p.sale_price)) * 100) / 100 AS SETTLEMENT_COMMISSION_RATE
      FROM {{ source('settles', 'settlement_product_closing') }} p
     WHERE p.deleted_at IS NULL
       AND p.closing_type IN ('PAYMENT', 'PAYMENT_OF_REFUND')
     GROUP BY p.reservation_no
),

-- 최초 Confirmed 날짜 계산을 위해(History 기준이 모수이기 때문에 최초 값을 가져올 필요가 있음)
FIRST_CONFIRM AS (
    SELECT t.reservation_no                                                      AS RESERVATION_NO
         , MIN(confirmed_at)                                                     AS CONFIRMED_AT
      FROM RESERVATION_TARGET t
      LEFT JOIN {{ source('orders', 'reservations_histories') }} h
        ON t.reservation_no = h.reservation_no
     WHERE h.status IN ('CONFIRM', 'FINISH')
     GROUP BY t.reservation_no
),

-- 로컬스테이에 필요한 값들을 가져오기 위해
LOCALSTAY_NODUP AS (
    SELECT DISTINCT
           l.lodging_id                                                          AS PRODUCT_ID
         , l.b2b                                                                 AS B2B
         , l.mrt_city_key_name                                                   AS MRT_CITY
      FROM {{ source('localstay', 'lodging') }} l
     -- null 값 제거 로직 추가
     WHERE mrt_city_key_name IS NOT NULL
),

-- 통합숙소 도시 추가
UNION_STAY_NODUP AS (
    SELECT DISTINCT
           CAST(property_id AS STRING)                                           AS PRODUCT_ID
         , city_key_name                                                         AS MRT_CITY
      FROM {{ source('unionstay', 'property_represent_mrt_region') }}
     WHERE city_key_name IS NOT NULL
),

-- 2023.10.26 특정 포인트 결제 모수
B2B_SPECIFIC_POINT_ORDER AS (
    SELECT DISTINCT
           CAST(h.action_type_related_id AS STRING)                              AS ORDER_NO
      FROM {{ source('points', 'points') }} p
      LEFT JOIN {{ source('points', 'point_action_histories') }} h
        ON p.id = h.point_id
       AND h.deleted_at IS NULL
     WHERE p.template_id = 100044 -- 요기요
       AND h.action_type = 'USE_ORDER'
),

-- Airtel(마이팩) 기준 PNR_NO 추출을 위해
AIRTEL_PACKAGE_PNR_NO AS (
    SELECT DISTINCT
           r.reservation_no                                                      AS RESVE_ID
         , CAST(d.flight_reservation_no AS INT64)                                AS PNR_NO
      FROM {{ source('orders', 'option_reservation_details') }} d
      LEFT JOIN {{ source('orders', 'option_reservations') }} o
        ON d.option_reservation_id = o.id
      LEFT JOIN {{ source('orders', 'reservations') }} r
        ON o.reservation_id = r.id
      LEFT JOIN {{ ref('DIM_USER_INFO') }} u
        ON r.user_id = u.USER_ID
     WHERE d.flight_reservation_no IS NOT NULL
       AND d.deleted_at IS NULL
       AND o.option_type = 'INDIVIDUAL_FLIGHT'
       AND (u.TEST_FLAG <> TRUE OR u.USER_ID IS NULL)
       AND r.created_at >= '2025-07-16 20:10:10' -- 마이팩 오픈 시점 : 조건 없을 시 Test 데이터로 인해 PNR 중복이 발생
    QUALIFY ROW_NUMBER() OVER (PARTITION BY r.reservation_no ORDER BY d.created_at DESC) = 1
),

-- Accomodation Package(마이팩 예약) 모수를 제외하기 위해
ACM_PACKAGE_RESVE AS (
    SELECT DISTINCT
           m.mapping_reservation_id                                              AS RESVE_ROW_ID
      FROM {{ source('orders', 'reservation_mapping') }} m
      LEFT JOIN {{ source('orders', 'reservations') }} r
        ON m.mapping_reservation_id = r.id
     WHERE m.deleted_at IS NULL
       AND m.created_at > '2025-07-01'
       AND r.type = 'ORIGIN'
),

-- MAP 관련 : 마이팩 예약을 컨트롤 하기 위해
MAP_HIST AS (
    SELECT m.reservation_id                                                      AS RESERVATION_ID
         , m.mapping_reservation_id                                              AS MAPPING_RESERVATION_ID
         , m.id                                                                  AS ID
         , LAG(m.id) OVER (PARTITION BY m.reservation_id ORDER BY m.id)          AS PREV_ID
      FROM {{ source('orders', 'reservation_mapping') }} m
     WHERE m.deleted_at IS NULL
       AND m.created_at >= '2025-07-01'
),

MAP_LATEST AS (
    SELECT m.reservation_id                                                      AS RESERVATION_ID
         , MAX(m.id)                                                             AS LATEST_ID
      FROM {{ source('orders', 'reservation_mapping') }} m
     WHERE m.deleted_at IS NULL
       AND m.created_at >= '2025-07-01'
     GROUP BY m.reservation_id
),

MAP_EXPANDED AS (
    -- 마이팩예약: reservation_id 당 1행(최신 id 부여)
    SELECT ml.reservation_id                                                     AS RESVE_ID
         , ml.latest_id                                                          AS MAPPING_ID
         , '마이팩예약'                                                             AS RESVE_TYPE
         , CAST(NULL AS INT64)                                                   AS MAPPING_CHANGE_ID
      FROM MAP_LATEST ml

    UNION ALL

    -- 원예약: 각 매핑행(각 id)에 대해 직전 id 부여
    SELECT mh.mapping_reservation_id                                             AS RESVE_ID
         , ml.latest_id                                                          AS MAPPING_ID
         , '원예약'                                                                AS RESVE_TYPE
         , CAST(mh.prev_id AS INT64)                                             AS MAPPING_CHANGE_ID
      FROM MAP_HIST mh
      JOIN MAP_LATEST ml
        ON ml.reservation_id = mh.reservation_id
),

PACKAGE_ROW AS (
    SELECT o.reservation_no                                                      AS RESERVATION_NO
         , o.type                                                                AS TYPE
         , r.product_id                                                          AS PRODUCT_ID
         , m.mapping_id                                                          AS MAPPING_ID
         , m.mapping_change_id                                                   AS MAPPING_CHANGE_ID
         , r.sale_commission                                                     AS SALE_COMMISSION
      FROM MAP_EXPANDED m
      LEFT JOIN {{ source('orders', 'option_reservations') }} r
        ON m.resve_id = r.reservation_id
       AND r.deleted_at IS NULL
      LEFT JOIN {{ source('orders', 'reservations') }} o
        ON r.reservation_id = o.id
       AND o.deleted_at IS NULL
     WHERE (o.system_provider = 'PKG' OR m.resve_id IS NOT NULL)
       AND o.created_at >= '2025-07-01'
       AND o.version = 2
),

-- 기존(과거) 마이팩 예약 수수료
PACKAGE_COMMISSION AS (
    SELECT p.reservation_no                                                      AS RESVE_ID
         , SUM(IFNULL(m.sale_commission, p.sale_commission))                     AS SALE_COMMISSION
      FROM PACKAGE_ROW p
      LEFT JOIN PACKAGE_ROW m
        ON m.type = 'ORIGIN'
       AND m.mapping_change_id IS NULL
       AND p.product_id = m.product_id
       AND p.mapping_id = m.mapping_id
     WHERE p.type <> 'ORIGIN'
     GROUP BY p.reservation_no
),

RESVE_PRSNL_CNT AS (
    SELECT r.reservation_id                                                      AS RESERVATION_ID
         , SUM(r.quantity)                                                       AS QUANTITY
      FROM {{ source('orders', 'option_reservations') }} r
     WHERE r.deleted_at IS NULL
     GROUP BY r.reservation_id
),

TRAVELER_CNT AS (
    SELECT t.reservation_no                                                      AS RESVE_ID
         , COUNT(*)                                                              AS RESVE_PRSNL_CNT
         , COUNTIF(t.traveler_age_type IN ('CHILD', 'INFANT'))                   AS CHILD_RESVE_PRSNL_CNT
         , COUNTIF(t.traveler_age_type NOT IN ('CHILD', 'INFANT') OR t.traveler_age_type IS NULL) AS ADULT_RESVE_PRSNL_CNT
      FROM {{ source('orders', 'reservation_travelers') }} t
     WHERE t.deleted_at IS NULL
     GROUP BY t.reservation_no
)

SELECT rt.basis_date                                                             AS BASIS_DATE
     , CAST(r.user_id AS STRING)                                                 AS USER_ID
     , CAST(r.reservation_no AS STRING)                                          AS RESVE_ID
     , CAST(o.id AS STRING)                                                      AS ORDER_ID
     , CAST(o.order_no AS STRING)                                                AS ORDER_NO
     , CAST(r.product_id AS STRING)                                              AS PRODUCT_ID
     , CAST(r.union_product_id AS STRING)                                        AS GID
     , CAST(IFNULL(ups.gpid, r.product_id) AS STRING)                            AS GPID
     , rt.kind                                                                   AS KIND
     , LOWER(r.status)                                                           AS RECENT_STATUS
     , rt.canceled_at                                                            AS CANCEL_KST_DT
     , IF(rt.kind = 2, rf.cancel_reason_type, NULL)                              AS CANCEL_REASON
     , IF(rt.kind = 2, rf.refunded_by_user_type, NULL)                           AS CANCEL_SUBJECT
     , IF(rt.kind = 2, rf.refund_type, NULL)                                     AS REFUND_TYPE
     , LOWER(r.product_type)                                                     AS PRODUCT_TYPE
     , LOWER(r.type)                                                             AS ORDER_RESVE_TYPE
     , r.product_category                                                        AS CATEGORY_NM
     , c.LV_1_CD                                                                 AS STANDARD_CATEGORY_LV_1_CD
     , c.LV_2_CD                                                                 AS STANDARD_CATEGORY_LV_2_CD
     , c.LV_3_CD                                                                 AS STANDARD_CATEGORY_LV_3_CD
     , r.created_at                                                              AS CREATE_KST_DT
     , r.updated_at                                                              AS UPDATE_KST_DT
     , CASE WHEN l.b2b = TRUE THEN 'B2B' -- 삼성 제휴 숙소
            WHEN bp.order_no IS NOT NULL THEN 'B2B' -- 특정 템플릿 포인트 결제
            WHEN r.entry_channel = 'AGENCY' AND r.partnership_code IS NOT NULL THEN 'B2B' -- 제휴(나중결제)
            WHEN r.entry_channel = 'TRAVELER' AND r.corp_partnership_code IS NOT NULL THEN 'B2B' -- 법인 제휴(삼성 임직원 상품)
            WHEN r.entry_channel = 'TRAVELER' AND r.marketing_partnership_code IS NOT NULL THEN 'B2C' -- 마케팅 파트너 프로모션 코드로 인입된 고객 일반 결제
            WHEN r.entry_channel = 'TRAVELER' AND r.partnership_code IS NOT NULL AND r.corp_partnership_code IS NOT NULL THEN 'B2B' -- 법인 제휴 후 일반 대리점 파트너쉽 매핑(TODO)
            WHEN r.entry_channel IS NULL OR r.entry_channel = 'TRAVELER' THEN 'B2C' -- 고객 일반 상품 결제
            ELSE 'B2C' END                                                       AS SALE_FORM_CD
     , CASE WHEN l.b2b = TRUE THEN 'corporate' -- 삼성 제휴 숙소
            WHEN bp.order_no IS NOT NULL THEN 'corporate' -- 특정 템플릿 포인트 결제
            WHEN r.entry_channel = 'AGENCY' AND r.partnership_code IS NOT NULL THEN 'partnership' -- 제휴(나중결제)
            WHEN r.entry_channel = 'TRAVELER' AND r.corp_partnership_code IS NOT NULL THEN 'corporate' -- 법인 제휴(삼성 임직원 상품)
            WHEN r.entry_channel = 'TRAVELER' AND r.marketing_partnership_code IS NOT NULL THEN 'marketing_partner' -- 마케팅 파트너 프로모션 코드로 인입된 고객 일반 결제
            WHEN r.entry_channel = 'TRAVELER' AND r.partnership_code IS NOT NULL AND r.corp_partnership_code IS NOT NULL THEN 'corporate_agency' -- 법인 제휴 후 일반 대리점 파트너쉽 매핑(TODO)
            WHEN r.entry_channel IS NULL OR r.entry_channel = 'TRAVELER' THEN 'customer' -- 고객 일반 상품 결제
            ELSE 'etc' END                                                       AS SALE_FORM_TYPE
     , LOWER(o.ordered_platform)                                                 AS PLATFORM
     , p.first_payment_date                                                      AS RESVE_PAID_KST_DT
     , h.confirmed_at                                                            AS RESVE_CONFIRM_KST_DT
     , DATE(IFNULL(r.kst_trip_started_at, r.trip_started_at))                    AS TRAVEL_START_KST_DATE
     , DATE_DIFF(DATE(r.trip_ended_at), DATE(r.trip_started_at), DAY)            AS TRAVEL_DURATION_VALUE
     , DATE(IFNULL(r.kst_trip_ended_at, r.trip_ended_at))                        AS TRAVEL_END_KST_DATE
     , LOWER(p.pg)                                                               AS PG_NM
     , r.partner_id                                                              AS PARTNER_ID
     -- 23.06.27 https://myrealtrip.atlassian.net/browse/DP-1714
     , CASE WHEN r.is_pay_later = TRUE THEN 'Y' ELSE 'N' END                     AS PAYMENT_LATER_FLAG
     , r.payment_limit_at                                                        AS PAYMENT_LIMIT_KST_DT
     , r.partnership_code                                                        AS PARTNERSHIP_CD
     , r.partnership_type                                                        AS PARTNERSHIP_TYPE
     , r.marketing_partnership_code                                              AS MARKETING_PARTNERSHIP_CD
     , sp.provider_code                                                          AS PROVIDER_CD
     , CAST(pp.partner_id AS STRING)                                             AS PARTNERSHIP_PARTNER_ID
     , CAST(r.marketing_link_id AS STRING)                                       AS MARKETING_LINK_ID
     -- 숙소 3.0 추가
     , COALESCE(us.mrt_city, l.mrt_city, ag.mrt_city, cr.city_key_name, urc.CITY_NM) AS CITY_CD
     , CASE WHEN cr.is_representative = TRUE THEN 'Y'
            WHEN cr.is_representative = FALSE THEN 'N'
            ELSE NULL END                                                        AS CITY_REPRESENTATIVE_FLAG
     , CASE WHEN r.reservation_no LIKE '%PKG%' OR r.reservation_no LIKE 'EXP-%' OR r.reservation_no LIKE 'SIM-%' THEN r.sale_price
            ELSE p.total_sale_price END * IF(rt.kind = 1, 1, -1)                 AS SALES_PRICE -- 22. 10.31 PKG 추가로 인한 로직 추가
     , p.payment_method                                                          AS PAYMENT_METHOD_VALUE
     , CASE WHEN r.reservation_no LIKE '%PKG%' OR r.reservation_no LIKE 'EXP-%' OR r.reservation_no LIKE 'SIM-%'
            THEN IF(rt.kind = 1, r.sale_price - IFNULL(rcp.coupon_price, 0) - r.point_amount, r.total_refund_amount * -1 + IFNULL(rcp.coupon_price, 0) + r.point_amount)
            ELSE IF(rt.kind = 1, p.order_payment_amount, IF(rf.refund_pg_amount <= p.order_payment_amount, rf.refund_pg_amount, p.order_payment_amount) * -1) END AS PAID_PRICE
     , CAST(IFNULL(rcp.coupon_price, 0) * IF(rt.kind = 1, 1, -1) AS NUMERIC) AS COUPON_PRICE
     , CAST(IFNULL(rcp.product_coupon_price, 0) * IF(rt.kind = 1, 1, -1) AS NUMERIC) AS PRODUCT_COUPON_PRICE
     , CAST(IFNULL(rcp.order_coupon_price, 0) * IF(rt.kind = 1, 1, -1) AS NUMERIC) AS ORDER_COUPON_PRICE
     , CAST(rcp.product_coupon_id AS INT64)                                     AS PRODUCT_COUPON_ID
     , CAST(rcp.order_coupon_id AS INT64)                                       AS ORDER_COUPON_ID
     , CASE WHEN r.reservation_no LIKE '%PKG%' OR r.reservation_no LIKE 'EXP-%' OR r.reservation_no LIKE 'SIM-%' THEN r.point_amount * IF(rt.kind = 1, 1, -1)
            ELSE IF(rt.kind = 1, p.point_payment_amount, IF(rf.refund_point_amount <= p.point_payment_amount, rf.refund_point_amount, p.point_payment_amount) * -1) END AS POINT_PRICE
     , IFNULL(pcc.sale_commission, r.total_sale_commission) * IF(rt.kind = 1, 1, -1) AS COMMISSION_PRICE
     , ROUND(SAFE_DIVIDE(IFNULL(pcc.sale_commission, r.total_sale_commission), CASE WHEN r.reservation_no LIKE '%PKG%' OR r.reservation_no LIKE 'EXP-%' OR r.reservation_no LIKE 'SIM-%' THEN r.sale_price ELSE p.total_sale_price END) * 100) / 100 AS COMMISSION_RATE
     , sc.settlement_commission_price * IF(rt.kind = 1, 1, -1)                   AS SETTLEMENT_COMMISSION_PRICE
     , sc.settlement_commission_rate                                             AS SETTLEMENT_COMMISSION_RATE
     , IFNULL(r.margin_discount_amount, 0) * IF(rt.kind = 1, 1, -1)               AS MARGIN_DISCOUNT_PRICE
     , r.margin_discount_type                                                    AS MARGIN_DISCOUNT_TYPE
     , LOWER(o.trip_purpose)                                                     AS RESVE_PURPOSE_TYPE
     , CASE WHEN c.LV_1_CD = 'PACKAGE' THEN COALESCE(pt.child_resve_prsnl_cnt, CASE WHEN pc.reservation_id IS NULL THEN ra.children ELSE 0 END)
            WHEN c.LV_1_CD = 'ACCOMMODATION' OR c.LV_3_CD = 'EUROPE_TRAIN' OR pc.reservation_id IS NULL THEN ra.children
            ELSE 0 END                                                           AS CHILD_RESVE_PRSNL_CNT
     , CASE WHEN c.LV_1_CD = 'PACKAGE' THEN COALESCE(pt.adult_resve_prsnl_cnt, CASE WHEN pc.reservation_id IS NULL THEN ra.adults ELSE pc.quantity END)
            WHEN c.LV_1_CD = 'ACCOMMODATION' OR c.LV_3_CD = 'EUROPE_TRAIN' OR pc.reservation_id IS NULL THEN ra.adults
            ELSE pc.quantity END                                                 AS ADULT_RESVE_PRSNL_CNT
     , CASE WHEN c.LV_1_CD = 'PACKAGE' THEN COALESCE(pt.resve_prsnl_cnt, CASE WHEN pc.reservation_id IS NULL THEN ra.children + ra.adults ELSE pc.quantity END)
            WHEN c.LV_1_CD = 'ACCOMMODATION' OR c.LV_3_CD = 'EUROPE_TRAIN' OR pc.reservation_id IS NULL THEN ra.children + ra.adults
            ELSE pc.quantity END                                                 AS RESVE_PRSNL_CNT
     , pn.pnr_no                                                                 AS PACKAGE_PNR_NO
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                        AS DW_LOAD_DT
  FROM RESERVATION_TARGET rt
  LEFT JOIN {{ source('orders', 'order_payments') }} p
    ON rt.payment_id = p.id
   AND p.deleted_at IS NULL
  LEFT JOIN {{ source('orders', 'orders') }} o
    ON p.order_id = o.id
   AND o.deleted_at IS NULL
  LEFT JOIN {{ source('orders', 'reservations') }} r
    ON rt.reservation_no = r.reservation_no
   AND r.deleted_at IS NULL
  LEFT JOIN {{ ref('INT_RESVE_COUPON_PRICE_D') }} rcp
    ON rt.reservation_no = rcp.RESVE_ID
   AND rt.kind = rcp.KIND
  LEFT JOIN {{ source('orders', 'reservation_additions') }} ra
    ON r.id = ra.reservation_id
   AND ra.deleted_at IS NULL
  LEFT JOIN RESVE_PRSNL_CNT pc
    ON r.id = pc.reservation_id
  LEFT JOIN TRAVELER_CNT pt
    ON r.reservation_no = pt.resve_id
  LEFT JOIN {{ source('partners', 'partnership') }} pp
    ON r.partnership_code = pp.code
  LEFT JOIN {{ source('ups', 'union_product_v3') }} ups
    ON r.union_product_id = ups.id
  LEFT JOIN SETTLEMENT_COMMISSION sc
    ON rt.reservation_no = sc.reservation_no
  LEFT JOIN AIRTEL_PACKAGE_PNR_NO pn
    ON rt.reservation_no = pn.resve_id
  LEFT JOIN ACM_PACKAGE_RESVE apr
    ON r.id = apr.resve_row_id
  LEFT JOIN PACKAGE_COMMISSION pcc
    ON rt.reservation_no = pcc.resve_id
  LEFT JOIN {{ source('mrt_mart_view', 'dim_standard_category') }} c
    ON ups.standard_category_code = c.LV_3_CD
  LEFT JOIN {{ ref('DIM_USER_INFO') }} u
    ON CAST(r.user_id AS STRING) = u.USER_ID
  LEFT JOIN CANCEL_NODUP rf
    ON p.order_id = rf.order_id
  LEFT JOIN FIRST_CONFIRM h
    ON rt.reservation_no = h.reservation_no
  LEFT JOIN CITY_NODUP cr
    ON r.product_id = cr.offer_id
  LEFT JOIN {{ ref('DIM_UPS_REP_CITY') }} urc
    ON CAST(r.union_product_id AS STRING) = urc.GID
  LEFT JOIN {{ source('mustang', 'mst_vehicle') }} vh
    ON r.product_id = CAST(vh.id AS STRING)
  LEFT JOIN {{ source('mustang', 'mst_agency') }} ag
    ON vh.agency_id = ag.id
  -- 숙소 3.0 추가
  LEFT JOIN LOCALSTAY_NODUP l
    ON r.union_product_id = l.product_id
  -- 통합숙소 추가
  LEFT JOIN UNION_STAY_NODUP us
    ON r.product_id = us.product_id
  -- 통합숙소 provider_code 소스 변경
  LEFT JOIN {{ source('unionstay', 'property') }} sp
    ON CAST(r.product_id AS STRING) = CAST(sp.property_id AS STRING)
  LEFT JOIN B2B_SPECIFIC_POINT_ORDER bp
    ON o.order_no = bp.order_no
  LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} tp
    ON CAST(r.union_product_id AS STRING) = tp.GID
 WHERE (u.TEST_FLAG <> TRUE OR u.USER_ID IS NULL)
   AND tp.GID IS NULL
   AND apr.resve_row_id IS NULL -- 2025. 09. 01 패키지 숙소 원예약 모수 제거
