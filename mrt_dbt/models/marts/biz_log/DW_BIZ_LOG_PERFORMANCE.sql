{{
    config(
        materialized='incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw',
        alias='DW_BIZ_LOG_PERFORMANCE',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['screen_name'],
        require_partition_filter = true
    )
}}

SELECT
    DATE(TIMESTAMP_ADD(received_timestamp, INTERVAL 9 HOUR)) AS basis_dt
     , TIMESTAMP_ADD(received_timestamp, INTERVAL 9 HOUR) AS received_timestamp_kst
     , TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR) AS event_timestamp_kst
     , screen_name
     , event_type
     , event_name
     , platform
     , pid
     , udid
     , user_id
     , lib_version
     , client_ip
     , session_id
     , CAST(JSON_EXTRACT_SCALAR(data, '$.tti') AS FLOAT64) AS tti
     , data
     , device
     , CURRENT_DATETIME('Asia/Seoul') AS dw_load_dt
FROM {{ source('log_stream','biz_log') }}
WHERE basis_dt BETWEEN "{{ var('logical_start_date_utc') }}" AND "{{ var('logical_end_date_utc') }}"
  AND (received_timestamp >= "{{ var('logical_start_date_utc') }} 15:00:00" AND received_timestamp < "{{ var('logical_end_date_utc') }} 15:00:00")
  AND event_type = 'performance'