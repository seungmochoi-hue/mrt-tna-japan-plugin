{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_USER_ACTIVE_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH LOG_PID AS (
   SELECT DISTINCT l.basis_dt AS BASIS_DATE
        , d.month AS MONTH
        , d.day AS DAY
        , d.iso_week AS WEEK
        , d.week_day_monday AS WEEK_DAY
        , l.platform AS PLATFORM
        , l.session_id AS SESSION_ID
        , l.pid AS PID
     FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
     LEFT JOIN {{ source('external_mart', 'DIM_DATE') }} d ON l.basis_dt = d.full_date
     WHERE l.basis_dt BETWEEN '{{ var('before_32_days_kst') }}' AND '{{ var('end_date_kst') }}'
      AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
)
SELECT T.BASIS_DATE AS BASIS_DATE
    ,  T.PLATFORM AS PLATFORM
    ,  MAX(T.TOTAL_USER_CNT) AS TOTAL_USER_CNT
    ,  MAX(T.ACTIVE_USER_CNT) AS ACTIVE_USER_CNT
    ,  MAX(T.DORMANT_USER_CNT) AS DORMANT_USER_CNT
    ,  MAX(T.LEAVE_USER_CNT) AS LEAVE_USER_CNT
    ,  MAX(T.NEW_USER_CNT) AS NEW_USER_CNT
    ,  MAX(T.PV) AS PV
    ,  MAX(T.UV) AS UV
    ,  MAX(T.USER_ID_CNT) AS USER_ID_CNT
    ,  MAX(T.LOGIN_ACTIVE_CNT) AS LOGIN_ACTIVE_CNT
    ,  MAX(T.NON_LOGIN_ACTIVE_CNT) AS NON_LOGIN_ACTIVE_CNT
    ,  MAX(T.PAID_CNT) AS PAID_CNT
    ,  MAX(T.WEEK_UV) AS WEEK_UV
    ,  MAX(T.WEEK_PV) AS WEEK_PV
    ,  MAX(T.MONTH_UV) AS MONTH_UV
    ,  MAX(T.MONTH_PV) AS MONTH_PV
  FROM (
  SELECT D.BASIS_DATE AS BASIS_DATE
      ,  'ALL' AS PLATFORM
      ,  D.TOTAL_USER_CNT AS TOTAL_USER_CNT
      ,  D.TOTAL_ACTIVE_USER_CNT AS ACTIVE_USER_CNT
      ,  D.TOTAL_DORMANT_USER_CNT AS DORMANT_USER_CNT
      ,  D.TOTAL_LEAVE_USER_CNT AS LEAVE_USER_CNT
      ,  NULL AS NEW_USER_CNT
      ,  NULL AS PV
      ,  NULL AS UV
      ,  NULL AS USER_ID_CNT
      ,  NULL AS LOGIN_ACTIVE_CNT
      ,  NULL AS NON_LOGIN_ACTIVE_CNT
      ,  NULL AS PAID_CNT
      ,  NULL AS WEEK_UV
      ,  NULL AS WEEK_PV
      ,  NULL AS MONTH_UV
      ,  NULL AS MONTH_PV
   FROM batch.MART_USER_STATS_D D
   WHERE BASIS_DATE BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'

UNION ALL

SELECT CAST(D.JOIN_KST_DT AS DATE)
     , D.JOIN_PLATFORM AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  COUNT(1) AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM {{ ref('DIM_USER_INFO') }} D
 WHERE CAST(D.JOIN_KST_DT AS DATE) BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
 GROUP BY CAST(D.JOIN_KST_DT AS DATE), D.JOIN_PLATFORM

UNION ALL

SELECT M.BASIS_DATE AS BASIS_DATE
    ,  M.PLATFORM AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  COUNT(DISTINCT M.SESSION_ID) AS PV
    ,  COUNT(DISTINCT M.PID) AS UV
    ,  COUNT(DISTINCT M.USER_ID) AS USER_ID_CNT
    ,  COUNT(DISTINCT CASE WHEN M.USER_ID IS NOT NULL THEN M.PID ELSE NULL END) AS LOGIN_ACTIVE_CNT
    ,  COUNT(DISTINCT CASE WHEN M.USER_ID IS NULL THEN M.PID ELSE NULL END) AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM (
   SELECT l.basis_dt AS BASIS_DATE
        , l.platform AS PLATFORM
        , l.session_id AS SESSION_ID
        , l.pid AS PID
        , MAX(l.user_id) AS USER_ID
     FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
     WHERE l.basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
      AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
     GROUP BY l.basis_dt, l.platform, l.session_id, l.pid
  ) M
GROUP BY M.BASIS_DATE, M.PLATFORM

UNION ALL

SELECT M.BASIS_DATE AS BASIS_DATE
    ,  'ALL' AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  COUNT(DISTINCT M.SESSION_ID) AS PV
    ,  COUNT(DISTINCT M.PID) AS UV
    ,  COUNT(DISTINCT M.USER_ID) AS USER_ID_CNT
    ,  COUNT(DISTINCT CASE WHEN M.USER_ID IS NOT NULL THEN M.PID ELSE NULL END) AS LOGIN_ACTIVE_CNT
    ,  COUNT(DISTINCT CASE WHEN M.USER_ID IS NULL THEN M.PID ELSE NULL END) AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM (
   SELECT l.basis_dt AS BASIS_DATE
        , l.session_id AS SESSION_ID
        , l.pid AS PID
        , MAX(l.user_id) AS USER_ID
     FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
     WHERE l.basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
      AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
     GROUP BY l.basis_dt, l.platform, l.session_id, l.pid
  ) M
GROUP BY M.BASIS_DATE

UNION ALL

SELECT S.BASIS_DATE AS BASIS_DATE
    ,  'ALL' AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  COUNT(DISTINCT S.USER_ID) AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM {{ ref('MART_SALE_D') }} S
WHERE S.BASIS_DATE BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
  AND S.KIND = 1
GROUP BY S.BASIS_DATE

UNION ALL

SELECT d.full_date AS BASIS_DATE
    ,  l.PLATFORM AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  COUNT(DISTINCT l.pid) AS MONTH_UV
    ,  COUNT(DISTINCT l.session_id) AS MONTH_PV
  FROM {{ source('external_mart', 'DIM_DATE') }} d
  LEFT JOIN  LOG_PID l ON d.month = l.MONTH AND d.day >= l.DAY
  WHERE d.full_date BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
  GROUP BY d.full_date, l.PLATFORM

UNION ALL

SELECT d.full_date AS BASIS_DATE
    ,  'ALL' AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  NULL AS WEEK_UV
    ,  NULL AS WEEK_PV
    ,  COUNT(DISTINCT l.pid) AS MONTH_UV
    ,  COUNT(DISTINCT l.session_id) AS MONTH_PV
  FROM {{ source('external_mart', 'DIM_DATE') }} d
  LEFT JOIN  LOG_PID l ON d.month = l.MONTH AND d.day >= l.DAY
  WHERE d.full_date BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
  GROUP BY d.full_date

UNION ALL

SELECT d.full_date AS BASIS_DATE
    ,  l.PLATFORM AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  COUNT(DISTINCT l.pid) AS WEEK_UV
    ,  COUNT(DISTINCT l.session_id) AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM {{ source('external_mart', 'DIM_DATE') }} d
  LEFT JOIN  LOG_PID l ON d.iso_week = l.WEEK AND d.week_day_monday >= l.WEEK_DAY
  WHERE d.full_date BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
  GROUP BY d.full_date, l.PLATFORM

UNION ALL

SELECT d.full_date AS BASIS_DATE
    ,  'ALL' AS PLATFORM
    ,  NULL AS TOTAL_USER_CNT
    ,  NULL AS ACTIVE_USER_CNT
    ,  NULL AS DORMANT_USER_CNT
    ,  NULL AS LEAVE_USER_CNT
    ,  NULL AS NEW_USER_CNT
    ,  NULL AS PV
    ,  NULL AS UV
    ,  NULL AS USER_ID_CNT
    ,  NULL AS LOGIN_ACTIVE_CNT
    ,  NULL AS NON_LOGIN_ACTIVE_CNT
    ,  NULL AS PAID_CNT
    ,  COUNT(DISTINCT l.pid) AS WEEK_UV
    ,  COUNT(DISTINCT l.session_id) AS WEEK_PV
    ,  NULL AS MONTH_UV
    ,  NULL AS MONTH_PV
  FROM {{ source('external_mart', 'DIM_DATE') }} d
  LEFT JOIN  LOG_PID l ON d.iso_week = l.WEEK AND d.week_day_monday >= l.WEEK_DAY
  WHERE d.full_date BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
  GROUP BY d.full_date
  ) T
GROUP BY T.BASIS_DATE, T.PLATFORM