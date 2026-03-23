{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_AIRPORT_CITY_MAPPING'
    )
}}

WITH RAW20_PRIORITY AS (
    SELECT UPPER(TRIM(A.code))                                        AS AIRPORT_CODE
         , A.id                                                       AS AIRPORT_ID
         , NULLIF(TRIM(A.airport_name), '')                           AS AIRPORT_NM
         , A.location_city_info_id                                    AS CITY_ID
         , NULLIF(TRIM(A.city_name), '')                              AS RAW_CITY_NM
         , NULLIF(TRIM(A.country_name), '')                           AS RAW_COUNTRY_NM
         , A.dw_load_dt                                               AS RAW_DW_LOAD_DT
         , ROW_NUMBER() OVER (
               PARTITION BY UPPER(TRIM(A.code))
               ORDER BY CASE WHEN A.location_city_info_id IS NOT NULL THEN 0 ELSE 1 END
                      , CASE WHEN NULLIF(TRIM(A.airport_name), '') = 'Metropolitan Area' THEN 1 ELSE 0 END
                      , A.dw_load_dt DESC
                      , A.id DESC
           )                                                          AS ROW_NUM
    FROM {{ source('mrt_20', 'mapping_airport_cities') }} A
    WHERE NULLIF(TRIM(A.code), '') IS NOT NULL
),
RAW20_PRIMARY AS (
    SELECT AIRPORT_CODE
         , AIRPORT_ID
         , AIRPORT_NM
         , CITY_ID
         , RAW_CITY_NM
         , RAW_COUNTRY_NM
    FROM RAW20_PRIORITY
    WHERE ROW_NUM = 1
),
RAW20_ENRICHED AS (
    SELECT R.AIRPORT_CODE
         , R.AIRPORT_ID
         , R.AIRPORT_NM
         , C.id                                                       AS CITY_ID
         , C.key_name                                                 AS CITY_NM
         , CI.id                                                      AS COUNTRY_ID
         , CI.key_name                                                AS COUNTRY_NM
         , RG.id                                                      AS REGION_ID
         , RG.key_name                                                AS REGION_NM
         , R.RAW_CITY_NM
         , R.RAW_COUNTRY_NM
    FROM RAW20_PRIMARY R
    LEFT JOIN {{ source('mrt_20', 'location_city_infos') }} C
        ON R.CITY_ID = C.id
    LEFT JOIN {{ source('mrt_20', 'location_country_infos') }} CI
        ON C.country_info_id = CI.id
    LEFT JOIN {{ source('mrt_20', 'location_region_infos') }} RG
        ON CI.region_info_id = RG.id
),
CITY_MAPPING_PRIORITY AS (
    SELECT UPPER(TRIM(M.airport_cd))                                  AS AIRPORT_CODE
         , M.city_info_id                                             AS CITY_ID
         , C.key_name                                                 AS CITY_NM
         , CI.id                                                      AS COUNTRY_ID
         , CI.key_name                                                AS COUNTRY_NM
         , RG.id                                                      AS REGION_ID
         , RG.key_name                                                AS REGION_NM
         , ROW_NUMBER() OVER (
               PARTITION BY UPPER(TRIM(M.airport_cd))
               ORDER BY M.city_info_id DESC
                      , C.key_name DESC
           )                                                          AS ROW_NUM
    FROM {{ source('mrt_mapping', 'city_mapping') }} M
    LEFT JOIN {{ source('mrt_20', 'location_city_infos') }} C
        ON M.city_info_id = C.id
    LEFT JOIN {{ source('mrt_20', 'location_country_infos') }} CI
        ON C.country_info_id = CI.id
    LEFT JOIN {{ source('mrt_20', 'location_region_infos') }} RG
        ON CI.region_info_id = RG.id
    WHERE NULLIF(TRIM(M.airport_cd), '') IS NOT NULL
      AND M.city_info_id IS NOT NULL
),
CITY_MAPPING_PRIMARY AS (
    SELECT AIRPORT_CODE
         , CITY_ID
         , CITY_NM
         , COUNTRY_ID
         , COUNTRY_NM
         , REGION_ID
         , REGION_NM
    FROM CITY_MAPPING_PRIORITY
    WHERE ROW_NUM = 1
),
AIRCODE_PRIORITY AS (
    SELECT UPPER(TRIM(A.airport_cd))                                  AS AIRPORT_CODE
         , NULLIF(TRIM(A.airport_eng_nm), '')                         AS AIRPORT_NM
         , NULLIF(TRIM(A.key_name), '')                               AS CITY_NM
         , ROW_NUMBER() OVER (
               PARTITION BY UPPER(TRIM(A.airport_cd))
               ORDER BY A.dw_load_dt DESC
                      , A.airport_eng_nm DESC
                      , A.key_name DESC
           )                                                          AS ROW_NUM
    FROM {{ source('mrt_mapping', 'aircode_city_mapping') }} A
    WHERE NULLIF(TRIM(A.airport_cd), '') IS NOT NULL
),
AIRCODE_PRIMARY AS (
    SELECT AIRPORT_CODE
         , AIRPORT_NM
         , CITY_NM
    FROM AIRCODE_PRIORITY
    WHERE ROW_NUM = 1
),
CARTOGRAPHER_CODE_PRIORITY AS (
    SELECT UPPER(TRIM(A.code_value))                                  AS AIRPORT_CODE
         , A.region_id                                                AS AIRPORT_REGION_ID
         , A.code_source                                              AS CODE_SOURCE
         , NULLIF(TRIM(R.en_name), '')                                AS AIRPORT_NM
         , ROW_NUMBER() OVER (
               PARTITION BY UPPER(TRIM(A.code_value))
               ORDER BY A.code_priority
                      , A.updated_at DESC
                      , A.dw_load_dt DESC
                      , A.region_id DESC
           )                                                          AS ROW_NUM
    FROM (
        SELECT A.region_id                                            AS region_id
             , A.iata_airport_code                                    AS code_value
             , 'AIRPORT'                                              AS code_source
             , 0                                                      AS code_priority
             , A.updated_at                                           AS updated_at
             , A.dw_load_dt                                           AS dw_load_dt
        FROM {{ source('cartographer', 'region_airport') }} A
        WHERE A.deleted_at IS NULL
          AND NULLIF(TRIM(A.iata_airport_code), '') IS NOT NULL

        UNION ALL

        SELECT A.region_id                                            AS region_id
             , A.iata_airport_metro_code                              AS code_value
             , 'METRO'                                                AS code_source
             , 1                                                      AS code_priority
             , A.updated_at                                           AS updated_at
             , A.dw_load_dt                                           AS dw_load_dt
        FROM {{ source('cartographer', 'region_airport') }} A
        WHERE A.deleted_at IS NULL
          AND NULLIF(TRIM(A.iata_airport_metro_code), '') IS NOT NULL
    ) A
    LEFT JOIN {{ source('cartographer', 'region') }} R
        ON A.region_id = R.region_id
       AND R.deleted_at IS NULL
),
CARTOGRAPHER_CODE_PRIMARY AS (
    SELECT AIRPORT_CODE
         , AIRPORT_REGION_ID
         , CODE_SOURCE
         , AIRPORT_NM
    FROM CARTOGRAPHER_CODE_PRIORITY
    WHERE ROW_NUM = 1
),
CARTOGRAPHER_RELATIONSHIP_PRIORITY AS (
    SELECT RR.region_id                                               AS AIRPORT_REGION_ID
         , RR.type                                                    AS RELATIONSHIP_TYPE
         , RR.relationship_region_id                                  AS RELATED_REGION_ID
         , ROW_NUMBER() OVER (
               PARTITION BY RR.region_id, RR.type
               ORDER BY CASE WHEN RR.main_yn = 'Y' THEN 0 ELSE 1 END
                      , RR.updated_at DESC
                      , RR.relationship_region_id DESC
           )                                                          AS ROW_NUM
    FROM {{ source('cartographer', 'region_relationship') }} RR
    WHERE RR.deleted_at IS NULL
      AND RR.relationship = 'UP'
      AND RR.type IN ('CITY', 'COUNTRY')
),
CARTOGRAPHER_RELATIONSHIP_PRIMARY AS (
    SELECT AIRPORT_REGION_ID
         , MAX(IF(RELATIONSHIP_TYPE = 'CITY' AND ROW_NUM = 1, RELATED_REGION_ID, NULL))
                                                                      AS CITY_REGION_ID
         , MAX(IF(RELATIONSHIP_TYPE = 'COUNTRY' AND ROW_NUM = 1, RELATED_REGION_ID, NULL))
                                                                      AS COUNTRY_REGION_ID
    FROM CARTOGRAPHER_RELATIONSHIP_PRIORITY
    GROUP BY 1
),
CARTOGRAPHER_ENRICHED AS (
    SELECT C.AIRPORT_CODE
         , C.AIRPORT_NM
         , CASE
               WHEN C.CODE_SOURCE = 'AIRPORT'
                   THEN NULLIF(TRIM(CI.en_name), '')
               ELSE NULL
           END                                                        AS CITY_NM
         , NULLIF(TRIM(CO.en_name), '')                               AS COUNTRY_NM
    FROM CARTOGRAPHER_CODE_PRIMARY C
    LEFT JOIN CARTOGRAPHER_RELATIONSHIP_PRIMARY R
        ON C.AIRPORT_REGION_ID = R.AIRPORT_REGION_ID
    LEFT JOIN {{ source('cartographer', 'region') }} CI
        ON R.CITY_REGION_ID = CI.region_id
       AND CI.deleted_at IS NULL
    LEFT JOIN {{ source('cartographer', 'region') }} CO
        ON R.COUNTRY_REGION_ID = CO.region_id
       AND CO.deleted_at IS NULL
),
AIRPORT_KEYS AS (
    SELECT AIRPORT_CODE FROM RAW20_PRIMARY

    UNION DISTINCT

    SELECT AIRPORT_CODE FROM CITY_MAPPING_PRIMARY

    UNION DISTINCT

    SELECT AIRPORT_CODE FROM AIRCODE_PRIMARY

    UNION DISTINCT

    SELECT AIRPORT_CODE FROM CARTOGRAPHER_CODE_PRIMARY
),
FINAL_BASE AS (
    SELECT K.AIRPORT_CODE                                             AS AIRPORT_CODE
         , COALESCE(R.AIRPORT_ID, CAST(ABS(FARM_FINGERPRINT(K.AIRPORT_CODE)) AS INT64))
                                                                      AS AIRPORT_ID
         , COALESCE(R.AIRPORT_NM, A.AIRPORT_NM, CG.AIRPORT_NM)        AS AIRPORT_NM
         , COALESCE(R.CITY_ID, C.CITY_ID)                             AS CITY_ID
         , COALESCE(R.CITY_NM, C.CITY_NM, R.RAW_CITY_NM, A.CITY_NM, CG.CITY_NM)
                                                                      AS CITY_NM
         , COALESCE(R.COUNTRY_ID, C.COUNTRY_ID)                       AS COUNTRY_ID
         , COALESCE(R.COUNTRY_NM, C.COUNTRY_NM, R.RAW_COUNTRY_NM, CG.COUNTRY_NM)
                                                                      AS COUNTRY_NM
         , COALESCE(R.REGION_ID, C.REGION_ID)                         AS REGION_ID
         , COALESCE(R.REGION_NM, C.REGION_NM)                         AS REGION_NM
         , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)         AS DW_LOAD_DT
    FROM AIRPORT_KEYS K
    LEFT JOIN RAW20_ENRICHED R USING (AIRPORT_CODE)
    LEFT JOIN CITY_MAPPING_PRIMARY C USING (AIRPORT_CODE)
    LEFT JOIN AIRCODE_PRIMARY A USING (AIRPORT_CODE)
    LEFT JOIN CARTOGRAPHER_ENRICHED CG USING (AIRPORT_CODE)
),
COUNTRY_NAME_RULES AS (
    SELECT *
    FROM {{ ref('GEO_COUNTRY_NAME_RULES') }}
),
COUNTRY_MASTER AS (
    SELECT CO.id                                                     AS COUNTRY_ID
         , CO.key_name                                               AS COUNTRY_NM
         , RG.id                                                     AS REGION_ID
         , RG.key_name                                               AS REGION_NM
    FROM {{ source('mrt_20', 'location_country_infos') }} CO
    LEFT JOIN {{ source('mrt_20', 'location_region_infos') }} RG
        ON CO.region_info_id = RG.id
),
CITY_NAME_RULES AS (
    SELECT *
    FROM {{ ref('GEO_AIRPORT_CITY_NAME_RULES') }}
),
CITY_SOURCE_NORMALIZED AS (
    SELECT C.id                                                       AS CITY_ID
         , C.key_name                                                 AS CITY_NM
         , C.country_info_id                                          AS COUNTRY_ID
         , {{ normalize_airport_city_lookup_key_expr('C.key_name') }} AS CITY_NM_NORMALIZED
    FROM {{ source('mrt_20', 'location_city_infos') }} C
),
CITY_SOURCE_NORMALIZED_UNIQUE AS (
    SELECT COUNTRY_ID
         , CITY_NM_NORMALIZED
         , MIN(CITY_ID)                                               AS CITY_ID
         , MIN(CITY_NM)                                               AS CITY_NM
    FROM CITY_SOURCE_NORMALIZED
    GROUP BY 1, 2
    HAVING COUNT(*) = 1
),
CITY_COUNTRY_EXACT_UNIQUE AS (
    SELECT C.key_name                                                 AS CITY_NM
         , CI.id                                                      AS COUNTRY_ID
         , CI.key_name                                                AS COUNTRY_NM
         , RG.id                                                      AS REGION_ID
         , RG.key_name                                                AS REGION_NM
    FROM {{ source('mrt_20', 'location_city_infos') }} C
    JOIN {{ source('mrt_20', 'location_country_infos') }} CI
        ON C.country_info_id = CI.id
    LEFT JOIN {{ source('mrt_20', 'location_region_infos') }} RG
        ON CI.region_info_id = RG.id
    QUALIFY COUNT(DISTINCT CI.id) OVER (PARTITION BY C.key_name) = 1
),
NORMALIZED_BASE AS (
    SELECT AIRPORT_CODE                                               AS AIRPORT_CODE
         , AIRPORT_ID                                                 AS AIRPORT_ID
         , AIRPORT_NM                                                 AS AIRPORT_NM
         , CITY_ID                                                    AS CITY_ID
         , {{ normalize_airport_city_name_expr('CITY_NM') }}          AS CITY_NM
         , COUNTRY_ID                                                 AS COUNTRY_ID
         , COALESCE(
               R.CANONICAL_COUNTRY_NM,
               CASE
                   WHEN REGEXP_CONTAINS(COUNTRY_NM, r'^USA\?\([A-Z]{2}\)$')
                       THEN 'United States of America'
                   ELSE NULLIF(TRIM(COUNTRY_NM), '')
               END
           )                                                          AS COUNTRY_NM
         , REGION_ID                                                  AS REGION_ID
         , REGION_NM                                                  AS REGION_NM
         , DW_LOAD_DT                                                 AS DW_LOAD_DT
    FROM FINAL_BASE
    LEFT JOIN COUNTRY_NAME_RULES R
        ON FINAL_BASE.COUNTRY_NM = R.RAW_COUNTRY_NM
),
COUNTRY_CANONICAL AS (
    SELECT B.AIRPORT_CODE                                             AS AIRPORT_CODE
         , B.AIRPORT_ID                                               AS AIRPORT_ID
         , B.AIRPORT_NM                                               AS AIRPORT_NM
         , B.CITY_ID                                                  AS CITY_ID
         , B.CITY_NM                                                  AS CITY_NM
         , COALESCE(TAX_BY_NAME.COUNTRY_ID, TAX_BY_ID.COUNTRY_ID, TAX_BY_CITY_FALLBACK.COUNTRY_ID, B.COUNTRY_ID)
                                                                      AS COUNTRY_ID
         , COALESCE(TAX_BY_NAME.COUNTRY_NM, TAX_BY_ID.COUNTRY_NM, TAX_BY_CITY_FALLBACK.COUNTRY_NM, B.COUNTRY_NM, CITY_FALLBACK.COUNTRY_NM)
                                                                      AS COUNTRY_NM
         , COALESCE(TAX_BY_NAME.REGION_ID, TAX_BY_ID.REGION_ID, TAX_BY_CITY_FALLBACK.REGION_ID, CITY_FALLBACK.REGION_ID, B.REGION_ID)
                                                                      AS REGION_ID
         , COALESCE(TAX_BY_NAME.REGION_NM, TAX_BY_ID.REGION_NM, TAX_BY_CITY_FALLBACK.REGION_NM, CITY_FALLBACK.REGION_NM, B.REGION_NM)
                                                                      AS REGION_NM
         , B.DW_LOAD_DT                                               AS DW_LOAD_DT
    FROM NORMALIZED_BASE B
    LEFT JOIN COUNTRY_MASTER TAX_BY_NAME
        ON B.COUNTRY_NM = TAX_BY_NAME.COUNTRY_NM
    LEFT JOIN COUNTRY_MASTER TAX_BY_ID
        ON B.COUNTRY_ID = TAX_BY_ID.COUNTRY_ID
    LEFT JOIN CITY_COUNTRY_EXACT_UNIQUE CITY_FALLBACK
        ON B.COUNTRY_ID IS NULL
       AND B.COUNTRY_NM IS NULL
       AND B.CITY_NM = CITY_FALLBACK.CITY_NM
    LEFT JOIN COUNTRY_MASTER TAX_BY_CITY_FALLBACK
        ON CITY_FALLBACK.COUNTRY_ID = TAX_BY_CITY_FALLBACK.COUNTRY_ID
),
CITY_PREPARED AS (
    SELECT B.AIRPORT_CODE                                             AS AIRPORT_CODE
         , B.AIRPORT_ID                                               AS AIRPORT_ID
         , B.AIRPORT_NM                                               AS AIRPORT_NM
         , B.CITY_ID                                                  AS CITY_ID
         , COALESCE(R.CANONICAL_CITY_NM, B.CITY_NM)                   AS CITY_NM
         , {{ normalize_airport_city_lookup_key_expr('COALESCE(R.CANONICAL_CITY_NM, B.CITY_NM)') }}
                                                                      AS CITY_LOOKUP_NM_NORMALIZED
         , B.COUNTRY_ID                                               AS COUNTRY_ID
         , B.COUNTRY_NM                                               AS COUNTRY_NM
         , B.REGION_ID                                                AS REGION_ID
         , B.REGION_NM                                                AS REGION_NM
         , B.DW_LOAD_DT                                               AS DW_LOAD_DT
    FROM COUNTRY_CANONICAL B
    LEFT JOIN CITY_NAME_RULES R
        ON B.COUNTRY_NM = R.COUNTRY_NM
       AND B.CITY_NM = R.RAW_CITY_NM
),
CITY_CANONICAL AS (
    SELECT B.AIRPORT_CODE                                             AS AIRPORT_CODE
         , B.AIRPORT_ID                                               AS AIRPORT_ID
         , B.AIRPORT_NM                                               AS AIRPORT_NM
         , COALESCE(B.CITY_ID, CI_BY_NAME.id, CI_BY_NORM.CITY_ID)     AS CITY_ID
         , COALESCE(CI_BY_ID.key_name, CI_BY_NAME.key_name, CI_BY_NORM.CITY_NM, B.CITY_NM)
                                                                      AS CITY_NM
         , B.COUNTRY_ID                                               AS COUNTRY_ID
         , B.COUNTRY_NM                                               AS COUNTRY_NM
         , B.REGION_ID                                                AS REGION_ID
         , B.REGION_NM                                                AS REGION_NM
         , B.DW_LOAD_DT                                               AS DW_LOAD_DT
    FROM CITY_PREPARED B
    LEFT JOIN {{ source('mrt_20', 'location_city_infos') }} CI_BY_NAME
        ON B.CITY_ID IS NULL
       AND B.CITY_NM = CI_BY_NAME.key_name
       AND B.COUNTRY_ID = CI_BY_NAME.country_info_id
    LEFT JOIN CITY_SOURCE_NORMALIZED_UNIQUE CI_BY_NORM
        ON B.CITY_ID IS NULL
       AND CI_BY_NAME.id IS NULL
       AND B.COUNTRY_ID = CI_BY_NORM.COUNTRY_ID
       AND B.CITY_LOOKUP_NM_NORMALIZED = CI_BY_NORM.CITY_NM_NORMALIZED
    LEFT JOIN {{ source('mrt_20', 'location_city_infos') }} CI_BY_ID
        ON COALESCE(B.CITY_ID, CI_BY_NAME.id, CI_BY_NORM.CITY_ID) = CI_BY_ID.id
)
SELECT AIRPORT_CODE                                                   AS AIRPORT_CODE
     , AIRPORT_ID                                                     AS AIRPORT_ID
     , {{ cleanup_airport_name_suffix_expr('AIRPORT_NM') }}           AS AIRPORT_NM
     , CITY_ID                                                        AS CITY_ID
     , CITY_NM                                                        AS CITY_NM
     , COUNTRY_ID                                                     AS COUNTRY_ID
     , COUNTRY_NM                                                     AS COUNTRY_NM
     , REGION_ID                                                      AS REGION_ID
     , REGION_NM                                                      AS REGION_NM
     , DW_LOAD_DT                                                     AS DW_LOAD_DT
FROM CITY_CANONICAL
