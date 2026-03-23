{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='DIM_HOTEL_CITY'
    )
}}


SELECT
    *
FROM {{ source("external_mart", "DIM_HOTEL_CITY") }}