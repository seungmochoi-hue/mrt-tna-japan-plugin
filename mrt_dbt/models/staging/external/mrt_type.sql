{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='mrt_type'
    )
}}


SELECT
    *
FROM {{ source("external_mapping", "mrt_type") }}