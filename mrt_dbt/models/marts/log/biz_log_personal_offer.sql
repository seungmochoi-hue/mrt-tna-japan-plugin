{{
    config(
        materialized = 'incremental',
        schema='batch',
        alias='biz_log_personal_offer',
        pre_hook=[
            "DELETE FROM {{ this }} WHERE basis_dt BETWEEN '{{ var('logical_start_date_utc') }}' AND '{{ var('logical_end_date_utc') }}'"
        ]
    )
}}


SELECT  * EXCEPT(pid)
, JSON_VALUE(DATA, '$.pid') AS PID
      , JSON_VALUE(DATA, '$.gid') AS GID
      , JSON_VALUE(DATA, '$.personal_offer_type') AS PERSONAL_OFFER_TYPE
      , SAFE_CAST(JSON_VALUE(DATA, '$.personal_offer_start_time') AS TIMESTAMP) AS PERSONAL_OFFER_START_TIME
      , SAFE_CAST(JSON_VALUE(DATA, '$.personal_offer_end_time') AS TIMESTAMP) AS PERSONAL_OFFER_END_TIME
      , EVENT_TIMESTAMP AS EVENT_TIMESTAMP_KST
      , DATE(EVENT_TIMESTAMP) AS BASIS_DT_KST
FROM {{ source('log_stream', 'biz_log') }}
WHERE BASIS_DT BETWEEN '{{ var("logical_start_date_utc") }}'
                   AND '{{ var("logical_end_date_utc") }}'
  AND EVENT_NAME = 'trigger_personal_offer'