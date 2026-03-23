{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_BIZ_TYPE_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_BIZ_TYPE_INFO") }}