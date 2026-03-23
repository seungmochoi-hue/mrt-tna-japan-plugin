{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_AIR_INTERNATIONAL_VI'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_AIR_INTERNATIONAL_VI") }}