{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_PACKAGE_PROFIT_D'
    )
}}
/* 패키지 상품 예약 단위 수익성(Profit) 마트.
   비항공 + 항공 + SURCHARGE 커미션을 합산하여 MRT_SALES_PRICE 산출.
   항공분 SERIES_FLIGHT는 SUPPLY 기반 마진(역마진 허용),
   INDIVIDUAL_FLIGHT는 PNR 기반 안분 산출.
   Grain: RESVE_ID (예약 1행) */

WITH INSURANCE_TRAVELER AS (
    SELECT
        RESERVATION_NO
      , COUNT(DISTINCT ID)                                                                     AS TRAVELER_CNT
    FROM {{ source('orders', 'reservation_travelers') }}
    GROUP BY RESERVATION_NO
)

, INSURANCE_PRICE AS (
    SELECT
        RESERVATION_NO
      , SUM(PRICE)                                                                             AS TOTAL_INSURANCE_PRICE
    FROM {{ source('payments', 'traveler_insurances') }}
    GROUP BY RESERVATION_NO
)

, INSURANCE_COST AS (
    SELECT
        r.RESERVATION_NO                                                                       AS RESVE_ID
      , i.TOTAL_INSURANCE_PRICE
      , rt.TRAVELER_CNT
    FROM {{ source('orders', 'reservations') }} r
    LEFT JOIN INSURANCE_PRICE i
        ON i.RESERVATION_NO = r.RESERVATION_NO
    LEFT JOIN INSURANCE_TRAVELER rt
        ON r.RESERVATION_NO = rt.RESERVATION_NO
)

-- 여행자 보험은 하루 전 가입됨. 가입 전까지 5,000원/인으로 기본값 적용
, INSURANCE_COST_MANI AS (
    SELECT
        RESVE_ID
      , CASE WHEN TOTAL_INSURANCE_PRICE IS NULL THEN 5000 * TRAVELER_CNT
             ELSE TOTAL_INSURANCE_PRICE END                                                    AS TOTAL_INSURANCE_PRICE
      , TRAVELER_CNT
    FROM INSURANCE_COST
)

, MARKETING_PARTNERSHIP_COMMISSION AS (
    SELECT
        RESERVATION_NO                                                                         AS RESVE_ID
      , SUM(MARKETING_PARTNERSHIP_COMMISSION)                                                  AS MARKETING_PARTNERSHIP_COMMISSION
    FROM {{ source('settles', 'payment_product_closing') }} p
    WHERE MARKETING_PARTNERSHIP_COMMISSION_RATE > 0
    GROUP BY RESERVATION_NO
)

, NONAIR_PACKAGE_ADJUST_RESVE_COMMISSION AS (
    SELECT
        s.RESVE_ID
      , s.RESVE_OPTION_ID
      , s.RESVE_VERSION_VALUE
      , CASE WHEN spi.PACKAGE_COMPONENT_GID IS NOT NULL
                  THEN s.SALES_PRICE - spi.ACTUAL_SUPPLY_PRICE
             WHEN scp.PACKAGE_OPTION_PARTNER_ID IS NOT NULL
                  THEN s.SALES_PRICE - ((s.SALES_PRICE - s.PAYMENT_COMMISSION_PRICE) * scp.ADJUSTMENT_RATE)
             WHEN s.SUPPLY_PRICE IS NOT NULL AND s.SUPPLY_PRICE > 0
                  THEN s.SALES_PRICE - s.SUPPLY_PRICE
             ELSE s.PAYMENT_COMMISSION_PRICE END                                               AS COMMISSION_PRICE
      , s.SALES_PRICE                                                                          AS SALES_PRICE
      , CASE WHEN spi.PACKAGE_COMPONENT_GID IS NOT NULL THEN spi.ACTUAL_SUPPLY_PRICE
             WHEN s.SUPPLY_PRICE IS NOT NULL AND s.SUPPLY_PRICE > 0 THEN s.SUPPLY_PRICE
             ELSE 0 END                                                                        AS SUPPLY_PRICE
    FROM {{ ref('MART_PACKAGE_OPTION_SALE_D') }} s
    LEFT JOIN {{ ref('FPNA_MYPACK_ACTUAL_SUPPLY_PRICE_INFO') }} spi
        ON spi.RESVE_ID = s.RESVE_ID
       AND spi.PACKAGE_COMPONENT_GID = s.PACKAGE_OPTION_GID
    LEFT JOIN {{ ref('FPNA_MYPACK_ACTUAL_SUPPLY_COST_PARTNER') }} scp
        ON scp.PACKAGE_OPTION_PARTNER_ID = s.PACKAGE_OPTION_PARTNER_ID
       AND DATE_TRUNC(s.BASIS_DATE, MONTH) = scp.RESVE_END_DATE
       AND DATE_TRUNC(s.TRAVEL_START_KST_DATE, MONTH) = scp.TRAVEL_MONTH
    LEFT JOIN {{ ref('FPNA_PKG_HARD_BLOCK_INFO') }} h1
        ON s.PACKAGE_OPTION_PARTNER_ID = h1.OPTION_PARTNER_ID
    LEFT JOIN {{ ref('FPNA_PKG_HARD_BLOCK_INFO') }} h2
        ON s.PACKAGE_OPTION_GID = h2.COMPONENT_GID
    WHERE s.KIND = 1
      AND (s.OPTION_RESVE_TYPE NOT LIKE '%FLIGHT%'
           OR s.OPTION_RESVE_TYPE IS NULL
           OR h1.OPTION_PARTNER_ID IS NOT NULL
           OR h2.COMPONENT_GID IS NOT NULL)
      AND s.RESVE_TYPE <> 'SURCHARGE'
)

