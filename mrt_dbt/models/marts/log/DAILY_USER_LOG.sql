{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='DAILY_USER_LOG',
        partition_by={
            'field': 'basis_dt',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


SELECT DISTINCT basis_dt
              , platform
              , pid
              , user_id
              , session_id
              , CASE
                    WHEN ref_url LIKE '%search.naver.com%' THEN 'search_naver'
                    WHEN ref_url LIKE '%search.daum.net%' THEN 'search_daum'
                    WHEN ref_url LIKE '%google.com/search%' THEN 'search_google'
                    WHEN ref_url LIKE '%facebook.com%' THEN 'sns_facebook'
                    WHEN ref_url LIKE '%instagram.com%' THEN 'sns_instagram'
                    WHEN ref_url LIKE '%skyscanner.net%' THEN 'flight_skyscanner'
                    WHEN ref_url LIKE '%skyscanner.co%' THEN 'flight_skyscanner'
                    WHEN ref_url LIKE '%flight.naver.com%' THEN 'flight_naver'
                    WHEN ref_url LIKE '%tour.store.naver.com%' THEN 'naverticketpass'
    END AS ref_url_source
              , JSON_VALUE(utm, '$.recent_utm_source') AS utm_source
              , JSON_VALUE(utm, '$.recent_utm_campaign') AS utm_campaign
              , JSON_VALUE(utm, '$.recent_utm_medium') AS utm_medium
              , JSON_VALUE(utm, '$.recent_utm_content') AS utm_content
              , JSON_VALUE(utm, '$.recent_utm_term') AS utm_term
              , mylink_id
FROM {{ ref('DW_BIZ_LOG_VIEW') }}
WHERE basis_dt = '{{ var("logical_start_date_kst") }}'
