{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_OPTION_NET_PRICE'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_OPTION_NET_PRICE") }}