, AIR_PACKAGE_ADJUST_RESVE_COMMISSION AS (
    -- 1) 비취소 옵션만 추출 (KIND=1 기준, 같은 옵션에 KIND=2 존재 시 제외)
    WITH DATA AS (
        SELECT
            s1.RESVE_ID
          , s1.ORDER_ID
          , s1.RESVE_VERSION_VALUE
          , s1.OPTION_RESVE_TYPE
          , s1.AIR_PNR_NO                                                                      AS PNR_NO
          , s1.PACKAGE_OPTION_PARTNER_ID
          , s1.PACKAGE_OPTION_GID
          , s1.SALES_PRICE
          , s1.PAYMENT_COMMISSION_PRICE
          , s1.SUPPLY_PRICE
        FROM {{ ref('MART_PACKAGE_OPTION_SALE_D') }} s1
        LEFT JOIN {{ ref('MART_PACKAGE_OPTION_SALE_D') }} s2
            ON s1.RESVE_OPTION_ID = s2.RESVE_OPTION_ID
           AND s2.KIND = 2
        WHERE s1.KIND = 1
          AND s1.OPTION_RESVE_TYPE IN ('SERIES_FLIGHT', 'INDIVIDUAL_FLIGHT')
          AND s2.RESVE_OPTION_ID IS NULL
          AND s1.RESVE_TYPE <> 'SURCHARGE'
    )

    -- 2) 하드블록 제외 (현재 비활성화 - 하드블록 필터 없이 전건 포함)
    , DATA_NHB AS (
        SELECT
            d.RESVE_ID
          , d.ORDER_ID
          , d.RESVE_VERSION_VALUE
          , d.OPTION_RESVE_TYPE
          , d.PNR_NO
          , d.PACKAGE_OPTION_PARTNER_ID
          , d.PACKAGE_OPTION_GID
          , COUNT(d.RESVE_ID) OVER (PARTITION BY d.ORDER_ID)                                   AS ORDER_RSV_CNT
          , SUM(d.SALES_PRICE)                                                                 AS SALES_PRICE
          , SUM(d.PAYMENT_COMMISSION_PRICE)                                                    AS PAYMENT_COMMISSION_PRICE
          , SUM(d.SUPPLY_PRICE)                                                                AS SUPPLY_PRICE
        FROM DATA d
        GROUP BY
            d.RESVE_ID
          , d.ORDER_ID
          , d.RESVE_VERSION_VALUE
          , d.OPTION_RESVE_TYPE
          , d.PNR_NO
          , d.PACKAGE_OPTION_PARTNER_ID
          , d.PACKAGE_OPTION_GID
    )

    -- 3) RV100의 PKG_NO 파싱: PNR과 패키지 주문번호 매핑
    , PNR_PKG AS (
        SELECT DISTINCT
            CAST(rv100.PNR_SEQNO AS FLOAT64)                                                   AS PNR_NO
          , TRIM(tok)                                                                          AS PKG_ORDER_NO
        FROM {{ source('air', 'TB_AIR_RV100') }} rv100
        CROSS JOIN UNNEST(SPLIT(REGEXP_REPLACE(TRIM(rv100.PKG_NO), r'[\s,]+', ' '), ' ')) tok
        WHERE rv100.PKG_NO IS NOT NULL
    )

    -- 4) PNR별 전체 주문 수 (안분 분모)
    , ORDER_CNT AS (
        SELECT
            p.PNR_NO
          , COUNT(DISTINCT p.PKG_ORDER_NO)                                                     AS ORDER_CNT
        FROM PNR_PKG p
        GROUP BY p.PNR_NO
    )

    -- 5) 항공 매출을 주문별로 안분
    , AIR_SALES AS (
        SELECT
            a.PNR_NO
          , o.ID                                                                               AS ORDER_ID
          , SUM(SAFE_DIVIDE(a.SALE_TOTAL_PRICE, oc.ORDER_CNT))                                 AS SALE_TOT_AMT_FOR_ORDER
          , MAX(a.IND_GROUP_FLAG)                                                              AS IND_GROUP_FLAG -- 비즈니스 의도: PNR 내 최대값(GROUP이면 GROUP 우선)
        FROM {{ ref('MART_AIR_SALE_D') }} a
        JOIN ORDER_CNT oc
            ON oc.PNR_NO = a.PNR_NO
        JOIN PNR_PKG p
            ON p.PNR_NO = a.PNR_NO
        LEFT JOIN {{ source('orders', 'orders') }} o
            ON o.ORDER_NO = p.PKG_ORDER_NO
           AND o.DELETED_AT IS NULL
        WHERE a.KIND = 1
          AND o.DELETED_AT IS NULL
        GROUP BY a.PNR_NO, o.ID
    )

    -- 6) 최종: 항공 커미션 산출
    -- SERIES_FLIGHT: PNR 매칭 > SUPPLY 마진(역마진 허용) > PAYMENT 폴백 / INDIVIDUAL_FLIGHT: PNR 매칭 > SUPPLY 폴백(역마진 제외) > PAYMENT 폴백
    SELECT
        d.RESVE_ID
      , CASE WHEN a.ORDER_ID IS NOT NULL
                  THEN SAFE_DIVIDE(d.SALES_PRICE - a.SALE_TOT_AMT_FOR_ORDER, d.ORDER_RSV_CNT)
             WHEN d.OPTION_RESVE_TYPE = 'SERIES_FLIGHT'
                  AND d.SUPPLY_PRICE IS NOT NULL AND d.SUPPLY_PRICE > 0
                  THEN d.SALES_PRICE - d.SUPPLY_PRICE                                                -- SERIES_FLIGHT: 역마진 허용 (SALES >= SUPPLY 가드 제거)
             WHEN d.SUPPLY_PRICE IS NOT NULL AND d.SUPPLY_PRICE > 0
                  AND d.SALES_PRICE >= d.SUPPLY_PRICE
                  THEN d.SALES_PRICE - d.SUPPLY_PRICE
             ELSE d.PAYMENT_COMMISSION_PRICE END                                               AS COMMISSION_PRICE
      , d.SALES_PRICE
      , a.IND_GROUP_FLAG
      , d.OPTION_RESVE_TYPE
      , d.SUPPLY_PRICE
    FROM DATA_NHB d
    LEFT JOIN AIR_SALES a
        ON CAST(a.PNR_NO AS STRING) = d.PNR_NO
       AND CAST(a.ORDER_ID AS STRING) = d.ORDER_ID
)

