{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_USER_FLOW_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH LOGS AS (
SELECT l.basis_dt
    ,  l.event_timestamp
    ,  l.session_id
    ,  l.user_id
    ,  l.platform
    ,  l.pid
    ,  l.screen_name
    ,  LEAD(screen_name) OVER (PARTITION BY basis_dt, session_id, pid ORDER BY event_timestamp) AS next_screen_name
  FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
  WHERE l.basis_dt BETWEEN '{{var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
    AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
    ORDER BY event_timestamp
)
SELECT l.basis_dt
    ,  l.event_timestamp
    ,  l.session_id
    ,  l.user_id
    ,  l.platform
    ,  l.pid
    ,  l.screen_name AS source_screen_name
    ,  l.next_screen_name AS target_screen_name
    ,  'move' AS division
  FROM LOGS l

UNION ALL

SELECT l.basis_dt
    ,  l.event_timestamp
    ,  l.session_id
    ,  l.user_id
    ,  l.platform
    ,  l.pid
    ,  IFNULL(l.next_screen_name, '마지막 페이지(이탈)') AS source_screen_name
    ,  l.screen_name AS target_screen_name
    ,  'inflow' AS division
  FROM LOGS l