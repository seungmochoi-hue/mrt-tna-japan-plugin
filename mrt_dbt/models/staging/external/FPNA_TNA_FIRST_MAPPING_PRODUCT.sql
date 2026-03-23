{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_FIRST_MAPPING_PRODUCT'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_FIRST_MAPPING_PRODUCT") }}