, PACKAGE_SURCHARGE_RESVE_COMMISSION AS (
    SELECT
        s.RESVE_ID                                                                             AS RESVE_ID
      , CASE WHEN s.OPTION_RESVE_TYPE LIKE '%FLIGHT%' THEN s.SALES_PRICE
             ELSE s.PAYMENT_COMMISSION_PRICE END                                               AS COMMISSION_PRICE
      , s.SALES_PRICE                                                                          AS SALES_PRICE
      , CAST(NULL AS STRING)                                                                   AS IND_GROUP_FLAG
      , CAST(NULL AS STRING)                                                                   AS OPTION_RESVE_TYPE
      , 0                                                                                      AS SUPPLY_PRICE
    FROM {{ ref('MART_PACKAGE_OPTION_SALE_D') }} s
    WHERE s.RESVE_TYPE = 'SURCHARGE'
      AND s.RECENT_OPTION_RESVE_STATUS <> 'fail'
)

-- 패키지 RESVE_ID 단위: 비항공 + 항공 + SURCHARGE 커미션 합산
, PACKAGE_RSV_SALES AS (
    SELECT
        t.RESVE_ID
      , SUM(t.COMMISSION_PRICE)                                                                AS MRT_SALES_PRICE
      , SUM(CASE WHEN t.TYPE = 'AIR' AND t.OPTION_RESVE_TYPE = 'SERIES_FLIGHT'
                      THEN t.SALES_PRICE    -- Block Air(단체항공)는 PG 수수료 기준금액에 포함
                 WHEN t.TYPE = 'AIR' THEN NULL  -- Individual Air(개별항공)는 PG 기준금액에서 제외
                 ELSE t.SALES_PRICE END)                                                       AS WITHOUT_AIR_SALES_PRICE
      , SUM(CASE WHEN t.TYPE = 'AIR' AND t.OPTION_RESVE_TYPE = 'SERIES_FLIGHT'
                      THEN t.SUPPLY_PRICE
                 WHEN t.TYPE = 'AIR' THEN NULL
                 ELSE t.SUPPLY_PRICE END)                                                      AS WITHOUT_AIR_SUPPLY_PRICE
      , SUM(t.SUPPLY_PRICE)                                                                    AS SUPPLY_PRICE
    FROM (
        SELECT
            a.RESVE_ID
          , 'NONAIR'                                                                           AS TYPE
          , a.COMMISSION_PRICE
          , a.SALES_PRICE
          , CAST(NULL AS STRING)                                                               AS IND_GROUP_FLAG
          , CAST(NULL AS STRING)                                                               AS OPTION_RESVE_TYPE
          , a.SUPPLY_PRICE
        FROM NONAIR_PACKAGE_ADJUST_RESVE_COMMISSION a

        UNION ALL

        SELECT
            b.RESVE_ID
          , 'AIR'                                                                              AS TYPE
          , b.COMMISSION_PRICE
          , b.SALES_PRICE
          , b.IND_GROUP_FLAG
          , b.OPTION_RESVE_TYPE
          , b.SUPPLY_PRICE
        FROM AIR_PACKAGE_ADJUST_RESVE_COMMISSION b

        UNION ALL

        SELECT
            c.RESVE_ID
          , 'SURCHARGE'                                                                        AS TYPE
          , c.COMMISSION_PRICE
          , c.SALES_PRICE
          , c.IND_GROUP_FLAG
          , c.OPTION_RESVE_TYPE
          , c.SUPPLY_PRICE
        FROM PACKAGE_SURCHARGE_RESVE_COMMISSION c
    ) t
    GROUP BY t.RESVE_ID
)

/* ---- MART_SALE_D 기반 PROFIT 마트 로직 ---- */

, B2B_POINT_RSV AS (
    SELECT DISTINCT
        s.RESVE_ID
    FROM {{ ref('MART_PACKAGE_OPTION_SALE_D') }} s
    LEFT JOIN {{ source('orders', 'orders') }} o
        ON s.ORDER_ID = CAST(o.ID AS STRING)
       AND o.DELETED_AT IS NULL
    LEFT JOIN {{ source('points', 'point_action_histories') }} ph
        ON o.ORDER_NO = CAST(ph.ACTION_TYPE_RELATED_ID AS STRING)
       AND ph.ACTION_TYPE LIKE '%USE%'
    LEFT JOIN {{ source('points', 'points') }} p
        ON ph.POINT_ID = p.ID
    LEFT JOIN {{ source('points', 'point_templates') }} pt
        ON p.TEMPLATE_ID = pt.ID
    WHERE s.KIND = 1
      AND pt.POINT_CATEGORY LIKE '%B2B%'
      AND s.POINT_PRICE IS NOT NULL
      AND s.POINT_PRICE != 0
)

, COUPON_APPLIED_RESVE AS (
    SELECT
        RESVE_ID
      , COUPON_USER_MAPPING_ID
      , COUPON_ID
      , COUPON_NM
      , COUPON_PUBLISH_TEAM
      , COUPON_PUBLISH_PURPOSE
      , USABLE_TYPE
      , PAYMENT_COUPON_PRICE
    FROM {{ ref('INT_COUPON_APPLIED_RESVE_D') }}
)

, COUPON_REP_RANKED AS (
    SELECT
        *
      , ROW_NUMBER() OVER (
            PARTITION BY RESVE_ID, USABLE_TYPE
            ORDER BY PAYMENT_COUPON_PRICE DESC, COUPON_USER_MAPPING_ID DESC, COUPON_ID DESC
        ) AS RN
    FROM COUPON_APPLIED_RESVE
)

