{{
    config(
        materialized='table',
        schema='temp',
        alias='TEMP_MART_HOTEL_MISSING_CITY_NM_D'
    )
}}



SELECT DISTINCT A.affiliate AS AFFILIATE_NM
              , A.city      AS CITY_NM
              , 'N'         AS SEND_SLACK_MESSAGE_FLAG
 FROM {{ source('localstay', 'hotel_reservupdate_detail') }} A
LEFT JOIN {{ ref('DIM_HOTEL_AFFILIATE_CITY_NM') }} B ON A.affiliate = B.AFFILIATE_NM AND A.city = B.CITY_NM
WHERE B.CITY_INFO_ID IS NULL