{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_REGION_TNA_MAPPING'
    )
}}

SELECT
    *
FROM {{ source("external_business", "FPNA_REGION_TNA_MAPPING") }}
