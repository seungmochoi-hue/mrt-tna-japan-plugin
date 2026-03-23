{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_UPS_REP_CITY'
    )
}}

SELECT DISTINCT CAST(t.GID AS STRING) AS GID
              ,  CASE WHEN is_representative = TRUE THEN 'Y' ELSE 'N' END AS REPRESENTATIVE_FLAG
              ,  t.continent AS CONTINENT_NM
              ,  t.country AS COUNTRY_NM
              ,  t.city AS CITY_NM
              ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT ups.id AS GID
              ,  REGEXP_EXTRACT(location,'"continent":"([^"]+)"') AS continent
              ,  REGEXP_EXTRACT(location, '"country":"([^"]+)"') AS country
              ,  REGEXP_EXTRACT(location, '"city":"([^"]+)"') AS city
              ,  ups.updated_at AS updated_at
              ,  REGEXP_EXTRACT(location, '"representative":(true|false)') = 'true' AS is_representative
              ,  ROW_NUMBER() OVER(PARTITION BY ups.id ORDER BY REGEXP_EXTRACT(location, '"representative":(true|false)') = 'true' DESC, ups.updated_at) AS rn
         FROM {{ source("ups", 'union_product_v3') }} ups,
         UNNEST(JSON_EXTRACT_ARRAY(ups.locations)) location
         WHERE ups.deleted_at IS NULL
     ) t
WHERE rn = 1