{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_TNA_PROFIT_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['SALE_FORM_CD', 'BIZ_TYPE', 'RECENT_STATUS']
    )
}}



WITH MART_SERVICE_NET_PRICE AS (
     SELECT  S.RESVE_ID
          ,  S.PARTNER_ID
          ,  SUM(P.price_amount * COALESCE(IFNULL(CASE WHEN ce.to_currency IN ('JPY', 'VND') THEN SAFE_DIVIDE(ce.standard_exchange_rate, 100) ELSE ce.standard_exchange_rate END
                                , mc.krw_rate), 1)) AS NET_PRICE
     FROM {{ ref('MART_SALE_D') }} S
     LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} O ON S.RESVE_ID = CAST(O.reservation_id AS STRING)
     LEFT JOIN {{ source('mrt_20', 'reservation_order_net_prices') }} P ON O.id = P.reservation_order_id
     LEFT JOIN {{ ref('mart_currency') }} mc ON DATE(mc.day) = S.BASIS_DATE AND mc.code = S.PAID_PRICE_CUR_TYPE
     LEFT JOIN {{ source('settles' , 'currency_exchanges') }} ce ON ce.standard_date = S.BASIS_DATE AND ce.to_currency = S.PAID_PRICE_CUR_TYPE AND ce.deleted_at IS NULL
     WHERE S.KIND = 1
       AND S.MRT_TYPE IN ('ticket', 'tour', 'lanstour', 'hotdeal', 'kids')
       AND P.id IS NOT NULL
       AND P.price_amount IS NOT NULL
       AND O.deleted_at IS NULL
       AND P.deleted_at IS NULL
     GROUP BY S.RESVE_ID, S.PARTNER_ID
),
MART_SERVICE_PARTNER_ID AS (
    SELECT DISTINCT P.PARTNER_ID
      FROM MART_SERVICE_NET_PRICE P
),
OPTION_MAPPING AS (
    WITH OPTION_PROFIT_IS_NOT_NULL_RESVE AS (
        SELECT DISTINCT CAST(O.RESERVATION_ID AS STRING) AS RESVE_ID
          FROM {{ source('mrt_20', 'reservation_orders') }} O
     LEFT JOIN (SELECT OPTION_ID, OPTION_NM, CAST(NET_PRICE_AMOUNT AS FLOAT64) AS NET_PRICE_AMOUNT, COMMISSION_RATE, START_DATE, END_DATE FROM {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} WHERE OPTION_ID IS NOT NULL) OP ON OP.OPTION_ID = CAST(O.OFFER_PRICE_ID AS STRING) AND DATE(O.CREATED_AT_KST) >= OP.START_DATE AND DATE(O.CREATED_AT_KST) <= OP.END_DATE
    WHERE OP.OPTION_ID IS NOT NULL AND O.DELETED_AT IS NULL

    UNION ALL

    SELECT DISTINCT R.RESERVATION_NO AS RESVE_ID,
    FROM {{ source('orders' , 'option_reservations') }} O
    LEFT JOIN {{ source('orders', 'reservations') }} R ON O.RESERVATION_ID = R.ID
    LEFT JOIN (SELECT OPTION_ID, OPTION_NM, CAST(NET_PRICE_AMOUNT AS FLOAT64) AS NET_PRICE_AMOUNT, COMMISSION_RATE, START_DATE, END_DATE FROM {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} WHERE OPTION_ID IS NOT NULL) OP ON OP.OPTION_ID = CAST(O.OPTION_ID AS STRING) AND DATE(O.created_at) >= OP.START_DATE AND DATE(O.created_at) <= OP.END_DATE
    WHERE OP.OPTION_ID IS NOT NULL
    AND O.DELETED_AT IS NULL
    AND R.DELETED_AT IS NULL
    ),
    SALES_DATA AS (
        SELECT S.RESVE_ID
            ,  S.BASIS_DATE
            ,  S.DOMAIN_NM
            ,  SUM(S.SALES_KRW_PRICE) AS GMV
        FROM {{ ref('MART_SALE_D') }} S
        LEFT JOIN (SELECT PARTNER_ID, PARTNER_NM, BIZ_TYPE_PARTNER FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }}) biz_type_partner ON CAST(biz_type_partner.PARTNER_ID AS STRING) = S.PARTNER_ID
        LEFT JOIN (SELECT PRODUCT_ID, PRODUCT_NM, BIZ_TYPE_PRODUCT FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }}) biz_type_product ON CAST(biz_type_product.PRODUCT_ID AS STRING) = S.PRODUCT_ID
        WHERE S.KIND = 1
        AND S.MRT_TYPE IN ('tour','ticket')
        AND ((biz_type_partner.biz_type_partner = 'Commerce' OR biz_type_product.biz_type_product = 'Commerce') OR S.RESVE_ID IN (SELECT DISTINCT RESVE_ID FROM OPTION_PROFIT_IS_NOT_NULL_RESVE))
        AND S.DOMAIN_NM IN ('2.0 PRODUCT', '3.0 PRODUCT')
        GROUP BY S.RESVE_ID, S.BASIS_DATE, S.DOMAIN_NM
    )
    SELECT SD.RESVE_ID
        ,  SUM(CASE WHEN OP.OPTION_ID IS NOT NULL AND OP.NET_PRICE_AMOUNT IS NOT NULL THEN OP.NET_PRICE_AMOUNT * O.quantity
                    WHEN SD.BASIS_DATE < '2022-01-01' AND O.OFFER_PRICE_ID IS NULL THEN SD.GMV * 0.03
                    ELSE IFNULL(ex_1.krw * O.quantity * np.net_price_1,0) + IFNULL(ex_2.krw * O.quantity * np.net_price_2,0) + IFNULL(ex_3.krw * O.quantity * np.net_price_3,0) + IFNULL(ex_4.krw * O.quantity * np.net_price_4,0) END) AS NET_PRICE
    FROM {{ source('mrt_20', 'reservation_orders') }} O
    LEFT JOIN SALES_DATA SD ON SD.RESVE_ID = CAST(O.RESERVATION_ID AS STRING) AND SD.DOMAIN_NM = '2.0 PRODUCT'
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_OPTION_NET_PRICE_INFO') }} np ON np.OPTION_ID = O.OFFER_PRICE_ID
    LEFT JOIN (SELECT OPTION_ID, OPTION_NM, CAST(NET_PRICE_AMOUNT AS FLOAT64) AS NET_PRICE_AMOUNT, COMMISSION_RATE, START_DATE, END_DATE FROM {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} WHERE OPTION_ID IS NOT NULL) OP ON OP.OPTION_ID = CAST(O.OFFER_PRICE_ID AS STRING) AND SD.BASIS_DATE >= OP.START_DATE AND SD.BASIS_DATE <= OP.END_DATE
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_1 ON ex_1.CURRENCY = np.CURRENCY_1 AND DATE(sd.basis_date) >= ex_1.START_DATE AND DATE(sd.basis_date) <= ex_1.END_DATE AND np.currency_1 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_2 ON ex_2.CURRENCY = np.CURRENCY_2 AND DATE(sd.basis_date) >= ex_2.START_DATE AND DATE(sd.basis_date) <= ex_2.END_DATE AND np.currency_2 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_3 ON ex_3.CURRENCY = np.CURRENCY_3 AND DATE(sd.basis_date) >= ex_3.START_DATE AND DATE(sd.basis_date) <= ex_3.END_DATE AND np.currency_3 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_4 ON ex_4.CURRENCY = np.CURRENCY_4 AND DATE(sd.basis_date) >= ex_4.START_DATE AND DATE(sd.basis_date) <= ex_4.END_DATE AND np.currency_4 IS NOT NULL
    WHERE O.DELETED_AT IS NULL AND SD.RESVE_ID IS NOT NULL
    GROUP BY SD.RESVE_ID

    UNION ALL

    SELECT SD.RESVE_ID
         , SUM(CASE WHEN OP.OPTION_ID IS NOT NULL AND OP.NET_PRICE_AMOUNT IS NOT NULL THEN OP.NET_PRICE_AMOUNT * O.quantity
        WHEN SD.BASIS_DATE < '2022-01-01' AND O.OPTION_ID IS NULL THEN SD.GMV * 0.03
        ELSE IFNULL(ex_1.krw * O.quantity * np.net_price_1,0) + IFNULL(ex_2.krw * O.quantity * np.net_price_2,0) + IFNULL(ex_3.krw * O.quantity * np.net_price_3,0) + IFNULL(ex_4.krw * O.quantity * np.net_price_4,0) END) AS NET_PRICE
    FROM {{ source('orders' , 'option_reservations') }} O
    LEFT JOIN {{ source('orders', 'reservations') }} R ON O.RESERVATION_ID = R.ID
    LEFT JOIN SALES_DATA SD ON SD.RESVE_ID = CAST(R.RESERVATION_NO AS STRING) AND SD.DOMAIN_NM = '3.0 PRODUCT'
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_OPTION_NET_PRICE_INFO') }} np ON CAST(np.OPTION_ID AS STRING) = O.option_id
    LEFT JOIN (SELECT OPTION_ID, OPTION_NM, CAST(NET_PRICE_AMOUNT AS FLOAT64) AS NET_PRICE_AMOUNT, COMMISSION_RATE, START_DATE, END_DATE FROM {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} WHERE OPTION_ID IS NOT NULL) OP ON OP.OPTION_ID = CAST(O.OPTION_ID AS STRING) AND SD.BASIS_DATE >= OP.START_DATE AND SD.BASIS_DATE <= OP.END_DATE
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_1 ON ex_1.CURRENCY = np.CURRENCY_1 AND DATE(sd.basis_date) >= ex_1.START_DATE AND DATE(sd.basis_date) <= ex_1.END_DATE AND np.currency_1 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_2 ON ex_2.CURRENCY = np.CURRENCY_2 AND DATE(sd.basis_date) >= ex_2.START_DATE AND DATE(sd.basis_date) <= ex_2.END_DATE AND np.currency_2 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_3 ON ex_3.CURRENCY = np.CURRENCY_3 AND DATE(sd.basis_date) >= ex_3.START_DATE AND DATE(sd.basis_date) <= ex_3.END_DATE AND np.currency_3 IS NOT NULL
    LEFT JOIN {{ ref('FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO') }} ex_4 ON ex_4.CURRENCY = np.CURRENCY_4 AND DATE(sd.basis_date) >= ex_4.START_DATE AND DATE(sd.basis_date) <= ex_4.END_DATE AND np.currency_4 IS NOT NULL
    WHERE O.DELETED_AT IS NULL
      AND SD.RESVE_ID IS NOT NULL
    GROUP BY SD.RESVE_ID
),
COMMERCE_NEW_STOCK_UNIT_PRICE AS (
    WITH AVG_STOCK_UNIT_PRICE AS (
        WITH TARGET_DATA AS (
            SELECT DISTINCT S.GID
            FROM {{ ref('MART_SALE_D') }} S
            LEFT JOIN {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} biz_type_partner ON CAST(biz_type_partner.PARTNER_ID AS STRING) = S.PARTNER_ID
            LEFT JOIN {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} biz_type_product ON CAST(biz_type_product.PRODUCT_ID AS STRING) = S.PRODUCT_ID
            WHERE S.KIND = 1
            AND S.MRT_TYPE IN ('tour','ticket')
            AND (biz_type_partner.biz_type_partner = 'Commerce' OR biz_type_product.biz_type_product = 'Commerce')
            AND S.DOMAIN_NM IN ('2.0 PRODUCT', '3.0 PRODUCT')
        )
        SELECT S.BASIS_DATE,
               S.OPTION_ID,
               MAX(S.AVG_STOCK_UNIT_PRICE) AS AVG_STOCK_UNIT_PRICE
        FROM {{ ref('MART_STOCK_STATUS_D') }} S
        WHERE S.GID IN (SELECT DISTINCT gid FROM TARGET_DATA)
        GROUP BY S.BASIS_DATE, S.OPTION_ID
    )
    SELECT s.RESVE_ID,
           SUM(COALESCE(o2.quantity,o3.quantity) * IFNULL(COALESCE(np2.AVG_STOCK_UNIT_PRICE, np3.AVG_STOCK_UNIT_PRICE),
           COALESCE(np22.net_price_amount, np33.net_price_amount))) AS TOTAL_NET_PRICE
           FROM {{ ref('MART_SALE_D') }} s
           LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} o2 ON s.RESVE_ID = CAST(O2.RESERVATION_ID AS STRING) AND s.DOMAIN_NM = '2.0 PRODUCT' AND o2.deleted_at IS NULL
           LEFT JOIN {{ source('orders', 'reservations') }} R ON s.RESVE_ID = R.reservation_no AND r.deleted_at IS NULL
           LEFT JOIN {{ source('orders' , 'option_reservations') }} o3 ON o3.RESERVATION_ID = R.ID AND o3.deleted_at IS NULL
           LEFT JOIN AVG_STOCK_UNIT_PRICE np2 ON np2.OPTION_ID = CAST(o2.offer_price_id AS STRING) AND np2.BASIS_DATE = s.BASIS_DATE AND s.DOMAIN_NM = '2.0 PRODUCT'
           LEFT JOIN AVG_STOCK_UNIT_PRICE np3 ON np3.OPTION_ID = o3.OPTION_ID AND np3.BASIS_DATE = s.BASIS_DATE AND s.DOMAIN_NM = '3.0 PRODUCT'
           LEFT JOIN {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} biz_type_partner ON CAST(biz_type_partner.PARTNER_ID AS STRING) = S.PARTNER_ID
           LEFT JOIN {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} biz_type_product ON CAST(biz_type_product.PRODUCT_ID AS STRING) = S.PRODUCT_ID
           LEFT JOIN {{ ref('FPNA_TNA_OPTION_NET_PRICE') }} np22 ON np22.OPTION_ID = CAST(o2.offer_price_id AS STRING) AND np22.start_date <= s.BASIS_DATE AND np22.end_date >= s.BASIS_DATE AND s.DOMAIN_NM = '2.0 PRODUCT'
           LEFT JOIN {{ ref('FPNA_TNA_OPTION_NET_PRICE') }} np33 ON np33.OPTION_ID = o3.OPTION_ID AND np22.start_date <= s.BASIS_DATE AND np22.end_date >= s.BASIS_DATE AND s.DOMAIN_NM = '3.0 PRODUCT'
    WHERE s.kind = 1
      AND s.BASIS_DATE >= '2024-01-01' AND s.BASIS_DATE != CURRENT_DATE()
      AND S.MRT_TYPE IN ('tour','ticket')
      AND S.DOMAIN_NM IN ('2.0 PRODUCT', '3.0 PRODUCT')
      AND (biz_type_partner.biz_type_partner = 'Commerce' OR biz_type_product.biz_type_product = 'Commerce')
    GROUP BY s.RESVE_ID
),
CONNECTED_NET_PRICE AS (
    SELECT s.RESVE_ID
         , SUM(np.price_amount * COALESCE(IFNULL(CASE WHEN ce.to_currency IN ('JPY', 'VND') THEN SAFE_DIVIDE(ce.standard_exchange_rate, 100) ELSE ce.standard_exchange_rate END
         , mc.krw_rate), 1)) AS NET_PRICE
    FROM {{ ref('MART_SALE_D') }} s
    LEFT JOIN {{ ref('MART_PARTNER_ORIGINAL_D') }} p ON s.PARTNER_ID = p.PARTNER_ID
    LEFT JOIN {{ source('mrt_20', 'reservation_orders') }} ro ON CAST(ro.reservation_id AS STRING) = s.RESVE_ID
    LEFT JOIN {{ source('mrt_20', 'reservation_order_net_prices') }} np ON np.reservation_order_id = ro.id
    LEFT JOIN {{ ref('mart_currency') }} mc ON DATE(mc.day) = S.BASIS_DATE AND mc.code = np.price_currency_code
    LEFT JOIN {{ source('settles' , 'currency_exchanges') }} ce ON ce.standard_date = S.BASIS_DATE AND ce.to_currency = np.price_currency_code AND ce.from_currency = 'KRW' AND ce.deleted_at IS NULL
    LEFT JOIN (SELECT DISTINCT CAST(I.PARTNER_ID AS STRING) AS PARTNER_ID FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} I WHERE I.BIZ_TYPE_PARTNER = 'Sanctum') BT ON BT.PARTNER_ID = s.PARTNER_ID
    LEFT JOIN (SELECT DISTINCT CAST(I.PRODUCT_ID AS STRING) AS PRODUCT_ID FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} I WHERE I.BIZ_TYPE_PARTNER = 'Sanctum') BP ON BP.PRODUCT_ID = s.PRODUCT_ID
    WHERE s.KIND = 1
    AND s.COUNTRY_NM NOT LIKE '%Korea%'
    AND (BT.PARTNER_ID IS NOT NULL OR BP.PRODUCT_ID IS NOT NULL)
    AND np.created_at >= '2023-02-07' AND s.DOMAIN_NM = '2.0 PRODUCT'
    AND ro.DELETED_AT IS NULL AND np.DELETED_AT IS NULL
    GROUP BY s.RESVE_ID

    UNION ALL

    SELECT r.reservation_no AS RESVE_ID
         , SUM(ro.supply_price) AS NET_PRICE
    FROM {{ source('orders' , 'option_reservations') }} ro
    LEFT JOIN {{ source('orders', 'reservations') }} r ON ro.RESERVATION_ID = r.ID
    LEFT JOIN {{ ref('MART_PARTNER_ORIGINAL_D') }} p ON ro.partner_id = p.partner_id
    LEFT JOIN (SELECT DISTINCT RESVE_ID, MAX(COUNTRY_NM) AS COUNTRY_NM FROM {{ ref('MART_SALE_D') }} WHERE KIND = 1 AND COUNTRY_NM NOT LIKE '%Korea%' GROUP BY 1) s ON s.RESVE_ID = r.RESERVATION_NO
    LEFT JOIN (SELECT DISTINCT CAST(I.PARTNER_ID AS STRING) AS PARTNER_ID FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} I WHERE I.BIZ_TYPE_PARTNER = 'Sanctum') BT ON BT.PARTNER_ID = R.PARTNER_ID
    LEFT JOIN (SELECT DISTINCT CAST(I.PRODUCT_ID AS STRING) AS PRODUCT_ID FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} I WHERE I.BIZ_TYPE_PARTNER = 'Sanctum') BP ON BP.PRODUCT_ID = R.PRODUCT_ID
    WHERE (BT.PARTNER_ID IS NOT NULL OR BP.PRODUCT_ID IS NOT NULL)
    AND ro.created_at >= '2023-02-07'
    AND ro.DELETED_AT IS NULL AND r.DELETED_AT IS NULL
    AND s.RESVE_ID IS NOT NULL
    GROUP BY r.reservation_no
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
    SELECT DISTINCT
        cu.RESERVATION_NO AS RESVE_ID
      , MAX(cc.TEMPLATE_ID) AS COUPON_ID
      , MAX(ct.NAME) AS COUPON_TITLE
    FROM {{ source('coupon' , 'coupon_user_mapping') }} AS cc
    LEFT JOIN {{ source('coupon' , 'coupon_templates') }} AS ct
        ON cc.TEMPLATE_ID = ct.ID
    LEFT JOIN {{ source('coupon' , 'coupon_use_history') }} AS cu
        ON cc.ID = cu.COUPON_USER_MAPPING_ID
       AND cu.ACTION_TYPE = 'USE'
    GROUP BY 1
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
    FROM {{ source('coupon' , 'coupon_templates') }} t
    LEFT JOIN {{ source('coupon' , 'coupon_template_condition_mappings') }} c ON t.id = c.template_id AND is_include = true
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
        {{ source('coupon' , 'coupon_templates') }} CCT
        LEFT JOIN {{ source('coupon', 'coupon_template_types') }} CCTT ON CCT.template_type_id = CCTT.id
    WHERE
        CCTT.publish_team = 'CORPORATION_BUSINESS'
),
MYLINK_PARTNERSHIP_CODE AS (
SELECT DISTINCT pp.code AS MARKETING_PARTNERSHIP_CD
FROM {{ source('partners' , 'partnership') }} AS pp
    LEFT JOIN {{ source('partners' , 'partner') }} AS p ON pp.partner_id = p.id
    LEFT JOIN {{ source('partners' , 'partner_account') }} a ON p.id = A.partner_id AND A.type = 'MASTER'
WHERE
    LEFT(code, 1) = 'M'
  AND p.business_registration_type IN ('DOMESTIC','PRIVATE')
  AND CAST(p.id AS STRING) NOT IN (SELECT DISTINCT PARTNER_ID FROM {{ source('external_business' , 'FPNA_MYLINK_PARTNER_INFO') }} WHERE MANAGEMENT_TEAM NOT IN ('B2B / 제휴여행사'))
)

