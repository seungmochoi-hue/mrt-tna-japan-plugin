{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_COMMERCE_ETC',
        enabled=false
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_COMMERCE_ETC") }}