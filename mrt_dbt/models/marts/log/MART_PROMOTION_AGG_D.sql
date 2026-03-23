{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_PROMOTION_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


SELECT  BASIS_DT AS BASIS_DT
     , JSON_VALUE(DATA, '$.campaign_id') AS CAMPAIGN_ID
     , COUNT(PID) AS PV
     , COUNT(DISTINCT PID) AS UV
     , COUNT(CASE WHEN PLATFORM = 'web' THEN PID END) AS PV_WEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'web' THEN PID END) AS UV_WEB
     , COUNT(CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS PV_IOS_MWEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios_mweb' THEN PID END) AS UV_IOS_MWEB
     , COUNT(CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS PV_AOS_MWEB
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos_mweb' THEN PID END) AS UV_AOS_MWEB
     , COUNT(CASE WHEN PLATFORM = 'ios' THEN PID END) AS PV_IOS
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'ios' THEN PID END) AS UV_IOS
     , COUNT(CASE WHEN PLATFORM = 'aos' THEN PID END) AS PV_AOS
     , COUNT(DISTINCT CASE WHEN PLATFORM = 'aos' THEN PID END) AS UV_AOS
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE BASIS_DT = '{{ var("logical_start_date_kst") }}'
  AND SCREEN_NAME = 'promotion_detail'
  AND EVENT_TYPE = 'pageview'
GROUP BY 1, 2
