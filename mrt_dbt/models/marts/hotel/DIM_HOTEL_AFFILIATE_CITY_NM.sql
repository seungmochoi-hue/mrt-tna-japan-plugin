{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_HOTEL_AFFILIATE_CITY_NM'
    )
}}


SELECT  K.CITY_INFO_ID
     ,  K.KEY_NM
     ,  K.BOOKING_CITY_NM
     ,  K.AFFILIATE_NM
     ,  K.CITY_NM
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT T.CITY_INFO_ID                                                    AS CITY_INFO_ID
              , T.KEY_NM                                                        AS KEY_NM
              , T.BOOKING_CITY_NM                                                    AS BOOKING_CITY_NM
              , CASE
                    WHEN row_num = 1 AND T.TRIP_NM IS NOT NULL THEN 'trip'
                    WHEN row_num = 2 AND T.EXPEDIA_NM IS NOT NULL THEN 'expedia'
                    WHEN row_num = 3 AND T.AIRBNB_NM IS NOT NULL THEN 'airbnb'
                    WHEN row_num = 4 AND T.HOTELS_NM IS NOT NULL THEN 'hotels'
                    WHEN row_num = 5 AND T.AGODA_NM IS NOT NULL THEN 'agoda'
                    WHEN row_num = 6 AND T.BOOKING_NM IS NOT NULL THEN 'booking' END     AS AFFILIATE_NM
              , CASE
                    WHEN row_num = 1 AND T.TRIP_NM IS NOT NULL THEN T.TRIP_NM
                    WHEN row_num = 2 AND T.EXPEDIA_NM IS NOT NULL THEN T.EXPEDIA_NM
                    WHEN row_num = 3 AND T.AIRBNB_NM IS NOT NULL THEN T.AIRBNB_NM
                    WHEN row_num = 4 AND T.HOTELS_NM IS NOT NULL THEN T.HOTELS_NM
                    WHEN row_num = 5 AND T.AGODA_NM IS NOT NULL THEN T.AGODA_NM
                    WHEN row_num = 6 AND T.BOOKING_NM IS NOT NULL THEN T.BOOKING_NM END   AS CITY_NM
         FROM (
                  SELECT h.CITY_INFO_ID    AS CITY_INFO_ID
                       , h.KEY_NM          AS KEY_NM
                       , h.BOOKING_CITY_NM AS BOOKING_CITY_NM
                       , h.TRIP_NM         AS TRIP_NM
                       , h.EXPEDIA_NM      AS EXPEDIA_NM
                       , h.AIRBNB_NM       AS AIRBNB_NM
                       , h.HOTELS_NM       AS HOTELS_NM
                       , h.AGODA_NM        AS AGODA_NM
                       , h.BOOKING_NM      AS BOOKING_NM
                       , row_num
                  FROM {{ ref('DIM_HOTEL_CITY') }} h
                  CROSS JOIN UNNEST([1, 2, 3, 4, 5, 6]) AS row_num
              ) T
     ) K
WHERE K.CITY_NM IS NOT NULL