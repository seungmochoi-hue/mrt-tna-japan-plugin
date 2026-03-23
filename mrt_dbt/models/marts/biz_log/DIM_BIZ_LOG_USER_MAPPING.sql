{{
    config(
        materialized='incremental',
        incremental_strategy = 'merge',
        schema='edw_biz_log',
        alias='DIM_BIZ_LOG_USER_MAPPING',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        pre_hook="DELETE FROM {{ this }} WHERE basis_dt = '{{ var('logical_start_date_kst') }}'"
    )
}}

SELECT
    DATE(TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR)) AS basis_dt
     -- , session_id
     , pid
     -- , udid
     -- , adid
     , user_id
     -- , MIN(event_timestamp) AS min_event_timestamp
     , TIMESTAMP_ADD(MIN(event_timestamp), INTERVAL 9 HOUR) AS min_event_timestamp_kst
     -- , MIN(received_timestamp) AS min_received_timestamp
     -- , TIMESTAMP_ADD(MIN(received_timestamp), INTERVAL 9 HOUR) AS min_received_timestamp_kst
     , CURRENT_TIMESTAMP() AS dw_load_dt
FROM {{ source('log_stream', 'biz_log') }}
WHERE basis_dt BETWEEN "{{ var('logical_start_date_utc') }}" AND "{{ var('logical_end_date_utc') }}"
    AND (event_timestamp >= "{{ var('logical_start_date_utc') }} 15:00:00" AND event_timestamp < "{{ var('logical_end_date_utc') }} 15:00:00")
    AND pid IS NOT NULL -- PID 없으면 매핑 불가, downstream 전체에서 미사용
    AND user_id IS NOT NULL AND user_id != "" AND user_id != 'null'
GROUP BY 1,2,3