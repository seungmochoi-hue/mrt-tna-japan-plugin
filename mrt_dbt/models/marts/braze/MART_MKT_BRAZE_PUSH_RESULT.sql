{{
    config(
        materialized = 'table',
        schema='braze',
        alias='MART_MKT_BRAZE_PUSH_RESULT',
        partition_by={
            'field': 'SEND_DATE_KST',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['CAMPAIGN_NAME']
    )
}}


WITH PUSH_SEND AS (
    SELECT  id AS push_send_id
          , user_id
          , external_user_id
          , campaign_name
          , campaign_id
          , canvas_id
          , canvas_name
          , canvas_variation_id
          , canvas_variation_name
          , canvas_step_id
          , canvas_step_name
          , TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS send_time_kst
          , EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS send_date_kst
           -- 2개 이상의 기기에 push가 전송되는 케이스에 대한 중복 처리를 위해 odr 조건 추가함 (user_id, campaign 또는 canvas, 날짜 기준으로 1회만 인정)
          , ROW_NUMBER() OVER(PARTITION BY CONCAT(user_id, COALESCE(campaign_id, canvas_step_id), EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)))) odr1
          FROM {{ source('external_braze', 'currents_pushnotification_send') }}
),
PUSH_CLICK AS (
    SELECT user_id
         , external_user_id
         , campaign_name
         , campaign_id
         , canvas_id
         , canvas_name
         , canvas_variation_id
         , canvas_variation_name
         , canvas_step_id
         , canvas_step_name
         , TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS click_time_kst
         , EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS click_date_kst
         , ROW_NUMBER() OVER(PARTITION BY CONCAT(user_id, COALESCE(campaign_id, canvas_step_id), EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)))) odr2
    FROM {{ source('external_braze', 'currents_pushnotification_open') }}
)
SELECT a.push_send_id AS PUSH_SEND_ID
      , a.user_id AS USER_ID
      , a.external_user_id AS EXTERNAL_USER_ID
      , a.campaign_name AS CAMPAIGN_NAME
      , a.campaign_id AS CAMPAIGN_ID
      , a.canvas_id AS CANVAS_ID
      , a.canvas_name AS CANVAS_NAME
      , a.canvas_variation_id AS CANVAS_VARIATION_ID
      , a.canvas_variation_name AS CANVAS_VARIATION_NAME
      , a.canvas_step_id AS CANVAS_STEP_ID
      , a.canvas_step_name AS CANVAS_STEP_NAME
      , a.send_time_kst AS SEND_TIME_KST
      , a.send_date_kst AS SEND_DATE_KST
      , b.click_time_kst AS CLICK_TIME_KST
      , b.click_date_kst AS CLICK_DATE_KST
      , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM PUSH_SEND a
LEFT JOIN PUSH_CLICK b ON a.user_id = b.user_id
                       AND COALESCE(a.campaign_id, a.canvas_step_id) = COALESCE(b.campaign_id, b.canvas_step_id)
                       AND a.send_time_kst < b.click_time_kst
                       AND b.click_time_kst < TIMESTAMP_ADD(a.send_time_kst , INTERVAL 24 HOUR)
WHERE odr1=1 AND (odr2 IS NULL OR odr2 = 1)