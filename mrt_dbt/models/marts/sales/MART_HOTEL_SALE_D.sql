{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_HOTEL_SALE_D',
        enabled=false
    )
}}


WITH HOTEL_RESERVUPDATE_DETAIL_NODUP AS (
SELECT H.id
    ,  H.history_id
    ,  H.ota_id
    ,  H.created_at_kst
    ,  H.updated_at_kst
    ,  H.reserv_id
    ,  H.reserv_date_kst
    ,  H.last_modified_kst
    ,  H.status
    ,  H.user_id
    ,  H.country
    ,  H.city
    ,  H.hotel_id
    ,  H.title
    ,  H.type
    ,  H.check_in
    ,  H.check_out
    ,  H.travel_nights
    ,  H.booking_window
    ,  H.ttv
    ,  H.ttv_currency
    ,  H.ttv_won
    ,  H.coupon
    ,  H.platform
    ,  H.affiliate
    ,  H.campaign
  FROM (
SELECT H.id
    ,  H.history_id
    ,  H.ota_id
    ,  H.created_at_kst
    ,  H.updated_at_kst
    ,  H.reserv_id
    ,  H.reserv_date_kst
    ,  H.last_modified_kst
    ,  H.status
    ,  H.user_id
    ,  H.country
    ,  H.city
    ,  H.hotel_id
    ,  H.title
    ,  H.type
    ,  H.check_in
    ,  H.check_out
    ,  H.travel_nights
    ,  H.booking_window
    ,  H.ttv
    ,  H.ttv_currency
    ,  H.ttv_won
    ,  H.coupon
    ,  H.platform
    ,  H.affiliate
    ,  H.campaign
    ,  ROW_NUMBER() OVER (PARTITION BY H.reserv_id ORDER BY H.updated_at_kst DESC) RN
 FROM {{ source('localstay', 'hotel_reservupdate_detail') }} H
 ) H
 WHERE H.RN = 1
),
RESERVUPDATE_DETAIL_NODUP_SNP AS (
SELECT CAST(h.id AS string) AS id
     , h.history_id AS history_id
     , h.ota_id AS ota_id
     , h.created_at_kst AS created_at_kst
     , h.updated_at_kst AS updated_at_kst
     , h.reserv_id AS reserv_id
     , h.reserv_date_kst AS reserv_date_kst
     , DATE(h.reserv_date_kst) AS reservation_kst_date
     , h.last_modified_kst AS last_modified_kst
     , CASE WHEN h.affiliate = 'agoda' THEN
            CASE WHEN h.status = 'BookingCharged' THEN 'wait_payment'
                 WHEN h.status = 'BookingReceived' THEN 'wait_confirm'
                 WHEN h.status = 'BookingConfirmed' THEN 'confirm'
                 WHEN h.status IN ('BookingCancelledByCustomer', 'BookingCancelled', 'TechnicalError') THEN 'cancel'
                 WHEN h.status = 'Departed' THEN 'finish' END
            WHEN h.affiliate = 'booking' THEN
            CASE WHEN h.status = 'booked' THEN 'confirm'
                 WHEN h.status IN ('cancelled', 'cancelled_by_hotel', 'cancelled_by_guest') THEN 'cancel'
                 WHEN h.status IN ('no_show', 'stayed', 'Finalised') THEN 'finish' END
            WHEN h.affiliate IN ('expedia', 'hotels') THEN
            CASE WHEN h.status = 'pending' THEN 'wait_confirm'
                 WHEN h.status = 'approved' AND h.check_in <= '{{ var("logical_start_date_kst") }}' THEN 'finish'
                 WHEN h.status = 'approved' THEN 'confirm'
                 WHEN h.status = 'rejected' THEN 'cancel' END
            WHEN h.affiliate = 'airbnb' THEN
            CASE WHEN h.status = 'Pending' THEN 'wait_confirm'
                 WHEN h.status = 'Approved' AND h.check_in <= '{{ var("logical_start_date_kst") }}' THEN 'finish'
                 WHEN h.status = 'Approved' THEN 'confirm'
                 WHEN h.status = 'Reversed' THEN 'cancel' END END AS status
     , IF(SAFE_CAST(h.user_id AS INT64) IS NULL, 'guest', h.user_id) AS user_id
     , h.country AS country
     , h.city AS city
     , h.hotel_id AS hotel_id
     , h.title AS title
     , h.type AS type
     , h.check_in AS check_in
     , h.check_out AS check_out
     , h.travel_nights AS travel_nights
     , h.booking_window AS booking_window
     , h.ttv AS ttv
     , h.ttv_currency AS ttv_currency
     , h.ttv_won AS ttv_won
     , h.coupon AS coupon
     , h.platform AS platform
     , h.affiliate AS affiliate
     , h.campaign AS cid
     , CASE WHEN h.affiliate = 'agoda' THEN
            CASE WHEN h.campaign = '1812701' THEN 'meta'
                 WHEN h.campaign = '1770098' THEN 'promo'
                 WHEN h.campaign = '1836557' THEN 'cross_promo'
                 WHEN h.campaign = '1842459' THEN 'paid_ad'
                 WHEN h.campaign = '1837220' THEN 'mkt_sns'
                 WHEN h.campaign = '1846010' THEN 'domestic'
                 WHEN h.campaign = '1843108' THEN 'MBC'
                 WHEN h.campaign = '1834962' THEN 'mkt_ua15'
                 ELSE 'etc' END
            WHEN h.affiliate = 'booking' THEN
            CASE WHEN h.campaign = '1811099' THEN 'meta'
                 WHEN h.campaign = '1876406' THEN 'promo'
                 WHEN h.campaign = '1876439' THEN 'cross_promo'
                 WHEN h.campaign = '1876405' THEN 'paid_ad'
                 WHEN h.campaign = '1876440' THEN 'mkt_sns'
                 WHEN h.campaign = '2021504' THEN 'domestic'
                 WHEN h.campaign = '1876429' THEN 'mkt_apppush'
                 WHEN h.campaign = '2039627' THEN 'project 1'
                 WHEN h.campaign = '2021498' THEN 'project 2'
                 WHEN h.campaign IN ('1138078', '1580978', '1808202') THEN 'null'
                 ELSE 'etc' END
            WHEN h.affiliate = 'expedia' THEN
            CASE WHEN h.campaign = 'meta'  THEN 'meta'
                 WHEN h.campaign = 'promo' THEN 'promo'
                 WHEN h.campaign = 'cross' THEN 'cross_promo'
                 WHEN h.campaign = 'ad'    THEN 'paid_ad'
                 WHEN h.campaign = 'blog'  THEN 'mkt_sns'
                 WHEN h.campaign = 'cross_flight15' THEN 'cross_lms'
                 ELSE 'etc' END
            WHEN h.affiliate = 'hotels' THEN
            CASE WHEN h.campaign = 'promo'    THEN 'promo'
                 WHEN h.campaign = 'cross'    THEN 'cross_promo'
                 WHEN h.campaign = 'ad'       THEN 'paid_ad'
                 WHEN h.campaign = 'blog'     THEN 'mkt_sns'
                 WHEN h.campaign = 'domestic' THEN 'domestic'
                 ELSE 'etc' END
            WHEN h.affiliate = 'airbnb' THEN
            CASE WHEN h.campaign = 'promo'       THEN 'promo'
                 WHEN h.campaign = 'cross_promo' THEN 'cross_promo'
                 WHEN h.campaign = 'blog'        THEN 'mkt_sns'
                 WHEN h.campaign = 'domestic'    THEN 'domestic'
                 WHEN h.campaign = 'mkt_apppush' THEN 'mkt_apppush'
                 WHEN h.campaign = 'cross_lms'   THEN 'cross_lms'
                 WHEN h.campaign = 'eudiny'      THEN 'eudiny'
                 ELSE 'etc' END END AS campaign
     , CURRENT_TIMESTAMP() AS dw_load_dt
FROM HOTEL_RESERVUPDATE_DETAIL_NODUP h
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON h.user_id = U.USER_ID
WHERE (U.TEST_FLAG <> true OR U.USER_ID IS NULL)
)
SELECT CAST(s.reserv_date_kst AS DATE) AS BASIS_DATE
    ,  s.reserv_id AS RESVE_ID
    ,  1 AS KIND
    ,  s.status AS RECENT_STATUS
    ,  NULL AS CANCEL_KST_DT
    ,  s.history_id AS HISTORY_ID
    ,  s.ota_id AS OTA_ID
    ,  s.reserv_date_kst AS RESVE_KST_DT
    ,  s.user_id AS USER_ID
    ,  s.country AS RESVE_COUNTRY_NM
    ,  IFNULL(H.KEY_NM, s.city) AS RESVE_CITY_NM
    ,  IF(s.hotel_id <> 'null', hotel_id, NULL) AS HOTEL_ID
    ,  LOWER(s.title) AS ACCOMMODATION_NM
    ,  LOWER(s.type) AS ACCOMMODATION_TYPE
    ,  s.check_in AS CHECK_IN_KST_DATE
    ,  s.check_out AS CHECK_OUT_KST_DATE
    ,  s.travel_nights AS STAY_DT_CNT
    ,  s.booking_window AS LEADTIME_VALUE
    ,  FLOOR(s.ttv * 100) / 100 AS SALES_PRICE
    ,  s.ttv_currency AS SALES_PRICE_CUR_TYPE
    ,  FLOOR(s.ttv_won * 100) / 100 AS SALES_KRW_PRICE
    ,  s.coupon AS USE_COUPON_NM
    ,  LOWER(s.platform) AS PLATFORM
    ,  LOWER(s.affiliate) AS OTA_NM
    ,  s.cid AS CAMPAIGN_ID
    ,  s.campaign AS CAMPAIGN_TYPE
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVUPDATE_DETAIL_NODUP_SNP s
LEFT JOIN {{ ref('DIM_HOTEL_AFFILIATE_CITY_NM') }} H ON H.CITY_NM = s.city AND H.AFFILIATE_NM = S.affiliate
WHERE s.status IN ('wait_confirm', 'confirm', 'cancel', 'finish')
  OR (s.ota_id = 'AG' AND s.status = 'wait_payment')

