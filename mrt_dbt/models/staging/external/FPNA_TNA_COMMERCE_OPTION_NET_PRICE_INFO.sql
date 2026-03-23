{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_COMMERCE_OPTION_NET_PRICE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_COMMERCE_OPTION_NET_PRICE_INFO") }}