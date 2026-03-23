{{
    config(
        materialized='table',
        schema='edw_biz_log',
        alias=make_date_partitioned_table_name('DW_BIZ_LOG'),
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by = ['event_type', 'screen_name', 'event_name'],
        require_partition_filter = true
    )
}}





{% call set_sql_header(config) %}
{% raw %}
CREATE TEMP FUNCTION extract_data(data String, meta String)
    RETURNS STRUCT<
{% endraw %}{{ var('struct_fields') }}{% raw %}>
    LANGUAGE js
AS R"""
if(!data || !meta) { return null; }
let parse_data = JSON.parse(data);
let parse_meta = JSON.parse(meta);
let defaults = new Set(['gid','gpid','item_horizon_index','item_vertical_index','section_horizon_index','section_name','section_title','section_vertical_index']);
let result = {};

for (let i = parse_meta.length; i > 0; i--) {
  const key = parse_meta[i-1].key;
  const dwField = parse_meta[i-1].dwField || (defaults.has(key) ? key : null);

  if(dwField && !result[dwField]) {
    if(key.indexOf('.') == -1) {
      const value = parse_data[key];
      result[dwField] = (typeof value === 'string') ? value : JSON.stringify(value);
    } else {
      const value = key.split(".").reduce((p,c)=>p&&p[c]||null, parse_data);
      result[dwField] = (typeof value === 'string') ? value : JSON.stringify(value);
    }
  }
}
return result;
""";
{% endraw %}
{% endcall %}
WITH RAW_LOG AS (
    SELECT
        * EXCEPT(dw_load_dt)
        , ROW_NUMBER() OVER (PARTITION BY DIV(UNIX_MILLIS(event_timestamp),100), session_id, pid, udid, adid, user_id, client_ip, event_type, event_name, event_key, data) AS duplicate_index
    FROM {{ source('log_stream','biz_log') }}
    WHERE basis_dt BETWEEN "{{ var('logical_start_date_utc') }}" AND "{{ var('logical_end_date_utc') }}"
        AND (received_timestamp >= "{{ var('logical_start_date_utc') }} 15:00:00" AND received_timestamp < "{{ var('logical_end_date_utc') }} 15:00:00")
        AND event_type NOT IN ('init', 'performance', 'abtest')
        AND ((event_type != 'purchase' AND session_id IS NOT NULL) OR (event_type = 'purchase'))
        AND client_ip != ''
)
, BOTS_IP AS (
    SELECT
        basis_dt
        , bot.bot_key
        , SPLIT(bot_key, ',')[OFFSET(0)] AS start_ip
        , CASE WHEN REGEXP_CONTAINS(bot_key, r',') THEN SPLIT(bot_key, ',')[OFFSET(1)] ELSE bot_key END AS end_ip
    FROM {{ ref('DIM_BIZ_LOG_BOTS') }} bot , UNNEST(GENERATE_DATE_ARRAY("{{ var('logical_start_date_utc') }}", "{{ var('logical_end_date_utc') }}")) basis_dt
    WHERE key_type = 'ip'
)
, BOTS_PID AS (
    SELECT bot.bot_key
    FROM {{ ref('DIM_BIZ_LOG_BOTS') }} bot
    WHERE key_type = 'pid'
)
, LOG AS (
    SELECT l.*
    FROM RAW_LOG l
        LEFT JOIN BOTS_IP bi ON l.basis_dt = bi.basis_dt AND NET.SAFE_IP_FROM_STRING(l.client_ip) BETWEEN NET.SAFE_IP_FROM_STRING(bi.start_ip) AND NET.SAFE_IP_FROM_STRING(bi.end_ip)
        LEFT JOIN BOTS_PID bp ON l.pid = bp.bot_key
    WHERE duplicate_index = 1 AND ((bi.bot_key IS NULL AND bp.bot_key IS NULL) OR l.platform IN ('aos', 'ios') OR l.event_type IN ('track'))
)
, META AS (
    SELECT
        platform
        , event_type
        , event_name
        , modify_event_name
        , screen_name
        , version
        , data_field
        , ARRAY_AGG(IFNULL(screen_name, 'ALL')) OVER(PARTITION BY platform, event_type, event_name) as screen_names
    FROM {{ source('log_biz', 'biz_log_meta') }}
)
SELECT

    DATE(TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR)) AS basis_dt
    , event_timestamp
    , TIMESTAMP_ADD(event_timestamp, INTERVAL 9 HOUR) AS event_timestamp_kst
    , received_timestamp
    , TIMESTAMP_ADD(received_timestamp, INTERVAL 9 HOUR) AS received_timestamp_kst
    , CASE
        WHEN l.platform IN (
            'aos', 'aos_mweb', 'aos_webview'
            , 'ios', 'ios_mweb', 'ios_webview'
            , 'web') THEN l.platform
        WHEN l.platform = 'web/android' THEN 'aos_mweb'
        WHEN l.platform = 'web/ios' THEN 'ios_mweb'
        WHEN l.platform = 'web/mobile' THEN 'mweb'
        WHEN l.platform LIKE '%android%' THEN 'aos'
        WHEN l.platform LIKE '%ios%' THEN 'ios'
        WHEN l.platform LIKE '%web%' THEN 'web'
        ELSE l.platform
    END AS platform
    , session_id
    , pid
    , udid
    , adid
    , NULLIF(JSON_VALUE(data, '$.mylink_id'),'') AS mylink_id
    , CASE WHEN user_id = '' OR user_id = '0' THEN NULL ELSE user_id END AS user_id
    , client_ip
    , l.event_type
    , IFNULL(l.screen_name, JSON_VALUE(data, '$.screen_name')) AS screen_name
    , IFNULL(m.modify_event_name, l.event_name) AS event_name
    , event_key
    , udf.decode(JSON_VALUE(l.data, '$.url')) AS url
    , udf.decode(IFNULL(JSON_VALUE(l.data, '$.ref_url')
        , IFNULL(JSON_VALUE(l.data, '$.refer_url'), JSON_VALUE(l.data, '$.reffer_url'))
    )) AS ref_url
    , TRIM(JSON_QUERY(l.data, '$.abtest'), '\"') AS abtest
    , TRIM(JSON_QUERY(l.data, '$.page_category'), '\"') AS page_category
    , TRIM(JSON_QUERY(l.data, '$.item_kind'), '\"') AS item_kind
    , TRIM(JSON_QUERY(l.data, '$.item_id'), '\"') AS item_id
    , TRIM(JSON_QUERY(l.data, '$.item_category'), '\"') AS item_category
    , TRIM(JSON_QUERY(l.data, '$.item_name'), '\"') AS item_name
    , TRIM(JSON_QUERY(l.data, '$.item_type'), '\"') AS item_type
    , extract_data(l.data, m.data_field) AS ds
    , l.data AS data

    , CASE
        WHEN udf.stringify_without_blank(utm) IS NOT NULL AND utm != '{}' THEN udf.stringify_without_blank(utm)
        WHEN REGEXP_CONTAINS(JSON_VALUE(data, '$.url'), r'(\&|\?)(n_|utm_|recent_utm_)[^=]+=') = TRUE THEN
            CONCAT('{"',REPLACE(udf.decode(ARRAY_TO_STRING(REGEXP_EXTRACT_ALL(JSON_VALUE(data, '$.url'), r'(?:n_|utm_|recent_utm_)[^=]+=[^&]+'), '","')), '=', '":"'),'"}')
        END AS utm
    , udf.stringify_without_blank(geo) AS geo
    , device
    , CASE
        WHEN l.platform IN ('ios') THEN STRUCT(
            NULL AS browser_name,
            NULL AS browser_version,
            TRIM(JSON_QUERY(device, '$.device_operating_system'), '\"') AS device_model,
            TRIM(JSON_QUERY(device, '$.device_mobile_marketing_name'), '\"') AS device_type,
            TRIM(JSON_QUERY(device, '$.device_mobile_model_name'), '\"') AS device_vendor,
            TRIM(JSON_QUERY(device, '$.device_operating_system_version'), '\"') AS os_name,
            TRIM(JSON_QUERY(device, '$.app_info_version'), '\"') AS os_version)
        WHEN l.platform IN ('aos') THEN STRUCT(
            NULL AS browser_name,
            NULL AS browser_version,
            TRIM(JSON_QUERY(device, '$.device_mobile_model_name'), '\"') AS device_model,
            TRIM(JSON_QUERY(device, '$.device_operating_system_version'), '\"') AS device_type,
            TRIM(JSON_QUERY(device, '$.device_mobile_marketing_name'), '\"') AS device_vendor,
            TRIM(JSON_QUERY(device, '$.device_operating_system_version'), '\"') AS os_name,
            TRIM(JSON_QUERY(device, '$.app_info_version'), '\"') AS os_version)
        ELSE udf.parse_user_agent(device)
    END AS ua
    , DATETIME(current_timestamp(), 'Asia/Seoul') AS dw_load_dt
FROM LOG l
LEFT JOIN META m
    ON l.event_type = m.event_type AND l.event_name = m.event_name
        AND CASE
                WHEN l.platform IN ('aos', 'ios', 'web') THEN l.platform
                WHEN l.platform LIKE '%web%' THEN 'web'
                WHEN l.platform LIKE '%android%' THEN 'aos'
                WHEN l.platform LIKE '%ios%' THEN 'ios'
            END = m.platform
        AND IF(m.screen_name != '*', l.screen_name = m.screen_name, l.screen_name NOT IN UNNEST(m.screen_names))