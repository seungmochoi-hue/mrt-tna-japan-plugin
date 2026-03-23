{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='temp_fpna_team_mapping'
    )
}}


SELECT
    *
FROM {{ source("external_business", "temp_fpna_team_mapping") }}