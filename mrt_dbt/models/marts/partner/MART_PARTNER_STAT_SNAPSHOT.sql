{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_PARTNER_STAT_SNAPSHOT',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}

SELECT CAST('{{ var("logical_start_date_kst") }}' AS DATE) AS BASIS_DATE
     ,  COUNT(DISTINCT IF(G.PARTNER_STATUS = 'active', G.PARTNER_ID, NULL)) AS ACTIVE_PARTNER_CNT
     ,  COUNT(DISTINCT IF(G.PARTNER_STATUS IN ('rest', 'resting'), G.PARTNER_ID, NULL)) AS REST_PARTNER_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('MART_PARTNER_ORIGINAL_D') }} G