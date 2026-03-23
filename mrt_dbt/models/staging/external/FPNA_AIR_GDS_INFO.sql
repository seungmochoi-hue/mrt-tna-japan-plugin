{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_AIR_GDS_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_AIR_GDS_INFO") }}