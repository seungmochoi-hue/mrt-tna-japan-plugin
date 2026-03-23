{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_USER_VISIT_LEAVE_D',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH DATA AS (
  SELECT l.basis_dt
      ,  l.pid
      ,  l.screen_name
      ,  l.event_timestamp_kst
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
   WHERE l.basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
     AND (l.event_name = 'pageview' OR l.event_type = 'pageview')
)
SELECT M.basis_dt
    ,  M.pid
    ,  MAX(M.pageview_cnt) AS pageview_cnt
    ,  MAX(M.first_screen_name) AS first_screen_name
    ,  MAX(M.last_screen_name) AS last_screen_name
  FROM (
SELECT T.basis_dt
    ,  T.pid
    ,  NULL pageview_cnt
    ,  IF(T.rank1 = 1, T.screen_name, NULL) AS first_screen_name
    ,  NULL AS last_screen_name
FROM (
SELECT l.basis_dt
    ,  l.pid
    ,  l.screen_name
    ,  DENSE_RANK() OVER(PARTITION BY l.basis_dt, l.pid ORDER BY l.event_timestamp_kst ASC) AS rank1
    ,  NULL AS rank2
FROM DATA l
WHERE l.screen_name <> 'signin'
) T

  UNION ALL

SELECT K.basis_dt
    ,  K.pid
    ,  NULL AS paegview_cnt
    ,  NULL AS first_screen_name
    ,  IF(K.rank2 = 1, K.screen_name, NULL) AS last_screen_name
    FROM (
SELECT l.basis_dt
    ,  l.pid
    ,  l.screen_name
    ,  NULL AS rank1
    ,  DENSE_RANK() OVER(PARTITION BY basis_dt, pid ORDER BY l.event_timestamp_kst DESC) AS rank2
  FROM DATA l
) K

UNION ALL

SELECT J.basis_dt
    ,  J.pid
    ,  COUNT(1) AS pageview_cnt
    ,  NULL AS first_screen_name
    ,  NULL AS last_screen_name
    FROM DATA J
GROUP BY J.basis_dt, J.pid
) M
GROUP BY M.basis_dt, M.pid