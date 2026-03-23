{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_RENTALCAR_PROFIT_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['SALE_FORM_CD', 'RECENT_STATUS', 'DOMAIN_NM']
    )
}}


WITH OUTBOUND_RENTALCAR_RESVE_PROFIT AS (
    SELECT 'CAR-' || FORMAT_TIMESTAMP('%Y%m%d', DATE(LEFT(r.created_date,10))) || '-' || R.res_id AS RESVE_ID
          , ROUND(SAFE_DIVIDE(SAFE_DIVIDE(CASE WHEN r.status = 'booked' THEN
        (CASE WHEN r.pay_type = 'PPD' THEN r.total_amount * 0.07
        ELSE r.basic_rate * 0.035 END)
        WHEN r.status = 'canceled' AND DATETIME_DIFF(DATETIME(r.pickup_datetime),DATETIME(r.canceled_date),HOUR) <= 72 THEN r.total_amount * 0.1 * 0.7
        ELSE 0 END,1.1),r.total_amount),3) AS COMMISSION_RATE
         , SAFE_DIVIDE(CASE WHEN r.status = 'booked' THEN (CASE WHEN r.pay_type = 'PPD' THEN r.total_amount * 0.07 ELSE r.basic_rate * 0.035 END)
        WHEN r.status = 'canceled' AND DATETIME_DIFF(DATETIME(r.pickup_datetime),DATETIME(r.canceled_date),HOUR) <= 72 THEN r.total_amount * 0.1 * 0.7
        ELSE 0 END,1.1) AS MRT_SALES_PRICE
    FROM {{ source('external', 'DW_MRT_TRIMO_RESERVATION') }} r
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
    LEFT JOIN {{ source('coupon', 'coupon_template_condition_mappings') }} c
    ON t.id = c.template_id AND is_include = true
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
)

SELECT S.BASIS_DATE,
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
       psc.accounting_project_code AS ACCOUNTING_PROJECT_CODE,
       CASE WHEN s.PARTNERSHIP_TYPE = 'AGENCY' THEN 'B2B'
            WHEN pd.IS_B2B_POINT_RSV = TRUE THEN 'B2B'
            ELSE 'MRT' END AS SALE_FORM_CD,
       S.MRT_TYPE,
       CASE WHEN BZP.PARTNER_ID IS NOT NULL THEN BZP.BIZ_TYPE
            WHEN BZG.GID IS NOT NULL THEN BZG.BIZ_TYPE ELSE NULL END                                    AS BIZ_TYPE,
       CASE WHEN S.PARTNERSHIP_CD IS NOT NULL THEN 'B2B_AGENCY_RC'
            WHEN pd.IS_B2B_POINT_RSV = TRUE THEN 'B2B_AFFILIATE_POINT_RC'
            WHEN (CASE WHEN UCR.RESVE_ID IS NOT NULL THEN UCR.COUPON_ID
                       WHEN CP.COUPON_NM IS NOT NULL THEN CP.COUPON_ID
                       WHEN COUPON_30.COUPON_ID IS NOT NULL THEN COUPON_30.COUPON_ID
                       WHEN ci.title IS NOT NULL THEN ci.id ELSE NULL END) IN (SELECT DISTINCT coupon_id FROM B2B_AFFILIATE_COUPON) THEN 'B2B_AFFILIATE_COUPON_RC'
            WHEN PC.MARKETING_PARTNERSHIP_CD IS NOT NULL THEN 'B2B_AGENCY_MYLINK_RC'
            WHEN S.STANDARD_CATEGORY_LV_3_CD = 'EUROPE_TRAIN' THEN 'OUTBOUND_TRAIN_RAILEUROPE'
            WHEN S.COUNTRY_NM LIKE '%Korea%' THEN 'DOMESTIC_RENTALCAR'
            ELSE 'OUTBOUND_RENTALCAR' END AS BIZ_TYPE_V2,
       CASE WHEN S.STANDARD_CATEGORY_LV_3_CD = 'EUROPE_TRAIN' THEN 'OUTBOUND_TRAIN_RAILEUROPE'
            WHEN S.COUNTRY_NM LIKE '%Korea%' THEN 'DOMESTIC_RENTALCAR'
            ELSE 'OUTBOUND_RENTALCAR' END AS BIZ_TYPE_V3,
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
       PO.NAME                                                                                          AS PARTNER_NM,
       S.GID,
       S.GPID,
       S.PRODUCT_ID,
       S.PRODUCT_TITLE                                                                                  AS PRODUCT_TITLE,
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
       CASE WHEN ORP.RESVE_ID IS NOT NULL THEN ORP.COMMISSION_RATE
            WHEN ((S.PARTNER_SETTLE_TYPE = 'internal' AND S.commission_rate != 1) OR S.commission_rate != 1)
            THEN SAFE_DIVIDE(S.commission_rate, 1.1) -- 내부정산
            ELSE SAFE_DIVIDE(0.05, 1.1) END                                                             AS COMMISSION_RATE,
       S.COMMISSION_PRICE AS SALES_COMMISSION_PRICE,
       S.PARTNER_SETTLE_TYPE,
       S.PARTNER_SALES_TYPE,
       S.PARTNERSHIP_CD,
       S.MARKETING_PARTNERSHIP_CD,
       pg.pg AS PG_NM,
       S.SALES_KRW_PRICE,
       IFNULL(SAFE_DIVIDE(CASE WHEN ORP.RESVE_ID IS NOT NULL THEN ORP.MRT_SALES_PRICE * 1.1
            WHEN ((S.PARTNER_SETTLE_TYPE = 'internal' AND S.commission_rate != 1) OR S.commission_rate != 1)
       THEN S.sales_krw_price * S.commission_rate -- 별도 정산
            ELSE S.sales_krw_price * 0.05 END,1.1)
            ,0)                                                                                 AS MRT_SALES_PRICE,
      CASE WHEN ORP.RESVE_ID IS NOT NULL THEN 1
            WHEN ((S.PARTNER_SETTLE_TYPE = 'internal' AND S.commission_rate != 1) OR S.commission_rate != 1)
       THEN 2 -- 별도 정산
            ELSE 99 END AS MRT_SALES_PRICE_TYPE,
       CASE
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
         )                                                                                                 AS PRODUCT_COUPON_PRICE,
       IFNULL(O30C.COUPON_PRICE, 0)
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
         )                                                                                                 AS ORDER_COUPON_PRICE,
       CASE
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
       IFNULL(S.point_price,0)                                                                          AS POINT_PRICE,
       IFNULL(CASE WHEN pd.POINT_SUM IS NOT NULL THEN S.point_price ELSE 0 END, 0)                              AS EXCLUDED_POINT_PRICE,
       IFNULL(SAFE_DIVIDE(S.DISCOUNT_PRICE,1.1),0)                                                      AS DISCOUNT_PRICE,
       IFNULL(FLOOR(CASE WHEN ORP.RESVE_ID IS NOT NULL THEN 0
                  ELSE S.sales_krw_price * IFNULL(pg.pg_com_rate,0.02) END * 100) / 100,0)              AS CHANNEL_FEE_PRICE,
       IFNULL(ampc.partnership_commission,0) AS AGENCY_FEE,
       IFNULL(ampc.marketing_partnership_commission,0) AS MARKETING_PARTNER_FEE,
       IFNULL(CASE WHEN pd.IS_B2B_POINT_RSV = TRUE THEN s.POINT_PRICE * 0.02 ELSE 0 END,0) AS AFFILIATE_POINT_FEE,
       CAST(NULL AS FLOAT64) AS NET_PRICE,
       DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                               AS DW_LOAD_DT
