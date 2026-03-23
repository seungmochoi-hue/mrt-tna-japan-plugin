{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_BANNER_AGG_D',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH BANNER_IMP AS (
    SELECT  BASIS_DT
         , CASE
               WHEN SCREEN_NAME = 'accommodation_main' AND JSON_VALUE(l.data, '$.section_name') LIKE '%OVERSEA%' THEN 'accommodation_main_해외'
               WHEN SCREEN_NAME IN ('tourticket', 'all_flights_main', 'main') THEN SCREEN_NAME
               ELSE 'accommodation_main_국내'
        END AS SCREEN_NAME
         , CASE
               WHEN SCREEN_NAME = 'all_flights_main' AND EVENT_NAME = 'flight_banner' THEN JSON_VALUE(data, '$.event_banner_name')
               WHEN SCREEN_NAME = 'all_flights_main' AND EVENT_NAME = 'flight_recommendation' THEN JSON_EXTRACT(data, '$.section_title')
               WHEN SCREEN_NAME = 'main' THEN ITEM_NAME
               ELSE ITEM_ID
        END AS BANNER_NAME
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS IMP_UV_WEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS IMP_UV_IOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS IMP_UV_AOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS IMP_UV_IOS
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS IMP_UV_AOS
    FROM {{ ref("DW_BIZ_LOG_VIEW") }} AS l
    WHERE BASIS_DT = DATE('{{ var("logical_start_date_kst") }}')
    AND EVENT_TYPE = 'impression'
    AND EVENT_NAME IN ('main_banner', 'banner', 'flight_banner', 'main_banner')
    AND SCREEN_NAME IN ('tourticket', 'accommodation_main', 'all_flights_main', 'main')
GROUP BY 1, 2, 3
    ),
    BANNER_CLICK AS (
SELECT  BASIS_DT
        , CASE WHEN SCREEN_NAME = 'accommodation_main' AND JSON_VALUE(l.data, '$.section_name') LIKE '%OVERSEA%' THEN 'accommodation_main_해외'
               WHEN SCREEN_NAME IN ('tourticket', 'all_flights_main', 'main') THEN SCREEN_NAME
               ELSE 'accommodation_main_국내'
               END AS SCREEN_NAME
        , CASE WHEN SCREEN_NAME = 'all_flights_main' AND EVENT_NAME = 'flight_banner' THEN JSON_VALUE(data, '$.event_banner_name')
               WHEN SCREEN_NAME = 'all_flights_main' AND EVENT_NAME = 'flight_recommendation' THEN JSON_EXTRACT(data, '$.section_title')
               WHEN SCREEN_NAME = 'main' THEN ITEM_NAME
               ELSE ITEM_ID
               END AS BANNER_NAME
        , COUNT(CASE WHEN PLATFORM = 'web' THEN PID END) AS CLICK_CNT_WEB
        , COUNT(CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS CLICK_CNT_IOS_MWEB
        , COUNT(CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS CLICK_CNT_AOS_MWEB
        , COUNT(CASE WHEN PLATFORM = 'ios' THEN PID END) AS CLICK_CNT_IOS
        , COUNT(CASE WHEN PLATFORM = 'aos' THEN PID END) AS CLICK_CNT_AOS
        , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS CLICK_UV_WEB
        , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS CLICK_UV_IOS_MWEB
        , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS CLICK_UV_AOS_MWEB
        , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS CLICK_UV_IOS
        , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS CLICK_UV_AOS
FROM {{ ref("DW_BIZ_LOG_VIEW") }} AS l
WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
  AND EVENT_TYPE = 'click'
  AND EVENT_NAME IN ('main_banner', 'banner', 'flight_banner', 'main_banner')
  AND SCREEN_NAME IN ('tourticket', 'accommodation_main', 'all_flights_main', 'main')
GROUP BY 1, 2, 3
    ),
    BASE_DATA AS (
SELECT  I.*
        , C.CLICK_CNT_WEB
        , C.CLICK_CNT_IOS_MWEB
        , C.CLICK_CNT_AOS_MWEB
        , C.CLICK_CNT_IOS
        , C.CLICK_CNT_AOS
        , C.CLICK_UV_WEB
        , C.CLICK_UV_IOS_MWEB
        , C.CLICK_UV_AOS_MWEB
        , C.CLICK_UV_IOS
        , C.CLICK_UV_AOS
FROM BANNER_IMP AS I
    LEFT JOIN BANNER_CLICK AS C
ON I.BASIS_DT = C.BASIS_DT
    AND I.SCREEN_NAME = C.SCREEN_NAME
    AND I.BANNER_NAME = C.BANNER_NAME
    )
SELECT  BASIS_DT AS BASIS_DT
     , SCREEN_NAME AS SCREEN_NAME
     , CASE
           WHEN SCREEN_NAME = 'all_flights_main' THEN BD.BANNER_NAME
           WHEN SCREEN_NAME = 'main' THEN REPLACE(BD.BANNER_NAME, 'gtm-main-', '')
           WHEN SCREEN_NAME = 'tourticket' THEN REPLACE(BD.BANNER_NAME, 'tna-main-', '')
           ELSE BANNER.TITLE
    END AS BANNER_NAME
     , IMP_UV_WEB AS IMP_UV_WEB
     , IMP_UV_IOS_MWEB AS IMP_UV_IOS_MWEB
     , IMP_UV_AOS_MWEB AS IMP_UV_AOS_MWEB
     , IMP_UV_IOS AS IMP_UV_IOS
     , IMP_UV_AOS AS IMP_UV_AOS
     , CLICK_CNT_WEB AS CLICK_CNT_WEB
     , CLICK_CNT_IOS_MWEB AS CLICK_CNT_IOS_MWEB
     , CLICK_CNT_AOS_MWEB AS CLICK_CNT_AOS_MWEB
     , CLICK_CNT_IOS AS CLICK_CNT_IOS
     , CLICK_CNT_AOS AS CLICK_CNT_AOS
     , CLICK_UV_WEB AS CLICK_UV_WEB
     , CLICK_UV_IOS_MWEB AS CLICK_UV_IOS_MWEB
     , CLICK_UV_AOS_MWEB AS CLICK_UV_AOS_MWEB
     , CLICK_UV_IOS AS CLICK_UV_IOS
     , CLICK_UV_AOS AS CLICK_UV_AOS
FROM BASE_DATA BD
LEFT JOIN edw.DW_MRT_SERVICE_CMS_ITEMS BANNER ON BD.BANNER_NAME = CAST(BANNER.ID AS STRING)
