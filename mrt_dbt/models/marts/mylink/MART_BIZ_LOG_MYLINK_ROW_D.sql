{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_BIZ_LOG_MYLINK_ROW_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['MYLINK_ID']
    )
}}

WITH LOG_ROW AS (
    SELECT L.basis_dt AS BASIS_DATE
        ,  CAST(L.pid AS STRING) AS PID
        ,  L.platform AS PLATFORM
        ,  CAST(L.item_id AS STRING) AS ITEM_ID
        ,  CAST(L.mylink_id AS STRING) AS MYLINK_ID
        ,  CASE WHEN L.screen_name in ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail') THEN L.event_timestamp_kst ELSE null END AS OFFER_DETAIL_KST_DT
        ,  CASE WHEN L.screen_name in ('purchase', 'checkout') AND L.event_name in ('purchase', 'checkout') THEN L.event_timestamp_kst ELSE null END AS CHECKOUT_KST_DT
        ,  CASE WHEN L.screen_name in ('purchase_complete', 'checkout_complete') AND L.event_name in ('purchase_complete', 'checkout_complete') THEN L.event_timestamp_kst ELSE null END AS CHECKOUT_COMPLETE_KST_DT
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} L
    WHERE L.basis_dt BETWEEN '{{ var("start_date_kst") }}' AND '{{ var("end_date_kst") }}'
      AND L.event_type = 'pageview'
      AND L.screen_name in ('offer_detail', 'hotel_offer_detail', 'lodging_detail', 'rentacar_detail', 'domestic_accommodation_detail', 'package_detail', 'esim_offer_detail', 'purchase', 'checkout', 'purchase_complete', 'checkout_complete')
      AND L.ITEM_ID IS NOT NULL AND LENGTH(L.ITEM_ID) > 0
      AND L.mylink_id IS NOT NULL

    UNION ALL

    -- 항공 추가
    SELECT L.basis_dt AS BASIS_DATE
         ,  CAST(L.pid AS STRING) AS PID
         ,  L.platform AS PLATFORM
         ,  'AIR' AS ITEM_ID
         ,  CAST(L.mylink_id AS STRING) AS MYLINK_ID
         ,  CASE WHEN L.screen_name in ('dom_flights_selected', 'intl_flights_avail_detail') THEN L.event_timestamp_kst ELSE null END AS OFFER_DETAIL_KST_DT
         ,  CASE WHEN L.screen_name in ('dom_flights_reservation', 'intl_flights_reservation') AND L.event_name in ('dom_flights_reservation', 'intl_flights_reservation') THEN L.event_timestamp_kst ELSE null END AS CHECKOUT_KST_DT
         ,  CASE WHEN L.screen_name in ('dom_flights_purchased', 'intl_flights_reservation_complete') AND L.event_name in ('purchase_complete', 'intl_flights_reservation_complete') THEN L.event_timestamp_kst ELSE null END AS CHECKOUT_COMPLETE_KST_DT
    FROM {{ ref('DW_BIZ_LOG_VIEW') }} L
    WHERE L.basis_dt BETWEEN '{{ var("start_date_kst") }}' AND '{{ var("end_date_kst") }}'
      AND L.event_type = 'pageview'
      AND L.screen_name in ('dom_flights_selected', 'intl_flights_avail_detail', 'dom_flights_reservation', 'intl_flights_reservation', 'dom_flights_purchased', 'intl_flights_reservation_complete')
      AND L.mylink_id IS NOT NULL
)
SELECT L.BASIS_DATE
     ,  L.PID
     ,  L.PLATFORM
     ,  L.ITEM_ID
     ,  L.MYLINK_ID
     ,  L.OFFER_DETAIL_KST_DT
     ,  L.CHECKOUT_KST_DT
     ,  L.CHECKOUT_COMPLETE_KST_DT
FROM LOG_ROW L
WHERE L.OFFER_DETAIL_KST_DT IS NOT NULL OR L.CHECKOUT_KST_DT IS NOT NULL OR L.CHECKOUT_COMPLETE_KST_DT IS NOT NULL