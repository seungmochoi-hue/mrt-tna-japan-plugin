{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_LODGMENT_PROFIT_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['SALE_FORM_CD', 'RECENT_STATUS', 'DOMAIN_NM']
    )
}}


WITH MRT_GID /* 직계약 호텔 수수료 맵핑을 위한 임시 테이블 */ AS (
    SELECT S.GID
         , MAX(S.COMMISSION_RATE) AS commission_rate
    FROM {{ ref("MART_SALE_D") }} S
    WHERE S.kind = 1
      AND S.hotel_affiliate_nm = 'mrt'
      AND S.mrt_type = 'hotel'
      AND S.partner_settle_type = 'internal'
    GROUP BY S.gid
),
OPEN_TICKET_GID AS (
    SELECT DISTINCT GID
        ,  OPEN_DATE
        ,  CLOSE_DATE
    FROM {{ ref('FPNA_TICKETLODGING_INFO') }}
    WHERE ACCOUNT_TYPE = '날짜지정'
      AND STATUS <> 'LOST'
      AND GID IS NOT NULL
),
OPEN_TICKET_RESVE_DATA AS (
    SELECT DISTINCT s.RESVE_ID, '날짜지정 숙박권' AS TYPE
    FROM {{ ref("MART_SALE_D") }} s
    LEFT JOIN OPEN_TICKET_GID o ON s.GID = o.GID AND (s.basis_date BETWEEN o.OPEN_DATE AND o.CLOSE_DATE)
    WHERE o.GID IS NOT NULL
),
OSP_MAPPING AS (
    SELECT T.gid
        ,  T.osp_id
        ,  T.osp_name
    FROM (
           SELECT CAST(L.lodging_id AS STRING) AS gid
                , L.osp_id
                , L.osp_name
                , ROW_NUMBER() OVER(PARTITION BY L.osp_id ORDER BY L.created_at DESC) AS idx
             FROM {{ source('localstay', 'lodging') }} L
    ) T
    WHERE T.idx = 1
),
HOCANCE_NORMAL_TICKET AS (
    SELECT  I.GID
         ,  AVG(CASE WHEN I.SETTLE_TYPE = '판매가' THEN I.MRT_TAKE_RATE
                     WHEN I.SETTLE_TYPE = '입금가' AND I.MRT_TAKE_RATE IS NOT NULL THEN I.MRT_TAKE_RATE
                     WHEN I.SETTLE_TYPE = '입금가' AND I.MRT_TAKE_RATE IS NULL THEN NULL
                     ELSE NULL END) AS MRT_TAKE_RATE
        ,  MAX(CASE WHEN I.OSP_ID = 'n/a' OR I.OSP_ID IS NULL THEN NULL ELSE I.OSP_ID END) AS OSP_ID
        ,  MAX(I.OSP_NM) AS OSP_NAME
    FROM {{ ref('FPNA_TICKETLODGING_INFO') }} I
    WHERE I.ACCOUNT_TYPE = '숙박권'
      AND I.GID IS NOT NULL
      AND I.STATUS <> 'LOST'
    GROUP BY I.GID
),
PRODUCT_TITLE_OSP_MAPPING AS (
    SELECT DISTINCT data.gid
         , data.osp_id
         , om2.osp_name
    FROM (
        SELECT DISTINCT s.gid
             , MAX(IFNULL(om1.osp_id, om2.osp_id)) AS osp_id
        FROM {{ ref("MART_SALE_D") }} s
        LEFT JOIN {{ source('localstay', 'lodging') }} om1 ON CAST(om1.osp_name AS STRING) = s.product_title
        LEFT JOIN {{ source('localstay', 'lodging') }} om2 ON CAST(om2.name AS STRING) = s.product_title
        WHERE s.KIND = 1 AND s.MRT_TYPE IN ('hotel') AND s.HOTEL_AFFILIATE_NM NOT IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb')
        GROUP BY S.gid
    ) data
    LEFT JOIN OSP_MAPPING om2 ON data.osp_id = om2.osp_id
    WHERE data.osp_id IS NOT NULL
),
DST_DATA AS (
    SELECT GID
        ,  OPEN_DATE
        ,  CLOSE_DATE
        ,  ACCOUNT_TYPE
        ,  PROMOTION_TYPE
        ,  DST_TEAM_TYPE
        ,  ROW_NO
    FROM {{ ref('FPNA_LODGMENT_DST_TOTAL_INFO') }}
    WHERE DST_STATUS NOT IN ('LOST', 'PITCH') AND DST_STATUS IS NOT NULL AND GID IS NOT NULL
),
B2B_NET_PRICE_DATA AS (
    WITH TOTAL AS (
        WITH DATA AS (
            WITH LODGING AS (
                SELECT DISTINCT
                CONCAT('STY', osp_id) AS gpid
                    , osp_id
                    , star
                FROM {{ source('localstay', 'lodging') }}
            ),
            RSV_CANCEL AS ( -- 예약별 취소 정보 (INT_FPNA_RSV_CANCEL ref 참조)
                SELECT * FROM {{ ref('INT_FPNA_RSV_CANCEL') }}
            ),
            HOTEL_RESV AS (
                SELECT s.*, IFNULL(DATE_DIFF(rc.CANCEL_DATE, s.BASIS_DATE, DAY),0) AS cancel_date_diff, rc.CANCEL_DATE
                FROM {{ ref("MART_SALE_D") }} s
                LEFT JOIN RSV_CANCEL rc ON rc.resve_id = s.resve_id
                WHERE KIND = 1
                AND MRT_TYPE = 'hotel'
                AND DOMAIN_NM IN ('2.0 PRODUCT', '3.0 PRODUCT')
            )
            SELECT DISTINCT HOTEL_RESV.resve_id
                 , HOTEL_RESV.TRAVEL_START_KST_DATE AS travel_start_date
                 , hotel_resv.GID
                 , hotel_resv.PRODUCT_TITLE
                 , hotel_resv.recent_status
                 , COALESCE(CAST(ord20.offer_price_id AS STRING),
                   SPLIT(ord30.option_id,':-:')[OFFSET(1)]) AS option_id
                 , COALESCE(ord20.title, ord30.option_title) AS option_title
                 , HOTEL_RESV.DOMAIN_NM
                 , HOTEL_RESV.CANCEL_DATE_DIFF
                 , COUNT(DISTINCT RESVE_ID) AS resv_cnt
                 , SUM(CASE
                       WHEN hotel_resv.DOMAIN_NM = '2.0 PRODUCT' THEN ord20.quantity
                       WHEN hotel_resv.DOMAIN_NM = '3.0 PRODUCT' THEN ord30.quantity
                       END) AS ticket_cnt
                 FROM HOTEL_RESV
                 LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} AS ord20
                 ON hotel_resv.RESVE_ID = CAST(ord20.reservation_id AS STRING) AND hotel_resv.DOMAIN_NM = '2.0 PRODUCT'
                 LEFT JOIN mrtdata.edw.DW_HOTEL_ONDA_PREMISES AS ho
                 ON hotel_resv.PRODUCT_ID = CAST(ho.mrt20_offer_id AS STRING) AND hotel_resv.DOMAIN_NM = '2.0 PRODUCT'
                 LEFT JOIN {{ source('orders', 'reservations') }} AS res30
                 ON hotel_resv.RESVE_ID = res30.reservation_no AND hotel_resv.DOMAIN_NM = '3.0 PRODUCT'
                 LEFT JOIN {{ source('orders', 'option_reservations') }} AS ord30
                 ON ord30.reservation_id = res30.id
                 LEFT JOIN LODGING AS l
                 ON hotel_resv.PRODUCT_ID = l.gpid
                 WHERE GID IN (SELECT DISTINCT gid FROM {{ ref('FPNA_B2B_GID_INFO') }} WHERE MRT_TYPE IN ('hotel','ticket_lodging','pension','lodging')) AND basis_date < '2023-03-01'
                 GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
            )
            SELECT
            d.resve_id,
            d.option_id,
            d.option_title,
            d.recent_status,
            (d.ticket_cnt * np.price_amount) AS gmv,
            d.ticket_cnt,
            d.ticket_cnt * np.NET_PRICE_AMOUNT AS net_price_amount,
            (d.ticket_cnt * np.price_amount) - (d.ticket_cnt * np.NET_PRICE_AMOUNT) AS net_sales,
            d.ticket_cnt * np.BACK_COMMISSION_PRICE_AMOUNT AS back_commission_price_amount,
            CASE
            WHEN np.FULL_REFUND_BEOFRE_DAY >= d.CANCEL_DATE_DIFF THEN d.ticket_cnt * np.support_price_amount
            WHEN np.FULL_REFUND_BEOFRE_DAY < d.CANCEL_DATE_DIFF THEN 0
            ELSE np.support_price_amount
            END AS support_price_amount,
            (d.ticket_cnt * np.price_amount) * (SELECT PARTNER_TAKE_RATE FROM {{ ref('FPNA_B2B_PARTNER_TAKE_RATE_INFO') }} WHERE TYPE = 'B2B_삼성' AND mrt_type = 'hotel' AND biz_type = 'Hotel') AS onda_commission_cost
            FROM DATA d
            LEFT JOIN {{ ref('FPNA_B2B_NET_PRICE_INFO') }} np ON CAST(np.option_id AS STRING) = d.option_id AND np.travel_start_date = d.travel_start_date
        )
    SELECT resve_id
         , SUM(gmv) AS gmv
         , SUM(IFNULL(net_sales,0) + IFNULL(back_commission_price_amount,0) - IFNULL(onda_commission_cost,0) + IFNULL(support_price_amount,0)) AS mrt_sales_w_vat
         , SAFE_DIVIDE(SUM(IFNULL(net_sales,0) + IFNULL(back_commission_price_amount,0) - IFNULL(onda_commission_cost,0) + IFNULL(support_price_amount,0)),1.1) AS mrt_sales_wo_vat
         , SAFE_DIVIDE(SAFE_DIVIDE(SUM(IFNULL(net_sales,0) + IFNULL(back_commission_price_amount,0) - IFNULL(onda_commission_cost,0) + IFNULL(support_price_amount,0)),1.1),SUM(gmv)) AS tr_wo_vat
    FROM TOTAL
    GROUP BY 1
),
SAMSUNG_B2B_2ND_DATA AS (
    WITH DATA AS (
        WITH B2B_HOTEL_RESV AS (
            SELECT *
            FROM {{ ref("MART_SALE_D") }}
            WHERE KIND = 1
            AND MRT_TYPE = 'hotel'
            AND DOMAIN_NM IN ('2.0 PRODUCT', '3.0 PRODUCT')
            AND GID IN (SELECT DISTINCT gid FROM {{ ref('FPNA_B2B_GID_INFO') }} WHERE MRT_TYPE IN ('hotel','ticket_lodging','pension','lodging') AND REMARK_1 IN ('재진행','신규'))
            AND BASIS_DATE >= '2023-04-03'
        )
        SELECT b2b.resve_id,
               CASE WHEN b2b.gid IN ('1097820','1097822') THEN b2b.sales_krw_price * 0.12
               ELSE IFNULL(bsi.mrt_take_amount*ord30.quantity,bsi2.mrt_take_amount*ord30.quantity) END AS mrt_take_amount
               FROM B2B_HOTEL_RESV b2b
               LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} AS ord20
               ON b2b.RESVE_ID = CAST(ord20.reservation_id AS STRING) AND b2b.DOMAIN_NM = '2.0 PRODUCT'
               LEFT JOIN {{ source('localstay', 'onda_premises') }} AS ho
               ON b2b.PRODUCT_ID = CAST(ho.mrt20_offer_id AS STRING) AND b2b.DOMAIN_NM = '2.0 PRODUCT'
               LEFT JOIN {{ source('orders', 'reservations') }} AS res30
               ON b2b.RESVE_ID = res30.reservation_no AND b2b.DOMAIN_NM = '3.0 PRODUCT'
               LEFT JOIN {{ source('orders', 'option_reservations') }} AS ord30
               ON ord30.reservation_id = res30.id
               LEFT JOIN {{ ref ('FPNA_B2B_SAMSUNG_INFO') }} AS bsi ON bsi.option_title = ord30.option_title
               LEFT JOIN {{ ref ('FPNA_B2B_SAMSUNG_INFO') }} AS bsi2 ON bsi2.option_title_2 = COALESCE(ord30.option_title, ord20.title)
        )
    SELECT resve_id, MAX(mrt_take_amount) AS mrt_take_amount
      FROM DATA GROUP BY 1
),
COUPON_APPLIED_RESVE AS (
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
),
COUPON_REP_RANKED AS (
    SELECT
        *
      , ROW_NUMBER() OVER (
            PARTITION BY RESVE_ID, USABLE_TYPE
            ORDER BY PAYMENT_COUPON_PRICE DESC, COUPON_USER_MAPPING_ID DESC, COUPON_ID DESC
        ) AS RN
    FROM COUPON_APPLIED_RESVE
),
PRODUCT_COUPON_REP AS (
    SELECT
        RESVE_ID
      , COUPON_ID
      , COUPON_NM
      , COUPON_PUBLISH_TEAM
      , COUPON_PUBLISH_PURPOSE
    FROM COUPON_REP_RANKED
    WHERE USABLE_TYPE = 'PRODUCT'
      AND RN = 1
),
ORDER_COUPON_REP AS (
    SELECT
        RESVE_ID
      , COUPON_ID
      , COUPON_NM
      , COUPON_PUBLISH_TEAM
      , COUPON_PUBLISH_PURPOSE
    FROM COUPON_REP_RANKED
    WHERE USABLE_TYPE = 'ORDER'
      AND RN = 1
),
CP_PRODUCT AS (
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
),
USED_COUPON_RESVE AS (
    SELECT
        cu.RESERVATION_NO AS RESVE_ID
      , MAX(cc.TEMPLATE_ID) AS COUPON_ID
      , MAX(ct.NAME) AS COUPON_TITLE
    FROM {{ source('coupon', 'coupon_user_mapping') }} AS cc
    LEFT JOIN {{ source('coupon', 'coupon_templates') }} AS ct
        ON cc.TEMPLATE_ID = ct.ID
    LEFT JOIN {{ source('coupon', 'coupon_use_history') }} AS cu
        ON cc.ID = cu.COUPON_USER_MAPPING_ID
       AND cu.ACTION_TYPE = 'USE'
    GROUP BY cu.RESERVATION_NO
),
COUPON_EXTRA_INFO AS (
    SELECT DISTINCT t.id AS coupon_id
         , flat_amount AS coupon_value
    -- 정액 쿠폰일 경우 value
         , CASE WHEN flat_amount IS NOT NULL THEN flat_amount * mrt_contribution_rate *0.01
           ELSE NULL END AS mrt_value
        , CASE WHEN flat_amount IS NOT NULL THEN flat_amount * partner_contribution_rate *0.01
          ELSE NULL END AS partner_value
    -- 정률 쿠폰일 경우 value
        , mrt_contribution_rate
        , partner_contribution_rate
    FROM {{ source('coupon', 'coupon_templates') }} t
    LEFT JOIN {{ source('coupon', 'coupon_template_condition_mappings') }} c ON t.id = c.template_id AND is_include = true
    -- 쿠폰 적용 상품 정보 매핑
    WHERE (partner_contribution_rate IS NOT NULL AND partner_contribution_rate > 0)
       OR (
           mrt_contribution_rate IS NOT NULL
           AND mrt_contribution_rate > 0
           AND mrt_contribution_rate < 100
       )
),
PRODUCT_30_COUPON_COST AS (
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
),
ORDER_30_COUPON_COST AS (
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
),
B2B_AFFILIATE_COUPON AS (
    SELECT
        DISTINCT CCT.id AS COUPON_ID
    FROM
        {{ source('coupon', 'coupon_templates') }} CCT
        LEFT JOIN {{ source('coupon', 'coupon_template_types') }} CCTT ON CCT.template_type_id = CCTT.id
    WHERE
        CCTT.publish_team = 'CORPORATION_BUSINESS'
),

