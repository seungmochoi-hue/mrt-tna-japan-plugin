{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_SEARCH_WORD_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

SELECT basis_dt,
       UPPER(REPLACE(JSON_VALUE(data, '$.search_word'), ' ', '')) AS search_word,
       COUNT(*) AS qc,
       COUNT(CASE WHEN platform = 'web' THEN 1 END) AS qc_web,
       COUNT(CASE WHEN platform = 'aos_mweb' THEN 1 END) AS qc_aos_mweb,
       COUNT(CASE WHEN platform = 'ios_mweb' THEN 1 END) AS qc_ios_mweb,
       COUNT(CASE WHEN platform = 'aos' THEN 1 END) AS qc_aos,
       COUNT(CASE WHEN platform = 'ios' THEN 1 END) AS qc_ios
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE basis_dt = '{{ var("logical_start_date_kst") }}'
AND event_name = 'gsearch'
GROUP BY 1,2
HAVING COUNT(*) >= 3