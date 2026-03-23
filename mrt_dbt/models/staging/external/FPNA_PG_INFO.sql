{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_PG_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_PG_INFO") }}