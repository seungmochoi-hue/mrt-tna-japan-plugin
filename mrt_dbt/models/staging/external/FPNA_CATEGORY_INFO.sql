{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_CATEGORY_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_CATEGORY_INFO") }}