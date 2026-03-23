{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='hocance_info'
    )
}}


SELECT
    *
FROM {{ source("external_business", "hocance_info") }}