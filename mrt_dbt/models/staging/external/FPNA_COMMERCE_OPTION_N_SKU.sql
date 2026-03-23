{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_COMMERCE_OPTION_N_SKU'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_COMMERCE_OPTION_N_SKU") }}