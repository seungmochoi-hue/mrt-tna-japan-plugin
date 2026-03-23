{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_UTM_PAGEVIEW_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        enabled=false
    )
}}

WITH BIZ_LOG AS (
SELECT l.basis_dt
    ,  l.session_id
    ,  l.pid
    ,  l.screen_name
    ,  l.url
    ,  l.platform
    ,  l.event_name
    ,  l.event_type
    ,  l.event_timestamp_kst
    ,  l.user_id
    ,  IF(l.action_index = 1, l.ref_url, NULL) AS ref_url
    ,  JSON_EXTRACT_SCALAR(utm, '$.utm_source') AS utm_source
    ,  JSON_EXTRACT_SCALAR(utm, '$.utm_medium') AS utm_medium
    ,  JSON_EXTRACT_SCALAR(utm, '$.utm_campaign') AS utm_campaign
    ,  IF(l.event_name = 'purchase_request', 1, 0) AS purchase_request_flag
    ,  IF(l.event_name = 'purchase_success', 1, 0) AS purchase_success_flag
FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
WHERE l.basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
),
LOG_PAGEVIEW AS (
    SELECT T.basis_dt
        ,  T.session_id
        ,  T.pid
        ,  MAX(T.first_view) AS first_view
        ,  MAX(T.first_screen_name) AS first_screen_name
        ,  MAX(T.second_view) AS second_view
        ,  MAX(T.second_screen_name) AS second_screen_name
      FROM (
    SELECT M.basis_dt
        ,  M.session_id
        ,  M.pid
        ,  IF(M.rank = 1, M.url, NULL) AS first_view
        ,  IF(M.rank = 1, M.screen_name, NULL) AS first_screen_name
        ,  IF(M.rank = 2, M.url, NULL) AS second_view
        ,  IF(M.rank = 2, M.screen_name, NULL) AS second_screen_name
      FROM (
    SELECT l.basis_dt
         , l.session_id
         , l.pid
         , l.url
         , l.screen_name
         , DENSE_RANK() OVER(PARTITION BY l.basis_dt, l.pid ORDER BY l.event_timestamp_kst ASC) AS rank
    FROM BIZ_LOG l
    WHERE  l.event_name = 'pageview' OR l.event_type ='pageview'
      ) M
      ) T
    GROUP BY T.basis_dt, T.session_id, T.pid
),
LOG_INFORM AS (
    SELECT l.basis_dt
        ,  l.session_id
        ,  l.pid
        ,  MAX(l.ref_url) AS ref_url
        ,  MAX(l.platform) AS platform
        ,  MAX(l.user_id) AS user_id
        ,  MAX(l.purchase_request_flag) AS purchase_request_flag
        ,  MAX(l.purchase_success_flag) AS purchase_success_flag
        ,  MAX(l.utm_source) AS utm_source
        ,  MAX(l.utm_medium) AS utm_medium
        ,  MAX(l.utm_campaign) AS utm_campaign
     FROM BIZ_LOG l
      GROUP BY l.basis_dt, l.session_id, l.pid
),
DATA AS (
SELECT T.basis_dt
    ,  T.session_id
    ,  T.pid
    ,  MAX(T.first_view) AS first_view
    ,  MAX(T.first_screen_name) AS first_screen_name
    ,  MAX(T.second_view) AS second_view
    ,  MAX(T.second_screen_name) AS second_screen_name
    ,  MAX(T.ref_url) AS ref_url
    ,  MAX(T.platform) AS platform
    ,  MAX(T.user_id) AS user_id
    ,  IF(MAX(T.purchase_request_flag) = 1, 'Y', 'N') AS purchase_request_flag
    ,  IF(MAX(T.purchase_success_flag) = 1, 'Y', 'N') AS purchase_success_flag
    ,  MAX(T.utm_source) AS utm_source
    ,  MAX(T.utm_medium) AS utm_medium
    ,  MAX(T.utm_campaign) AS utm_campaign
  FROM (
SELECT p.basis_dt
    ,  p.session_id
    ,  p.pid
    ,  p.first_view
    ,  p.first_screen_name
    ,  p.second_view
    ,  p.second_screen_name
    ,  NULL AS ref_url
    ,  NULL AS platform
    ,  NULL AS user_id
    ,  NULL AS purchase_request_flag
    ,  NULL AS purchase_success_flag
    ,  NULL AS utm_source
    ,  NULL AS utm_medium
    ,  NULL AS utm_campaign
  FROM LOG_PAGEVIEW p

UNION ALL

SELECT i.basis_dt
    ,  i.session_id
    ,  i.pid
    ,  NULL AS first_view
    ,  NULL AS first_screen_name
    ,  NULL AS second_view
    ,  NULL AS second_screen_name
    ,  i.ref_url
    ,  i.platform
    ,  i.user_id
    ,  i.purchase_request_flag
    ,  i.purchase_success_flag
    ,  i.utm_source
    ,  i.utm_medium
    ,  i.utm_campaign
  FROM LOG_INFORM i
  ) T
GROUP BY T.basis_dt, T.session_id, T.pid
)
SELECT d.basis_dt
    ,  d.session_id
    ,  d.pid
    ,  d.first_view
    ,  d.first_screen_name
    ,  d.second_view
    ,  d.second_screen_name
    ,  d.ref_url
    ,  d.platform
    ,  d.user_id
    ,  d.purchase_request_flag
    ,  d.purchase_success_flag
    ,  d.utm_source
    ,  d.utm_medium
    ,  d.utm_campaign
    ,  CASE WHEN (d.utm_source IS NOT NULL OR d.utm_medium IS NOT NULL OR d.utm_campaign IS NOT NULL) THEN 'Y' ELSE 'N' END AS utm_flag
  FROM DATA d