UNION ALL

SELECT CAST(s.reserv_date_kst AS DATE) AS BASIS_DATE
    ,  s.reserv_id AS RESVE_ID
    ,  2 AS KIND
    ,  s.status AS RECENT_STATUS
    ,  s.reserv_date_kst AS CANCEL_KST_DT
    ,  s.history_id AS HISTORY_ID
    ,  s.ota_id AS OTA_ID
    ,  s.reserv_date_kst AS RESVE_KST_DT
    ,  s.user_id AS USER_ID
    ,  s.country AS TRAVEL_COUNTRY_NM
    ,  IFNULL(H.KEY_NM, s.city) AS RESVE_CITY_NM
    ,  IF(s.hotel_id <> 'null', s.hotel_id, NULL) AS HOTEL_ID
    ,  LOWER(s.title) AS ACCOMMODATION_NM
    ,  LOWER(s.type) AS ACCOMMODATION_TYPE
    ,  s.check_in AS CHECK_IN_KST_DATE
    ,  s.check_out AS CHECK_OUT_KST_DATE
    ,  s.travel_nights AS NIGHT_VALUE
    ,  s.booking_window AS LEADTIME_VALUE
    ,  FLOOR(s.ttv * 100) / 100 * -1 AS SALES_PRICE
    ,  s.ttv_currency AS SALES_PRICE_CUR_TYPE
    ,  FLOOR(s.ttv_won * 100) / 100 * -1 AS SALES_KRW_PRICE
    ,  s.coupon AS USE_COUPON_VALUE
    ,  LOWER(s.platform) AS PLATFORM
    ,  LOWER(s.affiliate) AS OTA_NM
    ,  s.cid AS CAMPAIGN_ID
    ,  s.campaign AS CAMPAIGN_VALUE
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM RESERVUPDATE_DETAIL_NODUP_SNP s
LEFT JOIN {{ ref('DIM_HOTEL_AFFILIATE_CITY_NM') }} H ON H.CITY_NM = s.city AND H.AFFILIATE_NM = S.affiliate
WHERE s.status IN ('cancel')