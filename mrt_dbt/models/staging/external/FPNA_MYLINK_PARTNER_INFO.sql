{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_MYLINK_PARTNER_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_MYLINK_PARTNER_INFO") }}