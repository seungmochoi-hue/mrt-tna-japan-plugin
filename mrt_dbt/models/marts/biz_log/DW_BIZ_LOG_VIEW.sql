{{
    config(
        materialized='view',
        schema='edw_biz_log',
        alias="VIEW_DW_BIZ_LOG"
    )
}}


SELECT *
FROM {{ remove_date_suffix(ref('DW_BIZ_LOG')) }}
WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 93 DAY)) AND FORMAT_DATE('%Y%m%d', CURRENT_DATE)
