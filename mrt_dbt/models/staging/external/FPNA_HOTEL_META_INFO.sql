{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_HOTEL_META_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_HOTEL_META_INFO") }}