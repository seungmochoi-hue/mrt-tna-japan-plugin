{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_ORDER_MADE_GID_PROFIT_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_ORDER_MADE_GID_PROFIT_INFO") }}