{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='DIM_TEST_USER'
    )
}}


SELECT
    *
FROM {{ source("external_mart", "DIM_TEST_USER") }}