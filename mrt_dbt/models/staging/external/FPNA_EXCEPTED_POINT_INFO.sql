{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_EXCEPTED_POINT_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_EXCEPTED_POINT_INFO") }}