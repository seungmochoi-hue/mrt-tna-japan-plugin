{{
    config(
        materialized='table',
        schema='edw_ext',
        alias='FPNA_TNA_NAVER_SMARTSTORE_OFFERS'
    )
}}


SELECT
    *
FROM {{ source("external_business", "FPNA_TNA_NAVER_SMARTSTORE_OFFERS") }}