{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='business',
        alias='MART_BIZ_LOG_PID_PROMOTION_CONVERSION_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


WITH USER_LOGIN_TERM AS (
    SELECT basis_dt AS BASIS_DATE
         ,  pid AS PID
         ,  user_id AS USER_ID
         ,  CASE WHEN MIN(min_event_timestamp_kst) OVER (PARTITION BY basis_dt, pid) = min_event_timestamp_kst THEN TIMESTAMP(CONCAT(CAST(CAST(min_event_timestamp_kst AS DATE) AS STRING), ' 00:00:00')) ELSE min_event_timestamp_kst END  AS MIN_TIME
        ,  IFNULL(LAG(min_event_timestamp_kst) OVER (PARTITION BY basis_dt, pid ORDER BY min_event_timestamp_kst DESC), TIMESTAMP(CONCAT(CAST(CAST(min_event_timestamp_kst AS DATE) AS STRING), ' 23:59:59'))) AS MAX_TIME
FROM {{ ref('DIM_BIZ_LOG_USER_MAPPING') }}
WHERE basis_dt = '{{ var("logical_start_date_kst") }}'
),
LOG_ROW AS (
SELECT L.basis_dt AS BASIS_DATE
        ,  L.pid AS PID
        ,  U.USER_ID AS USER_ID
        ,  L.platform AS PLATFORM
        ,  L.ds.campaign_id AS CAMPAIGN_ID
        ,  L.ITEM_ID
        ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_source'), udf.url_param(url, 'utm_source')) AS UTM_SOURCE
        ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_campaign'), udf.url_param(url, 'utm_campaign')) AS UTM_CAMPAIGN
        ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_medium'), udf.url_param(url, 'utm_medium')) AS UTM_MEDIUM
        ,  IFNULL(JSON_VALUE(utm, '$.recent_utm_content'), udf.url_param(url, 'utm_content')) AS UTM_CONTENT
        ,  IFNULL(JSON_VALUE(utm, '$.recent_n_ad'), udf.url_param(url, 'n_ad')) AS N_AD
        ,  IFNULL(JSON_VALUE(utm, '$.recent_n_campaign_type'), udf.url_param(url, 'n_campaign_type')) AS N_CAMPAIGN_TYPE
        ,  CASE WHEN L.screen_name IN ('promotion_detail') THEN L.event_timestamp_kst ELSE NULL END AS PROMOTION_DETAIL
        ,  CASE WHEN L.screen_name IN ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail') THEN L.event_timestamp_kst ELSE NULL END AS OFFER_DETAIL
        ,  CASE WHEN L.screen_name IN ('purchase', 'checkout') AND L.event_name IN ('purchase', 'checkout') THEN L.event_timestamp_kst ELSE NULL END AS CHECKOUT
        ,  CASE WHEN L.screen_name IN ('purchase_complete', 'checkout_complete') AND L.event_name IN ('purchase_complete', 'checkout_complete') THEN L.event_timestamp_kst ELSE NULL END AS CHECKOUT_COMPLETE
FROM {{ ref('DW_BIZ_LOG_VIEW') }} L
LEFT JOIN USER_LOGIN_TERM U ON L.basis_dt = U.BASIS_DATE AND L.pid = U.PID AND L.event_timestamp_kst > U.MIN_TIME AND L.event_timestamp_kst <= U.MAX_TIME
WHERE L.basis_dt = '{{ var("logical_start_date_kst") }}'
  AND L.event_type = 'pageview'
  AND L.screen_name IN ('promotion_detail', 'offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail', 'purchase', 'checkout', 'purchase_complete', 'checkout_complete')
--AND L.ds.campaign_id IS NOT NULL AND LENGTH(L.ds.campaign_id) > 0
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
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
    WHERE l.basis_dt = '{{ var("logical_start_date_kst") }}'
    ) T
WHERE T.RN = 1
    ),
    PROMOTION_DETAIL_REF_URL AS (
SELECT T.BASIS_DATE
        ,  T.PID
        ,  T.CAMPAIGN_ID
        ,  T.REF_URL
FROM (
    SELECT l.basis_dt AS BASIS_DATE
        ,  l.pid AS PID
        ,  l.ds.campaign_id AS CAMPAIGN_ID
        ,  l.ref_url AS REF_URL
        ,  ROW_NUMBER() OVER (PARTITION BY l.basis_dt, l.pid, l.ds.campaign_id ORDER BY l.event_timestamp_kst) AS RN
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
    WHERE l.basis_dt = '{{ var("logical_start_date_kst") }}'
    AND l.event_type = 'pageview' AND l.screen_name IN ('promotion_detail')
    ) T
WHERE T.RN = 1
    ),
    LOG_ROW_WITH_MIN AS (
SELECT L.BASIS_DATE
        , L.PID
        , L.USER_ID
        , L.PLATFORM
        , L.CAMPAIGN_ID
        , L.UTM_SOURCE
        , L.UTM_CAMPAIGN
        , L.UTM_MEDIUM
        , L.UTM_CONTENT
        , L.N_AD
        , L.N_CAMPAIGN_TYPE
        , MIN(L.PROMOTION_DETAIL) AS PROMOTION_DETAIL_MIN
        , MIN(L.CHECKOUT) AS CHECKOUT_MIN
FROM LOG_ROW L
GROUP BY L.BASIS_DATE, L.PID, L.USER_ID, L.PLATFORM, L.CAMPAIGN_ID, L.UTM_SOURCE, L.UTM_CAMPAIGN, L.UTM_MEDIUM, L.UTM_CONTENT, L.N_AD, L.N_CAMPAIGN_TYPE
    ),
    DISTINCT_PID_WITHOUT_TIMESTAMP AS (
SELECT L.BASIS_DATE AS BASIS_DATE
        ,  L.PID AS PID
        ,  L.USER_ID AS USER_ID
        ,  L.PLATFORM AS PLATFORM
        ,  L.CAMPAIGN_ID AS CAMPAIGN_ID
        ,  L.UTM_SOURCE AS UTM_SOURCE
        ,  L.UTM_CAMPAIGN AS UTM_CAMPAIGN
        ,  L.UTM_MEDIUM AS UTM_MEDIUM
        ,  L.UTM_CONTENT AS UTM_CONTENT
        ,  L.N_AD AS N_AD
        ,  L.N_CAMPAIGN_TYPE AS N_CAMPAIGN_TYPE
        ,  M.PROMOTION_DETAIL_MIN AS PROMOTION_DETAIL
        ,  C.ITEM_ID
        ,  MIN(C.OFFER_DETAIL) AS OFFER_DETAIL
        ,  MIN(CASE WHEN C.OFFER_DETAIL > M.PROMOTION_DETAIL_MIN THEN C.OFFER_DETAIL ELSE NULL END) AS WITH_EVENT_OFFER_DETAIL
        ,  MIN(C.CHECKOUT) AS CHECKOUT
        ,  MIN(CASE WHEN C.CHECKOUT > M.PROMOTION_DETAIL_MIN THEN C.CHECKOUT ELSE NULL END) AS WITH_EVENT_CHECKOUT
        ,  MIN(C.CHECKOUT_COMPLETE) AS CHECKOUT_COMPLETE
        ,  MIN(CASE WHEN C.CHECKOUT_COMPLETE > M.PROMOTION_DETAIL_MIN THEN C.CHECKOUT_COMPLETE ELSE NULL END) AS WITH_EVENT_CHECKOUT_COMPLETE
FROM (
    SELECT *
    FROM LOG_ROW
    WHERE CAMPAIGN_ID IS NOT NULL AND PROMOTION_DETAIL IS NOT NULL
    ) L
    LEFT JOIN (
    SELECT *
    FROM LOG_ROW
    WHERE OFFER_DETAIL IS NOT NULL OR CHECKOUT IS NOT NULL OR CHECKOUT_COMPLETE IS NOT NULL
    ) AS C
ON L.BASIS_DATE = C.BASIS_DATE
    AND L.PID = C.PID
    AND (L.UTM_SOURCE = C.UTM_SOURCE OR (L.UTM_SOURCE IS NULL AND C.UTM_SOURCE IS NULL))
    AND (L.UTM_CAMPAIGN = C.UTM_CAMPAIGN OR (L.UTM_CAMPAIGN IS NULL AND C.UTM_CAMPAIGN IS NULL))
    AND (L.UTM_MEDIUM = C.UTM_MEDIUM OR (L.UTM_MEDIUM IS NULL AND C.UTM_MEDIUM IS NULL))
    AND (L.UTM_CONTENT = C.UTM_CONTENT OR (L.UTM_CONTENT IS NULL AND C.UTM_CONTENT IS NULL))
    AND (L.N_AD = C.N_AD OR (L.N_AD IS NULL AND C.N_AD IS NULL))
    AND (L.N_CAMPAIGN_TYPE = C.N_CAMPAIGN_TYPE OR (L.N_CAMPAIGN_TYPE IS NULL AND C.N_CAMPAIGN_TYPE IS NULL))
    LEFT JOIN LOG_ROW_WITH_MIN M ON L.BASIS_DATE = M.BASIS_DATE
    AND L.PID = M.PID
    AND (L.USER_ID = M.USER_ID OR (L.USER_ID IS NULL AND M.USER_ID IS NULL))
    AND (L.PLATFORM = M.PLATFORM OR (L.PLATFORM IS NULL AND M.PLATFORM IS NULL))
    AND (L.CAMPAIGN_ID = M.CAMPAIGN_ID OR (L.CAMPAIGN_ID IS NULL AND M.CAMPAIGN_ID IS NULL))
    AND (L.UTM_SOURCE = M.UTM_SOURCE OR (L.UTM_SOURCE IS NULL AND M.UTM_SOURCE IS NULL))
    AND (L.UTM_CAMPAIGN = M.UTM_CAMPAIGN OR (L.UTM_CAMPAIGN IS NULL AND M.UTM_CAMPAIGN IS NULL))
    AND (L.UTM_MEDIUM = M.UTM_MEDIUM OR (L.UTM_MEDIUM IS NULL AND M.UTM_MEDIUM IS NULL))
    AND (L.UTM_CONTENT = M.UTM_CONTENT OR (L.UTM_CONTENT IS NULL AND M.UTM_CONTENT IS NULL))
    AND (L.N_AD = M.N_AD OR (L.N_AD IS NULL AND M.N_AD IS NULL))
    AND (L.N_CAMPAIGN_TYPE = M.N_CAMPAIGN_TYPE OR (L.N_CAMPAIGN_TYPE IS NULL AND M.N_CAMPAIGN_TYPE IS NULL))
GROUP BY L.BASIS_DATE, L.PID, L.USER_ID, L.PLATFORM, L.CAMPAIGN_ID, L.UTM_SOURCE, L.UTM_CAMPAIGN, L.UTM_MEDIUM, L.UTM_CONTENT, L.N_AD, L.N_CAMPAIGN_TYPE, M.PROMOTION_DETAIL_MIN, C.ITEM_ID
    )
