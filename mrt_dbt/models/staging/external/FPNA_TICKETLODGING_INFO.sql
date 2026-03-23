{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TICKETLODGING_INFO'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TICKETLODGING_INFO") }}