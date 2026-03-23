SELECT M.AIRPORT_CODE
     , M.CITY_ID
     , M.CITY_NM
     , C.key_name AS CANONICAL_CITY_NM
FROM {{ ref('DIM_AIRPORT_CITY_MAPPING') }} M
JOIN {{ source('mrt_20', 'location_city_infos') }} C
    ON M.CITY_ID = C.id
WHERE M.CITY_ID IS NOT NULL
  AND M.CITY_NM != C.key_name
