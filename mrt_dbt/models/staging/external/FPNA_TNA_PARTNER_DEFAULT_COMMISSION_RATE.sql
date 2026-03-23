{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_PARTNER_DEFAULT_COMMISSION_RATE'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_PARTNER_DEFAULT_COMMISSION_RATE") }}