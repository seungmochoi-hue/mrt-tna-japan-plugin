{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_KIDS_CIC_LEGACY_OFFER_COMMISSION_RATE'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_KIDS_CIC_LEGACY_OFFER_COMMISSION_RATE") }}