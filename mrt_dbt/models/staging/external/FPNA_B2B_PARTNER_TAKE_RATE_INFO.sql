{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_B2B_PARTNER_TAKE_RATE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_B2B_PARTNER_TAKE_RATE_INFO") }}