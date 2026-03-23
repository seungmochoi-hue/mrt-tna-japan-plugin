{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_BIZ_LOG_PID_CONVERSION_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day'
        },
        pre_hook="DELETE FROM {{ this }} WHERE BASIS_DATE IN ( '{{ var('start_date_kst') }}',  '{{ var('end_date_kst') }}' )"
    )
}}


WITH USER_LOGIN_TERM AS (
    SELECT basis_dt AS BASIS_DATE
         ,  pid AS PID
         ,  user_id AS USER_ID
         ,  CASE WHEN MIN(min_event_timestamp_kst) OVER (PARTITION BY basis_dt, pid) = min_event_timestamp_kst THEN TIMESTAMP(CONCAT(CAST(CAST(min_event_timestamp_kst AS DATE) AS STRING), ' 00:00:00')) ELSE min_event_timestamp_kst END  AS MIN_TIME
        ,  IFNULL(LAG(min_event_timestamp_kst) OVER (PARTITION BY basis_dt, pid ORDER BY min_event_timestamp_kst DESC), TIMESTAMP(CONCAT(CAST(CAST(min_event_timestamp_kst AS DATE) AS STRING), ' 23:59:59'))) AS MAX_TIME
    FROM {{ ref('DIM_BIZ_LOG_USER_MAPPING') }}
    WHERE basis_dt IN ('{{ var("start_date_kst") }}', '{{ var("end_date_kst") }}')
),
LOG_ROW AS (
    SELECT l.basis_dt AS BASIS_DATE
            ,  l.pid AS PID
            ,  u.USER_ID AS USER_ID
            ,  l.platform AS PLATFORM
            ,  l.item_id AS ITEM_ID
            ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_source'), udf.url_param(url, 'utm_source')) AS UTM_SOURCE
            ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_campaign'), udf.url_param(url, 'utm_campaign')) AS UTM_CAMPAIGN
            ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_medium'), udf.url_param(url, 'utm_medium')) AS UTM_MEDIUM
            ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_content'), udf.url_param(url, 'utm_content')) AS UTM_CONTENT
            ,  IFNULL(JSON_VALUE(utm, '$.recent_n_ad'), udf.url_param(url, 'n_ad')) AS N_AD
            ,  IFNULL(JSON_VALUE(utm, '$.recent_n_campaign_type'), udf.url_param(url, 'n_campaign_type')) AS N_CAMPAIGN_TYPE
            ,  CASE WHEN l.screen_name IN ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail') THEN l.event_timestamp_kst ELSE NULL END AS OFFER_DETAIL
            ,  CASE WHEN l.screen_name IN ('purchase', 'checkout') AND l.event_name IN ('purchase', 'checkout') THEN l.event_timestamp_kst ELSE NULL END AS CHECKOUT
            ,  CASE WHEN l.screen_name IN ('purchase_complete', 'checkout_complete') AND l.event_name IN ('purchase_complete', 'checkout_complete') THEN l.event_timestamp_kst ELSE NULL END AS CHECKOUT_COMPLETE
            ,  CASE WHEN l.screen_name IN ('purchase_complete', 'checkout_complete') AND l.event_name IN ('purchase_complete', 'checkout_complete') THEN l.ds.reservation_id ELSE NULL END AS CHECKOUT_COMPLETE_RESVE_ID
    FROM {{ ref("DW_BIZ_LOG_VIEW") }} l
    LEFT JOIN USER_LOGIN_TERM u ON l.basis_dt = u.BASIS_DATE AND l.pid = u.PID AND l.event_timestamp_kst > u.MIN_TIME AND l.event_timestamp_kst <= u.MAX_TIME
    WHERE l.basis_dt IN  ('{{ var("start_date_kst") }}', '{{ var("end_date_kst") }}')
      AND l.event_type = 'pageview'
      AND l.screen_name IN ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail', 'purchase', 'checkout', 'purchase_complete', 'checkout_complete')
      AND l.ITEM_ID IS NOT NULL AND LENGTH(l.ITEM_ID) > 0
),
TODAY_FIRST_REF_URL AS (
    SELECT T.BASIS_DATE
        ,  T.PID
        ,  T.REF_URL
    FROM (
        SELECT l.basis_dt AS BASIS_DATE
            ,  l.pid AS PID
            ,  l.ref_url AS REF_URL
            ,  ROW_NUMBER() OVER (PARTITION BY l.basis_dt, l.pid ORDER BY l.event_timestamp_kst) AS RN
        FROM {{ ref("DW_BIZ_LOG_VIEW") }} l
        WHERE l.basis_dt IN ('{{ var("start_date_kst") }}', '{{ var("end_date_kst") }}')
        ) T
    WHERE T.RN = 1
),
OFFER_DETAIL_REF_URL AS (
    SELECT T.BASIS_DATE
            ,  T.PID
            ,  T.ITEM_ID
            ,  T.REF_URL
    FROM (
        SELECT l.basis_dt AS BASIS_DATE
            ,  l.pid AS PID
            ,  l.item_id AS ITEM_ID
            ,  l.ref_url AS REF_URL
            ,  ROW_NUMBER() OVER (PARTITION BY l.basis_dt, l.pid, l.item_id order by l.event_timestamp_kst) as RN
        FROM {{ ref("DW_BIZ_LOG_VIEW") }} l
        WHERE l.basis_dt IN ('{{ var("start_date_kst") }}', '{{ var("end_date_kst") }}')
          AND l.event_type = 'pageview' AND l.screen_name in ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'package_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'esim_offer_detail')
        ) T
    WHERE T.RN = 1
      AND T.REF_URL IS NOT NULL
),
LOG_ROW_WITH_MIN AS (
    SELECT L.BASIS_DATE
         , L.PID
         , L.USER_ID
         , L.PLATFORM
         , L.ITEM_ID
         , L.UTM_SOURCE
         , L.UTM_CAMPAIGN
         , L.UTM_MEDIUM
         , L.UTM_CONTENT
         , L.N_AD
         , L.N_CAMPAIGN_TYPE
         , MIN(L.OFFER_DETAIL) AS OFFER_DETAIL_MIN
         , MIN(L.CHECKOUT) AS CHECKOUT_MIN
    FROM LOG_ROW L
    GROUP BY L.BASIS_DATE, L.PID, L.USER_ID, L.PLATFORM, L.ITEM_ID, L.UTM_SOURCE, L.UTM_CAMPAIGN, L.UTM_MEDIUM, L.UTM_CONTENT, L.N_AD, L.N_CAMPAIGN_TYPE
),
DISTINCT_PID_WITHOUT_TIMESTAMP AS (
    SELECT L.BASIS_DATE AS BASIS_DATE
        ,  L.PID AS PID
        ,  L.USER_ID AS USER_ID
        ,  L.PLATFORM AS PLATFORM
        ,  L.ITEM_ID AS ITEM_ID
        ,  L.UTM_SOURCE AS UTM_SOURCE
        ,  L.UTM_CAMPAIGN AS UTM_CAMPAIGN
        ,  L.UTM_MEDIUM AS UTM_MEDIUM
        ,  L.UTM_CONTENT AS UTM_CONTENT
        ,  L.N_AD AS N_AD
        ,  L.N_CAMPAIGN_TYPE AS N_CAMPAIGN_TYPE
        ,  MIN(L.OFFER_DETAIL) AS OFFER_DETAIL
        ,  MIN(L.CHECKOUT) AS CHECKOUT
        ,  MIN(CASE WHEN L.CHECKOUT > M.OFFER_DETAIL_MIN THEN L.CHECKOUT ELSE NULL END) AS WITH_EVENT_CHECKOUT
        ,  MIN(L.CHECKOUT_COMPLETE) AS CHECKOUT_COMPLETE
        ,  MIN(CASE WHEN L.CHECKOUT_COMPLETE > M.CHECKOUT_MIN THEN L.CHECKOUT_COMPLETE ELSE NULL END) AS WITH_EVENT_CHECKOUT_COMPLETE
        ,  MIN(L.CHECKOUT_COMPLETE_RESVE_ID) AS CHECKOUT_COMPLETE_RESVE_ID
    FROM LOG_ROW L
    LEFT JOIN LOG_ROW_WITH_MIN M ON L.BASIS_DATE = M.BASIS_DATE
                                AND L.PID = M.PID
                                AND (L.USER_ID = M.USER_ID OR (L.USER_ID IS NULL AND M.USER_ID IS NULL))
                                AND (L.PLATFORM = M.PLATFORM OR (L.PLATFORM IS NULL AND M.PLATFORM IS NULL))
                                AND (L.ITEM_ID = M.ITEM_ID OR (L.ITEM_ID IS NULL AND M.ITEM_ID IS NULL))
                                AND (L.UTM_SOURCE = M.UTM_SOURCE OR (L.UTM_SOURCE IS NULL AND M.UTM_SOURCE IS NULL))
                                AND (L.UTM_CAMPAIGN = M.UTM_CAMPAIGN OR (L.UTM_CAMPAIGN IS NULL AND M.UTM_CAMPAIGN IS NULL))
                                AND (L.UTM_MEDIUM = M.UTM_MEDIUM OR (L.UTM_MEDIUM IS NULL AND M.UTM_MEDIUM IS NULL))
                                AND (L.UTM_CONTENT = M.UTM_CONTENT OR (L.UTM_CONTENT IS NULL AND M.UTM_CONTENT IS NULL))
                                AND (L.N_AD = M.N_AD OR (L.N_AD IS NULL AND M.N_AD IS NULL))
                                AND (L.N_CAMPAIGN_TYPE = M.N_CAMPAIGN_TYPE OR (L.N_CAMPAIGN_TYPE IS NULL AND M.N_CAMPAIGN_TYPE IS NULL))
    GROUP BY L.BASIS_DATE, L.PID, L.USER_ID, L.PLATFORM, L.ITEM_ID, L.UTM_SOURCE, L.UTM_CAMPAIGN, L.UTM_MEDIUM, L.UTM_CONTENT, L.N_AD, L.N_CAMPAIGN_TYPE
)
SELECT L.BASIS_DATE AS BASIS_DATE
    ,  L.PID AS PID
    ,  L.USER_ID AS USER_ID
    ,  L.PLATFORM AS PLATFORM
    ,  L.ITEM_ID AS ITEM_ID
    ,  R.REF_URL AS REF_URL
    ,  L.UTM_SOURCE AS UTM_SOURCE
    ,  L.UTM_CAMPAIGN AS UTM_CAMPAIGN
    ,  L.UTM_MEDIUM AS UTM_MEDIUM
    ,  L.UTM_CONTENT AS UTM_CONTENT
    ,  L.N_AD AS N_AD
    ,  L.N_CAMPAIGN_TYPE AS N_CAMPAIGN_TYPE
    ,  D.REF_URL AS OFFER_DETAIL_REF_URL
    ,  CASE WHEN L.OFFER_DETAIL IS NOT NULL THEN 1 ELSE 0 END AS OFFER_DETAIL_FLAG
    ,  L.OFFER_DETAIL AS OFFER_DETAIL_FIRST_ACCESS_DT
    ,  CASE WHEN L.CHECKOUT IS NOT NULL THEN 1 ELSE 0 END AS CHECKOUT_FLAG
    ,  L.CHECKOUT AS CHECKOUT_FIRST_ACCESS_DT
    ,  CASE WHEN L.WITH_EVENT_CHECKOUT IS NOT NULL THEN 1 ELSE 0 END AS WITH_EVENT_CHECKOUT_FLAG
    ,  L.WITH_EVENT_CHECKOUT AS WITH_EVENT_CHECKOUT_FIRST_ACCESS_DT
    ,  CASE WHEN L.CHECKOUT_COMPLETE IS NOT NULL THEN 1 ELSE 0 END AS CHECKOUT_COMPLETE_FLAG
    ,  L.CHECKOUT_COMPLETE AS CHECKOUT_COMPLETE_FIRST_ACCESS_DT
    ,  CASE WHEN L.WITH_EVENT_CHECKOUT_COMPLETE IS NOT NULL THEN 1 ELSE 0 END AS WITH_EVENT_CHECKOUT_COMPLETE_FLAG
    ,  L.WITH_EVENT_CHECKOUT_COMPLETE AS WITH_EVENT_CHECKOUT_COMPLETE_FIRST_ACCESS_DT
    ,  L.CHECKOUT_COMPLETE_RESVE_ID AS CHECKOUT_COMPLETE_RESVE_ID
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM DISTINCT_PID_WITHOUT_TIMESTAMP L
LEFT JOIN TODAY_FIRST_REF_URL R ON L.BASIS_DATE = R.BASIS_DATE AND L.PID = R.PID
LEFT JOIN OFFER_DETAIL_REF_URL D ON L.BASIS_DATE = D.BASIS_DATE AND L.PID = D.PID AND L.ITEM_ID = D.ITEM_ID