SELECT L.BASIS_DATE AS BASIS_DATE
     ,  L.PID AS PID
     ,  L.USER_ID AS USER_ID
     ,  L.PLATFORM AS PLATFORM
     ,  L.CAMPAIGN_ID AS CAMPAIGN_ID
     ,  R.REF_URL AS REF_URL
     ,  L.UTM_SOURCE AS UTM_SOURCE
     ,  L.UTM_CAMPAIGN AS UTM_CAMPAIGN
     ,  L.UTM_MEDIUM AS UTM_MEDIUM
     ,  L.UTM_CONTENT AS UTM_CONTENT
     ,  L.N_AD AS N_AD
     ,  L.N_CAMPAIGN_TYPE AS N_CAMPAIGN_TYPE
     ,  D.REF_URL AS PROMOTION_DETAIL_REF_URL
     ,  CASE WHEN L.PROMOTION_DETAIL IS NOT NULL THEN 1 ELSE 0 END AS PROMOTION_DETAIL_FLAG
     ,  L.PROMOTION_DETAIL AS PROMOTION_DETAIL_FIRST_ACCESS_DT
     ,  L.ITEM_ID
     ,  CASE WHEN L.OFFER_DETAIL IS NOT NULL THEN 1 ELSE 0 END AS OFFER_DETAIL_FLAG
     ,  L.OFFER_DETAIL AS OFFER_DETAIL_FIRST_ACCESS_DT
     ,  CASE WHEN L.WITH_EVENT_OFFER_DETAIL IS NOT NULL THEN 1 ELSE 0 END AS WITH_EVENT_OFFER_DETAIL_FLAG
     ,  L.WITH_EVENT_OFFER_DETAIL AS WITH_EVENT_OFFER_DETAILT_FIRST_ACCESS_DT
     ,  CASE WHEN L.CHECKOUT IS NOT NULL THEN 1 ELSE 0 END AS CHECKOUT_FLAG
     ,  L.CHECKOUT AS CHECKOUT_FIRST_ACCESS_DT
     ,  CASE WHEN L.WITH_EVENT_CHECKOUT IS NOT NULL THEN 1 ELSE 0 END AS WITH_EVENT_CHECKOUT_FLAG
     ,  L.WITH_EVENT_CHECKOUT AS WITH_EVENT_CHECKOUT_FIRST_ACCESS_DT
     ,  CASE WHEN L.CHECKOUT_COMPLETE IS NOT NULL THEN 1 ELSE 0 END AS CHECKOUT_COMPLETE_FLAG
     ,  L.CHECKOUT_COMPLETE AS CHECKOUT_COMPLETE_FIRST_ACCESS_DT
     ,  CASE WHEN L.WITH_EVENT_CHECKOUT_COMPLETE IS NOT NULL THEN 1 ELSE 0 END AS WITH_EVENT_CHECKOUT_COMPLETE_FLAG
     ,  L.WITH_EVENT_CHECKOUT_COMPLETE AS WITH_EVENT_CHECKOUT_COMPLETE_FIRST_ACCESS_DT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM DISTINCT_PID_WITHOUT_TIMESTAMP L
LEFT JOIN TODAY_FIRST_REF_URL R ON L.BASIS_DATE = R.BASIS_DATE AND L.PID = R.PID
LEFT JOIN PROMOTION_DETAIL_REF_URL D ON L.BASIS_DATE = D.BASIS_DATE AND L.PID = D.PID AND L.CAMPAIGN_ID = D.CAMPAIGN_ID