{{
    config(
        materialized = 'table',
        schema='batch',
        alias='CHANNEL_USERCHATS_INFO'
    )
}}

WITH DEPTHS_TP AS (
    SELECT id
    , MIN(CASE WHEN unnest_tags NOT LIKE '%무응답%' AND RIGHT(LOWER(unnest_tags), 2) = '1d' THEN SUBSTR(TRIM(LOWER(unnest_tags)), 0, LENGTH(TRIM(unnest_tags))- 3) END) AS depth1
    , MIN(CASE WHEN unnest_tags NOT LIKE '%무응답%' AND RIGHT(LOWER(unnest_tags), 2) = '2d' THEN SUBSTR(TRIM(LOWER(unnest_tags)), 0, LENGTH(TRIM(unnest_tags))- 3) END) AS depth2
    , MIN(CASE WHEN unnest_tags NOT LIKE '%무응답%' AND RIGHT(LOWER(unnest_tags), 2) = '3d' THEN SUBSTR(TRIM(LOWER(unnest_tags)), 0, LENGTH(TRIM(unnest_tags))- 3) END) AS depth3
    , MIN(CASE WHEN unnest_tags NOT LIKE '%무응답%' AND LOWER(tags) LIKE '%1d%' AND RIGHT(LOWER(unnest_tags), 2) NOT IN ('1d', '2d', '3d') AND unnest_tags NOT LIKE '%bot%' THEN TRIM(unnest_tags) END) AS category
    , MIN(CASE WHEN unnest_tags LIKE '%무응답%' THEN TRIM(unnest_tags) END) AS no_answer
    FROM {{ source('external', 'DW_CHANNEL_USERCHATS') }}, UNNEST(split(replace(trim(tags, '[]'), '\'', ''))) AS unnest_tags
    GROUP BY 1
)
SELECT id
    , TIMESTAMP_ADD(TIMESTAMP_MILLIS(CAST(createdAt AS INT64)), INTERVAL 9 HOUR) AS createdAt_kst
    , MIN(CASE
            WHEN RIGHT(LOWER(unnest_tags), 2) = '1d' THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_1d)', ''))
            WHEN RIGHT(LOWER(unnest_tags), 2) != '1d' AND TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_1d)', '')) IN (SELECT DISTINCT depth1 FROM DEPTHS_TP) THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_1d)', ''))
          END) AS depth1
    , MIN(CASE
            WHEN RIGHT(LOWER(unnest_tags), 2) = '2d' THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_2d)', ''))
            WHEN RIGHT(LOWER(unnest_tags), 2) != '2d' AND TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_2d)', '')) IN (SELECT DISTINCT depth2 FROM DEPTHS_TP) THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_2d)', ''))
          END) AS depth2
    , MIN(CASE
            WHEN RIGHT(LOWER(unnest_tags), 2) = '3d' THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_3d)', ''))
            WHEN RIGHT(LOWER(unnest_tags), 2) != '3d' AND TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_3d)', '')) IN (SELECT DISTINCT depth3 FROM DEPTHS_TP) THEN TRIM(REGEXP_REPLACE(unnest_tags, r'(?i)(_3d)', ''))
          END) AS depth3
    , MIN(CASE WHEN unnest_tags NOT LIKE '%무응답%' AND TRIM(unnest_tags) IN (SELECT category FROM DEPTHS_TP) AND unnest_tags NOT LIKE '%bot%' THEN TRIM(unnest_tags) END) AS category
    , MIN(CASE WHEN unnest_tags LIKE '%무응답%' THEN TRIM(unnest_tags) END) AS no_answer
FROM {{ source('external', 'DW_CHANNEL_USERCHATS') }}, UNNEST(split(replace(trim(tags, '[]'), '\'', ''))) AS unnest_tags
GROUP BY 1, 2