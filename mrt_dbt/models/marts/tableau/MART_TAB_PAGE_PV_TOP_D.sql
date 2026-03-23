{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_PAGE_PV_TOP_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH PAGEVIEW_LOG AS (
SELECT l.basis_dt
    ,  l.platform AS PLATFORM
    ,  l.pid
    ,  l.session_id
    ,  l.screen_name
    ,  LEAD(screen_name) OVER (PARTITION BY basis_dt, session_id, pid ORDER BY event_timestamp) AS next_screen_name
  FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
  WHERE l.basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
    AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
    ORDER BY event_timestamp
)
SELECT l.basis_dt AS BASIS_DATE
    ,  l.platform AS PLATFORM
    ,  l.screen_name AS SCREEN_NAME
    ,  COUNT(DISTINCT pid) AS VISIT_PID_CNT
    ,  COUNT(DISTINCT IF(l.next_screen_name IS NULL, pid, NULL)) AS INFLOW_PID_CNT
    ,  COUNT(DISTINCT session_id) AS VISIT_SESSION_ID_CNT
    ,  COUNT(DISTINCT IF(l.next_screen_name IS NULL, session_id, NULL)) AS INFLOW_SESSION_ID_CNT
    ,  COUNT(pid) AS VISIT_CNT
    ,  COUNT(IF(l.next_screen_name IS NULL, pid, NULL)) AS INFLOW_CNT
 FROM PAGEVIEW_LOG l
  GROUP BY l.basis_dt, l.platform, l.screen_name