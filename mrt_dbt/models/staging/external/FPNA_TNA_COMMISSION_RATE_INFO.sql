{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_COMMISSION_RATE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_COMMISSION_RATE_INFO") }}