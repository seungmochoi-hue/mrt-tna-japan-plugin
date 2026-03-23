{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_PROMOTION_ITEM_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH IMP_DATA AS (
    SELECT  BASIS_DT
         , JSON_VALUE(DATA, '$.campaign_id') AS CAMPAIGN_ID
         , EVENT_NAME
         , ITEM_TYPE
         , ITEM_ID
         , ITEM_NAME
         , COUNT(CASE WHEN PLATFORM = 'web' THEN PID END) AS IMP_CNT_WEB
         , COUNT(CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS IMP_CNT_IOS_MWEB
         , COUNT(CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS IMP_CNT_AOS_MWEB
         , COUNT(CASE WHEN PLATFORM = 'ios' THEN PID END) AS IMP_CNT_IOS
         , COUNT(CASE WHEN PLATFORM = 'aos' THEN PID END) AS IMP_CNT_AOS
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS IMP_UV_WEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS IMP_UV_IOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS IMP_UV_AOS_MWEB
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS IMP_UV_IOS
         , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS IMP_UV_AOS
    FROM {{ ref('DW_BIZ_LOG_VIEW') }}
    WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
      AND EVENT_TYPE = 'impression'
      AND SCREEN_NAME = 'promotion_detail'
    GROUP BY 1, 2, 3, 4, 5, 6
),
     CLICK_DATA AS (
         SELECT  JSON_VALUE(DATA, '$.campaign_id') AS CAMPAIGN_ID
              , BASIS_DT
              , EVENT_NAME
              , ITEM_TYPE
              , ITEM_ID
              , ITEM_NAME
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
         FROM {{ ref('DW_BIZ_LOG_VIEW') }}
         WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
           AND SCREEN_NAME = 'promotion_detail'
           AND EVENT_TYPE = 'click'
         GROUP BY 1, 2, 3, 4, 5, 6
     )
SELECT I.CAMPAIGN_ID AS CAMPAIGN_ID
     , I.BASIS_DT AS BASIS_DT
     , I.EVENT_NAME AS EVENT_NAME
     , I.ITEM_TYPE AS ITEM_TYPE
     , I.ITEM_ID AS ITEM_ID
     , I.ITEM_NAME AS ITEM_NAME
     , I.IMP_CNT_WEB AS IMP_CNT_WEB
     , I.IMP_CNT_IOS_MWEB AS IMP_CNT_IOS_MWEB
     , I.IMP_CNT_AOS_MWEB AS IMP_CNT_AOS_MWEB
     , I.IMP_CNT_IOS AS IMP_CNT_IOS
     , I.IMP_CNT_AOS AS IMP_CNT_AOS
     , I.IMP_UV_WEB AS IMP_UV_WEB
     , I.IMP_UV_IOS_MWEB AS IMP_UV_IOS_MWEB
     , I.IMP_UV_AOS_MWEB AS IMP_UV_AOS_MWEB
     , I.IMP_UV_IOS AS IMP_UV_IOS
     , I.IMP_UV_AOS AS IMP_UV_AOS
     , C.CLICK_CNT_WEB AS CLICK_CNT_WEB
     , C.CLICK_CNT_IOS_MWEB AS CLICK_CNT_IOS_MWEB
     , C.CLICK_CNT_AOS_MWEB AS CLICK_CNT_AOS_MWEB
     , C.CLICK_CNT_IOS AS CLICK_CNT_IOS
     , C.CLICK_CNT_AOS AS CLICK_CNT_AOS
     , C.CLICK_UV_WEB AS CLICK_UV_WEB
     , C.CLICK_UV_IOS_MWEB AS CLICK_UV_IOS_MWEB
     , C.CLICK_UV_AOS_MWEB AS CLICK_UV_AOS_MWEB
     , C.CLICK_UV_IOS AS CLICK_UV_IOS
     , C.CLICK_UV_AOS AS CLICK_UV_AOS
FROM IMP_DATA I
LEFT JOIN CLICK_DATA C ON CASE WHEN I.ITEM_ID IS NOT NULL AND I.ITEM_TYPE IS NOT NULL THEN
                              I.BASIS_DT = C.BASIS_DT AND I.CAMPAIGN_ID = C.CAMPAIGN_ID AND I.EVENT_NAME = C.EVENT_NAME
                                  AND I.ITEM_TYPE = C.ITEM_TYPE AND I.ITEM_ID = C.ITEM_ID AND I.ITEM_NAME = C.ITEM_NAME
                          WHEN I.ITEM_ID IS NOT NULL AND I.ITEM_TYPE IS NULL THEN
                              I.BASIS_DT = C.BASIS_DT AND I.CAMPAIGN_ID = C.CAMPAIGN_ID AND I.EVENT_NAME = C.EVENT_NAME
                                  AND I.ITEM_ID = C.ITEM_ID AND I.ITEM_NAME = C.ITEM_NAME
                          WHEN I.ITEM_ID IS NULL AND I.ITEM_TYPE IS NOT NULL THEN
                              I.BASIS_DT = C.BASIS_DT AND I.CAMPAIGN_ID = C.CAMPAIGN_ID AND I.EVENT_NAME = C.EVENT_NAME
                                  AND I.ITEM_TYPE = C.ITEM_TYPE AND I.ITEM_NAME = C.ITEM_NAME
                          ELSE
                              I.BASIS_DT = C.BASIS_DT AND I.CAMPAIGN_ID = C.CAMPAIGN_ID AND I.EVENT_NAME = C.EVENT_NAME AND I.ITEM_NAME = C.ITEM_NAME
                          END
