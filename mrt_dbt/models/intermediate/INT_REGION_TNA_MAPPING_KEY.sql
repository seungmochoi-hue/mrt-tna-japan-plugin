{{
    config(
        materialized='table',
        schema='edw_intermediate'
    )
}}

WITH MAPPING_RAW AS (
    SELECT
        TRIM(CITY_NM)                    AS CITY_NM
      , TRIM(COUNTRY_NM)                 AS COUNTRY_NM
      , TRIM(REGION_NM)                  AS REGION_NM
      , NULLIF(TRIM(REGION_TNA_NM), '')  AS REGION_TNA_NM
    FROM {{ ref('FPNA_REGION_TNA_MAPPING') }}
    /* 키가 빈칸(또는 공백만)인 row 제외 */
    WHERE NULLIF(TRIM(CITY_NM), '') IS NOT NULL
      AND NULLIF(TRIM(COUNTRY_NM), '') IS NOT NULL
      AND NULLIF(TRIM(REGION_NM), '') IS NOT NULL
),
COUNTRY_NAME_RULES AS (
    SELECT *
    FROM {{ ref('GEO_COUNTRY_NAME_RULES') }}
),
COUNTRY_MASTER AS (
    SELECT CO.id                              AS COUNTRY_ID
         , CO.key_name                        AS COUNTRY_NM
         , RG.key_name                        AS REGION_NM
    FROM {{ source('mrt_20', 'location_country_infos') }} CO
    LEFT JOIN {{ source('mrt_20', 'location_region_infos') }} RG
        ON CO.region_info_id = RG.id
),
MAPPING_COUNTRY_NORMALIZED AS (
    SELECT M.CITY_NM                                      AS CITY_NM
         , COALESCE(R.CANONICAL_COUNTRY_NM, M.COUNTRY_NM) AS COUNTRY_NM
         , M.REGION_TNA_NM                                AS REGION_TNA_NM
    FROM MAPPING_RAW M
    LEFT JOIN COUNTRY_NAME_RULES R
        ON M.COUNTRY_NM = R.RAW_COUNTRY_NM
),
VALID_CITY AS (
    /* 유효 City key 목록 */
    SELECT DISTINCT
        TRIM(key_name) AS CITY_NM
    FROM {{ source('mrt_20', 'location_city_infos') }}
    WHERE NULLIF(TRIM(key_name), '') IS NOT NULL
),
VALID_REGION AS (
    /* 유효 Region key 목록 */
    SELECT DISTINCT
        TRIM(key_name) AS REGION_NM
    FROM {{ source('mrt_20', 'location_region_infos') }}
    WHERE NULLIF(TRIM(key_name), '') IS NOT NULL
),
BASE AS (
    /* 유효 key만 남기기: INNER JOIN으로 미존재 값 제외 */
    SELECT
        M.CITY_NM        AS CITY_NM_KEY
      , T.COUNTRY_NM     AS COUNTRY_NM_KEY
      , T.REGION_NM      AS REGION_NM_KEY
      , M.REGION_TNA_NM  AS REGION_TNA_NM
    FROM MAPPING_COUNTRY_NORMALIZED M
    INNER JOIN VALID_CITY VC
        ON M.CITY_NM = VC.CITY_NM
    INNER JOIN COUNTRY_MASTER T
        ON M.COUNTRY_NM = T.COUNTRY_NM
    INNER JOIN VALID_REGION VR
        ON T.REGION_NM = VR.REGION_NM
)
SELECT
    CITY_NM_KEY
  , COUNTRY_NM_KEY
  , REGION_NM_KEY
  , REGION_TNA_NM
FROM BASE
