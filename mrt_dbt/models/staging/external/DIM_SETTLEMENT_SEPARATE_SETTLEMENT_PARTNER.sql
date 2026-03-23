{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='DIM_SETTLEMENT_SEPARATE_SETTLEMENT_PARTNER'
    )
}}


SELECT
    *
FROM {{ source("external_settlement", "DIM_SETTLEMENT_SEPARATE_SETTLEMENT_PARTNER") }}