SELECT S.BASIS_DATE,
       S.SALE_FORM_CD                                                                                AS SALE_FORM_CD_v1,
       S.TRAVEL_START_KST_DATE                                                                          AS TRAVEL_START_DATE,
       S.TRAVEL_END_KST_DATE                                                                            AS TRAVEL_END_DATE,
       DATE_DIFF(S.TRAVEL_END_KST_DATE, S.TRAVEL_START_KST_DATE, DAY)                                   AS TRAVEL_DAYS,
       rc.CANCEL_DATE                                                                                   AS CANCEL_DATE,
       DATE_DIFF(rc.CANCEL_DATE, S.BASIS_DATE, DAY)                                                     AS RESVE_CANCEL_DAY_DIFF,
       S.RECENT_STATUS,
       S.ORDER_ID,
       S.ORDER_NO,
       S.RESVE_ID,
       S.DOMAIN_NM,
       S.RESVE_PRSNL_CNT,
       S.TRAVEL_ID,
       S.TRAVEL_DETAIL_ID, --추가(2023.04.19)
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
       S.PROVIDER_CD,
       psc.accounting_project_code                                                                            AS ACCOUNTING_PROJECT_CODE,
       CASE WHEN s.PARTNERSHIP_CD IS NOT NULL THEN 'B2B'
            WHEN pd.IS_B2B_POINT_RSV = TRUE THEN 'B2B'
            WHEN s.STANDARD_CATEGORY_LV_1_CD IN ('TOUR', 'TICKET', 'CLASS', 'SANP', 'ACTIVITY', 'CONVENIENCE') AND s.STANDARD_CATEGORY_LV_3_CD NOT LIKE '%KIDS%' AND (S.COUNTRY_NM = 'Korea, Republic of') THEN 'KIDS'
            WHEN (s.mrt_type = 'kids' OR s.PARTNER_ID IN ('20859','20858','101172','101238','100326') OR s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%') THEN 'KIDS'
            ELSE 'MRT' END AS SALE_FORM_CD,
       S.MRT_TYPE,
       CASE WHEN BZP.PARTNER_ID IS NOT NULL THEN BZP.BIZ_TYPE
            WHEN BZG.GID IS NOT NULL THEN BZG.BIZ_TYPE
            WHEN biz_type_partner.PARTNER_ID IS NOT NULL THEN biz_type_partner.BIZ_TYPE_PARTNER
            WHEN biz_type_product.PRODUCT_ID IS NOT NULL THEN biz_type_product.BIZ_TYPE_PRODUCT
            WHEN s.mrt_type = 'hotdeal' THEN 'Hotdeal'
            ELSE 'Normal' END                                                                           AS BIZ_TYPE,
       CASE
           --B2B
           WHEN s.PARTNERSHIP_CD IS NOT NULL AND S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'B2B_AGENCY_MYPACK'
           WHEN PC.MARKETING_PARTNERSHIP_CD IS NOT NULL AND S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'B2B_AGENCY_MYLINK_MYPACK'
           WHEN s.PARTNERSHIP_CD IS NOT NULL AND (s.STANDARD_CATEGORY_LV_1_CD NOT IN ('PACKAGE', 'ORDER_MADE') OR s.STANDARD_CATEGORY_LV_2_CD IN ('KIDS_ORDER_MADE')) THEN 'B2B_AGENCY_TA'
           WHEN pd.IS_B2B_POINT_RSV = TRUE AND S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'B2B_AFFILIATE_POINT_MYPACK'
           WHEN pd.IS_B2B_POINT_RSV = TRUE AND ((s.STANDARD_CATEGORY_LV_1_CD NOT IN ('ORDER_MADE') AND s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE')) OR s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE')) AND s.STANDARD_CATEGORY_LV_1_CD NOT IN ('PACKAGE') THEN 'B2B_AFFILIATE_POINT_TA'
           WHEN (CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
                      WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
                      WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_ID
                      WHEN ci.title IS NOT NULL THEN ci.id ELSE NULL END) IN (SELECT DISTINCT coupon_id FROM B2B_AFFILIATE_COUPON) AND S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'B2B_AFFILIATE_COUPON_MYPACK'
           WHEN (CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
                      WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
                      WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_ID
                      WHEN ci.title IS NOT NULL THEN ci.id ELSE NULL END) IN (SELECT DISTINCT coupon_id FROM B2B_AFFILIATE_COUPON) AND ((s.STANDARD_CATEGORY_LV_1_CD NOT IN ('ORDER_MADE') AND s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE')) OR s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE')) AND s.STANDARD_CATEGORY_LV_1_CD NOT IN ('PACKAGE') THEN 'B2B_AFFILIATE_COUPON_TA'
           WHEN PC.MARKETING_PARTNERSHIP_CD IS NOT NULL AND (s.STANDARD_CATEGORY_LV_1_CD NOT IN ('PACKAGE', 'ORDER_MADE') OR s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE')) THEN 'B2B_AGENCY_MYLINK_TA'
           WHEN s.STANDARD_CATEGORY_LV_3_CD = 'B2B_AFFILIATE_FLIGHT_GROUP' THEN 'B2B_AFFILIATE_FLIGHT'
           WHEN s.STANDARD_CATEGORY_LV_3_CD = 'ESIM_SUPPLIER' THEN 'OUTBOUND_ESIM_USIM'
           WHEN (s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND s.STANDARD_CATEGORY_LV_2_CD NOT IN ('KIDS_ORDER_MADE', 'B2B_AFFILIATE_ORDER_MADE')) THEN 'B2B_AGENCY_ORDER_MADE'
           WHEN (s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND s.STANDARD_CATEGORY_LV_2_CD IN ('B2B_AFFILIATE_ORDER_MADE')) THEN 'B2B_AFFILIATE_ORDER_MADE'
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND s.BASIS_DATE >= '2023-05-30' AND (s.PARTNERSHIP_TYPE NOT IN ('AGENCY') OR s.PARTNERSHIP_TYPE IS NULL) THEN 'B2B_PACKAGE_ONLINE'
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND s.BASIS_DATE >= '2023-05-30' AND s.PARTNERSHIP_CD IS NOT NULL THEN 'B2B_PACKAGE_OFFLINE'
           --KIDS
           WHEN s.STANDARD_CATEGORY_LV_3_CD IN ('KIDS_ABROAD_ENGLISH_CAMP') THEN 'OUTBOUND_KIDS_ENGLISH_CAMP'
           WHEN s.STANDARD_CATEGORY_LV_3_CD IN ('KIDS_ABROAD_ADMISSION_TICKET_V2', 'KIDS_ABROAD_OUTDOOR_ACTIVITY', 'KIDS_ABROAD_DOCENT', 'KIDS_ABROAD_PREMIUM_KIDSCLUB', 'KIDS_ABROAD_LOCAL_TOUR', 'KIDS_ABROAD_PREMIUM_FULL_PACKAGE', 'KIDS_ABROAD_PREMIUM_SEMI_PACKAGE', 'KIDS_ABROAD_PREMIUM_RESORT') THEN 'OUTBOUND_KIDS_NONKIDS'
           WHEN s.PARTNER_ID IN ('20859','20858','101172','101238','101367') OR (s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%' AND s.STANDARD_CATEGORY_LV_3_CD LIKE '%MADE%' AND (S.COUNTRY_NM = 'Korea, Republic of')) THEN 'DOMESTIC_KIDS_MADE'
           WHEN s.PARTNER_ID IN ('20859','20858','101172','101238','101367') OR (s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%' AND s.STANDARD_CATEGORY_LV_3_CD LIKE '%MADE%' AND (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL)) THEN 'OUTBOUND_KIDS_MADE'
           WHEN (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) AND (s.mrt_type = 'kids' OR s.PARTNER_ID IN ('20859','20858','101172','101238','100326') OR s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%') THEN 'OUTBOUND_KIDS_NORMAL'
           WHEN (S.COUNTRY_NM = 'Korea, Republic of') AND (s.mrt_type = 'kids' OR s.PARTNER_ID IN ('20859','20858','101172','101238','100326') OR s.STANDARD_CATEGORY_LV_3_CD LIKE '%KIDS%') THEN 'DOMESTIC_KIDS_NORMAL'
           --TNA
           WHEN (s.PARTNER_ID IN (SELECT DISTINCT CAST(partner_id AS STRING) AS partner_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_partner = 'Commerce') OR s.product_id IN (SELECT DISTINCT CAST(product_id AS STRING) AS product_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_product = 'Commerce')) AND (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) THEN 'OUTBOUND_COMMERCE'
           WHEN (s.PARTNER_ID IN (SELECT DISTINCT CAST(partner_id AS STRING) AS partner_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_partner = 'Commerce') OR s.product_id IN (SELECT DISTINCT CAST(product_id AS STRING) AS product_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_product = 'Commerce')) AND (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_COMMERCE'
           WHEN (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) THEN 'OUTBOUND_TNA'
           WHEN (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_TNA'
           ELSE NULL END AS BIZ_TYPE_V2,
       CASE --맞춤여행 & 패키지 구분
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN 'ORDER_MADE'
           --WHEN S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND S.STANDARD_CATEGORY_LV_3_CD like '%KIDS%' THEN 'KIDS_PACKAGE'
           --WHEN S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND S.STANDARD_CATEGORY_LV_2_CD = 'PKG_AIR' THEN 'AIR_ONLY'
           --WHEN S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND S.STANDARD_CATEGORY_LV_3_CD = 'PKG_AIRTEL' THEN 'AIRTEL'
           --WHEN S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND S.STANDARD_CATEGORY_LV_2_CD = 'PKG_TNA' THEN 'TNA_PLUS'
           --WHEN S.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' THEN 'PACKAGE_OTHERS'
           WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_STAY_DOMESTIC' THEN 'PKG_STAY_DOMESTIC'
           WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_BIZ_STAY' THEN 'PKG_STAY_OUTBOUND'
           WHEN s.STANDARD_CATEGORY_LV_3_CD = 'PKG_TNA_DOMESTIC' THEN 'PKG_TNA_DOMESTIC'
           WHEN s.STANDARD_CATEGORY_LV_2_CD = 'PKG_BIZ_TNA' THEN 'PKG_TNA_OUTBOUND'
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN 'ORDER_MADE'
           WHEN s.STANDARD_CATEGORY_LV_3_CD = 'ESIM_SUPPLIER' THEN 'OUTBOUND_ESIM_USIM'
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) THEN 'PKG_OTHERS_OUTBOUND'
           WHEN s.STANDARD_CATEGORY_LV_1_CD = 'PACKAGE' AND (S.COUNTRY_NM = 'Korea, Republic of') THEN 'PKG_OTHERS_DOMESTIC'
           --TNA
           WHEN (s.PARTNER_ID IN (SELECT DISTINCT CAST(partner_id AS STRING) AS partner_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_partner = 'Commerce') OR s.product_id IN (SELECT DISTINCT CAST(product_id AS STRING) AS product_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_product = 'Commerce')) AND (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) THEN 'OUTBOUND_COMMERCE'
           WHEN (s.PARTNER_ID IN (SELECT DISTINCT CAST(partner_id AS STRING) AS partner_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_partner = 'Commerce') OR s.product_id IN (SELECT DISTINCT CAST(product_id AS STRING) AS product_id FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }} WHERE biz_type_product = 'Commerce')) AND (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_COMMERCE'
           WHEN (S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL) THEN 'OUTBOUND_TNA'
           WHEN (S.COUNTRY_NM = 'Korea, Republic of') THEN 'DOMESTIC_TNA'
           ELSE NULL END AS BIZ_TYPE_V3,
       FC.FPNA_CATEGORY,
       S.TEAM_DIVISION, --추가(2023.04.19)
       S.FLIGHT_RESVE_ID, --추가(2023.04.19)
       S.FLIGHT_CREATE_KST_DT, --추가(2023.04.19)
       S.FLIGHT_TRAVEL_START_KST_DATE, --추가(2023.04.19)
       S.HOTEL_CAMPAIGN_ID, --추가(2023.04.19)
       S.CREATE_KST_DT, --추가(2023.04.19)
       S.CONFIRM_KST_DT, --추가(2023.04.19)
       S.CONFIRM_KST_DATE, --추가(2023.04.19)
       S.CREATE_KST_DATE, --추가(2023.04.19)
       S.PARTNER_ID,
       A.NAME                                                                                          AS PARTNER_NM,
       S.GID,
       S.GPID,
       S.PRODUCT_ID,
       S.PRODUCT_TITLE                                                                                  AS product_title,
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
       /* TR%  -------------------------------------------------------------------------------------------------------------------------------------------------------------- */
       FLOOR((CASE
                  --키즈
                  WHEN kcloc.TARGET_TR IS NOT NULL THEN kcloc.TARGET_TR * 1.1
                  WHEN ktr.MRT_TAKE_RATE IS NOT NULL THEN ktr.MRT_TAKE_RATE * 1.1
                  --B2B
                  WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.SETTLE_YN = 'Y' AND fomti.SETTLE_TAKE_RATE IS NOT NULL THEN SAFE_DIVIDE(fomti.SETTLE_TAKE_RATE * s.SALES_KRW_PRICE, s.SALES_KRW_PRICE)
                  WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.GID IS NOT NULL THEN SAFE_DIVIDE(fomti.AVG_TAKE_RATE * s.SALES_KRW_PRICE, s.SALES_KRW_PRICE)
                  WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN SAFE_DIVIDE(0.03 * s.SALES_KRW_PRICE, s.SALES_KRW_PRICE)
                  -- 내부 정산
                  WHEN S.PARTNER_ID = '14842' AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate --테이블엔조이 예외케이스 반영
                  WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate --과거 별도정산 product_id 맵핑
                  WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate --과거 별도정산 product_id 맵핑
                  WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_RATE -- 내부정산 commission_rate 맵핑
                  WHEN S.PARTNER_SETTLE_TYPE LIKE '%external%' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_RATE -- 별도정산인데 100%가 아닌 건 맵핑
                  WHEN S.PARTNER_SETTLE_TYPE IS NULL AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_RATE -- 정산타입 missing -> commission_rate 맵핑
                  -- 연동상품 공급가 연동 (PP.PARTNER_ID = 연동 상품의 파트너 ID)
                  WHEN pcb.PARTNER_ID IS NOT NULL THEN pcb.COMMISSION_RATE
                  WHEN CNP.RESVE_ID IS NOT NULL THEN FLOOR(SAFE_DIVIDE((S.SALES_KRW_PRICE - CNP.NET_PRICE), S.SALES_KRW_PRICE) * 100) / 100
                  WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c.avg_tr IS NOT NULL THEN tna_c.avg_tr
                  WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c_p.avg_tr IS NOT NULL THEN tna_c_p.avg_tr
                  WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c.avg_tr IS NOT NULL THEN tna_c.avg_tr
                  WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c_p.avg_tr IS NOT NULL THEN tna_c_p.avg_tr
                  WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate
                  WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate
                  WHEN PP.PARTNER_ID IS NOT NULL THEN FLOOR(SAFE_DIVIDE((S.SALES_KRW_PRICE - P.NET_PRICE), S.SALES_KRW_PRICE) * 100) / 100
                  -- 옵션가 맵핑 (커머스)
                  WHEN cup.resve_id IS NOT NULL AND cup.TOTAL_NET_PRICE != 0 AND cup.TOTAL_NET_PRICE IS NOT NULL THEN FLOOR(SAFE_DIVIDE((S.SALES_KRW_PRICE - cup.TOTAL_NET_PRICE),S.SALES_KRW_PRICE) *100) / 100
                  WHEN OP.NET_PRICE <> 0 AND OP.NET_PRICE IS NOT NULL THEN FLOOR(SAFE_DIVIDE((S.SALES_KRW_PRICE - OP.NET_PRICE),S.SALES_KRW_PRICE) *100) / 100
                  -- 기타 별도 정산 맵핑
                  WHEN ex_product.product_id IS NOT NULL THEN ex_product.commission_rate
                  WHEN ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate
                  WHEN dcr.partner_id IS NOT NULL THEN dcr.commission_rate
                  --WHEN OP.NET_PRICE = 0 or OP.NET_PRICE is null THEN 0.03
                  -- 예외케이스 수수료 3% 적용 로직
                  WHEN S.COMMISSION_RATE = 1 THEN NULL
                  ELSE NULL END)
                 / 1.1 * 100) / 100                                                                          AS COMMISSION_RATE,
       S.COMMISSION_PRICE AS SALES_COMMISSION_PRICE,
       S.PARTNER_SETTLE_TYPE,
       S.PARTNER_SALES_TYPE,
       S.PARTNERSHIP_CD,
       S.MARKETING_PARTNERSHIP_CD,
       pg.pg AS PG_NM,
       S.SALES_KRW_PRICE,
       /* 총매출 -------------------------------------------------------------------------------------------------------------------------------------------------------------- */
       IFNULL(FLOOR(--CASE WHEN S.RECENT_STATUS IN ('confirm', 'finish') THEN
                 (CASE
                     --키즈
                     WHEN kcloc.TARGET_TR IS NOT NULL THEN s.SALES_KRW_PRICE * kcloc.TARGET_TR * 1.1
                     WHEN ktr.MRT_TAKE_RATE IS NOT NULL THEN s.SALES_KRW_PRICE * ktr.MRT_TAKE_RATE * 1.1
                     --B2B
                     WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.SETTLE_YN = 'Y' AND fomti.SETTLE_TAKE_RATE IS NOT NULL THEN fomti.SETTLE_TAKE_RATE * s.SALES_KRW_PRICE
                     WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.GID IS NOT NULL THEN fomti.AVG_TAKE_RATE * s.SALES_KRW_PRICE
                     WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN 0.03 * s.SALES_KRW_PRICE
                    -- 내부 정산
                     WHEN S.PARTNER_ID = '14842' AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate * S.SALES_KRW_PRICE --테이블엔조이 예외케이스 반영
                     WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate * S.SALES_KRW_PRICE --과거 별도정산 product_id 맵핑
                     WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate * S.SALES_KRW_PRICE --과거 별도정산 product_id 맵핑
                     WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_RATE * S.SALES_KRW_PRICE -- 내부정산 commission_rate 맵핑
                     WHEN S.PARTNER_SETTLE_TYPE LIKE '%external%' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_PRICE -- 별도정산인데 100%가 아닌 건 맵핑
                     WHEN S.PARTNER_SETTLE_TYPE IS NULL AND (S.COMMISSION_RATE > 0 AND S.COMMISSION_RATE < 1) AND S.COMMISSION_RATE IS NOT NULL THEN S.COMMISSION_RATE * S.SALES_KRW_PRICE -- 정산타입 missing -> commission_rate 맵핑
                    -- 연동상품 공급가 연동 (PP.PARTNER_ID = 연동 상품의 파트너 ID)
                     WHEN pcb.PARTNER_ID IS NOT NULL THEN (S.SALES_KRW_PRICE * pcb.COMMISSION_RATE)
                     WHEN CNP.RESVE_ID IS NOT NULL THEN (S.SALES_KRW_PRICE - CNP.NET_PRICE)
                     WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c.avg_tr IS NOT NULL THEN tna_c.avg_tr * S.SALES_KRW_PRICE
                     WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c_p.avg_tr IS NOT NULL THEN tna_c_p.avg_tr * S.SALES_KRW_PRICE
                     WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c.avg_tr IS NOT NULL THEN tna_c.avg_tr * S.SALES_KRW_PRICE
                     WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c_p.avg_tr IS NOT NULL THEN tna_c_p.avg_tr * S.SALES_KRW_PRICE
                     WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_product.product_id IS NOT NULL THEN ex_product.commission_rate * S.SALES_KRW_PRICE
                     WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate * S.SALES_KRW_PRICE
                     WHEN PP.PARTNER_ID IS NOT NULL THEN (S.SALES_KRW_PRICE - P.NET_PRICE)
                    -- 옵션가 맵핑 (커머스)
                     WHEN cup.resve_id IS NOT NULL AND cup.TOTAL_NET_PRICE != 0 AND cup.TOTAL_NET_PRICE IS NOT NULL THEN S.SALES_KRW_PRICE - cup.TOTAL_NET_PRICE
                     WHEN OP.NET_PRICE <> 0 AND OP.NET_PRICE IS NOT NULL THEN (S.SALES_KRW_PRICE - OP.NET_PRICE)
                    -- 기타 별도 정산 맵핑
                     WHEN ex_product.product_id IS NOT NULL THEN ex_product.commission_rate * S.SALES_KRW_PRICE
                     WHEN ex_partner.partner_id IS NOT NULL THEN ex_partner.commission_rate * S.SALES_KRW_PRICE
                     WHEN dcr.partner_id IS NOT NULL THEN dcr.commission_rate * S.SALES_KRW_PRICE
                    --WHEN OP.NET_PRICE = 0 or OP.NET_PRICE is null THEN 0.03 * S.SALES_KRW_PRICE
                    -- 예외케이스 수수료 3% 적용 로직
                     WHEN S.COMMISSION_RATE = 1 THEN 0.03 * S.SALES_KRW_PRICE
                     ELSE 0.03 * S.SALES_KRW_PRICE END) / 1.1 * 100) / 100,0)                                                AS MRT_SALES_PRICE,
                 CASE -- MRT_SALES_PRICE 검증을 위해
                      --키즈
                      WHEN kcloc.TARGET_TR IS NOT NULL THEN 1
                      WHEN ktr.MRT_TAKE_RATE IS NOT NULL THEN 2
                      --B2B
                      WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.SETTLE_YN = 'Y' AND fomti.SETTLE_TAKE_RATE IS NOT NULL THEN 3
                      WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' AND fomti.GID IS NOT NULL THEN 4
                      WHEN s.STANDARD_CATEGORY_LV_1_CD = 'ORDER_MADE' THEN 5
                     -- 내부 정산
                      WHEN S.PARTNER_ID = '14842' AND ex_product.product_id IS NOT NULL THEN 6 --테이블엔조이 예외케이스 반영
                      WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_product.product_id IS NOT NULL THEN 7 --과거 별도정산 product_id 맵핑
                      WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND ex_partner.partner_id IS NOT NULL THEN 8 --과거 별도정산 product_id 맵핑
                      WHEN S.PARTNER_SETTLE_TYPE = 'internal' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN 9 -- 내부정산 commission_rate 맵핑
                      WHEN S.PARTNER_SETTLE_TYPE LIKE '%external%' AND S.COMMISSION_RATE <> 1 AND S.COMMISSION_RATE IS NOT NULL THEN 10 -- 별도정산인데 100%가 아닌 건 맵핑
                      WHEN S.PARTNER_SETTLE_TYPE IS NULL AND (S.COMMISSION_RATE > 0 AND S.COMMISSION_RATE < 1) AND S.COMMISSION_RATE IS NOT NULL THEN 11 -- 정산타입 missing -> commission_rate 맵핑
                     -- 연동상품 공급가 연동 (PP.PARTNER_ID = 연동 상품의 파트너 ID)
                      WHEN pcb.PARTNER_ID IS NOT NULL THEN 12
                      WHEN CNP.RESVE_ID IS NOT NULL THEN 13
                      WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c.avg_tr IS NOT NULL THEN 14
                      WHEN S.PARTNER_ID IN (SELECT DISTINCT PARTNER_ID FROM MART_SERVICE_PARTNER_ID) AND S.DOMAIN_NM = '3.0 PRODUCT' AND tna_c_p.avg_tr IS NOT NULL THEN 15
                      WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c.avg_tr IS NOT NULL THEN 16
                      WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND tna_c_p.avg_tr IS NOT NULL THEN 17
                      WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_product.product_id IS NOT NULL THEN 18
                      WHEN PP.PARTNER_ID IS NOT NULL AND (P.NET_PRICE = 0 OR P.NET_PRICE IS NULL) AND ex_partner.partner_id IS NOT NULL THEN 19
                      WHEN PP.PARTNER_ID IS NOT NULL THEN 20
                     -- 옵션가 맵핑 (커머스)
                      WHEN cup.resve_id IS NOT NULL AND cup.TOTAL_NET_PRICE != 0 AND cup.TOTAL_NET_PRICE IS NOT NULL THEN 21
                      WHEN OP.NET_PRICE <> 0 AND OP.NET_PRICE IS NOT NULL THEN 22
                     -- 기타 별도 정산 맵핑
                      WHEN ex_product.product_id IS NOT NULL THEN 23
                      WHEN ex_partner.partner_id IS NOT NULL THEN 24
                      WHEN dcr.partner_id IS NOT NULL THEN 25
                     --WHEN OP.NET_PRICE = 0 or OP.NET_PRICE is null THEN 0.03 * S.SALES_KRW_PRICE
                     -- 예외케이스 수수료 3% 적용 로직
                      WHEN S.COMMISSION_RATE = 1 THEN 26
                      ELSE 99 END AS MRT_SALES_PRICE_TYPE
      , CASE
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
        )                                                                                                 AS PRODUCT_COUPON_PRICE
      , IFNULL(O30C.COUPON_PRICE, 0)
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
        )                                                                                                 AS ORDER_COUPON_PRICE
      , CASE
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
        )                                                                                                 AS COUPON_PRICE,
       IFNULL(S.point_price,0)                                                                              AS POINT_PRICE,
       IFNULL(CASE WHEN pd.POINT_SUM IS NOT NULL THEN S.point_price ELSE 0 END, 0)                              AS EXCLUDED_POINT_PRICE,
       IFNULL(SAFE_DIVIDE(S.DISCOUNT_PRICE,1.1),0)                                                             AS DISCOUNT_PRICE,
       IFNULL(FLOOR(CASE WHEN npo.PRODUCT_ID IS NOT NULL THEN S.sales_krw_price * 0.0563
                  ELSE S.sales_krw_price * IFNULL(pg.pg_com_rate,0.02)
                  END * 100) / 100,0)                                                                     AS CHANNEL_FEE_PRICE,
       IFNULL(ampc.partnership_commission,0) AS AGENCY_FEE,
       IFNULL(ampc.marketing_partnership_commission,0) AS MARKETING_PARTNER_FEE,
       IFNULL(CASE WHEN pd.IS_B2B_POINT_RSV = TRUE THEN s.POINT_PRICE * 0.02 ELSE 0 END,0) AS AFFILIATE_POINT_FEE,
       COALESCE(CNP.NET_PRICE, cup.TOTAL_NET_PRICE, OP.NET_PRICE) AS NET_PRICE,
       DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                                     AS DW_LOAD_DT
FROM {{ ref('MART_SALE_D') }} S
LEFT JOIN {{ ref('MART_USER_D') }} U ON S.USER_ID = U.USER_ID
LEFT JOIN {{ source('partners' , 'partner') }} PO ON S.PARTNER_ID = CAST(PO.ID AS STRING)
LEFT JOIN {{ source('partners' , 'partner_account') }} A ON PO.id = A.partner_id AND A.type = 'MASTER'
LEFT JOIN {{ source('mrt_20' , 'promotion_coupon_codes') }} pcc ON CAST(pcc.reservation_id AS STRING) = S.RESVE_ID
LEFT JOIN {{ source('mrt_20' , 'promotion_coupons') }} ci ON ci.id = pcc.coupon_id
LEFT JOIN CP_PRODUCT CP ON CP.RESVE_ID = S.RESVE_ID
LEFT JOIN USED_COUPON_RESVE UCR ON UCR.RESVE_ID = S.RESVE_ID
LEFT JOIN PRODUCT_COUPON_REP PCR ON PCR.RESVE_ID = S.RESVE_ID
LEFT JOIN ORDER_COUPON_REP OCR ON OCR.RESVE_ID = S.RESVE_ID
LEFT JOIN {{ source('orders', 'reservations') }} R ON S.RESVE_ID = R.reservation_no AND R.deleted_at IS NULL
LEFT JOIN (SELECT DISTINCT h.RESERVATION_NO AS RESVE_ID, MAX(h.template_id) AS COUPON_ID, MAX(t.name) AS coupon_title FROM {{ source('mrt_20', 'coupon_reservation_history') }} h LEFT JOIN {{ source('coupon' , 'coupon_templates') }} t ON h.template_id = t.id WHERE h.DELETED_AT IS NULL AND t.DELETED_AT IS NULL GROUP BY 1) AS COUPON_30 ON COUPON_30.RESVE_ID = S.RESVE_ID
LEFT JOIN COUPON_EXTRA_INFO cei_2 ON cei_2.coupon_id = ci.id
LEFT JOIN COUPON_EXTRA_INFO cei_legacy ON cei_legacy.coupon_id = (
    CASE
        WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
        WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
        ELSE COUPON_30.COUPON_ID
    END
)
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_2 ON fci_2.coupon_id = ci.id AND fci_2.type = '2.0 product'
LEFT JOIN {{ ref('fpna_coupon_info') }} fci_3
    ON fci_3.coupon_id = (
        CASE
            WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
            WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
            ELSE COUPON_30.COUPON_ID
        END
    )
   AND fci_3.type = '3.0 product'
LEFT JOIN PRODUCT_30_COUPON_COST P30C ON P30C.RESVE_ID = S.RESVE_ID
LEFT JOIN ORDER_30_COUPON_COST O30C ON O30C.RESVE_ID = S.RESVE_ID
LEFT JOIN MART_SERVICE_NET_PRICE P ON S.RESVE_ID = P.RESVE_ID AND S.DOMAIN_NM = '2.0 PRODUCT'
LEFT JOIN MART_SERVICE_PARTNER_ID PP ON S.PARTNER_ID = PP.PARTNER_ID AND S.DOMAIN_NM = '2.0 PRODUCT'
LEFT JOIN {{ ref('fpna_external_commission_tna_connected') }} tna_c ON CAST(tna_c.product_id AS STRING) = S.PRODUCT_ID
LEFT JOIN {{ ref('fpna_external_commission_tna_connected_partner') }} tna_c_p ON CAST(tna_c_p.partner_id AS STRING) = S.PARTNER_ID
LEFT JOIN OPTION_MAPPING OP ON S.RESVE_ID = OP.RESVE_ID
LEFT JOIN (SELECT PARTNER_ID, PARTNER_NM, BIZ_TYPE_PARTNER FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }}) biz_type_partner ON CAST(biz_type_partner.PARTNER_ID AS STRING) = S.PARTNER_ID
LEFT JOIN (SELECT PRODUCT_ID, PRODUCT_NM, BIZ_TYPE_PRODUCT FROM {{ ref('FPNA_TNA_BIZ_TYPE_INFO') }}) biz_type_product ON CAST(biz_type_product.PRODUCT_ID AS STRING) = S.PRODUCT_ID
LEFT JOIN {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} ex_partner ON CAST(ex_partner.partner_id AS STRING) = S.PARTNER_ID AND S.basis_date >= ex_partner.start_date AND S.basis_date <= ex_partner.end_date
LEFT JOIN {{ ref('FPNA_TNA_COMMISSION_RATE_INFO') }} ex_product ON CAST(ex_product.product_id AS STRING) = S.PRODUCT_ID AND S.basis_date >= ex_product.start_date AND S.basis_date <= ex_product.end_date
LEFT JOIN {{ ref('FPNA_TNA_FIRST_MAPPING_PARTNER') }} first_partner ON CAST(first_partner.partner_id AS STRING) = S.PARTNER_ID AND S.basis_date >= first_partner.start_date AND S.basis_date <= first_partner.end_date
LEFT JOIN {{ ref('FPNA_TNA_FIRST_MAPPING_PRODUCT') }} first_product ON CAST(first_product.product_id AS STRING) = S.PRODUCT_ID AND S.basis_date >= first_product.start_date AND S.basis_date <= first_product.end_date
LEFT JOIN {{ ref('INT_FPNA_RSV_CANCEL') }} rc ON S.RESVE_ID = rc.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_POINT_DETAIL') }} pd ON pd.RESVE_ID = S.RESVE_ID
LEFT JOIN (SELECT DISTINCT partner_id, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZP ON S.partner_id = BZP.PARTNER_ID
LEFT JOIN (SELECT DISTINCT GID, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZG ON S.gid = BZG.gid
LEFT JOIN CONNECTED_NET_PRICE CNP ON CNP.RESVE_ID = S.RESVE_ID
--LEFT JOIN (select distinct partner_id from business.FPNA_TNA_PARTNER_EXCEPTION) FPE on S.PARTNER_ID = FPE.PARTNER_ID
LEFT JOIN (SELECT DISTINCT product_id FROM {{ ref('FPNA_TNA_NAVER_SMARTSTORE_OFFERS') }}) npo ON S.PRODUCT_ID = npo.PRODUCT_ID
LEFT JOIN {{ ref('FPNA_TNA_CONNECTED_PARTNERS_COMMISSION_BASE') }} pcb ON S.PARTNER_ID = pcb.PARTNER_ID
LEFT JOIN (SELECT DISTINCT partner_id, MAX(accounting_project_code) AS accounting_project_code FROM {{ source('settles' , 'partner_settlement_configs') }} GROUP BY 1) psc ON psc.partner_id = s.partner_id
LEFT JOIN {{ ref('FPNA_CATEGORY_INFO') }} FC ON S.STANDARD_CATEGORY_LV_3_CD = FC.LV_3_CD
LEFT JOIN {{ ref('INT_FPNA_PG_FEE') }} pg ON s.RESVE_ID = pg.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_AGENCY_COMMISSION') }} ampc ON ampc.RESVE_ID = s.RESVE_ID
LEFT JOIN {{ ref('FPNA_ORDER_MADE_GID_PROFIT_INFO') }} fomti ON fomti.gid = s.gid
LEFT JOIN {{ ref('FPNA_KIDS_CIC_LEGACY_OFFER_COMMISSION_RATE') }} kcloc ON kcloc.PRODUCT_ID = s.PRODUCT_ID
LEFT JOIN (SELECT DISTINCT PRODUCT_ID, MAX(MRT_TAKE_RATE) AS MRT_TAKE_RATE FROM {{ ref('FPNA_KIDS_CIC_MADE_PRODUCT_INFO') }} WHERE MRT_TAKE_RATE IS NOT NULL GROUP BY 1) ktr ON ktr.product_id = s.product_id
LEFT JOIN COMMERCE_NEW_STOCK_UNIT_PRICE cup ON cup.resve_id = s.resve_id
LEFT JOIN {{ ref('FPNA_TNA_PARTNER_DEFAULT_COMMISSION_RATE') }} dcr ON dcr.PARTNER_ID = s.PARTNER_ID
LEFT JOIN MYLINK_PARTNERSHIP_CODE PC ON S.MARKETING_PARTNERSHIP_CD = PC.MARKETING_PARTNERSHIP_CD
WHERE S.kind = 1
  AND S.RESVE_ID NOT LIKE '%PKG%'
  AND S.STANDARD_CATEGORY_LV_1_CD NOT IN ('FLIGHT', 'ACCOMMODATION', 'TRANSPORTATION_V2', 'INSURANCE', 'AIR_ANCILLARY')
