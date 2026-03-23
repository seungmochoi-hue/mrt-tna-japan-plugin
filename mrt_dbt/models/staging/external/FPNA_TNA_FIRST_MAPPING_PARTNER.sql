{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_FIRST_MAPPING_PARTNER'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_FIRST_MAPPING_PARTNER") }}