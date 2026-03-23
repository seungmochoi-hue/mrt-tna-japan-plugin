{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='fpna_coupon_info'
    )
}}


SELECT
    *
FROM {{ source("external_business", "fpna_coupon_info") }}
