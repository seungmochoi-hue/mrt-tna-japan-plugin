{{
    config(
        materialized='table',
        schema='edw_external',
        alias='DIM_TEST_PRODUCT'
    )
}}


SELECT
    *
FROM {{ source("external_mart", "DIM_TEST_PRODUCT") }}