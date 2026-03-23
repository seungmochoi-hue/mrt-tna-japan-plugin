{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_B2B_GID_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_B2B_GID_INFO") }}