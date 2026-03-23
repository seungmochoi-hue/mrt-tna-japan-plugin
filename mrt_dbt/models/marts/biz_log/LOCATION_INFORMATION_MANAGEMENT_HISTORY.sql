{{
    config(
        materialized='incremental',
        schema='edw',
        alias='LOCATION_INFORMATION_MANAGEMENT_HISTORY',
        cluster_by = ['user_id', 'platform'],
        unique_key = ['user_id', 'platform']
    )
}}

SELECT
    user_id
    , platform
    , '마이리얼트립서비스' AS using_service
    , '-' AS recipient
    , 'API' AS using_method
    , MIN(event_timestamp_kst) AS acquisition_date
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE user_id IS NOT NULL
   AND geo IS NOT NULL
   AND basis_dt = "{{ var('logical_start_date_kst')}}"
GROUP BY 1,2,3,4,5