MYLINK_PARTNERSHIP_CODE AS (
SELECT DISTINCT pp.code AS MARKETING_PARTNERSHIP_CD
FROM {{ source('partners', 'partnership') }} AS pp
    LEFT JOIN {{ source('partners', 'partner') }} AS p ON pp.partner_id = p.id
    LEFT JOIN {{ source('partners', 'partner_account') }} a ON p.id = A.partner_id AND A.type = 'MASTER'
WHERE
    LEFT(code, 1) = 'M'
  AND p.business_registration_type IN ('DOMESTIC','PRIVATE')
  AND CAST(p.id AS STRING) NOT IN (SELECT DISTINCT PARTNER_ID FROM {{ ref('FPNA_MYLINK_PARTNER_INFO') }} WHERE MANAGEMENT_TEAM NOT IN ('B2B / 제휴여행사'))
),
PACKAGE_RESVE AS (
SELECT DISTINCT RESVE_ID
  FROM {{ ref('MART_PACKAGE_OPTION_SALE_D') }} S
WHERE S.KIND = 1
  AND S.BASIS_DATE > '2025-07-01'
  AND S.RESVE_ID NOT LIKE '%PKG%'
),
STAY_PROPERTY_LATEST AS (
    SELECT
        CAST(property_id AS STRING) AS GID
        , resell_market AS RESELL_MARKET
    FROM mrtdata.edw.DW_MRT_STAY_PROPERTY
    QUALIFY ROW_NUMBER() OVER (PARTITION BY property_id ORDER BY updated_at DESC) = 1
)

