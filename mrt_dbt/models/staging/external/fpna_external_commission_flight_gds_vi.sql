{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='fpna_external_commission_flight_gds_vi'
    )
}}


SELECT
    *
FROM {{ source("external_business", "fpna_external_commission_flight_gds_vi") }}