, PRODUCT_COUPON_REP AS (
    SELECT
        RESVE_ID
      , COUPON_ID
      , COUPON_NM
      , COUPON_PUBLISH_TEAM
      , COUPON_PUBLISH_PURPOSE
    FROM COUPON_REP_RANKED
    WHERE USABLE_TYPE = 'PRODUCT'
      AND RN = 1
)

, ORDER_COUPON_REP AS (
    SELECT
        RESVE_ID
      , COUPON_ID
      , COUPON_NM
      , COUPON_PUBLISH_TEAM
      , COUPON_PUBLISH_PURPOSE
    FROM COUPON_REP_RANKED
    WHERE USABLE_TYPE = 'ORDER'
      AND RN = 1
)

, CP_PRODUCT AS (
    SELECT
        cp.RESVE_ID
      , cp.COUPON_ID
      , cp.COUPON_NM
      , cp.COUPON_PUBLISH_TEAM
      , cp.COUPON_PUBLISH_PURPOSE
    FROM {{ ref('MART_COUPON_RESVE_D') }} cp
    JOIN {{ source('coupon', 'coupon_templates') }} ct
      ON cp.COUPON_ID = ct.ID
    WHERE ct.USABLE_TYPE = 'PRODUCT'
)

, USED_COUPON_RESVE AS (
    SELECT
        cu.RESERVATION_NO                                                                       AS RESVE_ID
      , MAX(cc.TEMPLATE_ID)                                                                     AS COUPON_ID
      , MAX(ct.NAME)                                                                            AS COUPON_TITLE
    FROM {{ source('coupon', 'coupon_user_mapping') }} cc
    LEFT JOIN {{ source('coupon', 'coupon_templates') }} ct
        ON cc.TEMPLATE_ID = ct.ID
    LEFT JOIN {{ source('coupon', 'coupon_use_history') }} cu
        ON cc.ID = cu.COUPON_USER_MAPPING_ID
       AND cu.ACTION_TYPE = 'USE'
    GROUP BY cu.RESERVATION_NO
)

-- 파트너 분담 쿠폰: partner_contribution_rate > 0인 쿠폰의 MRT/파트너 부담 비율
, COUPON_EXTRA_INFO AS (
    SELECT DISTINCT
        t.ID                                                                                   AS COUPON_ID
      , t.FLAT_AMOUNT                                                                          AS COUPON_VALUE
      , CASE WHEN t.FLAT_AMOUNT IS NOT NULL
                  THEN t.FLAT_AMOUNT * t.MRT_CONTRIBUTION_RATE * 0.01
             ELSE NULL END                                                                     AS MRT_VALUE
      , CASE WHEN t.FLAT_AMOUNT IS NOT NULL
                  THEN t.FLAT_AMOUNT * t.PARTNER_CONTRIBUTION_RATE * 0.01
             ELSE NULL END                                                                     AS PARTNER_VALUE
      , t.MRT_CONTRIBUTION_RATE
      , t.PARTNER_CONTRIBUTION_RATE
    FROM {{ source('coupon', 'coupon_templates') }} t
    LEFT JOIN {{ source('coupon', 'coupon_template_condition_mappings') }} c
        ON t.ID = c.TEMPLATE_ID
       AND c.IS_INCLUDE = TRUE
    WHERE (t.PARTNER_CONTRIBUTION_RATE IS NOT NULL AND t.PARTNER_CONTRIBUTION_RATE > 0)
       OR (
           t.MRT_CONTRIBUTION_RATE IS NOT NULL
           AND t.MRT_CONTRIBUTION_RATE > 0
           AND t.MRT_CONTRIBUTION_RATE < 100
       )
)

, PRODUCT_30_COUPON_COST AS (
    SELECT
        CAP.RESVE_ID
      , SUM(CAP.PAYMENT_COUPON_PRICE) AS COUPON_AMOUNT
      , SUM({{ fpna_coupon_burden_price('CAP.PAYMENT_COUPON_PRICE', 'FCI_3_PRODUCT', 'CEI_3_PRODUCT') }}) AS COUPON_PRICE
    FROM COUPON_APPLIED_RESVE CAP
    LEFT JOIN {{ ref('fpna_coupon_info') }} FCI_3_PRODUCT
      ON CAP.COUPON_ID = FCI_3_PRODUCT.COUPON_ID
     AND FCI_3_PRODUCT.TYPE = '3.0 product'
    LEFT JOIN COUPON_EXTRA_INFO CEI_3_PRODUCT
      ON CAP.COUPON_ID = CEI_3_PRODUCT.COUPON_ID
    WHERE CAP.USABLE_TYPE = 'PRODUCT'
    GROUP BY CAP.RESVE_ID
)

, ORDER_30_COUPON_COST AS (
    SELECT
        CAP.RESVE_ID
      , SUM({{ fpna_coupon_burden_price('CAP.PAYMENT_COUPON_PRICE', 'FCI_3_ORDER', 'CEI_3_ORDER') }}) AS COUPON_PRICE
    FROM COUPON_APPLIED_RESVE CAP
    LEFT JOIN {{ ref('fpna_coupon_info') }} FCI_3_ORDER
      ON CAP.COUPON_ID = FCI_3_ORDER.COUPON_ID
     AND FCI_3_ORDER.TYPE = '3.0 product'
    LEFT JOIN COUPON_EXTRA_INFO CEI_3_ORDER
      ON CAP.COUPON_ID = CEI_3_ORDER.COUPON_ID
    WHERE CAP.USABLE_TYPE = 'ORDER'
    GROUP BY CAP.RESVE_ID
)

, B2B_AFFILIATE_COUPON AS (
    SELECT DISTINCT
        cct.ID                                                                                 AS COUPON_ID
    FROM {{ source('coupon', 'coupon_templates') }} cct
    LEFT JOIN {{ source('coupon', 'coupon_template_types') }} cctt
        ON cct.TEMPLATE_TYPE_ID = cctt.ID
    WHERE cctt.PUBLISH_TEAM = 'CORPORATION_BUSINESS'
)

