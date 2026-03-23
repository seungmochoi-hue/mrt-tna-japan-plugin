{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_COMMERCE_EXCHANGE_RATE_INFO") }}