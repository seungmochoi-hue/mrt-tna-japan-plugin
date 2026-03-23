{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TYPE_V3'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TYPE_V3") }}