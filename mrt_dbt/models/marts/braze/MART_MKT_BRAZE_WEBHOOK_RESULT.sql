{{
    config(
        materialized = 'table',
        schema='braze',
        alias='MART_MKT_BRAZE_WEBHOOK_RESULT',
        partition_by={
            'field': 'SEND_DATE_KST',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['CAMPAIGN_NAME']
    )
}}



SELECT a.id AS WEBHOOK_SEND_ID
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
     , TIMESTAMP_ADD(TIMESTAMP_SECONDS(a.time), INTERVAL 9 HOUR) AS SEND_TIME_KST
     , EXTRACT(DATE FROM TIMESTAMP_ADD(TIMESTAMP_SECONDS(a.time), INTERVAL 9 HOUR)) AS SEND_DATE_KST
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('external_braze', 'currents_webhook_send') }} a
WHERE a.campaign_name IS NOT NULL OR a.canvas_step_id IS NOT NULL