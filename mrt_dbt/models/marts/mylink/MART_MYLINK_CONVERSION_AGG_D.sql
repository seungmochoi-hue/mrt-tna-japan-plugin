{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_MYLINK_CONVERSION_AGG_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

{% set mylink_log_item_flag_expr = "CASE WHEN L.ITEM_ID = CAST(S.gid AS STRING) THEN 'Y' ELSE 'N' END" %}
{% set mylink_sale_gid_flag_expr = "CASE WHEN S.GID = CAST(U.gid AS STRING) THEN 'Y' ELSE 'N' END" %}
{% set mylink_domain_case_expr = "CASE WHEN L.ITEM_ID = 'AIR' THEN 'AIR' ELSE '3.0 PRODUCT' END" %}
{% set mylink_platform_map_expr = "CASE WHEN S.PLATFORM = 'web_android' THEN 'aos_mweb' WHEN S.PLATFORM = 'ios_traveler' THEN 'ios' WHEN S.PLATFORM = 'web_desktop' THEN 'web' WHEN S.PLATFORM = 'web_ios' THEN 'ios_mweb' WHEN S.PLATFORM = 'android_traveler' THEN 'aos' END" %}

{% set purchase_configs = [
    {
        'item_id_expr': 'CAST(L.ITEM_ID AS STRING)',
        'domain_nm_expr': "'3.0 PRODUCT'",
        'platform_expr': 'L.PLATFORM',
        'mylink_item_flag_expr': mylink_log_item_flag_expr,
        'extra_where': "AND L.ITEM_ID <> 'AIR'",
        'group_by': ['L.ITEM_ID', 'L.MYLINK_ID', mylink_log_item_flag_expr, 'L.PLATFORM']
    },
    {
        'item_id_expr': 'CAST(L.ITEM_ID AS STRING)',
        'domain_nm_expr': "'3.0 PRODUCT'",
        'platform_expr': "'TOTAL'",
        'mylink_item_flag_expr': mylink_log_item_flag_expr,
        'extra_where': "AND L.ITEM_ID <> 'AIR'",
        'group_by': ['L.ITEM_ID', 'L.MYLINK_ID', mylink_log_item_flag_expr]
    },
    {
        'item_id_expr': "'TOTAL'",
        'domain_nm_expr': mylink_domain_case_expr,
        'platform_expr': 'L.PLATFORM',
        'mylink_item_flag_expr': "'N'",
        'extra_where': '',
        'group_by': [mylink_domain_case_expr, 'L.MYLINK_ID', 'L.PLATFORM']
    },
    {
        'item_id_expr': "'TOTAL'",
        'domain_nm_expr': mylink_domain_case_expr,
        'platform_expr': "'TOTAL'",
        'mylink_item_flag_expr': "'N'",
        'extra_where': '',
        'group_by': [mylink_domain_case_expr, 'L.MYLINK_ID']
    }
] %}

{% set sale_configs = [
    {
        'gid_expr': 'S.GID',
        'domain_nm_expr': 'S.DOMAIN_NM',
        'platform_expr': mylink_platform_map_expr,
        'mylink_item_flag_expr': mylink_sale_gid_flag_expr,
        'domain_where': "S.DOMAIN_NM = '3.0 PRODUCT'",
        'group_by': ['S.MARKETING_LINK_ID', 'S.GID', 'S.DOMAIN_NM', 'S.PLATFORM', mylink_sale_gid_flag_expr]
    },
    {
        'gid_expr': 'S.GID',
        'domain_nm_expr': 'S.DOMAIN_NM',
        'platform_expr': "'TOTAL'",
        'mylink_item_flag_expr': mylink_sale_gid_flag_expr,
        'domain_where': "S.DOMAIN_NM = '3.0 PRODUCT'",
        'group_by': ['S.MARKETING_LINK_ID', 'S.GID', 'S.DOMAIN_NM', mylink_sale_gid_flag_expr]
    },
    {
        'gid_expr': "'TOTAL'",
        'domain_nm_expr': 'S.DOMAIN_NM',
        'platform_expr': mylink_platform_map_expr,
        'mylink_item_flag_expr': "'N'",
        'domain_where': "S.DOMAIN_NM IN ('AIR', '3.0 PRODUCT')",
        'group_by': ['S.MARKETING_LINK_ID', 'S.DOMAIN_NM', 'S.PLATFORM']
    },
    {
        'gid_expr': "'TOTAL'",
        'domain_nm_expr': 'S.DOMAIN_NM',
        'platform_expr': "'TOTAL'",
        'mylink_item_flag_expr': "'N'",
        'domain_where': "S.DOMAIN_NM IN ('3.0 PRODUCT', 'AIR')",
        'group_by': ['S.MARKETING_LINK_ID', 'S.DOMAIN_NM']
    }
] %}

WITH INCOMING_LOG_PID_DT AS (
    SELECT L.PID
        ,  L.ITEM_ID
        ,  L.MYLINK_ID
        ,  MIN(L.OFFER_DETAIL_KST_DT) AS INCOMING_KST_DT
    FROM {{ ref('MART_BIZ_LOG_MYLINK_ROW_D') }} L
    WHERE L.BASIS_DATE BETWEEN '{{ var('before_30_days_kst') }}' AND '{{ var("logical_start_date_kst") }}'
    GROUP BY L.PID, L.ITEM_ID, L.MYLINK_ID
),
PURCHASE_PID_DT AS (
{% for c in purchase_configs %}
    {{ mylink_conversion_purchase_select(c['item_id_expr'], c['domain_nm_expr'], c['platform_expr'], c['mylink_item_flag_expr'], c['extra_where'], c['group_by']) }}
    {% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
), 
MART_SALE_D AS (
WITH COMMISION_PRICE AS (
    SELECT P.reservation_no AS RESVE_ID
          , CASE WHEN P.closing_type = 'PAYMENT' THEN 1 
                 WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END AS KIND 
          , SUM(P.marketing_partnership_commission) AS SALE_COMMISSION_PRICE
     FROM {{ source('settles', 'payment_product_closing') }} P
     WHERE P.payment_date >= '{{ var('before_30_days_kst') }}'
       AND P.closing_type IN ('PAYMENT', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND')
       AND P.deleted_at IS NULL
    GROUP BY P.reservation_no, CASE WHEN P.closing_type = 'PAYMENT' THEN 1
                                    WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END

    UNION ALL

    SELECT P.reservation_no AS RESVE_ID
         , CASE WHEN P.closing_type = 'PAYMENT' THEN 1
                WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END AS KIND
         , SUM(P.partnership_commission) AS SALE_COMMISSION_PRICE
    FROM {{ source('settles','partnership_settlement_product_closing') }} P
    LEFT JOIN {{ source('settles','payment_product_closing') }} PP ON P.reservation_no = PP.reservation_no
    WHERE P.partnership_type = 'MARKETING'
      AND P.PRODUCT_TYPE != 'FLIGHT'
    AND p.deleted_at IS NULL
    AND PP.id IS NULL
    AND P.settlement_date >= '{{ var('before_30_days_kst') }}' -- date(P.created_at)
    AND P.closing_type IN ('PAYMENT', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND')
    GROUP BY P.reservation_no, CASE WHEN P.closing_type = 'PAYMENT' THEN 1
                                WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END

    UNION ALL

    SELECT concat('f', reservation_id) AS RESVE_ID
         , CASE WHEN P.closing_type = 'PAYMENT' THEN 1
                WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END AS KIND
         , SUM(P.marketing_partnership_commission) AS SALE_COMMISSION_PRICE
    FROM {{ source('settles','flight_payment_product_closing') }} P
    WHERE P.payment_date >= '{{ var('before_30_days_kst') }}'
      AND P.closing_type IN ('PAYMENT', 'PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND')
      AND P.deleted_at IS NULL
    GROUP BY concat('f', reservation_id), CASE WHEN P.closing_type = 'PAYMENT' THEN 1
                                               WHEN P.closing_type IN ('PARTIAL_REFUND', 'PARTIAL_REFUND_AFTER_FINISH', 'REFUND') THEN 2 END
)
{% for c in sale_configs %}
    {{ mylink_conversion_sale_select(c['gid_expr'], c['domain_nm_expr'], c['platform_expr'], c['mylink_item_flag_expr'], c['domain_where'], c['group_by']) }}
    {% if not loop.last %}UNION ALL{% endif %}
{% endfor %}
)
SELECT CAST(L.BASIS_DATE AS DATE) AS BASIS_DATE
     , CAST(L.MYLINK_ID AS STRING) AS MYLINK_ID
     , CAST(L.ITEM_ID AS STRING) AS GID

     , L.DOMAIN_NM AS DOMAIN_NM
     , L.PLATFORM AS PLATFORM
     , L.MYLINK_ITEM_FLAG AS MYLINK_ITEM_FLAG

     , L.TODAY_OFFER_DETAIL AS TODAY_OFFER_DETAIL_CNT
     , L.TODAY_CHECKOUT AS TODAY_CHECKOUT_CNT
     , L.TODAY_CHECKOUT_COMPLETE AS TODAY_CHECKOUT_COMPLETE_CNT
     , L.TODAY_CHECKOUT_WITHOUT_INFLOW AS TODAY_CHECKOUT_WITHOUT_INFLOW_CNT
     , L.TODAY_CHECKOUT_COMPLETE_WITHOUT_INFLOW AS TODAY_CHECKOUT_COMPLETE_WITHOUT_INFLOW_CNT

     , L.WEEKLY_OFFER_DETAIL AS WEEKLY_OFFER_DETAIL_CNT
     , L.WEEKLY_CHECKOUT AS WEEKLY_CHECKOUT_CNT
     , L.WEEKLY_CHECKOUT_COMPLETE AS WEEKLY_CHECKOUT_COMPLETE_CNT
     , L.WEEKLY_CHECKOUT_WITHOUT_INFLOW AS WEEKLY_CHECKOUT_WITHOUT_INFLOW_CNT
     , L.WEEKLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW AS WEEKLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW_CNT

     , L.MONTHLY_OFFER_DETAIL AS MONTHLY_OFFER_DETAIL_CNT
     , L.MONTHLY_CHECKOUT AS MONTHLY_CHECKOUT_CNT
     , L.MONTHLY_CHECKOUT_COMPLETE AS MONTHLY_CHECKOUT_COMPLETE_CNT
     , L.MONTHLY_CHECKOUT_WITHOUT_INFLOW AS MONTHLY_CHECKOUT_WITHOUT_INFLOW_CNT
     , L.MONTHLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW AS MONTHLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW_CNT

     , IFNULL(S.TODAY_RESVE_USER_CNT, 0) AS TODAY_RESVE_USER_CNT
     , IFNULL(S.TODAY_RESVE_QUANTITY_CNT, 0) AS TODAY_RESVE_QUANTITY_CNT
     , IFNULL(S.TODAY_SALE_QUANTITY_CNT, 0) AS TODAY_SALE_QUANTITY_CNT
     , IFNULL(S.TODAY_SALE_PRICE, 0) AS TODAY_SALE_PRICE
     , IFNULL(S.TODAY_SALE_COMMISSION_PRICE, 0) AS TODAY_SALE_COMMISSION_PRICE

     , IFNULL(S.TODAY_CANCEL_RESVE_USER_CNT, 0) AS TODAY_CANCEL_RESVE_USER_CNT
     , IFNULL(S.TODAY_CANCEL_RESVE_QUANTITY_CNT, 0) AS TODAY_CANCEL_RESVE_QUANTITY_CNT
     , IFNULL(S.TODAY_CANCEL_SALE_QUANTITY_CNT, 0) AS TODAY_CANCEL_SALE_QUANTITY_CNT
     , IFNULL(S.TODAY_CANCEL_SALE_PRICE, 0) AS TODAY_CANCEL_SALE_PRICE
     , IFNULL(S.TODAY_CANCEL_SALE_COMMISSION_PRICE, 0) AS TODAY_CANCEL_SALE_COMMISSION_PRICE

     , IFNULL(S.WEEKLY_RESVE_USER_CNT, 0) AS WEEKLY_RESVE_USER_CNT
     , IFNULL(S.WEEKLY_RESVE_QUANTITY_CNT, 0) AS WEEKLY_RESVE_QUANTITY_CNT
     , IFNULL(S.WEEKLY_SALE_QUANTITY_CNT, 0) AS WEEKLY_SALE_QUANTITY_CNT
     , IFNULL(S.WEEKLY_SALE_PRICE, 0) AS WEEKLY_SALE_PRICE
     , IFNULL(S.WEEKLY_SALE_COMMISSION_PRICE, 0) AS WEEKLY_SALE_COMMISSION_PRICE

     , IFNULL(S.WEEKLY_CANCEL_RESVE_USER_CNT, 0) AS WEEKLY_CANCEL_RESVE_USER_CNT
     , IFNULL(S.WEEKLY_CANCEL_RESVE_QUANTITY_CNT, 0) AS WEEKLY_CANCEL_RESVE_QUANTITY_CNT
     , IFNULL(S.WEEKLY_CANCEL_SALE_QUANTITY_CNT, 0) AS WEEKLY_CANCEL_SALE_QUANTITY_CNT
     , IFNULL(S.WEEKLY_CANCEL_SALE_PRICE, 0) AS WEEKLY_CANCEL_SALE_PRICE
     , IFNULL(S.WEEKLY_CANCEL_SALE_COMMISSION_PRICE, 0) AS WEEKLY_CANCEL_SALE_COMMISSION_PRICE

     , IFNULL(S.MONTHLY_RESVE_USER_CNT, 0) AS MONTHLY_RESVE_USER_CNT
     , IFNULL(S.MONTHLY_RESVE_QUANTITY_CNT, 0) AS MONTHLY_RESVE_QUANTITY_CNT
     , IFNULL(S.MONTHLY_SALE_QUANTITY_CNT, 0) AS MONTHLY_SALE_QUANTITY_CNT
     , IFNULL(S.MONTHLY_SALE_PRICE, 0) AS MONTHLY_SALE_PRICE
     , IFNULL(S.MONTHLY_SALE_COMMISSION_PRICE, 0) AS MONTHLY_SALE_COMMISSION_PRICE

     , IFNULL(S.MONTHLY_CANCEL_RESVE_USER_CNT, 0) AS MONTHLY_CANCEL_RESVE_USER_CNT
     , IFNULL(S.MONTHLY_CANCEL_RESVE_QUANTITY_CNT, 0) AS MONTHLY_CANCEL_RESVE_QUANTITY_CNT
     , IFNULL(S.MONTHLY_CANCEL_SALE_QUANTITY_CNT, 0) AS MONTHLY_CANCEL_SALE_QUANTITY_CNT
     , IFNULL(S.MONTHLY_CANCEL_SALE_PRICE, 0) AS MONTHLY_CANCEL_SALE_PRICE
     , IFNULL(S.MONTHLY_CANCEL_SALE_COMMISSION_PRICE, 0) AS MONTHLY_CANCEL_SALE_COMMISSION_PRICE

     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM PURCHASE_PID_DT L
LEFT JOIN MART_SALE_D S ON L.MYLINK_ID = S.MARKETING_LINK_ID AND L.ITEM_ID = S.GID AND L.MYLINK_ITEM_FLAG = S.MYLINK_ITEM_FLAG AND L.PLATFORM = S.PLATFORM AND L.DOMAIN_NM = S.DOMAIN_NM
