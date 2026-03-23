{{
    config(
        materialized = 'incremental',
        schema='batch',
        alias='community_log_v2',
        pre_hook=[
            "DELETE FROM {{ this }} WHERE basis_dt =  '{{ var('logical_start_date_kst') }}'"
        ]
    )
}}

SELECT basis_dt
     , screen_name
     , session_id
     , pid
     , user_id
     , event_name
     , event_type
     , platform
     , event_timestamp_kst
     , JSON_VALUE(data, '$.post_id') AS post_id
     , item_id
     , item_kind
     , JSON_VALUE(data, '$.board_id') AS board_id
     , JSON_VALUE(data, '$.board_name') AS board_name
     , JSON_VALUE(data, '$.category_id') AS category_id
     , JSON_VALUE(data, '$.category_name') AS category_name
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE basis_dt =  '{{ var("logical_start_date_kst") }}'
  AND (screen_name LIKE '%community%' OR screen_name IN ('immersive_detail'))