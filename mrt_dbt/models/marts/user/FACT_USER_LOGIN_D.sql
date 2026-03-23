{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'merge',
        schema='edw_mart',
        alias='FACT_USER_LOGIN_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by=["USER_ID"],
        pre_hook="DELETE FROM {{ this }} WHERE BASIS_DT = '{{ var('logical_start_date_kst') }}'"

    )
}}

{% call set_sql_header(config) %}
CREATE TEMP FUNCTION convert_platform(platform STRING) AS (
    CASE
        WHEN platform LIKE '%mweb%' AND platform NOT IN ('aos_webview', 'ios_webview') THEN 'mweb'
        WHEN platform  LIKE '%web%' AND platform NOT IN ('aos_webview', 'ios_webview') THEN 'web'
        WHEN platform  LIKE '%android%' OR platform LIKE '%aos%' THEN 'aos'
        WHEN platform  LIKE '%ios%' THEN 'ios'
        ELSE platform
    END
);
{% endcall %}

WITH TABLE_LOGIN AS (
    SELECT
        DATE(current_sign_in_at) AS basis_dt
        , CAST(id AS STRING) AS user_id
        , MIN(current_sign_in_at) AS login_kst_dt
    FROM {{ source('members',  'users') }}
    WHERE updated_at >= TIMESTAMP_ADD('{{ var("logical_start_date_utc") }} 15:00:00', INTERVAL 9 HOUR)  AND updated_at < TIMESTAMP_ADD('{{ var("logical_end_date_utc") }} 15:00:00', INTERVAL 9 HOUR)
      AND current_sign_in_at >= TIMESTAMP_ADD('{{ var("logical_start_date_utc") }} 15:00:00', INTERVAL 9 HOUR) AND current_sign_in_at < TIMESTAMP_ADD('{{ var("logical_end_date_utc") }} 15:00:00', INTERVAL 9 HOUR)
    GROUP BY 1,2
), LOG_LOGIN AS (
    SELECT
        DATE(TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR)) AS basis_dt
         , user_id
         , MIN(TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR)) AS login_kst_dt
         , STRING_AGG(platform ORDER BY event_timestamp ASC LIMIT 1) AS login_platform
         , STRING_AGG(DISTINCT convert_platform(platform)) AS USE_PLATFORMS
    FROM {{ source('log_stream', 'biz_log') }}
    WHERE
        user_id IS NOT NULL AND user_id NOT IN ('', ' ', 'null')
      AND NOT (event_type = 'truck' AND event_name = 'user_join')
      AND basis_dt BETWEEN '{{ var("logical_start_date_utc") }}' AND '{{ var("logical_end_date_utc") }}'
      AND event_timestamp >= '{{ var("logical_start_date_utc") }} 15:00:00' AND event_timestamp < '{{ var("logical_end_date_utc") }} 15:00:00'
    GROUP BY 1,2
)
SELECT
    COALESCE(t.basis_dt, l.basis_dt) AS BASIS_DT
     , COALESCE(t.user_id, l.user_id) AS USER_ID
     , COALESCE(l.login_kst_dt, t.login_kst_dt) AS LOGIN_KST_DT
     , convert_platform(l.login_platform) AS LOGIN_PLATFORM
     , l.USE_PLATFORMS
     , CASE
           WHEN t.user_id IS NOT NULL AND l.user_id IS NOT NULL THEN 'BOTH'
           WHEN t.user_id IS NOT NULL THEN 'TABLE'
           WHEN l.user_id IS NOT NULL THEN 'LOG'
    END AS DATA_TYPE
     , CURRENT_DATETIME('Asia/Seoul') AS DW_LOAD_DT
FROM TABLE_LOGIN t
    FULL OUTER JOIN LOG_LOGIN l ON t.basis_dt = l.basis_dt AND t.user_id = l.user_id