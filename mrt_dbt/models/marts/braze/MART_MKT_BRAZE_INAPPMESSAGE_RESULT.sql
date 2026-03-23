{{
    config(
        materialized = 'table',
        schema='braze',
        alias='MART_MKT_BRAZE_INAPPMESSAGE_RESULT',
        partition_by={
            'field': 'IMPRESSION_DATE_KST',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['CAMPAIGN_NAME']
    )
}}


WITH INAPPMESSAGE_IMPRESSION AS (
    SELECT id AS inappmessage_impression_id
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
         , TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS impression_time_kst
         , EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS impression_date_kst
    FROM {{ source('external_braze', 'currents_inappmessage_impression') }}
),
INAPPMESSAGE_CLICK AS (
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
         , button_id
         , TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR) AS click_time_kst
         , EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(time) , INTERVAL 9 HOUR)) AS click_date_kst
     FROM {{ source('external_braze', 'currents_inappmessage_click') }}
)
SELECT a.inappmessage_impression_id AS INAPPMESSAGE_IMPRESSION_ID
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
     , a.impression_time_kst AS IMPRESSION_TIME_KST
     , a.impression_date_kst AS IMPRESSION_DATE_KST
     , c.click_time_kst AS CLICK_TIME_KST
     , c.click_date_kst AS CLICK_DATE_KST
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM INAPPMESSAGE_IMPRESSION a
LEFT JOIN INAPPMESSAGE_CLICK c ON a.user_id = c.user_id
                               AND IFNULL(a.campaign_id, 'na') = IFNULL(c.campaign_id, 'na')
                               AND IFNULL(a.canvas_step_id, 'na') = IFNULL(c.canvas_step_id, 'na')
                               AND a.impression_time_kst < c.click_time_kst
                               AND c.click_time_kst < TIMESTAMP_ADD(a.impression_time_kst , INTERVAL 1 DAY)
                               AND (c.button_id = '1' OR c.button_id IS NULL)