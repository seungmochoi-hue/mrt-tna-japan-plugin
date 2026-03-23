{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_BIZ_LOG_EURORAIL_PID_CONVERSION_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day'
        },
        pre_hook="DELETE FROM {{ this }} WHERE BASIS_DATE BETWEEN '{{ var('start_date_kst') }}' AND '{{ var('end_date_kst') }}' "
    )
}}

WITH USER_LOGIN_TERM AS (
    SELECT  m.basis_dt AS BASIS_DATE
         ,  m.pid AS PID
         ,  m.user_id AS USER_ID
         ,  CASE WHEN MIN(m.min_event_timestamp_kst) OVER (PARTITION BY m.basis_dt, m.pid) = m.min_event_timestamp_kst THEN TIMESTAMP(CONCAT(CAST(CAST(m.min_event_timestamp_kst AS DATE) AS STRING), ' 00:00:00')) ELSE m.min_event_timestamp_kst END  AS MIN_TIME
         ,  IFNULL(LAG(m.min_event_timestamp_kst) OVER (PARTITION BY m.basis_dt, m.pid ORDER BY m.min_event_timestamp_kst DESC), TIMESTAMP(CONCAT(CAST(CAST(m.min_event_timestamp_kst AS DATE) AS STRING), ' 23:59:59'))) AS MAX_TIME
    FROM {{ ref('DIM_BIZ_LOG_USER_MAPPING') }} m
    WHERE m.basis_dt BETWEEN '{{ var("start_date_kst") }}' AND '{{ var("end_date_kst") }}'
),
BASE_LOG AS (
    SELECT l.basis_dt
        ,  l.pid
        ,  l.user_id
        ,  l.platform
        ,  l.data
        ,  l.ref_url
        ,  l.screen_name
        ,  l.item_id
        ,  l.event_name
        ,  l.event_type
        ,  l.utm
        ,  l.event_timestamp_kst
        ,  l.ds.order_id
        ,  l.ds.reservation_id
    FROM {{ ref("DW_BIZ_LOG_VIEW") }} l
    LEFT JOIN USER_LOGIN_TERM u ON l.basis_dt = u.BASIS_DATE AND l.pid = u.PID AND l.event_timestamp_kst > u.MIN_TIME AND l.event_timestamp_kst <= u.MAX_TIME
    WHERE l.basis_dt BETWEEN '{{ var("start_date_kst") }}' AND '{{ var("end_date_kst") }}'
      AND l.screen_name IN ('europe_train_ticket_search_result','checkout','checkout_complete')
      AND l.event_type = 'pageview'
),
TICKET_SEARCH AS (
    SELECT b.basis_dt
        ,  b.pid
        ,  b.user_id
        ,  b.platform
        ,  JSON_VALUE(b.data, '$.departure') AS departure
        ,  JSON_VALUE(b.data, '$.arrival') AS arrival
        ,  JSON_VALUE(b.data, '$.journey') AS journey
        ,  JSON_VALUE(b.data, '$.direction') AS direction
        ,  b.ref_url
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_source'), JSON_VALUE(b.utm, '$.utm_source')) AS utm_source
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_campaign'), JSON_VALUE(b.utm, '$.utm_campaign')) AS utm_campaign
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_medium'), JSON_VALUE(b.utm, '$.utm_medium')) AS utm_medium
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_content'), JSON_VALUE(b.utm, '$.utm_content')) AS utm_content
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_term'), JSON_VALUE(b.utm, '$.utm_term')) AS utm_term
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_n_ad'), JSON_VALUE(b.utm, '$.n_ad')) AS n_ad
        ,  IFNULL(JSON_VALUE(b.utm, '$.recent_n_campaign_type'), JSON_VALUE(b.utm, '$.n_campaign_type')) AS n_campaign_type
        ,  MIN(b.event_timestamp_kst) AS event_timestamp_kst
    FROM BASE_LOG b
    WHERE b.screen_name = 'europe_train_ticket_search_result'
    GROUP BY b.basis_dt, b.pid, b.user_id, b.platform, JSON_VALUE(b.data, '$.departure'), JSON_VALUE(b.data, '$.arrival')
          ,  JSON_VALUE(b.data, '$.journey'), JSON_VALUE(b.data, '$.direction'),  b.ref_url
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_source'), JSON_VALUE(b.utm, '$.utm_source'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_campaign'), JSON_VALUE(b.utm, '$.utm_campaign'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_medium'), JSON_VALUE(b.utm, '$.utm_medium'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_content'), JSON_VALUE(b.utm, '$.utm_content'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_utm_term'), JSON_VALUE(b.utm, '$.utm_term'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_n_ad'), JSON_VALUE(b.utm, '$.n_ad'))
          ,  IFNULL(JSON_VALUE(b.utm, '$.recent_n_campaign_type'), JSON_VALUE(b.utm, '$.n_campaign_type'))
),
CHECKOUT AS (
    SELECT l.basis_dt
         , l.pid
         , l.item_id
         , MIN(l.event_timestamp_kst) AS event_timestamp_kst
    FROM BASE_LOG l
    JOIN {{ source ('mrt_mart_view', 'MART_PRODUCT_D') }} p ON l.item_id = p.gid
    WHERE l.event_name = 'checkout'
      AND l.event_type = 'pageview'
      AND p.STANDARD_CATEGORY_LV_3_CD = 'EUROPE_TRAIN'
    GROUP BY l.basis_dt, l.pid, l.item_id
),
CHECKOUT_COMPLETE AS (
    SELECT l.basis_dt
         , l.pid
         , l.item_id
         , MIN(l.event_timestamp_kst) AS event_timestamp_kst
         , MIN(l.order_id) AS order_id
         , MIN(l.reservation_id) AS reservation_id
    FROM BASE_LOG l
    JOIN {{ source ('mrt_mart_view', 'MART_PRODUCT_D') }} p ON l.item_id = p.gid
    WHERE l.event_name = 'checkout_complete'
      AND l.event_type = 'pageview'
      AND p.STANDARD_CATEGORY_LV_3_CD = 'EUROPE_TRAIN'
    GROUP BY l.basis_dt, l.pid, l.item_id
)
SELECT b.basis_dt AS BASIS_DATE
     , b.pid AS PID
     , b.user_id AS USER_ID
     , b.platform AS PLATFORM
     , c.item_id AS ITEM_ID
     , b.departure AS DEPARTURE_NM
     , b.arrival AS ARRIVAL_NM
     , b.journey AS JOURNEY_CD
     , b.direction AS DIRECTION_CD
     , b.ref_url AS REF_URL
     , b.utm_source AS UTM_SOURCE
     , b.utm_campaign AS UTM_CAMPAIGN
     , b.utm_medium AS UTM_MEDIUM
     , b.utm_content AS UTM_CONTENT
     , b.utm_term AS UTM_TERM
     , b.n_ad AS N_AD
     , b.n_campaign_type AS N_CAMPAIGN_TYPE
     , b.event_timestamp_kst AS OFFER_DETAIL_DT
     , c.event_timestamp_kst AS CHECKOUT_DT
     , cc.event_timestamp_kst AS CHECKOUT_COMPLETE_DT
     , cc.order_id AS CHECKOUT_COMPLETE_ORDER_ID
     , cc.reservation_id AS CHECKOUT_COMPLETE_RESVE_ID
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM TICKET_SEARCH b
LEFT JOIN CHECKOUT c ON c.pid = b.pid AND c.basis_dt = b.basis_dt
LEFT JOIN CHECKOUT_COMPLETE cc ON c.pid = cc.pid AND c.basis_dt = cc.basis_dt AND c.item_id = cc.item_id
