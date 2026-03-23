{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_CONNECTED_PARTNERS_COMMISSION_BASE'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_CONNECTED_PARTNERS_COMMISSION_BASE") }}