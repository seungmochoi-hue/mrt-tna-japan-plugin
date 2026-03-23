{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='fpna_external_commission_tna_connected'
    )
}}


SELECT
    *
FROM {{ source("external_business", "fpna_external_commission_tna_connected") }}