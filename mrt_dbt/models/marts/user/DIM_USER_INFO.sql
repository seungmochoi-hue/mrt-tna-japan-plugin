{{
    config(
        materialized = 'table',
        schema='edw_mart',
        alias='DIM_USER_INFO'
    )
}}

WITH OAUTH AS (
    SELECT
        user_id
         , provider
    FROM (
             SELECT
                 user_id
                  , provider
                  , ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY created_at ASC) AS rn
             FROM {{ source('members', 'o_auth_providers') }}
         ) WHERE rn = 1
),
     PLATFORM AS (
         SELECT
             user_id
              , MAX(APP_INSTALL_FLAG) AS APP_INSTALL_FLAG
         FROM (
                  SELECT
                      user_id
                       , REGEXP_CONTAINS(USE_PLATFORMS, r'aos|ios')  AS APP_INSTALL_FLAG
                  FROM {{ ref('FACT_USER_LOGIN_D') }}
              )
         GROUP BY user_id
     ),
     GUIDE AS (
         SELECT DISTINCT user_id FROM {{ source('mrt_20', 'guides') }}
     )
SELECT
    CAST(u.id AS STRING) AS USER_ID
     , u.created_at AS JOIN_KST_DT
     , CASE
           WHEN u.created_platform IN ('web/mobile', 'web/ios', 'web/android') THEN 'mweb'
           WHEN SPLIT(u.created_platform, '/')[OFFSET(0)] = 'android' THEN 'aos'
           ELSE SPLIT(u.created_platform, '/')[OFFSET(0)]
    END AS JOIN_PLATFORM
     , IFNULL(o.provider, 'email') AS JOIN_OAUTH_TYPE
     , IF(JSON_EXTRACT_SCALAR(u.subscription_settings, '$.sms') = 'true', TRUE, FALSE) AS SMS_RECV_AGREE
     , IF(JSON_EXTRACT_SCALAR(u.subscription_settings, '$.push') = 'true', TRUE, FALSE) AS PUSH_RECV_AGREE
     , IF(JSON_EXTRACT_SCALAR(u.subscription_settings, '$.email') = 'true', TRUE, FALSE) AS MAIL_RECV_AGREE
     , u.location_data_agree AS POSITION_ARGREEMENT_FLAG
     , u.phone_verified AS PHONE_VALID_FLAG
     , u.resting AS DORMANT_FLAG
     , IF(resting = TRUE, DATE(TIMESTAMP_ADD(u.current_sign_in_at, INTERVAL 365 DAY)), NULL) AS DORMANT_KST_DT
     , CASE
           WHEN user_withdraw IS NOT NULL THEN u.user_withdraw
           WHEN u.left_at IS NOT NULL THEN TRUE
           ELSE FALSE
    END AS LEAVE_FLAG
     , u.left_at AS LEAVE_KST_DT
     , u.mrt_staff_flag AS MRT_STAFF_FLAG
     , IF(mrt_staff_flag || test.USER_ID IS NOT NULL, TRUE, FALSE) AS TEST_FLAG
     , p.APP_INSTALL_FLAG
     , g.user_id IS NOT NULL AS GUIDE_FLAG
     , CASE WHEN u.resting = TRUE THEN 'DORMANT'
            WHEN u.left_at IS NOT NULL OR u.user_withdraw = TRUE THEN 'LEAVE'
            WHEN prev.DORMANT_FLAG = TRUE AND u.resting != TRUE THEN 'RETURN'
            WHEN u.created_at >= '{{ var("logical_end_date_utc") }}' THEN 'NEW'
            ELSE 'ACTIVE'
    END AS STATUS
     , IFNULL(GREATEST(updated_at, deleted_at), updated_at) AS UPDATE_KST_DT
     , CURRENT_DATETIME('Asia/Seoul') AS DW_LOAD_DT
FROM {{ source('members', 'users') }} u
         LEFT JOIN PLATFORM p ON CAST(u.id AS STRING) = p.user_id
         LEFT JOIN OAUTH o ON u.id = o.user_id
         LEFT JOIN GUIDE g ON u.id = g.user_id
         LEFT JOIN (SELECT USER_ID, DORMANT_FLAG FROM edw_mart.DIM_USER_INFO_HIST WHERE BASIS_DT = '{{ var("logical_start_date_utc") }}') prev ON CAST(u.id AS STRING) = prev.USER_ID
         LEFT JOIN (SELECT DISTINCT USER_ID FROM {{ ref('DIM_TEST_USER') }}) test ON CAST(u.id AS STRING) = test.USER_ID
