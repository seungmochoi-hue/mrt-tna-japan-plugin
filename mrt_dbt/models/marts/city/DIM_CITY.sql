{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_CITY',
        cluster_by=['COUNTRY']
    )
}}


WITH MRT_CITY AS (
    SELECT DISTINCT
        ci.key_name AS code
                  , ci.key_name AS city
                  , co.key_name AS country
                  , ro.key_name AS region
                  , 'mrt' AS source
                  , 1 AS rank
    FROM {{ source("mrt_20", "location_city_infos") }} ci
    LEFT JOIN {{ source("mrt_20", "location_country_infos") }} co ON ci.country_info_id = co.id
    LEFT JOIN {{ source("mrt_20", "location_region_infos") }} ro ON co.region_info_id = ro.id

    UNION ALL

    SELECT DISTINCT
        code
       , ci.key_name AS city
       , co.key_name AS country
       , ro.key_name AS region
       , source
       , 2 AS rank
    FROM {{ ref("ST_DIM_CITY") }} s
    LEFT JOIN {{ source("mrt_20", "location_city_infos") }} ci ON s.city = ci.key_name
    LEFT JOIN {{ source("mrt_20", "location_country_infos") }} co ON ci.country_info_id = co.id
    LEFT JOIN {{ source("mrt_20", "location_region_infos") }} ro ON co.region_info_id = ro.id
    WHERE ci.key_name IS NOT NULL
),
TBL AS (
    SELECT ROW_NUMBER() OVER (PARTITION BY code ORDER BY rank, city) AS row_num
        , code
        , city
        , country
        , region
        , source
        , rank
    FROM MRT_CITY
)
SELECT code AS CODE
     , city AS CITY
     , country AS COUNTRY
     , region AS REGION
     , source AS SOURCE
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM TBL
WHERE row_num = 1
