{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_PKG_HARD_BLOCK_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_PKG_HARD_BLOCK_INFO") }}