, MYLINK_PARTNERSHIP_CODE AS (
    SELECT DISTINCT
        pp.CODE                                                                                AS MARKETING_PARTNERSHIP_CD
    FROM {{ source('partners', 'partnership') }} pp
    LEFT JOIN {{ source('partners', 'partner') }} p
        ON pp.PARTNER_ID = p.ID
    LEFT JOIN {{ source('partners', 'partner_account') }} a
        ON p.ID = a.PARTNER_ID
       AND a.TYPE = 'MASTER'
    WHERE LEFT(pp.CODE, 1) = 'M'
      AND p.BUSINESS_REGISTRATION_TYPE IN ('DOMESTIC', 'PRIVATE')
      AND CAST(p.ID AS STRING) NOT IN (
          SELECT DISTINCT PARTNER_ID
          FROM {{ ref('FPNA_MYLINK_PARTNER_INFO') }}
          WHERE MANAGEMENT_TEAM NOT IN ('B2B / 제휴여행사')
      )
)

, COUPON_30 AS (
    SELECT
        h.RESERVATION_NO                                                                       AS RESVE_ID
      , MAX(h.TEMPLATE_ID)                                                                     AS COUPON_ID    -- 비즈니스 의도: 예약당 최대 template_id를 대표 쿠폰으로 선택
      , MAX(t.NAME)                                                                            AS COUPON_TITLE -- 비즈니스 의도: 예약당 최대값
    FROM {{ source('coupon', 'coupon_reservation_history') }} h
    LEFT JOIN {{ source('coupon', 'coupon_templates') }} t
        ON h.TEMPLATE_ID = t.ID
    WHERE h.DELETED_AT IS NULL
      AND t.DELETED_AT IS NULL
    GROUP BY h.RESERVATION_NO
)

