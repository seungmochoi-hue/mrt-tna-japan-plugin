{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key = 'user_id',
        schema='edw_biz_log',
        alias='FACT_USER_LAST_LOGIN_D',
        cluster_by = ['user_id'],
        merge_update_columns=['is_install_app', 'last_login_dt_kst', 'last_login_platform', 'dw_load_dt']
    )
}}



WITH RANKED_LOGINS AS (
    SELECT
        user_id
        , platform
        , start_event_timestamp_kst
        , ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY start_event_timestamp_kst DESC) AS rn
    FROM {{ ref('DIM_BIZ_LOG_KEY_MAPPING') }}
    WHERE basis_dt BETWEEN "{{ var('logical_start_date_kst') }}" AND "{{ var('logical_end_date_kst') }}"
),

AGGREGATED_LOGINS AS (
    SELECT
        user_id
        , MAX(CASE WHEN platform IN ('aos', 'ios') THEN TRUE ELSE FALSE END) AS is_install_app
        , MAX(start_event_timestamp_kst) AS last_login_dt_kst
        , MAX(CASE WHEN rn = 1 THEN platform END) AS last_login_platform
        , CURRENT_DATETIME('Asia/Seoul') AS dw_load_dt
    FROM RANKED_LOGINS
    GROUP BY user_id
)

SELECT *
FROM AGGREGATED_LOGINS
