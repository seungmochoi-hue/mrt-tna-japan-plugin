{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_TAB_USER_PAGEVIEW_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

WITH PAGEVIEW_HOUR AS (
 SELECT l.basis_dt AS BASIS_DATE
      , EXTRACT(HOUR FROM l.event_timestamp_kst) AS DAY_HOUR
      , l.platform AS PLATFORM
      , l.session_id
      , l.pid
   FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
  WHERE basis_dt BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}'
    AND (l.event_type = 'pageview' OR l.event_name = 'pageview')
)
SELECT P.BASIS_DATE
    ,  'ALL' AS DAY_HOUR
    ,  'ALL' AS PLATFORM
    ,  COUNT(1) AS PV
    ,  COUNT(DISTINCT P.pid) AS UV
  FROM PAGEVIEW_HOUR P
GROUP BY P.BASIS_DATE

UNION ALL

SELECT P.BASIS_DATE
    ,  'ALL' AS DAY_HOUR
    ,  P.PLATFORM AS PLATFORM
    ,  COUNT(1) AS PV
    ,  COUNT(DISTINCT P.pid) AS UV
 FROM PAGEVIEW_HOUR P
GROUP BY P.BASIS_DATE, P.PLATFORM

UNION ALL

SELECT P.BASIS_DATE
    ,  IF(P.DAY_HOUR < 10, '0' || CAST(P.DAY_HOUR AS STRING), CAST(P.DAY_HOUR AS STRING))  AS DAY_HOUR
    ,  'ALL' AS PLATFORM
    ,  COUNT(1) AS PV
    ,  COUNT(DISTINCT P.pid) AS UV
 FROM PAGEVIEW_HOUR P
GROUP BY P.BASIS_DATE, P.DAY_HOUR

UNION ALL

SELECT P.BASIS_DATE
    ,  IF(P.DAY_HOUR < 10, '0' || CAST(P.DAY_HOUR AS STRING), CAST(P.DAY_HOUR AS STRING))  AS DAY_HOUR
    ,  P.PLATFORM AS PLATFORM
    ,  COUNT(1) AS PV
    ,  COUNT(DISTINCT P.pid) AS UV
 FROM PAGEVIEW_HOUR P
GROUP BY P.BASIS_DATE, P.DAY_HOUR, P.PLATFORM