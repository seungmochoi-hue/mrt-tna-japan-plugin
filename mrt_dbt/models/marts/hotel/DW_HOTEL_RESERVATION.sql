{{
    config(
        materialized='table',
        schema='edw',
        alias='DW_HOTEL_RESERVATION'
    )
}}

SELECT CAST(h.id AS STRING) AS id
     , h.history_id AS history_id
     , h.ota_id AS ota_id
     , h.created_at AS created_at
     , h.created_at_kst AS created_at_kst
     , h.updated_at AS updated_at
     , h.updated_at_kst AS updated_at_kst
     , h.reserv_id AS reserv_id
     , h.reserv_date AS reserv_date
     , h.reserv_date_kst AS reserv_date_kst
     , DATE(h.reserv_date_kst) AS reservation_kst_date
     , h.last_modified AS last_modified
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
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS dw_load_dt
FROM {{ source('localstay', 'hotel_reservupdate_detail') }} h
