{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        schema='edw_biz_log',
        alias='DIM_BIZ_LOG_KEY_MAPPING',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day'
        },
        require_partition_filter = true,
        pre_hook="DELETE FROM {{ this }} WHERE BASIS_DT = '{{ var('logical_start_date_kst') }}'"
    )
}}

SELECT
    basis_dt
     , user_id
     , session_id
     , pid
     , MAX(adid) AS adid
     , MAX(udid) AS udid
     , MIN(event_timestamp_kst) AS start_event_timestamp_kst
     , MAX(
        CASE
            WHEN platform LIKE '%mweb%' AND platform NOT IN ('aos_webview', 'ios_webview') THEN 'mweb'
            WHEN platform LIKE '%web%' AND platform NOT IN ('aos_webview', 'ios_webview') THEN 'web'
            WHEN platform LIKE '%android%' OR platform LIKE '%aos%' THEN 'aos'
            WHEN platform LIKE '%ios%' THEN 'ios'
            ELSE platform END
    ) AS platform
     , CURRENT_TIMESTAMP() AS dw_load_dt
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE user_id IS NOT NULL
  AND session_id IS NOT NULL
  AND pid IS NOT NULL
  AND basis_dt >= "{{ var('logical_start_date_kst') }}" AND basis_dt < "{{ var('logical_end_date_kst') }}"
GROUP BY basis_dt, user_id, session_id, pid