SELECT S.BASIS_DATE,
       S.ORDER_ID,
       S.ORDER_NO,
       S.RESVE_ID,
       S.DOMAIN_NM,
       S.TRAVEL_START_KST_DATE                                                                          AS TRAVEL_START_DATE,
       S.TRAVEL_END_KST_DATE                                                                            AS TRAVEL_END_DATE,
       DATE_DIFF(S.TRAVEL_END_KST_DATE, S.TRAVEL_START_KST_DATE, DAY)                                   AS TRAVEL_DAYS,
       rc.CANCEL_DATE                                                                                   AS CANCEL_DATE,
       DATE_DIFF(rc.CANCEL_DATE, S.BASIS_DATE, DAY)                                                     AS RESVE_CANCEL_DAY_DIFF,
       S.RECENT_STATUS,
       S.RESVE_PRSNL_CNT,
       S.TRAVEL_ID,
       S.TRAVEL_DETAIL_ID,
       U.MRT_STAFF_FLAG                                                                                 AS MRT_STAFF_FLAG,
       S.USER_ID,
       S.CATEGORY_NM,
       S.CATEGORY_CD,
       S.SUB_CATEGORY_CD,
       S.STANDARD_CATEGORY_LV_1_CD,
       S.STANDARD_CATEGORY_LV_1_NM,
       S.STANDARD_CATEGORY_LV_2_CD,
       S.STANDARD_CATEGORY_LV_2_NM,
       S.STANDARD_CATEGORY_LV_3_CD,
       S.STANDARD_CATEGORY_LV_3_NM,
       S.PARTNERSHIP_TYPE,
       psc.accounting_project_code AS ACCOUNTING_PROJECT_CODE,
       CASE WHEN s.PARTNERSHIP_TYPE = 'AGENCY' THEN 'B2B'
            WHEN s.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 'B2B'
            WHEN pd.IS_B2B_POINT_RSV = TRUE THEN 'B2B'
            WHEN s.STANDARD_CATEGORY_LV_2_CD = 'KIDS_ACCOMMODATION_TICKET' THEN 'KIDS'
            ELSE 'MRT' END AS SALE_FORM_CD,
       S.MRT_TYPE,
       CASE WHEN BZP.PARTNER_ID IS NOT NULL THEN BZP.BIZ_TYPE
            WHEN BZG.GID IS NOT NULL THEN BZG.BIZ_TYPE
            WHEN otrd.RESVE_ID IS NOT NULL THEN 'Hocance'
            WHEN S.MRT_TYPE = 'ticket_lodging' THEN 'Hocance'
            WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN 'Hotel_meta'
            WHEN S.MRT_TYPE = 'hotel' THEN 'Hotel'
            WHEN S.MRT_TYPE = 'pension' THEN 'Pension'
            WHEN S.MRT_TYPE = 'lodging' THEN 'Lodging' END                                              AS BIZ_TYPE,
       CASE WHEN s.PARTNERSHIP_CD IS NOT NULL THEN 'B2B_AGENCY_AC'
            WHEN S.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 'B2B_AFFILIATE_PROMOTION'
            WHEN pd.IS_B2B_POINT_RSV = TRUE THEN 'B2B_AFFILIATE_POINT_AC'
            WHEN (CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
                       WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
                       WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_ID
                       WHEN ci.title IS NOT NULL THEN ci.id ELSE NULL END) IN (SELECT DISTINCT coupon_id FROM B2B_AFFILIATE_COUPON) THEN 'B2B_AFFILIATE_COUPON_AC'
            WHEN PC.MARKETING_PARTNERSHIP_CD IS NOT NULL THEN 'B2B_AGENCY_MYLINK_AC'
            WHEN S.PARTNER_ID IN ('114540', '19355') THEN 'PKG_TOURTEL'
            WHEN S.STANDARD_CATEGORY_LV_2_CD = 'KIDS_ACCOMMODATION_TICKET' THEN 'KIDS_ACCOMMODATION_TICKET'
            WHEN (S.STANDARD_CATEGORY_LV_2_CD = 'LOCAL_ACCOMMODATION' AND S.STANDARD_CATEGORY_LV_3_CD = 'LOCAL_ACCOMMODATION_V2') THEN 'LOCAL_LODGING'
            WHEN (S.mrt_type IN ('lodging') AND (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL)) OR (s.STANDARD_CATEGORY_LV_3_CD = 'LODGING_V2' AND (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL))
                 OR (
                    S.PROVIDER_CD = 'STAYNET'
                    AND (
                        (S.STANDARD_CATEGORY_LV_2_CD = 'MINBAK' AND S.STANDARD_CATEGORY_LV_3_CD = 'KOREAN_MINBAK')
                    )
                ) THEN 'KOREAN_LODGING'
            WHEN (S.mrt_type IN ('lodging') AND (S.COUNTRY_NM = 'Korea, Republic of')) OR (s.STANDARD_CATEGORY_LV_3_CD = 'LODGE_V2' AND (S.COUNTRY_NM = 'Korea, Republic of'))
                 OR (S.STANDARD_CATEGORY_LV_2_CD = 'MINBAK' AND S.STANDARD_CATEGORY_LV_3_CD = 'DOMESTIC_MINBAK') THEN 'JEJU_LODGING'
            WHEN dd.ACCOUNT_TYPE = '숙박권' OR s.STANDARD_CATEGORY_LV_2_CD = 'ACCOMMODATION_TICKET' OR dd.ACCOUNT_TYPE = '날짜지정' OR S.HOTEL_AFFILIATE_NM = 'mrt' OR S.PARTNER_ID IN ('21293') OR S.GID IN ('2555714', '1098860') THEN 'DIRECT_SALES_ACCOMMODATION'
           --WHEN p.PARTNER_ID IN ('AG','BC','EX','HC','AB') THEN 'HOTEL_META'
            WHEN (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_ACCOMMODATION'
            WHEN (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL) THEN 'OUTBOUND_ACCOMMODATION'
            ELSE NULL END AS BIZ_TYPE_V2,
       CASE WHEN sp.RESELL_MARKET IS TRUE THEN 'RESELL_ACCOMMODATION'
            WHEN S.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'B2B_ACCOMMODATION_DOM'
            WHEN S.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 'B2B_ACCOMMODATION_OUT'
            --WHEN S.PARTNER_ID IN ('114540', '19355') THEN 'PKG_TOURTEL'
            WHEN (S.STANDARD_CATEGORY_LV_2_CD = 'LOCAL_ACCOMMODATION' AND S.STANDARD_CATEGORY_LV_3_CD = 'LOCAL_ACCOMMODATION_V2') THEN 'LOCAL_LODGING'
            WHEN (S.mrt_type IN ('lodging') AND (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL)) OR (s.STANDARD_CATEGORY_LV_3_CD = 'LODGING_V2' AND (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL))
                 OR (
                    S.PROVIDER_CD = 'STAYNET'
                    AND (
                        (S.STANDARD_CATEGORY_LV_2_CD = 'MINBAK' AND S.STANDARD_CATEGORY_LV_3_CD = 'KOREAN_MINBAK')
                    )
                ) THEN 'KOREAN_LODGING'
            WHEN (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL) AND S.PROVIDER_CD = 'STAYNET' THEN 'OUTBOUND_ACCOMMODATION_STAYNET'
            WHEN dd.ACCOUNT_TYPE = '숙박권' OR s.STANDARD_CATEGORY_LV_2_CD = 'ACCOMMODATION_TICKET' OR dd.ACCOUNT_TYPE = '날짜지정' OR S.HOTEL_AFFILIATE_NM = 'mrt' OR S.PARTNER_ID IN ('21293') OR S.GID IN ('2555714', '1098860') OR S.PROVIDER_CD = 'STAYNET' THEN 'DIRECT_SALES_ACCOMMODATION'
            WHEN (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_ACCOMMODATION'
            WHEN (S.COUNTRY_NM != 'Korea, Republic of' OR S.COUNTRY_NM IS NULL) THEN 'OUTBOUND_ACCOMMODATION'
            ELSE NULL END AS BIZ_TYPE_V3,
       FC.FPNA_CATEGORY,
       S.TEAM_DIVISION,
       S.FLIGHT_RESVE_ID,
       S.FLIGHT_CREATE_KST_DT,
       S.FLIGHT_TRAVEL_START_KST_DATE,
       S.HOTEL_CAMPAIGN_ID,
       S.CREATE_KST_DT,
       S.CONFIRM_KST_DT,
       S.CONFIRM_KST_DATE,
       S.CREATE_KST_DATE,
       S.HOTEL_AFFILIATE_NM,
       S.PROVIDER_CD,
       S.PARTNER_ID,
       PO.NAME                                                                                          AS PARTNER_NM,
       CASE WHEN om.gid IS NOT NULL THEN om.osp_id
            WHEN hnt.osp_id IS NOT NULL THEN hnt.osp_id
            WHEN pom.gid IS NOT NULL THEN pom.osp_id
            WHEN om2.osp_id IS NOT NULL THEN om2.osp_id
            WHEN om3.osp_id IS NOT NULL THEN om3.osp_id
            ELSE NULL END                                                                               AS ACCOUNT_ID,
       CASE WHEN om.gid IS NOT NULL THEN om.osp_name
            WHEN hnt.osp_name IS NOT NULL THEN hnt.osp_name
            WHEN pom.osp_name IS NOT NULL THEN pom.osp_name
            WHEN om2.osp_name IS NOT NULL THEN om2.osp_name
            WHEN om3.osp_name IS NOT NULL THEN om3.osp_name
            ELSE NULL END                                                                               AS ACCOUNT_NAME,
       S.GID,
       S.GPID,
       S.PRODUCT_ID,
       CASE WHEN S.product_title IS NULL THEN CONCAT(S.HOTEL_AFFILIATE_NM, '_hotel')
            ELSE S.product_title END                                                                    AS PRODUCT_TITLE,
       CASE WHEN S.COUNTRY_NM = 'Korea, Republic of' THEN 'Domestic'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL THEN 'Outbound'
            ELSE 'Outbound' END                                                                         AS REGION_TYPE,
       S.REGION_NM,
       CASE WHEN S.COUNTRY_NM IS NULL THEN 'Others'
            ELSE S.COUNTRY_NM END                                                                       AS COUNTRY_NM,
       CASE WHEN S.CITY_NM IS NULL THEN 'Others'
            ELSE S.city_nm END                                                                          AS CITY_NM,
       CASE WHEN S.CITY_NM = 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'Y'
            WHEN S.CITY_NM != 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM IS NULL THEN 'N' ELSE 'N' END                                             AS JEJU_FLAG,
       CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
            WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
            WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_ID
            WHEN ci.title IS NOT NULL THEN ci.id ELSE NULL END                                          AS COUPON_ID,
       PCR.COUPON_ID                                                                                    AS PRODUCT_COUPON_ID,
       OCR.COUPON_ID                                                                                    AS ORDER_COUPON_ID,
       CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_TITLE
            WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_NM
            WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_TITLE
            WHEN ci.title IS NOT NULL THEN ci.title
            WHEN S.coupon_price > 0 AND CP.COUPON_NM IS NULL AND ci.title IS NULL THEN 'UNKNOWN'
            WHEN ci.title IS NULL AND CP.COUPON_NM IS NULL THEN NULL
            ELSE 'ERROR' END                                                                            AS COUPON_TITLE,
       CASE WHEN S.coupon_price > 0 AND CP.COUPON_ID IS NULL AND ci.id IS NULL THEN 'UNKNOWN'
            ELSE CP.COUPON_PUBLISH_TEAM END                                                             AS COUPON_PUBLISH_TEAM_NM,
       CASE WHEN S.coupon_price > 0 AND CP.COUPON_ID IS NULL AND ci.id IS NULL THEN 'UNKNOWN'
            ELSE CP.COUPON_PUBLISH_PURPOSE END                                                          AS COUPON_PUBLISH_PURPOSE_NM,
       CASE WHEN S.CROSS_SELL_FLAG IS NULL THEN 'N'
            ELSE S.CROSS_SELL_FLAG END                                                                  AS CROSS_SELL_FLAG,
       SAFE_DIVIDE(CASE
            WHEN s.PARTNER_SETTLE_TYPE = 'internal' THEN s.commission_rate
            WHEN s.GID IN (SELECT DISTINCT gid FROM {{ ref('FPNA_B2B_GID_INFO') }} WHERE MRT_TYPE IN ('hotel','ticket_lodging','pension','lodging') AND REMARK_1 IN ('재진행','신규')) AND b2b_2nd.resve_id IS NOT NULL AND b2b_2nd.mrt_take_amount IS NULL THEN 0.12
            WHEN b2b_2nd.resve_id IS NOT NULL THEN SAFE_DIVIDE(b2b_2nd.mrt_take_amount,s.sales_krw_price)
            WHEN bd.resve_id IS NOT NULL THEN SAFE_DIVIDE(bd.mrt_sales_wo_vat,s.sales_krw_price)
            WHEN s.BASIS_DATE < '2024-10-21' AND s.gid IN (SELECT DISTINCT CAST(GID AS STRING) FROM edw.DW_MRT_STAY_PROPERTY_B2B_INFO) THEN 0.18
            WHEN s.BASIS_DATE < '2024-10-21' AND s.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 0.12
            WHEN s.PARTNER_ID = '19260' THEN s.COMMISSION_RATE
            /* 호텔 제휴 수수료율 하드코딩 */
            WHEN fhmi.HOTEL_AFFILIATE_NM IS NOT NULL THEN fhmi.COMMISSION_RATE * 1.1
            /* 직계약 호텔 수수료 맵핑 */
            WHEN S.HOTEL_AFFILIATE_NM = 'mrt' AND S.partner_settle_type = 'external' AND mrt.commission_rate IS NOT NULL THEN mrt.commission_rate
            /* ONDA 내부정산 이전 수수료 8% 하드코딩 */
            WHEN S.partner_id = '16928' THEN 0.08
            /* 펜션 내부정산 이외 수수료 8% 하드코딩 */
            WHEN S.mrt_type = 'pension' AND S.partner_settle_type = 'external' AND (S.commission_rate = 1 OR S.commission_rate IS NULL) THEN 0.08
            /* 민박 이상치 OR결측치 관련 데이터 대체 */
            WHEN S.mrt_type = 'lodging' AND S.partner_settle_type IS NULL AND S.commission_rate = 0 THEN 0.1
            WHEN S.mrt_type = 'lodging' AND S.partner_id = '13145' THEN 0.1
            /* 호캉스 수수료율 맵핑 */
            WHEN hnt.gid IS NOT NULL AND hnt.MRT_TAKE_RATE IS NOT NULL THEN hnt.MRT_TAKE_RATE
            /* 기타 내부정산 수수료 맵핑 */
            WHEN S.COMMISSION_RATE = 1 THEN NULL
            ELSE S.COMMISSION_RATE END,1.1)                                                                   AS COMMISSION_RATE,
       S.COMMISSION_PRICE AS SALES_COMMISSION_PRICE,
       S.PARTNER_SETTLE_TYPE,
       S.PARTNER_SALES_TYPE,
       S.PARTNERSHIP_CD,
       S.MARKETING_PARTNERSHIP_CD,
       pg.pg AS PG_NM,
       S.SALES_KRW_PRICE,
       --CASE WHEN S.RECENT_STATUS IN ('confirm','finish') then
        (IFNULL(SAFE_DIVIDE(
            (CASE    /* 호텔 제휴 수수료 하드코딩 */
            WHEN s.PARTNER_SETTLE_TYPE = 'internal' THEN s.commission_price
            WHEN s.GID IN (SELECT DISTINCT gid FROM {{ ref('FPNA_B2B_GID_INFO') }} WHERE MRT_TYPE IN ('hotel','ticket_lodging','pension','lodging') AND REMARK_1 IN ('재진행','신규')) AND b2b_2nd.resve_id IS NOT NULL AND b2b_2nd.mrt_take_amount IS NULL THEN s.SALES_KRW_PRICE * 0.12
            WHEN b2b_2nd.resve_id IS NOT NULL AND b2b_2nd.mrt_take_amount IS NOT NULL THEN b2b_2nd.mrt_take_amount
            WHEN bd.resve_id IS NOT NULL AND bd.mrt_sales_wo_vat IS NOT NULL THEN bd.mrt_sales_wo_vat
            WHEN s.BASIS_DATE < '2024-10-21' AND s.gid IN (SELECT DISTINCT CAST(GID AS STRING) FROM edw.DW_MRT_STAY_PROPERTY_B2B_INFO) THEN s.SALES_KRW_PRICE * 0.18
            WHEN s.BASIS_DATE < '2024-10-21' AND s.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN s.SALES_KRW_PRICE * 0.12
            WHEN s.PARTNER_ID = '19260' THEN s.SALES_KRW_PRICE * s.COMMISSION_RATE
            WHEN fhmi.HOTEL_AFFILIATE_NM IS NOT NULL THEN S.SALES_KRW_PRICE * fhmi.COMMISSION_RATE * 1.1
            /* 직계약 호텔 수수료 맵핑 */
            WHEN S.HOTEL_AFFILIATE_NM = 'mrt' AND S.PARTNER_SETTLE_TYPE = 'external' AND mrt.commission_rate IS NOT NULL THEN mrt.commission_rate * S.sales_krw_price
            /* 내부정산 이전 ONDA 수수료 하드맵핑 -> 8% */
            WHEN S.PARTNER_ID = '16928' THEN 0.08 * S.SALES_KRW_PRICE
            /* 펜션 내부정산 이외 수수료 8% 하드코딩 */
            WHEN S.mrt_type = 'pension' AND S.partner_settle_type = 'external' AND (S.commission_rate = 1 OR S.commission_rate IS NULL) THEN S.sales_krw_price * 0.08
            /* 민박 이상치 OR결측치 관련 데이터 대체 */
            WHEN S.mrt_type = 'lodging' AND S.partner_settle_type IS NULL AND S.commission_rate = 0 THEN S.sales_krw_price * 0.1
            WHEN S.mrt_type = 'lodging' AND S.partner_id = '13145' THEN S.sales_krw_price * 0.1
            /* 호캉스 수수료율 맵핑 */
            WHEN hnt.gid IS NOT NULL AND hnt.MRT_TAKE_RATE IS NOT NULL THEN hnt.MRT_TAKE_RATE * S.sales_krw_price
            /* 맵핑안된 건 있을 경우 mrt_sales => NULL 값 처리 */
            WHEN S.commission_rate = 1 THEN NULL
            /* 내부정산 수수료 맵핑 */
            ELSE S.commission_rate * S.sales_krw_price END), 1.1),0))                                AS MRT_SALES_PRICE,
       CASE    /* 호텔 제휴 수수료 하드코딩 */
            WHEN s.PARTNER_SETTLE_TYPE = 'internal' THEN 1
            WHEN s.GID IN (SELECT DISTINCT gid FROM {{ ref('FPNA_B2B_GID_INFO') }} WHERE MRT_TYPE IN ('hotel','ticket_lodging','pension','lodging') AND REMARK_1 IN ('재진행','신규')) AND b2b_2nd.resve_id IS NOT NULL AND b2b_2nd.mrt_take_amount IS NULL THEN 2
            WHEN b2b_2nd.resve_id IS NOT NULL AND b2b_2nd.mrt_take_amount IS NOT NULL THEN 3
            WHEN bd.resve_id IS NOT NULL AND bd.mrt_sales_wo_vat IS NOT NULL THEN 4
            WHEN s.BASIS_DATE < '2024-10-21' AND s.gid IN (SELECT DISTINCT CAST(GID AS STRING) FROM edw.DW_MRT_STAY_PROPERTY_B2B_INFO) THEN 5
            WHEN s.BASIS_DATE < '2024-10-21' AND s.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 6
            WHEN s.PARTNER_ID = '19260' THEN 7
            WHEN fhmi.HOTEL_AFFILIATE_NM IS NOT NULL THEN 8
            /* 직계약 호텔 수수료 맵핑 */
            WHEN S.HOTEL_AFFILIATE_NM = 'mrt' AND S.PARTNER_SETTLE_TYPE = 'external' AND mrt.commission_rate IS NOT NULL THEN 9
            /* 내부정산 이전 ONDA 수수료 하드맵핑 -> 8% */
            WHEN S.PARTNER_ID = '16928' THEN 10
            /* 펜션 내부정산 이외 수수료 8% 하드코딩 */
            WHEN S.mrt_type = 'pension' AND S.partner_settle_type = 'external' AND (S.commission_rate = 1 OR S.commission_rate IS NULL) THEN 11
            /* 민박 이상치 OR결측치 관련 데이터 대체 */
            WHEN S.mrt_type = 'lodging' AND S.partner_settle_type IS NULL AND S.commission_rate = 0 THEN 12
            WHEN S.mrt_type = 'lodging' AND S.partner_id = '13145' THEN 13
            /* 호캉스 수수료율 맵핑 */
            WHEN hnt.gid IS NOT NULL AND hnt.MRT_TAKE_RATE IS NOT NULL THEN 14
            /* 맵핑안된 건 있을 경우 mrt_sales => NULL 값 처리 */
            WHEN S.commission_rate = 1 THEN 15
            /* 내부정산 수수료 맵핑 */
            ELSE 99 END AS MRT_SALES_PRICE_TYPE,
       CASE
           WHEN S.STANDARD_CATEGORY_LV_3_CD = 'EXTERNAL_ACCOMMODATION' THEN IFNULL(
                CAST(
                    SAFE_DIVIDE(
                        SAFE_DIVIDE(
                            S.PRODUCT_COUPON_PRICE,
                            NULLIF(S.PRODUCT_COUPON_PRICE + S.ORDER_COUPON_PRICE, 0)
                        ) * (S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE),
                        1.1
                    ) AS INT64
                ),
                IFNULL(CAST(SAFE_DIVIDE(S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE, 1.1) AS INT64), 0)
           )
           WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN 0
           ELSE CASE
                    WHEN ci.ID IS NULL THEN 0
                    WHEN GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0) = 0 THEN 0
                    WHEN UCR.RESVE_ID IS NOT NULL OR CP.COUPON_NM IS NOT NULL OR COUPON_30.COUPON_ID IS NOT NULL
                        THEN CASE
                                WHEN fci_2.COUPON_ID IS NOT NULL OR cei_2.COUPON_ID IS NOT NULL
                                    THEN {{ fpna_coupon_burden_price(
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                                        'fci_2',
                                        'cei_2',
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                                    ) }}
                                ELSE {{ fpna_coupon_burden_price(
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                                        'fci_3',
                                        'cei_legacy',
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                                    ) }}
                             END
                    ELSE {{ fpna_coupon_burden_price(
                            'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_2',
                            'cei_2',
                            'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                END
                + IFNULL(P30C.COUPON_PRICE, 0)
                + IFNULL(
                    CAST(
                        SAFE_DIVIDE(
                            S.PRODUCT_COUPON_PRICE,
                            NULLIF(S.PRODUCT_COUPON_PRICE + S.ORDER_COUPON_PRICE, 0)
                        ) * IF(
                            ci.ID IS NULL
                            AND P30C.RESVE_ID IS NULL
                            AND O30C.RESVE_ID IS NULL
                            AND S.COUPON_PRICE > 0,
                            {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                            0
                        ) AS INT64
                    ),
                    IF(
                        ci.ID IS NULL
                        AND P30C.RESVE_ID IS NULL
                        AND O30C.RESVE_ID IS NULL
                        AND S.COUPON_PRICE > 0,
                        {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                        0
                    )
                )
           END                                                                                  AS PRODUCT_COUPON_PRICE,
       CASE
           WHEN S.STANDARD_CATEGORY_LV_3_CD = 'EXTERNAL_ACCOMMODATION' THEN
                IFNULL(CAST(SAFE_DIVIDE(S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE, 1.1) AS INT64), 0)
                - IFNULL(
                    CAST(
                        SAFE_DIVIDE(
                            SAFE_DIVIDE(
                                S.PRODUCT_COUPON_PRICE,
                                NULLIF(S.PRODUCT_COUPON_PRICE + S.ORDER_COUPON_PRICE, 0)
                            ) * (S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE),
                            1.1
                        ) AS INT64
                    ),
                    IFNULL(CAST(SAFE_DIVIDE(S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE, 1.1) AS INT64), 0)
                )
           WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN 0
           ELSE IFNULL(O30C.COUPON_PRICE, 0)
                + IF(
                    ci.ID IS NULL
                    AND P30C.RESVE_ID IS NULL
                    AND O30C.RESVE_ID IS NULL
                    AND S.COUPON_PRICE > 0,
                    {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                    0
                )
                - IFNULL(
                    CAST(
                        SAFE_DIVIDE(
                            S.PRODUCT_COUPON_PRICE,
                            NULLIF(S.PRODUCT_COUPON_PRICE + S.ORDER_COUPON_PRICE, 0)
                        ) * IF(
                            ci.ID IS NULL
                            AND P30C.RESVE_ID IS NULL
                            AND O30C.RESVE_ID IS NULL
                            AND S.COUPON_PRICE > 0,
                            {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                            0
                        ) AS INT64
                    ),
                    IF(
                        ci.ID IS NULL
                        AND P30C.RESVE_ID IS NULL
                        AND O30C.RESVE_ID IS NULL
                        AND S.COUPON_PRICE > 0,
                        {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                        0
                    )
                )
           END                                                                                  AS ORDER_COUPON_PRICE,
       CASE
           WHEN S.STANDARD_CATEGORY_LV_3_CD = 'EXTERNAL_ACCOMMODATION' THEN IFNULL(CAST(SAFE_DIVIDE(S.SALES_KRW_PRICE * fhmi.DISCOUNT_RATE, 1.1) AS INT64), 0)
           WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN 0
           ELSE CASE
                    WHEN ci.ID IS NULL THEN 0
                    WHEN GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0) = 0 THEN 0
                    WHEN UCR.RESVE_ID IS NOT NULL OR CP.COUPON_NM IS NOT NULL OR COUPON_30.COUPON_ID IS NOT NULL
                        THEN CASE
                                WHEN fci_2.COUPON_ID IS NOT NULL OR cei_2.COUPON_ID IS NOT NULL
                                    THEN {{ fpna_coupon_burden_price(
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                                        'fci_2',
                                        'cei_2',
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                                    ) }}
                                ELSE {{ fpna_coupon_burden_price(
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                                        'fci_3',
                                        'cei_legacy',
                                        'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                                    ) }}
                             END
                    ELSE {{ fpna_coupon_burden_price(
                            'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)',
                            'fci_2',
                            'cei_2',
                            'GREATEST(S.PRODUCT_COUPON_PRICE - IFNULL(P30C.COUPON_AMOUNT, 0), 0)'
                        ) }}
                END
                + IFNULL(P30C.COUPON_PRICE, 0)
                + IFNULL(O30C.COUPON_PRICE, 0)
                + IF(
                    ci.ID IS NULL
                    AND P30C.RESVE_ID IS NULL
                    AND O30C.RESVE_ID IS NULL
                    AND S.COUPON_PRICE > 0,
                    {{ fpna_coupon_burden_price('S.COUPON_PRICE', 'fci_3', 'cei_legacy') }},
                    0
                )
           END                                                                                  AS COUPON_PRICE,
       IFNULL(CASE WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN NULL
                   WHEN S.point_price IS NULL THEN 0
                   --when S.recent_status IN ('confirm', 'finish') THEN S.point_price
                   ELSE S.point_price
                   END,0)                                                                                      AS POINT_PRICE,
       IFNULL(CASE WHEN pd.POINT_SUM IS NOT NULL THEN S.point_price ELSE 0 END, 0)                              AS EXCLUDED_POINT_PRICE,
       /* 제로마진 할인 등 맵핑 */
       IFNULL(SAFE_DIVIDE(CASE WHEN s.BASIS_DATE >= '2024-10-21' AND s.STANDARD_CATEGORY_LV_2_CD = 'B2B_ACCOMMODATION' THEN 0
                               ELSE S.DISCOUNT_PRICE END,1.1),0)                                                             AS DISCOUNT_PRICE,
       /* 채널수수료 (ex. PG수수료) 맵핑 */
       IFNULL(ROUND(IFNULL(CASE WHEN S.HOTEL_AFFILIATE_NM IN ('booking', 'hotels', 'agoda', 'expedia', 'airbnb') THEN 0
            --when S.recent_status IN ('confirm', 'finish') THEN S.sales_krw_price * IFNULL(pg.pg_com_rate,0.02)
            --else 0
            ELSE S.sales_krw_price * IFNULL(pg.pg_com_rate,0.02)
            END,0), 2),0)                                                                                  AS CHANNEL_FEE_PRICE,
       --IFNULL((CASE WHEN s.RECENT_STATUS IN ('confirm', 'finish') THEN ampc.partnership_commission ELSE 0 END),0) AS AGENCY_FEE,
       IFNULL(ampc.partnership_commission ,0) AS AGENCY_FEE,
       --IFNULL((CASE WHEN s.RECENT_STATUS IN ('confirm', 'finish') THEN ampc.marketing_partnership_commission ELSE 0 END),0) AS MARKETING_PARTNER_FEE,
       IFNULL(ampc.marketing_partnership_commission,0) AS MARKETING_PARTNER_FEE,
       --(CASE WHEN s.RECENT_STATUS IN ('confirm', 'finish') AND pd.IS_B2B_POINT_RSV = TRUE THEN s.POINT_PRICE * 0.02 ELSE 0 END) AS AFFILIATE_POINT_FEE,
       IFNULL(CASE WHEN pd.IS_B2B_POINT_RSV = TRUE THEN s.POINT_PRICE * 0.02 ELSE 0 END,0) AS AFFILIATE_POINT_FEE,
       CAST(NULL AS FLOAT64) AS NET_PRICE,
       DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                                      AS DW_LOAD_DT
FROM {{ ref("MART_SALE_D") }} S
LEFT JOIN STAY_PROPERTY_LATEST sp ON S.GID = sp.GID
LEFT JOIN {{ ref('MART_USER_D') }} U ON S.USER_ID = U.USER_ID /* 마리터 구분값 추가를 위한 맵핑 */
LEFT JOIN {{ source('partners', 'partner') }} PO ON S.PARTNER_ID = CAST(PO.ID AS STRING)
LEFT JOIN {{ source('mrt_20', 'promotion_coupon_codes') }} pcc ON CAST(pcc.reservation_id AS STRING) = S.RESVE_ID /* 2.0 쿠폰 맵핑 */
LEFT JOIN {{ source('mrt_20', 'promotion_coupons') }} ci ON ci.id = pcc.coupon_id /* 2.0 쿠폰 맵핑 */
LEFT JOIN CP_PRODUCT CP ON CP.RESVE_ID = S.RESVE_ID
LEFT JOIN USED_COUPON_RESVE UCR ON UCR.RESVE_ID = S.RESVE_ID
LEFT JOIN PRODUCT_COUPON_REP PCR ON PCR.RESVE_ID = S.RESVE_ID
LEFT JOIN ORDER_COUPON_REP OCR ON OCR.RESVE_ID = S.RESVE_ID
LEFT JOIN {{ source('orders', 'reservations') }} R ON S.RESVE_ID = R.reservation_no AND R.DELETED_AT IS NULL
LEFT JOIN (SELECT DISTINCT h.RESERVATION_NO AS RESVE_ID, MAX(h.template_id) AS COUPON_ID, MAX(t.name) AS coupon_title FROM {{ source('mrt_20', 'coupon_reservation_history') }} h LEFT JOIN {{ source('coupon', 'coupon_templates') }} t ON h.template_id = t.id WHERE h.DELETED_AT IS NULL AND t.DELETED_AT IS NULL GROUP BY 1) AS COUPON_30 ON COUPON_30.RESVE_ID = S.RESVE_ID
LEFT JOIN COUPON_EXTRA_INFO cei_2 ON cei_2.coupon_id = ci.id
LEFT JOIN COUPON_EXTRA_INFO cei_legacy ON cei_legacy.coupon_id = (
    CASE
        WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
        WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
        ELSE COUPON_30.COUPON_ID
    END
)
LEFT JOIN MRT_GID mrt ON mrt.gid = S.gid /* gid 내부정산 수수료 맵핑 */
LEFT JOIN {{ ref('fpna_external_commission_stay_all') }} stay ON stay.mrt_type = S.mrt_type AND CAST(stay.gid AS STRING) = S.gid /* 마리트 직계약 호텔 수수료율 맵핑 (별도정산) */
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_2 ON fci_2.coupon_id = ci.id AND fci_2.type = '2.0 product' /* 2.0 쿠폰 마리트 실부담가 맵핑 */
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_3
    ON fci_3.coupon_id = (
        CASE
            WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
            WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
            ELSE COUPON_30.COUPON_ID
        END
    )
   AND fci_3.type = '3.0 product' /* 3.0 쿠폰 마리트 실부담가 맵핑 */
LEFT JOIN PRODUCT_30_COUPON_COST P30C ON P30C.RESVE_ID = S.RESVE_ID
LEFT JOIN ORDER_30_COUPON_COST O30C ON O30C.RESVE_ID = S.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_RSV_CANCEL') }} rc ON S.RESVE_ID = rc.RESVE_ID /* 취소일 맵핑 */
LEFT JOIN {{ ref('FPNA_HOTEL_META_INFO') }} fhmi ON fhmi.MRT_TYPE = S.MRT_TYPE AND S.BASIS_DATE >= fhmi.START_DATE AND S.BASIS_DATE <= fhmi.END_DATE AND fhmi.HOTEL_AFFILIATE_NM = S.HOTEL_AFFILIATE_NM /* 호텔메타 손익 맵핑*/
LEFT JOIN OPEN_TICKET_RESVE_DATA otrd ON otrd.RESVE_ID = s.RESVE_ID
LEFT JOIN HOCANCE_NORMAL_TICKET hnt ON hnt.gid = S.gid
LEFT JOIN OSP_MAPPING om ON CAST(om.gid AS STRING) = S.gid /* OSP_ID 맵핑 - 날짜지정 호캉스, ONDA 연동 호텔 및 펜션 */
LEFT JOIN PRODUCT_TITLE_OSP_MAPPING pom ON pom.gid = s.gid
LEFT JOIN (SELECT DISTINCT osp_id, osp_name FROM OSP_MAPPING) om2 ON pom.osp_id = CAST(om2.osp_id AS STRING)
LEFT JOIN (SELECT DISTINCT osp_id, osp_name FROM OSP_MAPPING) om3 ON hnt.osp_id = CAST(om3.osp_id AS STRING)
LEFT JOIN {{ ref('INT_FPNA_POINT_DETAIL') }} pd ON pd.RESVE_ID = S.RESVE_ID
LEFT JOIN (SELECT DISTINCT partner_id, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZP ON S.partner_id = BZP.PARTNER_ID
LEFT JOIN (SELECT DISTINCT GID, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZG ON S.gid = BZG.gid
LEFT JOIN (SELECT DISTINCT partner_id, MAX(accounting_project_code) AS accounting_project_code FROM {{ source('settles', 'partner_settlement_configs') }} GROUP BY 1) psc ON psc.partner_id = s.partner_id
LEFT JOIN {{ ref('FPNA_CATEGORY_INFO') }} FC ON S.STANDARD_CATEGORY_LV_3_CD = FC.LV_3_CD
LEFT JOIN {{ ref('INT_FPNA_PG_FEE') }} pg ON s.RESVE_ID = pg.RESVE_ID
LEFT JOIN DST_DATA dd ON dd.GID = s.GID AND s.BASIS_DATE >= dd.OPEN_DATE AND s.BASIS_DATE <= dd.CLOSE_DATE
LEFT JOIN B2B_NET_PRICE_DATA bd ON bd.resve_id = s.resve_id
LEFT JOIN SAMSUNG_B2B_2ND_DATA b2b_2nd ON b2b_2nd.resve_id = s.resve_id
LEFT JOIN {{ ref('INT_FPNA_AGENCY_COMMISSION') }} ampc ON ampc.RESVE_ID = s.RESVE_ID
LEFT JOIN MYLINK_PARTNERSHIP_CODE PC ON S.MARKETING_PARTNERSHIP_CD = PC.MARKETING_PARTNERSHIP_CD
LEFT JOIN PACKAGE_RESVE PR ON PR.RESVE_ID = S.RESVE_ID
WHERE S.KIND = 1
  AND S.STANDARD_CATEGORY_LV_1_CD IN ('ACCOMMODATION')
  AND S.RESVE_ID NOT LIKE '%PKG%'
  AND PR.RESVE_ID IS NULL
  AND S.DOMAIN_NM <> 'AIR ANCILLARY'
