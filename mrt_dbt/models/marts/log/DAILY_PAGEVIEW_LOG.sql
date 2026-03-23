{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='DAILY_PAGEVIEW_LOG',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


SELECT DISTINCT basis_dt
              , pid
              , user_id
              , screen_name
              , event_name
              , event_type
              , item_id
              , url
              , JSON_VALUE(data, '$.campaign_id') AS campaign_id
              , DATETIME(MIN(event_timestamp_kst) OVER(PARTITION BY basis_dt, pid, screen_name, event_name, event_type , JSON_VALUE(data, '$.campaign_id'), item_id)) AS PID_SCREEN_FIRST_ACCESS_DT
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE basis_dt = '{{ var("logical_start_date_kst") }}'
  AND event_type = 'pageview'