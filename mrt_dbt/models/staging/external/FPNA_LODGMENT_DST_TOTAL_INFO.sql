{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_LODGMENT_DST_TOTAL_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_LODGMENT_DST_TOTAL_INFO") }}