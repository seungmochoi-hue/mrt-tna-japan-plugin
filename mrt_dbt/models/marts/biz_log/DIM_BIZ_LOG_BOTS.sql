{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        schema='edw_biz_log',
        alias='DIM_BIZ_LOG_BOTS',
        cluster_by = ['key_type', 'bot_key'],
        unique_key = ['key_type', 'bot_key'],
        merge_update_columns = [],
        require_partition_filter = true
    )
}}

{% set bot_regex = ['robot',
        'AdsBot',
        'Googlebot',
        'Mediapartners-Google',
        'Applebot',
        'Pinterestbot',
        'Bingbot',
        'Slurp',
        'DuckDuckBot',
        'Baiduspider',
        'YandexBot',
        'Baiduspider',
        'Spider',
        'facebot',
        'facebookexternalhit',
        'ia_archiver',
        'Yeti',
        'ahrefs',
        'Headless',
        'Mypack_flight_crawling'
]
%}

WITH FRAME AS (
    SELECT
        basis_dt
        , pid
        , client_ip
        , user_id
        , event_type
        , NULLIF(JSON_EXTRACT_SCALAR(data, '$.ref_url'), '') AS ref_url
        , REGEXP_CONTAINS(device, r'{{"|".join(bot_regex)}}') AS is_bot
    FROM {{ source('log_stream', 'biz_log') }}
    WHERE basis_dt BETWEEN "{{ var('logical_start_date_kst') }}" AND "{{ var('logical_end_date_kst') }}"
)
, BOT_CLIENT AS (
    SELECT
        client_ip
        , 'user agent detect' AS detail
    FROM FRAME
    WHERE is_bot IS TRUE
    AND client_ip NOT LIKE '10.30.%'
    AND client_ip IS NOT NULL
    GROUP BY client_ip
)
SELECT
    'pid' AS key_type
    , pid AS bot_key
    , 'rule detect' AS detail
    , DATETIME(current_timestamp(), 'Asia/Seoul') AS dw_load_dt
FROM (
    SELECT
        basis_dt
        , pid
        , SUM(CASE event_type WHEN 'init' THEN 1 ELSE 0 END) AS initCount
        , SUM(CASE event_type WHEN 'pageview' THEN 1 ELSE 0 END) AS pageviewCount
        , SUM(CASE WHEN event_type = 'pageview' AND ref_url IS NULL THEN 1 ELSE 0 END) AS noRefPageviewCount
        , SUM(CASE event_type WHEN 'click' THEN 1 ELSE 0 END) AS clickCount
        , SUM(CASE event_type WHEN 'impression' THEN 1 ELSE 0 END) AS impressionCount
    FROM FRAME
    WHERE client_ip NOT IN ( SELECT client_ip FROM BOT_CLIENT )
        AND pid IS NOT NULL
    GROUP BY basis_dt, pid
    HAVING
        clickCount = 0
        AND impressionCount = 0
        AND pageviewCount > 10
        AND initCount = pageviewCount
        AND pageviewCount = noRefPageviewCount
        AND MAX(user_id) IS NULL
)
GROUP BY bot_key
UNION ALL
SELECT
    'ip' AS key_type
     , client_ip AS bot_key
     , 'user agent detect' AS detail
     , DATETIME(current_timestamp(), 'Asia/Seoul') AS dw_load_dt
FROM BOT_CLIENT