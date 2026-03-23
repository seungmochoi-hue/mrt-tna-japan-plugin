{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_MYPACK_ACTUAL_SUPPLY_COST_PARTNER'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_MYPACK_ACTUAL_SUPPLY_COST_PARTNER") }}