{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_KIDS_CIC_MADE_PRODUCT_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_KIDS_CIC_MADE_PRODUCT_INFO") }}