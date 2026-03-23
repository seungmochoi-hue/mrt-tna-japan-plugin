{{
    config(
        materialized='table',
        schema='temp',
        alias='resve_attribute'
    )
}}


WITH BASE AS (
    SELECT CAST(u.reservation_no AS STRING) AS RESVE_ID
        ,  '3.0 PRODUCT' AS DOMAIN_NM
        ,  1 AS PRIORITY_NUM
        ,  datetime(u.created_at) AS CREATED_KST_DATE
        ,  datetime(u.updated_at) AS UPDATED_KST_DATE
        ,  u.utm_medium AS FIRST_UTM_MEDIUM
        ,  u.utm_source AS FIRST_UTM_SOURCE
        ,  u.utm_campaign AS FIRST_UTM_CAMPAIGN
        ,  u.utm_term AS FIRST_UTM_TERM
        ,  u.utm_content AS FIRST_UTM_CONTENT
        ,  u.recent_utm_medium AS UTM_MEDIUM
        ,  u.recent_utm_source AS UTM_SOURCE
        ,  u.recent_utm_campaign AS UTM_CAMPAIGN
        ,  u.recent_utm_term AS UTM_TERM
        ,  u.recent_utm_content AS UTM_CONTENT
        ,  JSON_EXTRACT_SCALAR(u.added_utm_infos, '$.recentNAd') AS N_AD
        ,  JSON_EXTRACT_SCALAR(u.added_utm_infos, '$.recentNAdGroup') AS N_AD_GROUP
        ,  JSON_EXTRACT_SCALAR(u.added_utm_infos, '$.recentNCampaignType') AS N_CAMPAIGN_TYPE
        ,  CAST(NULL AS STRING) AS N_KEYWORD
        ,  JSON_EXTRACT_SCALAR(u.added_utm_infos, '$.recentNKeywordId') AS N_KEYWORD_ID
        ,  CAST(NULL AS STRING) AS MRT_CONTENTS_VALUE
        ,  CAST(NULL AS STRING) AS APP_PLATFORM
        ,  CAST(NULL AS STRING) AS APP_IDFA_VALUE
        ,  CAST(NULL AS STRING) AS APP_ADID_VALUE
        ,  CAST(NULL AS STRING) AS APP_DEVICE_TYPE
        ,  CAST(NULL AS STRING) AS APP_SITE_ID_VALUE
        ,  CAST(NULL AS STRING) AS APP_SUB_SITE_ID_VALUE
        ,  CAST(NULL AS STRING) AS APP_ADSET_VALUE
        ,  CAST(NULL AS STRING) AS APP_AD_VALUE
        ,  CAST(NULL AS STRING) AS APP_CHANNEL_VALUE
    FROM {{ source('orders', 'reservation_utm_infos') }} u
    WHERE u.reservation_id IS NOT NULL
      AND u.updated_at BETWEEN '{{ var("before_8_days_kst") }} 00:00:00' AND '{{ var("logical_end_date_kst") }} 23:59:59'
      AND (u.recent_utm_source IS NOT NULL OR JSON_EXTRACT_SCALAR(u.added_utm_infos, '$.recentNAd') IS NOT NULL)
      AND u.deleted_at IS NULL

    UNION ALL

    SELECT L.ds.reservation_id AS RESVE_ID
        ,  'BIZLOG' AS DOMAIN_NM
        ,  2 AS PRIORITY_NUM
        ,  CAST(L.event_timestamp_kst AS DATETIME) AS CREATED_KST_DATE
        ,  CAST(L.event_timestamp_kst AS DATETIME) AS UPDATED_KST_DATE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_MEDIUM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_SOURCE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CAMPAIGN
        ,  CAST(NULL AS STRING) AS FIRST_UTM_TERM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CONTENT
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_utm_source'), udf.url_param(L.url, 'utm_source')) AS UTM_SOURCE
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_utm_campaign'), udf.url_param(L.url, 'utm_campaign')) AS UTM_CAMPAIGN
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_utm_medium'), udf.url_param(L.url, 'utm_medium')) AS UTM_MEDIUM
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_utm_term'), udf.url_param(L.url, 'utm_term')) AS UTM_TERM
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_utm_content'), udf.url_param(L.url, 'utm_content')) AS UTM_CONTENT
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_n_ad'), udf.url_param(L.url, 'n_ad')) AS N_AD
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_n_ad_group'), udf.url_param(L.url, 'n_ad_group')) AS N_AD_GROUP
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_n_campaign_type'), udf.url_param(L.url, 'n_campaign_type')) AS N_CAMPAIGN_TYPE
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_n_keyword'), udf.url_param(L.url, 'n_keyword')) AS N_KEYWORD
        ,  IFNULL(JSON_VALUE(L.utm, '$.recent_n_keyword_id'), udf.url_param(L.url, 'n_keyword_id')) AS N_KEYWORD_ID
        ,  IFNULL(JSON_VALUE(L.utm, '$.mrt_contents'), udf.url_param(L.url, 'mrt_contents')) AS MRT_CONTENTS
        ,  CAST(NULL AS STRING) AS APP_PLATFORM
        ,  CAST(NULL AS STRING) AS APP_IDFA_VALUE
        ,  CAST(NULL AS STRING) AS APP_ADID_VALUE
        ,  CAST(NULL AS STRING) AS APP_DEVICE_TYPE
        ,  CAST(NULL AS STRING) AS APP_SITE_ID_VALUE
        ,  CAST(NULL AS STRING) AS APP_SUB_SITE_ID_VALUE
        ,  CAST(NULL AS STRING) AS APP_ADSET_VALUE
        ,  CAST(NULL AS STRING) AS APP_AD_VALUE
        ,  CAST(NULL AS STRING) AS APP_CHANNEL_VALUE
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} L
    WHERE L.basis_dt BETWEEN '{{ var("before_8_days_kst") }}' AND '{{ var("logical_end_date_kst") }}'
      AND L.event_type = 'pageview'
      AND L.screen_name IN ('purchase_complete', 'checkout_complete')
      AND IFNULL(JSON_VALUE(L.utm, '$.recent_n_keyword'), udf.url_param(L.url, 'n_keyword')) IS NOT NULL
      AND L.ds.reservation_id IS NOT NULL
      AND (IFNULL(JSON_VALUE(L.utm, '$.recent_utm_source'), udf.url_param(L.url, 'utm_source')) IS NOT NULL OR
           IFNULL(JSON_VALUE(L.utm, '$.recent_n_ad'), udf.url_param(L.url, 'n_ad')) IS NOT NULL)

    UNION ALL

    SELECT concat('f', u.reservation_id) AS RESVE_ID
        ,  'AIR' AS DOMAIN_NM
        ,  3 AS PRIORITY_NUM
        ,  datetime(u.created_at) AS CREATED_KST_DATE
        ,  datetime(u.updated_at) AS UPDATED_KST_DATE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_MEDIUM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_SOURCE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CAMPAIGN
        ,  CAST(NULL AS STRING) AS FIRST_UTM_TERM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CONTENT
        ,  u.recent_utm_medium AS UTM_MEDIUM
        ,  u.recent_utm_source AS UTM_SOURCE
        ,  u.recent_utm_campaign AS UTM_CAMPAIGN
        ,  u.recent_utm_term AS UTM_TERM
        ,  u.recent_utm_content AS UTM_CONTENT
        ,  IF(u.recent_utm_source IN ('Naver_brand', 'naver_brand', 'naver_contents', 'NaverShopping', 'NAD'), u.recent_n_ad, NULL) AS N_AD
        ,  IF(u.recent_utm_source IN ('Naver_brand', 'naver_brand', 'naver_contents', 'NaverShopping', 'NAD'), u.recent_n_ad_group, NULL) AS N_AD_GROUP
        ,  IF(u.recent_utm_source IN ('Naver_brand', 'naver_brand', 'naver_contents', 'NaverShopping', 'NAD'), u.recent_n_campaign_type, NULL) AS N_CAMPAIGN_TYPE
        ,  IF(u.recent_utm_source IN ('Naver_brand', 'naver_brand', 'naver_contents', 'NaverShopping', 'NAD'), u.recent_n_keyword, NULL) AS N_KEYWORD
        ,  IF(u.recent_utm_source IN ('Naver_brand', 'naver_brand', 'naver_contents', 'NaverShopping', 'NAD'), u.recent_n_keyword_id, NULL) AS N_KEYWORD_ID
        ,  CAST(NULL AS STRING) AS MRT_CONTENTS_VALUE
        ,  CAST(NULL AS STRING) AS APP_PLATFORM
        ,  CAST(NULL AS STRING) AS APP_IDFA_VALUE
        ,  CAST(NULL AS STRING) AS APP_ADID_VALUE
        ,  CAST(NULL AS STRING) AS APP_DEVICE_TYPE
        ,  CAST(NULL AS STRING) AS APP_SITE_ID
        ,  CAST(NULL AS STRING) AS APP_SUB_SITE_ID
        ,  CAST(NULL AS STRING) AS APP_ADSET_VALUE
        ,  CAST(NULL AS STRING) AS APP_AD_VALUE
        ,  CAST(NULL AS STRING) AS APP_CHANNEL_VALUE
    FROM {{ source('air', 'TB_RESERVATION_UTM_INFOS') }} u
    WHERE u.created_at BETWEEN '{{ var("before_8_days_kst") }} 00:00:00' AND '{{ var("logical_end_date_kst") }} 23:59:59'
      AND u.reservation_type = 'PAYMENT'
      AND u.reservation_id IS NOT NULL
      AND (u.recent_utm_medium IS NOT NULL OR u.recent_n_ad IS NOT NULL)
      AND u.deleted_at IS NULL

    UNION ALL

    SELECT CASE WHEN JSON_EXTRACT_SCALAR(a.custom_event_properties, '$.productType') IN ('FLIGHT', 'flight') THEN concat('f', a.transaction_ID)
           ELSE a.transaction_ID END AS RESVE_ID
        , 'AIRBRIDGE' AS DOMAIN_NM
        ,  4 AS PRIORITY_NUM
        ,  SAFE_CAST(TIMESTAMP_MILLIS(CAST(a.event_Timestamp AS INT64)) AS DATETIME) AS CREATED_KST_DATE
        ,  SAFE_CAST(TIMESTAMP_MILLIS(CAST(a.event_Timestamp AS INT64)) AS DATETIME) AS UPDATED_KST_DATE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_MEDIUM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_SOURCE
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CAMPAIGN
        ,  CAST(NULL AS STRING) AS FIRST_UTM_TERM
        ,  CAST(NULL AS STRING) AS FIRST_UTM_CONTENT
        ,  CAST(NULL AS STRING) AS UTM_MEDIUM
        ,  CASE WHEN a.channel = 'airbridge.websdk' THEN COALESCE(a.CTA_Param_1, a.sub_Sub_Publisher_1)
           ELSE a.channel END AS UTM_SOURCE  --sub_param_1 쓰는 로직 태우기 smart_script 쓰는거
        ,  a.campaign AS UTM_CAMPAIGN
        ,  a.ad_creative AS UTM_TERM
        ,  a.ad_group AS UTM_CONTENT
        ,  CAST(NULL AS STRING) AS N_AD
        ,  a.sub_sub_publisher_3 AS N_AD_GROUP -- 23.03.15 w2a 용 파라미터 추가
        ,  a.sub_sub_publisher_2 AS N_CAMPAIGN_TYPE
        ,  a.ad_creative_ID AS N_KEYWORD -- TBD
        ,  a.term AS N_KEYWORD_ID -- TBD
        ,  CAST(NULL AS STRING) AS MRT_CONTENTS_VALUE
        ,  CASE WHEN a.platform = 'Android' THEN 'android/traveler'
                WHEN a.platform = 'iOS' THEN 'ios/traveler'
                ELSE NULL END AS APP_PLATFORM
        ,  a.idfa AS APP_IDFA_VALUE
        ,  a.gaid AS APP_ADID_VALUE
        ,  a.device_Type AS APP_DEVICE_TYPE
        ,  a.sub_publisher AS APP_SITE_ID
        ,  a.sub_sub_publisher_1 AS APP_SUB_SITE_ID
        ,  a.ad_group AS APP_ADSET_VALUE
        ,  a.ad_creative AS APP_AD_VALUE
        ,  a.sub_Publisher AS APP_CHANNEL_VALUE
    FROM {{ source('external', 'AIRBRIDGE_APP') }} a
    WHERE a.basis_date BETWEEN '{{ var("before_8_days_kst") }}' AND '{{ var("logical_end_date_kst") }}'
    AND a.event_Name = 'Order Complete'
    AND a.transaction_ID IS NOT NULL -- reservation id null제외
    AND ((a.channel IS NOT NULL AND a.channel NOT IN ('unattributed')) OR a.sub_sub_publisher_3 IS NOT NULL)
)
SELECT RESVE_ID
     ,  DOMAIN_NM
     ,  CREATED_KST_DATE
     ,  UPDATED_KST_DATE
     ,  FIRST_UTM_MEDIUM
     ,  FIRST_UTM_SOURCE
     ,  FIRST_UTM_CAMPAIGN
     ,  FIRST_UTM_TERM
     ,  FIRST_UTM_CONTENT
     ,  UTM_MEDIUM
     ,  UTM_SOURCE
     ,  UTM_CAMPAIGN
     ,  UTM_TERM
     ,  UTM_CONTENT
     ,  N_AD
     ,  N_AD_GROUP
     ,  N_CAMPAIGN_TYPE
     ,  N_KEYWORD
     ,  N_KEYWORD_ID
     ,  MRT_CONTENTS_VALUE
     ,  APP_PLATFORM
     ,  APP_IDFA_VALUE
     ,  APP_ADID_VALUE
     ,  APP_DEVICE_TYPE
     ,  APP_SITE_ID_VALUE
     ,  APP_SUB_SITE_ID_VALUE
     ,  APP_ADSET_VALUE
     ,  APP_AD_VALUE
     ,  APP_CHANNEL_VALUE
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT RESVE_ID
              ,  DOMAIN_NM
              ,  CREATED_KST_DATE
              ,  UPDATED_KST_DATE
              ,  FIRST_UTM_MEDIUM
              ,  FIRST_UTM_SOURCE
              ,  FIRST_UTM_CAMPAIGN
              ,  FIRST_UTM_TERM
              ,  FIRST_UTM_CONTENT
              ,  UTM_MEDIUM
              ,  UTM_SOURCE
              ,  UTM_CAMPAIGN
              ,  UTM_TERM
              ,  UTM_CONTENT
              ,  N_AD
              ,  N_AD_GROUP
              ,  N_CAMPAIGN_TYPE
              ,  N_KEYWORD
              ,  N_KEYWORD_ID
              ,  MRT_CONTENTS_VALUE
              ,  APP_PLATFORM
              ,  APP_IDFA_VALUE
              ,  APP_ADID_VALUE
              ,  APP_DEVICE_TYPE
              ,  APP_SITE_ID_VALUE
              ,  APP_SUB_SITE_ID_VALUE
              ,  APP_ADSET_VALUE
              ,  APP_AD_VALUE
              ,  APP_CHANNEL_VALUE
              ,  PRIORITY_NUM
              ,  ROW_NUMBER() OVER (PARTITION BY RESVE_ID ORDER BY PRIORITY_NUM ASC) AS rn
         FROM BASE B
     )
WHERE rn = 1