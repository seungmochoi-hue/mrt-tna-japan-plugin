{{
    config(
        materialized='table',
        schema='mrt_mapping',
        alias='city_to_region'
    )
}}

SELECT DISTINCT
    CAST(o.id AS STRING) AS offer_id
  , city.id             AS city_info_id
  , con.id              AS con_info_id
  , rgn.id              AS rgn_info_id
  , city.key_name       AS city_key_name
  , con.key_name        AS con_key_name
  , rgn.key_name        AS rgn_key_name
  , region
  , lci.is_representative -- 대표 도시 설정 여부 추가
FROM {{ source('mrt_20', 'offers') }} AS o
         JOIN {{ source("mrt_20", "offers_location_city_infos") }} AS lci ON lci.offer_id = o.id
         LEFT JOIN {{ source("mrt_20", "location_city_infos") }} AS city ON city.id = lci.city_info_id
         LEFT JOIN {{ source("mrt_20", "location_country_infos") }} con ON con.id = city.country_info_id
         LEFT JOIN {{ source("mrt_20", "location_region_infos") }} rgn ON rgn.id = con.region_info_id
UNION ALL
SELECT DISTINCT
    CONCAT("BNB", p.id) AS offer_id
  , c.id                AS city_info_id
  , co.id               AS con_info_id
  , r.id                AS rgn_info_id
  , c.key_name          AS city_key_name
  , co.key_name         AS con_key_name
  , r.key_name          AS rgn_key_name
  , region
  , CAST(NULL AS BOOL)  AS is_representative -- 숙소는 대표 도시 개념이 없으므로 NULL로 통일
FROM {{ source("products", "products") }} p
         JOIN {{ source("products", "product_city_mappings") }} m ON p.id = m.product_id
         LEFT JOIN {{ source("products", "location_cities") }} c ON m.location_city_id = c.id
         LEFT JOIN {{ source("products", "location_countries") }} co ON c.country_id = co.id
         LEFT JOIN {{ source("products", "location_regions") }} r ON co.region_id = r.id