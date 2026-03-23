{{
    config(
        materialized = 'incremental',
        schema='business',
        alias='community_logs_v1',
        pre_hook=[
            "DELETE FROM {{ this }} WHERE BASIS_DT =  '{{ var('logical_start_date_kst') }}'"
        ]
    )
}}

WITH DATASET AS (
    SELECT basis_dt, DATETIME(event_timestamp_kst) AS event_timestamp_kst, screen_name, event_type, event_name, platform, user_id, pid, item_id, item_kind,
           JSON_VALUE(l.data, '$.board_id') AS board_id,
           JSON_VALUE(l.data, '$.board_name') AS board_name,
           JSON_VALUE(l.data, '$.category_id') AS category_id,
           JSON_VALUE(l.data, '$.category_name') AS category_name,
           JSON_VALUE(device, '$.app_info_version') AS app_version,
           data,
           item_type,
           item_name,
           JSON_VALUE(l.data, '$.tab_name') AS tab_name,
           JSON_VALUE(l.data, '$.marker_type') AS marker_type,
           geo AS geo
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
    WHERE basis_dt = '{{ var("logical_start_date_kst") }}'
      AND screen_name IN ('community_home', 'community_home_popup', 'board_selector','community_onboarding','community_onboarding_guideline','community_post_write','community_post_detail', 'community_comment_detail'
        -- 소셜 추가 (25.03.12)
        ,  'social_my_home', 'Social_Region_Search', 'social_avatar_detail','social_pet_detail','social_my_pet_list','social_pet_catalog'
        , 'social_full_screen_guide','social_mission_attendance')

    UNION ALL

    SELECT basis_dt, DATETIME(event_timestamp_kst) AS event_timestamp_kst, screen_name, event_type, event_name, platform, user_id, pid, item_id, item_kind,
           JSON_VALUE(l.data, '$.board_id') AS board_id,
           JSON_VALUE(l.data, '$.board_name') AS board_name,
           JSON_VALUE(l.data, '$.category_id') AS category_id,
           JSON_VALUE(l.data, '$.category_name') AS category_name,
           JSON_VALUE(device, '$.app_info_version') AS app_version,
           data,
           item_type,
           item_name,
           JSON_VALUE(l.data, '$.tab_name') AS tab_name,
           JSON_VALUE(l.data, '$.marker_type') AS marker_type,
           geo AS geo
    FROM {{ ref("DW_BIZ_LOG_VIEW") }} l
    WHERE basis_dt  = '{{ var("logical_start_date_kst") }}'
      AND l.event_type = 'impression'
      AND screen_name IN ('community_home', 'community_home_popup', 'board_selector','community_onboarding','community_onboarding_guideline','community_post_write','community_post_detail', 'community_comment_detail'
        -- 소셜 추가 (25.03.12)
        ,  'social_my_home', 'Social_Region_Search', 'social_avatar_detail','social_pet_detail','social_my_pet_list','social_pet_catalog'
        , 'social_full_screen_guide','social_mission_attendance')
)
SELECT * EXCEPT(item_type, item_name, tab_name, marker_type, geo)
, CURRENT_DATETIME() AS updated_at
, item_type, item_name, tab_name, marker_type, geo
FROM DATASET