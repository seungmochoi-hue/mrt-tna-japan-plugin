{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='ST_DIM_CITY'
    )
}}


SELECT
    *
FROM {{ source("external_st", "ST_DIM_CITY") }}