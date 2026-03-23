{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PARTNER_ORIGINAL_D'
    )
}}


WITH FIRST_SQL AS (
    SELECT CAST(G.id AS STRING)                         AS PARTNER_ID
         , U.username                                   AS PARTNER_NAME
         , '2.0 SOURCE'                                 AS PARTNER_SOURCE
         , IF(G.COMPANY = TRUE, 'Y', 'N')               AS COMPANY_FLAG
         , GT.company_name                              AS COMPANY_NM
         , GT.representative_name                       AS REPRESENTATIVE_NM
         , G.business_license_number                    AS BUSINESS_LICENSE_NUMBER
         , G.user_id                                    AS USER_ID
         , U.email                                      AS EMAIL
         , GT.email                                     AS TAX_INVOICE_EMAIL
         , G.commission_rate                            AS COMMISSION_RATE
         , G.status                                     AS PARTNER_STATUS
         , G.profit_currency_code                       AS PROFIT_CURRENCY_CODE
         , G.allow_message                              AS ALLOW_MESSAGE
         , G.subscription_settings                      AS SUBSCRIPTION_SETTING
         , G.current_visa_status                        AS CURRENT_VISA_STATUS
         , G.length_of_residence                        AS LENGTH_OF_RESIDENCE
         , G.settle_type                                AS SETTLE_TYPE
         , G.sales_type                                 AS SALES_TYPE
         , CAST(G.created_at_kst  AS DATE)              AS CREATE_KST_DATE
         , G.created_at_kst AS CREATE_KST_DT
         , CAST(G.updated_at_kst AS DATE)               AS UPDATE_KST_DATE
         , CAST(G.first_activated_at_kst  AS DATE)      AS FIRST_ACTIVATED_KST_DATE
         , CAST(G.current_activated_at_kst  AS DATE)    AS CURRENT_ACTIVATED_KST_DATE
         , CAST(G.notice_read_at_kst  AS DATE)          AS NOTICE_READ_KST_DATE
         , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
    FROM {{ source('mrt_20', 'guides') }} G
    LEFT JOIN {{ source('members', 'users') }} U ON G.user_id = U.id
    LEFT JOIN {{ source('mrt_20', 'guide_tax_invoice_infos') }} GT ON G.id = GT.guide_id
    WHERE G.deleted_at_kst IS NULL
),
SECOND_SQL AS (
    SELECT CAST(p.id AS STRING) AS PARTNER_ID
         , p.nickname AS PARTNER_NAME
         , '3.0 SOURCE'                                 AS PARTNER_SOURCE
         , CAST(NULL AS STRING) AS COMPANY_FLAG -- 사업자 등록 여부 기반
         , p.company_name AS COMPANY_NM
         , p.representative_name AS REPRESENTATIVE_NM
         , p.business_registration_number AS BUSINESS_LICENSE_NUMBER
         , CAST(NULL AS INT64) AS USER_ID -- 신규 테이블에서 해당 정보 없음
         , p.email AS EMAIL
         , CAST(NULL AS STRING) AS TAX_INVOICE_EMAIL -- 신규 테이블에서 해당 정보 없음
         , CAST(NULL AS FLOAT64) AS COMMISSION_RATE -- 신규 테이블에서 해당 정보 없음
         , LOWER(p.status) AS PARTNER_STATUS
         , CAST(NULL AS STRING) AS PROFIT_CURRENCY_CODE -- 신규 테이블에서 해당 정보 없음
         , CAST(pc.push_notification AS BOOL) AS ALLOW_MESSAGE
         , CONCAT(
            '{"push": "', IF(pc.push_notification, 'true', 'false'),
            '", "email": "', IF(pc.email_notification, 'true', 'false'), '"}'
           ) AS SUBSCRIPTION_SETTING -- JSON 형식 변환
         , CAST(NULL AS STRING) AS CURRENT_VISA_STATUS -- 신규 테이블에서 해당 정보 없음
         , CAST(NULL AS STRING) AS LENGTH_OF_RESIDENCE -- 신규 테이블에서 해당 정보 없음
         , CAST(NULL AS STRING) AS SETTLE_TYPE -- 신규 테이블에서 해당 정보 없음
         , CAST(NULL AS STRING) AS SALES_TYPE -- 신규 테이블에서 해당 정보 없음
         , DATE(p.created_at) AS CREATE_KST_DATE
         , p.created_at AS CREATE_KST_DT
         , DATE(p.modified_at) AS UPDATE_KST_DATE
         , DATE(p.first_activated_at) AS FIRST_ACTIVATED_KST_DATE
         , DATE(p.recent_activated_at) AS CURRENT_ACTIVATED_KST_DATE
         , CAST(NULL AS DATE) AS NOTICE_READ_KST_DATE -- 신규 테이블에서 해당 정보 없음
         , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
    FROM {{ source('partners', 'partner') }} p
    LEFT JOIN {{ source('partners', 'partner_contact') }} pc ON p.id = pc.partner_id
    LEFT JOIN FIRST_SQL o ON o.PARTNER_ID = CAST(p.id AS STRING)
    WHERE o.PARTNER_ID IS NULL
)

SELECT * FROM FIRST_SQL
UNION ALL
SELECT * FROM SECOND_SQL

