SELECT
DISTINCT dwField
FROM (
SELECT
    dwField
FROM (
    SELECT
        LOWER(REGEXP_REPLACE(JSON_VALUE(DATA, '$.dwField'), '[^a-zA-Z0-9_\\.]+', '')) AS dwField
    FROM
    edw_biz_log.biz_log_meta, UNNEST(JSON_EXTRACT_ARRAY(data_field)) DATA )
    WHERE
        dwField IS NOT NULL
        AND dwField NOT IN ('',
        'null',
        'NULL')
    UNION ALL
    SELECT
        d AS dwField
    FROM
    UNNEST(["gid","gpid","section_name","section_title","section_vertical_index","section_horizon_index","item_vertical_index","item_horizon_index"])d )
order by 1