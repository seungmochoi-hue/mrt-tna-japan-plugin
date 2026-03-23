{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_INSURANCE_PROFIT_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['RECENT_STATUS', 'DOMAIN_NM']
    )
}}



WITH RSV_CANCEL AS (
    SELECT RESVE_ID                                                                          AS RESVE_ID
         , DATE(CANCEL_KST_DT)                                                               AS CANCEL_DATE
    FROM {{ ref('MART_SALE_D') }}
    WHERE KIND = 2
)
SELECT S.BASIS_DATE
     , S.TRAVEL_START_KST_DATE                                                                          AS TRAVEL_START_DATE
     , S.TRAVEL_END_KST_DATE                                                                            AS TRAVEL_END_DATE
     , DATE_DIFF(S.TRAVEL_END_KST_DATE, S.TRAVEL_START_KST_DATE, DAY)                                   AS TRAVEL_DAYS
     , RC.CANCEL_DATE                                                                                   AS CANCEL_DATE
     , DATE_DIFF(RC.CANCEL_DATE, S.BASIS_DATE, DAY)                                                     AS RESVE_CANCEL_DAY_DIFF
     , S.RECENT_STATUS
     , S.ORDER_ID
     , S.ORDER_NO
     , S.RESVE_ID
     , S.DOMAIN_NM
     , S.RESVE_PRSNL_CNT
     , S.TRAVEL_ID
     , S.TRAVEL_DETAIL_ID --추가(2023.04.19)
     , U.MRT_STAFF_FLAG                                                                                 AS MRT_STAFF_FLAG
     , S.USER_ID
     , S.CATEGORY_NM
     , S.CATEGORY_CD
     , S.SUB_CATEGORY_CD
     , S.STANDARD_CATEGORY_LV_1_CD
     , S.STANDARD_CATEGORY_LV_1_NM
     , S.STANDARD_CATEGORY_LV_2_CD
     , S.STANDARD_CATEGORY_LV_2_NM
     , S.STANDARD_CATEGORY_LV_3_CD
     , S.STANDARD_CATEGORY_LV_3_NM
     , S.PARTNERSHIP_TYPE
     , S.PROVIDER_CD
     , psc.accounting_project_code                                                                       AS ACCOUNTING_PROJECT_CODE
     , 'MRT'                                                                                             AS SALE_FORM_CD
     , S.MRT_TYPE
     , 'INSURANCE'                                                                                      AS BIZ_TYPE
     , 'INSURANCE'                                                                                      AS BIZ_TYPE_V2
     , 'INSURANCE'                                                                                      AS BIZ_TYPE_V3
     , FC.FPNA_CATEGORY
     , S.TEAM_DIVISION --추가(2023.04.19)
     , S.FLIGHT_RESVE_ID --추가(2023.04.19)
     , S.FLIGHT_CREATE_KST_DT --추가(2023.04.19)
     , S.FLIGHT_TRAVEL_START_KST_DATE --추가(2023.04.19)
     , S.HOTEL_CAMPAIGN_ID --추가(2023.04.19)
     , S.CREATE_KST_DT --추가(2023.04.19)
     , S.CONFIRM_KST_DT --추가(2023.04.19)
     , S.CONFIRM_KST_DATE --추가(2023.04.19)
     , S.CREATE_KST_DATE --추가(2023.04.19)
     , S.PARTNER_ID
     , A.name                                                                                           AS PARTNER_NM
     , S.GID
     , S.GPID
     , S.PRODUCT_ID
     , S.PRODUCT_TITLE                                                                                  AS PRODUCT_TITLE
     , CASE WHEN S.COUNTRY_NM = 'Korea, Republic of' THEN 'Domestic'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL THEN 'Outbound'
            ELSE 'Outbound' END                                                                         AS REGION_TYPE
     , S.REGION_NM
     , CASE WHEN S.COUNTRY_NM IS NULL THEN 'Others'
            ELSE S.COUNTRY_NM END                                                                       AS COUNTRY_NM
     , CASE WHEN S.CITY_NM IS NULL THEN 'Others'
            ELSE S.city_nm END                                                                          AS CITY_NM
     , CASE WHEN S.CITY_NM = 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'Y'
            WHEN S.CITY_NM != 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM IS NULL THEN 'N' ELSE 'N' END                                             AS JEJU_FLAG
     , NULL                                                                                             AS COUPON_ID
     , CAST(NULL AS INT64)                                                                              AS PRODUCT_COUPON_ID
     , CAST(NULL AS INT64)                                                                              AS ORDER_COUPON_ID
     , CAST(NULL AS STRING)                                                                             AS COUPON_TITLE
     , CAST(NULL AS STRING)                                                                             AS COUPON_PUBLISH_TEAM_NM
     , CAST(NULL AS STRING)                                                                             AS COUPON_PUBLISH_PURPOSE_NM
     , CASE WHEN S.CROSS_SELL_FLAG IS NULL THEN 'N'
            ELSE S.CROSS_SELL_FLAG END                                                                  AS CROSS_SELL_FLAG
     , CASE WHEN S.BASIS_DATE >= '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 0.23
            WHEN S.BASIS_DATE < '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 0.3
            WHEN S.RESVE_ID LIKE '%ia%' THEN 0.5
            WHEN S.BASIS_DATE BETWEEN '2023-02-01' AND '2023-02-28' THEN 0.4
            ELSE 0.45 END                                                                               AS COMMISSION_RATE
     , S.COMMISSION_PRICE                                                                               AS SALES_COMMISSION_PRICE
     , S.PARTNER_SETTLE_TYPE
     , S.PARTNER_SALES_TYPE
     , S.PARTNERSHIP_CD
     , S.MARKETING_PARTNERSHIP_CD
     , CAST(NULL AS STRING)                                                                             AS PG_NM
     , S.SALES_KRW_PRICE
     , CASE WHEN S.BASIS_DATE >= '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 0.23 * S.SALES_KRW_PRICE
            WHEN S.BASIS_DATE < '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 0.3 * S.SALES_KRW_PRICE
            WHEN S.RESVE_ID LIKE '%ia%' THEN 0.5 * S.SALES_KRW_PRICE
            WHEN S.BASIS_DATE BETWEEN '2023-02-01' AND '2023-02-28' THEN 0.4 * S.SALES_KRW_PRICE
            ELSE 0.45 * S.SALES_KRW_PRICE END                                                           AS MRT_SALES_PRICE
     , CASE WHEN S.BASIS_DATE >= '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 1
            WHEN S.BASIS_DATE < '2022-07-01' AND (S.RESVE_ID LIKE 'io%' OR S.RESVE_ID LIKE 'in%') THEN 2
            WHEN S.RESVE_ID LIKE '%ia%' THEN 3
            WHEN S.BASIS_DATE BETWEEN '2023-02-01' AND '2023-02-28' THEN 4
            ELSE 99 END                                                                                 AS MRT_SALES_PRICE_TYPE
     , 0                                                                                                AS PRODUCT_COUPON_PRICE
     , 0                                                                                                AS ORDER_COUPON_PRICE
     , 0                                                                                                AS COUPON_PRICE
     , 0                                                                                                AS POINT_PRICE
     , 0                                                                                                AS EXCLUDED_POINT_PRICE
     , CAST(0 AS FLOAT64)                                                                               AS DISCOUNT_PRICE
     , CAST(0 AS FLOAT64)                                                                               AS CHANNEL_FEE_PRICE
     , 0                                                                                                AS AGENCY_FEE
     , 0                                                                                                AS MARKETING_PARTNER_FEE
     , CAST(0 AS FLOAT64)                                                                               AS AFFILIATE_POINT_FEE
     , CAST(NULL AS FLOAT64)                                                                            AS NET_PRICE
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                               AS DW_LOAD_DT
FROM {{ ref('MART_SALE_D') }} S
LEFT JOIN {{ ref('MART_USER_D') }} U ON S.USER_ID = U.USER_ID
LEFT JOIN {{ source('partners', 'partner') }} PO ON S.PARTNER_ID = CAST(PO.ID AS STRING)
LEFT JOIN {{ source('partners', 'partner_account') }} A ON PO.id = A.partner_id AND A.type = 'MASTER'
LEFT JOIN {{ ref('FPNA_CATEGORY_INFO') }} FC ON S.STANDARD_CATEGORY_LV_3_CD = FC.LV_3_CD
LEFT JOIN RSV_CANCEL RC ON S.RESVE_ID = RC.RESVE_ID
LEFT JOIN (SELECT DISTINCT partner_id, MAX(accounting_project_code) AS accounting_project_code FROM {{ source('settles', 'partner_settlement_configs') }} GROUP BY 1) psc ON psc.partner_id = S.partner_id
WHERE S.KIND = 1
  AND S.STANDARD_CATEGORY_LV_1_CD IN ('INSURANCE')
