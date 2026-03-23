{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_BIZ_TYPE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_BIZ_TYPE_INFO") }}