FROM {{ ref('MART_SALE_D') }} S
LEFT JOIN {{ ref('MART_USER_D') }} U ON S.USER_ID = U.USER_ID
LEFT JOIN {{ source('partners', 'partner') }} PO ON S.PARTNER_ID = CAST(PO.ID AS STRING)
LEFT JOIN {{ ref('FPNA_CATEGORY_INFO') }} FC ON S.STANDARD_CATEGORY_LV_3_CD = FC.LV_3_CD
LEFT JOIN {{ source('mrt_20', 'promotion_coupon_codes') }} pcc ON CAST(pcc.reservation_id AS STRING) = S.RESVE_ID
LEFT JOIN {{ source('mrt_20', 'promotion_coupons') }} ci ON ci.id = pcc.coupon_id
LEFT JOIN CP_PRODUCT CP ON CP.RESVE_ID = S.RESVE_ID
LEFT JOIN USED_COUPON_RESVE UCR ON UCR.RESVE_ID = S.RESVE_ID
LEFT JOIN PRODUCT_COUPON_REP PCR ON PCR.RESVE_ID = S.RESVE_ID
LEFT JOIN ORDER_COUPON_REP OCR ON OCR.RESVE_ID = S.RESVE_ID
LEFT JOIN (SELECT DISTINCT h.RESERVATION_NO AS RESVE_ID, MAX(h.template_id) AS COUPON_ID, MAX(t.name) AS coupon_title FROM {{ source('mrt_20', 'coupon_reservation_history') }} h LEFT JOIN {{ source('coupon', 'coupon_templates') }} t ON h.template_id = t.id WHERE h.DELETED_AT IS NULL AND t.DELETED_AT IS NULL GROUP BY 1) AS COUPON_30 ON COUPON_30.RESVE_ID = S.RESVE_ID
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
LEFT JOIN {{ ref('INT_FPNA_RSV_CANCEL') }} rc ON S.RESVE_ID = rc.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_POINT_DETAIL') }} pd ON pd.RESVE_ID = S.RESVE_ID
LEFT JOIN (SELECT DISTINCT partner_id, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZP ON S.partner_id = BZP.PARTNER_ID
LEFT JOIN (SELECT DISTINCT GID, biz_type FROM {{ ref('FPNA_BIZ_TYPE_INFO') }}) BZG ON S.gid = BZG.gid
LEFT JOIN OUTBOUND_RENTALCAR_RESVE_PROFIT ORP ON ORP.RESVE_ID = S.RESVE_ID
LEFT JOIN (SELECT DISTINCT partner_id, MAX(accounting_project_code) AS accounting_project_code FROM {{ source('settles', 'partner_settlement_configs') }} GROUP BY 1) psc ON psc.partner_id = s.partner_id
LEFT JOIN {{ ref('INT_FPNA_PG_FEE') }} pg ON s.RESVE_ID = pg.RESVE_ID
LEFT JOIN {{ ref('INT_FPNA_AGENCY_COMMISSION') }} ampc ON ampc.RESVE_ID = s.RESVE_ID
LEFT JOIN MYLINK_PARTNERSHIP_CODE PC ON S.MARKETING_PARTNERSHIP_CD = PC.MARKETING_PARTNERSHIP_CD
WHERE S.kind = 1
  AND S.STANDARD_CATEGORY_LV_1_CD IN ('TRANSPORTATION_V2')
