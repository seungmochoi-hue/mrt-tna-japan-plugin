{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_VERTICAL_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}



WITH LOG_DATA AS (
    SELECT  BASIS_DT
         , EVENT_NAME
         , ITEM_NAME
         , JSON_VALUE(DATA, '$.vertical_name') AS VERTICAL_NAME
         , COUNT(PID) AS CLICK_CNT
         , COUNT(DISTINCT PID) AS CLICK_UV
         , COUNT(CASE WHEN PLATFORM = 'web' THEN PID END) AS CLICK_CNT_WEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS CLICK_UV_WEB
         , COUNT(CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS CLICK_CNT_IOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS CLICK_UV_IOS_MWEB
         , COUNT(CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS CLICK_CNT_AOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS CLICK_UV_AOS_MWEB
         , COUNT(CASE WHEN PLATFORM = 'ios' THEN PID END) AS CLICK_CNT_IOS
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS CLICK_UV_IOS
         , COUNT(CASE WHEN PLATFORM = 'aos' THEN PID END) AS CLICK_CNT_AOS
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS CLICK_UV_AOS
         , 0 AS IMP_UV
         , 0 AS IMP_UV_WEB
         , 0 AS IMP_UV_IOS_MWEB
         , 0 AS IMP_UV_AOS_MWEB
         , 0 AS IMP_UV_IOS
         , 0 AS IMP_UV_AOS
    FROM {{ ref("DW_BIZ_LOG_VIEW") }}
    WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
    AND EVENT_TYPE = 'click'
    AND (
   (PLATFORM IN ('web', 'ios_mweb', 'aos_mweb') AND SCREEN_NAME IN ('main', 'common') AND EVENT_NAME IN ('sub_vertical', 'vertical', 'gnb'))
    OR (PLATFORM IN ('ios', 'aos') AND SCREEN_NAME = 'main' AND EVENT_NAME IN ('sub_vertical', 'vertical'))
    )
GROUP BY 1, 2, 3, 4

UNION ALL

SELECT  BASIS_DT
     , EVENT_NAME
     , ITEM_NAME
     , JSON_VALUE(DATA, '$.vertical_name') AS VERTICAL_NAME
     , 0 AS CLICK_CNT
     , 0 AS CLICK_UV
     , 0 AS CLICK_CNT_WEB
     , 0 AS CLICK_UV_WEB
     , 0 AS CLICK_CNT_IOS_MWEB
     , 0 AS CLICK_UV_IOS_MWEB
     , 0 AS CLICK_CNT_AOS_MWEB
     , 0 AS CLICK_UV_AOS_MWEB
     , 0 AS CLICK_CNT_IOS
     , 0 AS CLICK_UV_IOS
     , 0 AS CLICK_CNT_AOS
     , 0 AS CLICK_UV_AOS
     , COUNT(DISTINCT PID) AS IMP_UV
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS IMP_UV_WEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS IMP_UV_IOS_MWEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS IMP_UV_AOS_MWEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS IMP_UV_IOS
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS IMP_UV_AOS
FROM {{ ref("DW_BIZ_LOG_VIEW") }}
WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
  AND event_type = 'impression'
  AND PLATFORM IN ('ios', 'aos')
  AND SCREEN_NAME = 'main'
  AND EVENT_NAME = 'vertical'
GROUP BY 1, 2, 3, 4
    )

SELECT BASIS_DT AS BASIS_DT
     , EVENT_NAME AS EVENT_NAME
     , ITEM_NAME AS ITEM_NAME
     , VERTICAL_NAME AS VERTICAL_NAME
     , MAX(CLICK_CNT) AS CLICK_CNT
     , MAX(CLICK_UV) AS CLICK_UV
     , MAX(CLICK_CNT_WEB) AS CLICK_CNT_WEB
     , MAX(CLICK_UV_WEB) AS CLICK_UV_WEB
     , MAX(CLICK_CNT_IOS_MWEB) AS CLICK_CNT_IOS_MWEB
     , MAX(CLICK_UV_IOS_MWEB) AS CLICK_UV_IOS_MWEB
     , MAX(CLICK_CNT_AOS_MWEB) AS CLICK_CNT_AOS_MWEB
     , MAX(CLICK_UV_AOS_MWEB) AS CLICK_UV_AOS_MWEB
     , MAX(CLICK_CNT_IOS) AS CLICK_CNT_IOS
     , MAX(CLICK_UV_IOS) AS CLICK_UV_IOS
     , MAX(CLICK_CNT_AOS) AS CLICK_CNT_AOS
     , MAX(CLICK_UV_AOS) AS CLICK_UV_AOS
     , MAX(IMP_UV) AS IMP_UV
     , MAX(IMP_UV_WEB) AS IMP_UV_WEB
     , MAX(IMP_UV_IOS_MWEB) AS IMP_UV_IOS_MWEB
     , MAX(IMP_UV_AOS_MWEB) AS IMP_UV_AOS_MWEB
     , MAX(IMP_UV_IOS) AS IMP_UV_IOS
     , MAX(IMP_UV_AOS) AS IMP_UV_AOS
FROM LOG_DATA
GROUP BY 1, 2, 3, 4
