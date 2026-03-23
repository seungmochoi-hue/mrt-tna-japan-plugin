SELECT M.AIRPORT_CODE
     , M.COUNTRY_ID
     , M.COUNTRY_NM
     , C.key_name AS CANONICAL_COUNTRY_NM
FROM {{ ref('DIM_AIRPORT_CITY_MAPPING') }} M
JOIN {{ source('mrt_20', 'location_country_infos') }} C
    ON M.COUNTRY_ID = C.id
WHERE M.COUNTRY_ID IS NOT NULL
  AND M.COUNTRY_NM != C.key_name