SELECT
    s.BASIS_DATE
  , s.TRAVEL_START_KST_DATE                                                                    AS TRAVEL_START_DATE
  , s.TRAVEL_END_KST_DATE                                                                      AS TRAVEL_END_DATE
  , DATE_DIFF(s.TRAVEL_END_KST_DATE, s.TRAVEL_START_KST_DATE, DAY)                             AS TRAVEL_DAYS
  , rc.CANCEL_DATE                                                                              AS CANCEL_DATE
  , DATE_DIFF(rc.CANCEL_DATE, s.BASIS_DATE, DAY)                                                AS RESVE_CANCEL_DAY_DIFF
  , s.RECENT_STATUS
  , s.ORDER_ID
  , s.ORDER_NO
  , s.RESVE_ID
  , r.VERSION                                                                                   AS RESVE_VERSION_VALUE
  , r.TYPE                                                                                      AS RESVE_TYPE
  , s.DOMAIN_NM
  , s.RESVE_PRSNL_CNT
  , s.TRAVEL_ID
  , s.TRAVEL_DETAIL_ID
  , u.MRT_STAFF_FLAG                                                                            AS MRT_STAFF_FLAG
  , s.USER_ID
  , s.CATEGORY_NM
  , s.CATEGORY_CD
  , s.SUB_CATEGORY_CD
  , s.STANDARD_CATEGORY_LV_1_CD
  , s.STANDARD_CATEGORY_LV_1_NM
  , s.STANDARD_CATEGORY_LV_2_CD
  , s.STANDARD_CATEGORY_LV_2_NM
  , s.STANDARD_CATEGORY_LV_3_CD
  , s.STANDARD_CATEGORY_LV_3_NM
  , s.PARTNERSHIP_TYPE
  , s.PROVIDER_CD
  , psc.ACCOUNTING_PROJECT_CODE                                                                 AS ACCOUNTING_PROJECT_CODE
  , CASE WHEN s.PARTNERSHIP_CD IS NOT NULL THEN 'B2B'
         WHEN br.RESVE_ID IS NOT NULL THEN 'B2B'
         WHEN s.STANDARD_CATEGORY_LV_1_CD IN ('TOUR', 'TICKET', 'CLASS', 'SANP', 'ACTIVITY', 'CONVENIENCE')
              AND s.STANDARD_CATEGORY_LV_3_CD NOT LIKE '%KIDS%'
              AND s.COUNTRY_NM = 'Korea, Republic of' THEN 'KIDS'
         WHEN s.MRT_TYPE = 'kids'
              OR s.PARTNER_ID IN ('20859', '20858', '101172', '101238', '100326')
              OR s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%' THEN 'KIDS'
         ELSE 'MRT' END                                                                         AS SALE_FORM_CD
  , s.MRT_TYPE
  , CASE WHEN s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%' THEN 'KIDS_PACKAGE'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_AIR' THEN 'AIR_ONLY'
         WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_AIRTEL' THEN 'AIRTEL'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_TNA' THEN 'TNA_PLUS'
         ELSE 'PACKAGE_OTHERS' END                                                              AS BIZ_TYPE
  , CASE WHEN s.PARTNERSHIP_CD IS NOT NULL AND s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE'
              THEN 'B2B_AGENCY_MYPACK'
         WHEN pc.MARKETING_PARTNERSHIP_CD IS NOT NULL
              THEN 'B2B_AGENCY_MYLINK_MYPACK'
         WHEN s.STANDARD_CATEGORY_LV_3_CD = 'B2B_AFFILIATE_FLIGHT_GROUP'
              THEN 'B2B_AFFILIATE_FLIGHT'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE'
              AND s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE', 'B2B_AFFILIATE_ORDER_MADE')
              THEN 'B2B_AGENCY_ORDER_MADE'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE'
              AND s.STANDARD_CATEGORY_LV_2_CD IN ('B2B_AFFILIATE_ORDER_MADE')
              THEN 'B2B_AFFILIATE_ORDER_MADE'
         WHEN br.RESVE_ID IS NOT NULL
              THEN 'B2B_AFFILIATE_POINT_MYPACK'
         WHEN (CASE WHEN ucr.RESVE_ID IS NOT NULL THEN ucr.COUPON_ID
                    WHEN cp.COUPON_NM IS NOT NULL THEN cp.COUPON_ID
                    WHEN coupon_30.COUPON_ID IS NOT NULL THEN coupon_30.COUPON_ID
                    WHEN ci.TITLE IS NOT NULL THEN ci.ID
                    ELSE NULL END) IN (SELECT DISTINCT COUPON_ID FROM B2B_AFFILIATE_COUPON)
              THEN 'B2B_AFFILIATE_COUPON_MYPACK'
         WHEN s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%' THEN 'KIDS_PACKAGE'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_AIR' THEN 'AIR_ONLY'
         WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_AIRTEL' THEN 'AIRTEL'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_TNA' THEN 'TNA_PLUS'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'PACKAGE_OTHERS'
         WHEN s.COUNTRY_NM != 'Korea, Republic of' AND s.COUNTRY_NM IS NOT NULL
              THEN 'OUTBOUND_TNA'
         WHEN s.COUNTRY_NM = 'Korea, Republic of' THEN 'DOMESTIC_TNA'
         ELSE 'PACKAGE_OTHERS' END                                                              AS BIZ_TYPE_V2
  , CASE WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_STAY_DOMESTIC' THEN 'PKG_STAY_DOMESTIC'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_BIZ_STAY' THEN 'PKG_STAY_OUTBOUND'
         WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_TNA_DOMESTIC' THEN 'PKG_TNA_DOMESTIC'
         WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_BIZ_TNA' THEN 'PKG_TNA_OUTBOUND'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN 'ORDER_MADE'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE'
              AND s.COUNTRY_NM != 'Korea, Republic of' AND s.COUNTRY_NM IS NOT NULL
              THEN 'PKG_OTHERS_OUTBOUND'
         WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE'
              AND s.COUNTRY_NM = 'Korea, Republic of' THEN 'PKG_OTHERS_DOMESTIC'
         WHEN s.COUNTRY_NM != 'Korea, Republic of' AND s.COUNTRY_NM IS NOT NULL
              THEN 'OUTBOUND_TNA'
         WHEN s.COUNTRY_NM = 'Korea, Republic of' THEN 'DOMESTIC_TNA'
         ELSE 'PACKAGE_OTHERS' END                                                              AS BIZ_TYPE_V3
  , fc.FPNA_CATEGORY
  , s.TEAM_DIVISION
  , s.FLIGHT_RESVE_ID
  , s.FLIGHT_CREATE_KST_DT
  , s.FLIGHT_TRAVEL_START_KST_DATE
  , s.HOTEL_CAMPAIGN_ID
  , s.CREATE_KST_DT
  , s.CONFIRM_KST_DT
  , s.CONFIRM_KST_DATE
  , s.CREATE_KST_DATE
  , s.PARTNER_ID
  , po.NAME                                                                                     AS PARTNER_NM
  , s.GID
  , s.GPID
  , s.PRODUCT_ID
  , s.PRODUCT_TITLE                                                                             AS PRODUCT_TITLE
  , CASE WHEN s.COUNTRY_NM = 'Korea, Republic of' THEN 'Domestic'
         WHEN s.COUNTRY_NM != 'Korea, Republic of' AND s.COUNTRY_NM IS NOT NULL THEN 'Outbound'
         ELSE 'Outbound' END                                                                    AS REGION_TYPE
  , s.REGION_NM
  , CASE WHEN s.COUNTRY_NM IS NULL THEN 'Others'
         ELSE s.COUNTRY_NM END                                                                  AS COUNTRY_NM
  , CASE WHEN s.CITY_NM IS NULL THEN 'Others'
         ELSE s.CITY_NM END                                                                     AS CITY_NM
  , CASE WHEN s.CITY_NM = 'Jeju' AND s.COUNTRY_NM = 'Korea, Republic of' THEN 'Y'
         WHEN s.CITY_NM != 'Jeju' AND s.COUNTRY_NM = 'Korea, Republic of' THEN 'N'
         WHEN s.COUNTRY_NM != 'Korea, Republic of' THEN 'N'
         WHEN s.COUNTRY_NM IS NULL THEN 'N'
         ELSE 'N' END                                                                           AS JEJU_FLAG
  , CASE WHEN ucr.RESVE_ID IS NOT NULL THEN ucr.COUPON_ID
         WHEN cp.COUPON_NM IS NOT NULL THEN cp.COUPON_ID
         WHEN coupon_30.COUPON_ID IS NOT NULL THEN coupon_30.COUPON_ID
         WHEN ci.TITLE IS NOT NULL THEN ci.ID
         ELSE NULL END                                                                          AS COUPON_ID
  , pcr.COUPON_ID                                                                              AS PRODUCT_COUPON_ID
  , ocr.COUPON_ID                                                                              AS ORDER_COUPON_ID
  , CASE WHEN ucr.RESVE_ID IS NOT NULL THEN ucr.COUPON_TITLE
         WHEN cp.COUPON_NM IS NOT NULL THEN cp.COUPON_NM
         WHEN coupon_30.COUPON_ID IS NOT NULL THEN coupon_30.COUPON_TITLE
         WHEN ci.TITLE IS NOT NULL THEN ci.TITLE
         WHEN s.COUPON_PRICE > 0 AND cp.COUPON_NM IS NULL AND ci.TITLE IS NULL THEN 'UNKNOWN'
         WHEN ci.TITLE IS NULL AND cp.COUPON_NM IS NULL THEN NULL
         ELSE 'ERROR' END                                                                       AS COUPON_TITLE
  , CASE WHEN s.COUPON_PRICE > 0 AND cp.COUPON_ID IS NULL AND ci.ID IS NULL THEN 'UNKNOWN'
         ELSE cp.COUPON_PUBLISH_TEAM END                                                        AS COUPON_PUBLISH_TEAM_NM
  , CASE WHEN s.COUPON_PRICE > 0 AND cp.COUPON_ID IS NULL AND ci.ID IS NULL THEN 'UNKNOWN'
         ELSE cp.COUPON_PUBLISH_PURPOSE END                                                     AS COUPON_PUBLISH_PURPOSE_NM
  , CASE WHEN s.CROSS_SELL_FLAG IS NULL THEN 'N'
         ELSE s.CROSS_SELL_FLAG END                                                             AS CROSS_SELL_FLAG
  /* 커미션율 = (3요소 합산 커미션 / 1.1) / 총판매가 */
  , FLOOR(SAFE_DIVIDE(
        SAFE_DIVIDE(
            CASE WHEN pkg.RESVE_ID IS NOT NULL THEN pkg.MRT_SALES_PRICE
                 ELSE s.COMMISSION_PRICE END
          , 1.1)
      , s.SALES_KRW_PRICE) * 100) / 100                                                        AS COMMISSION_RATE
  , s.COMMISSION_PRICE                                                                          AS SALES_COMMISSION_PRICE
  , s.PARTNER_SETTLE_TYPE
  , s.PARTNER_SALES_TYPE
  , s.PARTNERSHIP_CD
  , s.MARKETING_PARTNERSHIP_CD
  , pg.PG                                                                                       AS PG_NM
  , pg.PG_COM_RATE                                                                              AS PG_RATE
  , s.SALES_KRW_PRICE
  /* MRT 총매출 = FLOOR(3요소 합산 커미션 / 1.1 * 100) / 100 */
  , IFNULL(FLOOR(
        CASE WHEN pkg.RESVE_ID IS NOT NULL THEN pkg.MRT_SALES_PRICE
             ELSE s.COMMISSION_PRICE END
      / 1.1 * 100) / 100, 0)                                                                   AS MRT_SALES_PRICE
  , pkg.SUPPLY_PRICE
  , pkg.WITHOUT_AIR_SUPPLY_PRICE
  , icm.TOTAL_INSURANCE_PRICE
  , CASE
        WHEN ci.ID IS NULL THEN 0
        WHEN GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0) = 0 THEN 0
        WHEN ucr.RESVE_ID IS NOT NULL OR cp.COUPON_NM IS NOT NULL OR coupon_30.COUPON_ID IS NOT NULL
            THEN CASE
                    WHEN fci_2.COUPON_ID IS NOT NULL OR cei_2.COUPON_ID IS NOT NULL
                        THEN {{ fpna_coupon_burden_price(
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_2',
                            'cei_2',
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                    ELSE {{ fpna_coupon_burden_price(
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_3',
                            'cei_legacy',
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                 END
        ELSE {{ fpna_coupon_burden_price(
                'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                'fci_2',
                'cei_2',
                'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
            ) }}
    END
    + IFNULL(P30C.COUPON_PRICE, 0)
    + IFNULL(
        CAST(
            SAFE_DIVIDE(
                s.PRODUCT_COUPON_PRICE,
                NULLIF(s.PRODUCT_COUPON_PRICE + s.ORDER_COUPON_PRICE, 0)
            ) * IF(
                ci.ID IS NULL
                AND P30C.RESVE_ID IS NULL
                AND O30C.RESVE_ID IS NULL
                AND s.COUPON_PRICE > 0,
                {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                0
            ) AS INT64
        ),
        IF(
            ci.ID IS NULL
            AND P30C.RESVE_ID IS NULL
            AND O30C.RESVE_ID IS NULL
            AND s.COUPON_PRICE > 0,
            {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
            0
        )
    )                                                                                         AS PRODUCT_COUPON_PRICE
  , IFNULL(O30C.COUPON_PRICE, 0)
    + IF(
        ci.ID IS NULL
        AND P30C.RESVE_ID IS NULL
        AND O30C.RESVE_ID IS NULL
        AND s.COUPON_PRICE > 0,
        {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
        0
    )
    - IFNULL(
        CAST(
            SAFE_DIVIDE(
                s.PRODUCT_COUPON_PRICE,
                NULLIF(s.PRODUCT_COUPON_PRICE + s.ORDER_COUPON_PRICE, 0)
            ) * IF(
                ci.ID IS NULL
                AND P30C.RESVE_ID IS NULL
                AND O30C.RESVE_ID IS NULL
                AND s.COUPON_PRICE > 0,
                {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                0
            ) AS INT64
        ),
        IF(
            ci.ID IS NULL
            AND P30C.RESVE_ID IS NULL
            AND O30C.RESVE_ID IS NULL
            AND s.COUPON_PRICE > 0,
            {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
            0
        )
    )                                                                                         AS ORDER_COUPON_PRICE
  , CASE
        WHEN ci.ID IS NULL THEN 0
        WHEN GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0) = 0 THEN 0
        WHEN ucr.RESVE_ID IS NOT NULL OR cp.COUPON_NM IS NOT NULL OR coupon_30.COUPON_ID IS NOT NULL
            THEN CASE
                    WHEN fci_2.COUPON_ID IS NOT NULL OR cei_2.COUPON_ID IS NOT NULL
                        THEN {{ fpna_coupon_burden_price(
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_2',
                            'cei_2',
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                    ELSE {{ fpna_coupon_burden_price(
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_3',
                            'cei_legacy',
                            'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                 END
        ELSE {{ fpna_coupon_burden_price(
                'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                'fci_2',
                'cei_2',
                'GREATEST(s.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
            ) }}
    END
    + IFNULL(P30C.COUPON_PRICE, 0)
    + IFNULL(O30C.COUPON_PRICE, 0)
    + IF(
        ci.ID IS NULL
        AND P30C.RESVE_ID IS NULL
        AND O30C.RESVE_ID IS NULL
        AND s.COUPON_PRICE > 0,
        {{ fpna_coupon_burden_price('s.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
        0
    )                                                                                         AS COUPON_PRICE
  , IFNULL(s.POINT_PRICE, 0)                                                                   AS POINT_PRICE
  , IFNULL(CASE WHEN pd.POINT_SUM IS NOT NULL THEN s.POINT_PRICE ELSE 0 END, 0)                 AS EXCLUDED_POINT_PRICE
  , IFNULL(SAFE_DIVIDE(s.DISCOUNT_PRICE, 1.1), 0)                                              AS DISCOUNT_PRICE
  , IFNULL(FLOOR(
        CASE WHEN r.VERSION = 1 THEN s.SALES_PRICE
             ELSE pkg.WITHOUT_AIR_SALES_PRICE END
      * IFNULL(pg.PG_COM_RATE, 0.02) * 100) / 100, 0)                                         AS CHANNEL_FEE_PRICE
  , IFNULL(ampc.PARTNERSHIP_COMMISSION, 0)                                                      AS AGENCY_FEE
  , s.SALES_KRW_PRICE
      * CASE WHEN s.MARKETING_PARTNERSHIP_CD IS NOT NULL THEN 0.035 ELSE 0 END                  AS MARKETING_PARTNER_FEE
  , IFNULL(CASE WHEN br.RESVE_ID IS NOT NULL THEN s.POINT_PRICE * 0.02 ELSE 0 END, 0)          AS AFFILIATE_POINT_FEE
  , CAST(NULL AS FLOAT64)                                                                       AS NET_PRICE
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                          AS DW_LOAD_DT
FROM {{ ref('MART_SALE_D') }} s
LEFT JOIN {{ ref('MART_USER_D') }} u
    ON s.USER_ID = u.USER_ID
LEFT JOIN {{ source('partners', 'partner') }} po
    ON s.PARTNER_ID = CAST(po.ID AS STRING)
LEFT JOIN {{ source('mrt_20', 'promotion_coupon_codes') }} pcc
    ON CAST(pcc.RESERVATION_ID AS STRING) = s.RESVE_ID
LEFT JOIN {{ source('mrt_20', 'promotion_coupons') }} ci
    ON ci.ID = pcc.COUPON_ID
LEFT JOIN CP_PRODUCT cp
    ON cp.RESVE_ID = s.RESVE_ID
LEFT JOIN USED_COUPON_RESVE ucr
    ON ucr.RESVE_ID = s.RESVE_ID
LEFT JOIN PRODUCT_COUPON_REP pcr
    ON pcr.RESVE_ID = s.RESVE_ID
LEFT JOIN {{ source('orders', 'reservations') }} r
    ON s.RESVE_ID = r.RESERVATION_NO
   AND r.DELETED_AT IS NULL
LEFT JOIN ORDER_COUPON_REP ocr
    ON ocr.RESVE_ID = s.RESVE_ID
LEFT JOIN COUPON_30
    ON coupon_30.RESVE_ID = s.RESVE_ID
LEFT JOIN COUPON_EXTRA_INFO cei_2
    ON cei_2.COUPON_ID = ci.ID
LEFT JOIN COUPON_EXTRA_INFO cei_legacy
    ON cei_legacy.COUPON_ID = (
        CASE
            WHEN ucr.RESVE_ID IS NOT NULL THEN ucr.COUPON_ID
            WHEN cp.COUPON_NM IS NOT NULL THEN cp.COUPON_ID
            ELSE coupon_30.COUPON_ID
        END
    )
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_2
    ON fci_2.COUPON_ID = ci.ID
   AND fci_2.TYPE = '2.0 product'
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_3
    ON fci_3.COUPON_ID = (
        CASE
            WHEN ucr.RESVE_ID IS NOT NULL THEN ucr.COUPON_ID
            WHEN cp.COUPON_NM IS NOT NULL THEN cp.COUPON_ID
            ELSE coupon_30.COUPON_ID
        END
    )
   AND fci_3.TYPE = '3.0 product'
LEFT JOIN PRODUCT_30_COUPON_COST P30C
    ON P30C.RESVE_ID = s.RESVE_ID
LEFT JOIN ORDER_30_COUPON_COST O30C
    ON O30C.RESVE_ID = s.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_RSV_CANCEL') }} rc
    ON s.RESVE_ID = rc.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_POINT_DETAIL') }} pd
    ON pd.RESVE_ID = s.RESVE_ID
LEFT JOIN (
    SELECT
        PARTNER_ID
      , MAX(ACCOUNTING_PROJECT_CODE)                                                            AS ACCOUNTING_PROJECT_CODE -- 비즈니스 의도: 파트너당 최신 프로젝트 코드
    FROM {{ source('settles', 'partner_settlement_configs') }}
    GROUP BY PARTNER_ID
) psc
    ON psc.PARTNER_ID = s.PARTNER_ID
LEFT JOIN {{ ref('FPNA_CATEGORY_INFO') }} fc
    ON s.STANDARD_CATEGORY_LV_3_CD = fc.LV_3_CD
LEFT JOIN {{ ref('INT_FPNA_PG_FEE') }} pg
    ON s.RESVE_ID = pg.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_AGENCY_COMMISSION') }} ampc
    ON ampc.RESVE_ID = s.RESVE_ID
LEFT JOIN B2B_POINT_RSV br
    ON s.RESVE_ID = br.RESVE_ID
LEFT JOIN PACKAGE_RSV_SALES pkg
    ON pkg.RESVE_ID = s.RESVE_ID
LEFT JOIN MYLINK_PARTNERSHIP_CODE pc
    ON s.MARKETING_PARTNERSHIP_CD = pc.MARKETING_PARTNERSHIP_CD
LEFT JOIN INSURANCE_COST_MANI icm
    ON icm.RESVE_ID = s.RESVE_ID
WHERE s.KIND = 1
  AND pkg.RESVE_ID IS NOT NULL
