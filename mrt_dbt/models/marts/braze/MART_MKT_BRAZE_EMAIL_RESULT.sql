{{
    config(
        materialized = 'table',
        schema='braze',
        alias='MART_MKT_BRAZE_EMAIL_RESULT',
        partition_by={
            'field': 'SEND_DATE_KST',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


WITH EMAIL_SEND AS (
    SELECT id AS email_send_id
      ,   user_id
      ,   external_user_id
      ,   campaign_name
      ,   campaign_id
      ,   canvas_id
      ,   canvas_name
      ,   canvas_variation_id
      ,   canvas_variation_name
      ,   canvas_step_id
      ,   canvas_step_name
      ,   TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS send_time_kst
      ,   EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS send_date_kst
    FROM {{ source('external_braze', 'currents_email_send') }}
),
EMAIL_OPEN AS (
    SELECT user_id
        ,  external_user_id
        ,  campaign_name
        ,  campaign_id
        ,  canvas_id
        ,  canvas_name
        ,  canvas_variation_id
        ,  canvas_variation_name
        ,  canvas_step_id
        ,  canvas_step_name
        ,  TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS open_time_kst
        ,  EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS open_date_kst
    FROM {{ source('external_braze', 'currents_email_open') }}
),
EMAIL_CLICK AS (
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
    FROM {{ source('external_braze', 'currents_email_click') }}
)
SELECT  a.email_send_id AS EMAIL_SEND_ID
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
      , b.open_time_kst AS OPEN_TIME_KST
      , b.open_date_kst AS OPEN_DATE_KST
      , c.click_time_kst AS CLICK_TIME_KST
      , c.click_date_kst AS CLICK_DATE_KST
      , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM EMAIL_SEND a
LEFT JOIN EMAIL_OPEN b ON a.user_id = b.user_id
                       AND IFNULL(a.campaign_id, 'na') = IFNULL(b.campaign_id, 'na')
                       AND IFNULL(a.canvas_step_id, 'na') = IFNULL(b.canvas_step_id, 'na')
                       AND a.send_time_kst < b.open_time_kst
                       AND b.open_time_kst < TIMESTAMP_ADD(a.send_time_kst , INTERVAL 3 DAY)
LEFT JOIN EMAIL_CLICK c ON a.user_id = c.user_id
                       AND IFNULL(a.campaign_id, 'na') = IFNULL(c.campaign_id, 'na')
                       AND IFNULL(a.canvas_step_id, 'na') = IFNULL(c.canvas_step_id, 'na')
                       AND a.send_time_kst < c.click_time_kst
                       AND c.click_time_kst < TIMESTAMP_ADD(a.send_time_kst , INTERVAL 3 DAY)