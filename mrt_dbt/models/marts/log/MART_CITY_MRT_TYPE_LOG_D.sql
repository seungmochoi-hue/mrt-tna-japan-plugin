{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='batch',
        alias='MART_CITY_MRT_TYPE_LOG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        }
    )
}}


SELECT  T.BASIS_DT AS BASIS_DT
     , T.PLATFORM AS PLATFORM
     , T.COUNTRY_NM AS COUNTRY_NM
     , T.CITY_NM AS CITY_NM
     , T.MRT_TYPE AS MRT_TYPE
     , MAX(T.TOTAL_RESERVATION_CNT) AS TOTAL_RESERVATION_CNT
     , MAX(T.TOTAL_RESERVATION_USER_CNT) AS TOTAL_RESERVATION_USER_CNT
     , MAX(T.TOTAL_SALE_PRICE) AS TOTAL_SALE_PRICE
     , MAX(OFFER_IMPRESSION) AS OFFER_IMPRESSION_CNT
     , MAX(OFFER_CLICK) AS OFFER_CLICK_CNT
     , SAFE_DIVIDE(MAX(OFFER_CLICK), MAX(OFFER_IMPRESSION)) * 100 AS OFFER_CLICK_RT
     , MAX(OFFER_DETAIL_UV) AS OFFER_DETAIL_UV
     , SAFE_DIVIDE(MAX(CHECKOUT_UV), MAX(OFFER_DETAIL_UV)) * 100 AS OFFER_TO_CHECKOUT_RT
     , MAX(CHECKOUT_UV) AS CHECKOUT_UV
     , SAFE_DIVIDE(MAX(CHECKOUT_COMPLETE_UV), MAX(CHECKOUT_UV)) * 100 AS CHECKOUT_TO_COMPLETE_RT
     , MAX(CHECKOUT_COMPLETE_UV) AS CHECKOUT_COMPLETE_UV
     , MAX(VIEW_ITEM_CNT) AS VIEW_ITEM_CNT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         -- 로그
         SELECT  L.BASIS_DT AS BASIS_DT
              , L.PLATFORM AS PLATFORM
              , MP.COUNTRY_NM AS COUNTRY_NM
              , MP.CITY_NM AS CITY_NM
              , MP.MRT_TYPE AS MRT_TYPE
              , NULL AS TOTAL_RESERVATION_CNT
              , NULL AS TOTAL_RESERVATION_USER_CNT
              , NULL AS TOTAL_SALE_PRICE
              , NULL AS OFFER_IMPRESSION
              , COUNT(DISTINCT CASE WHEN L.ITEM_KIND = 'offer' AND L.EVENT_TYPE = 'click' THEN L.PID END) AS OFFER_CLICK
              , COUNT(DISTINCT CASE WHEN L.EVENT_TYPE = 'pageview' AND L.SCREEN_NAME IN ('offer_detail', 'domestic_accommodation_detail', 'lodging_detail', 'rentacar_detail') THEN L.PID END) AS OFFER_DETAIL_UV
              , COUNT(DISTINCT CASE WHEN L.EVENT_TYPE = 'pageview' AND L.SCREEN_NAME IN ('offer_detail', 'domestic_accommodation_detail', 'lodging_detail', 'rentacar_detail') THEN CONCAT(L.ITEM_ID, L.PID) END) AS VIEW_ITEM_CNT
              , COUNT(DISTINCT CASE WHEN L.EVENT_TYPE = 'pageview' AND L.SCREEN_NAME IN ('purchase', 'checkout') THEN L.PID END) AS CHECKOUT_UV
              , COUNT(DISTINCT CASE WHEN L.EVENT_TYPE = 'pageview' AND L.SCREEN_NAME IN ('purchase_complete', 'checkout_complete') THEN L.PID END) AS CHECKOUT_COMPLETE_UV
         FROM {{ ref('DW_BIZ_LOG_VIEW') }} L
         LEFT JOIN {{ source("products", "products") }} P ON L.ITEM_ID = CONCAT('BNB', P.ID)
         LEFT JOIN {{ source ('mrt_mart_view', 'MART_PRODUCT_D') }} MP ON CASE WHEN L.ITEM_ID LIKE '%BNB%' THEN CAST(P.UNION_PRODUCT_ID AS STRING) ELSE L.ITEM_ID END = MP.GID
         WHERE L.BASIS_DT = '{{ var("logical_start_date_kst") }}'
           AND L.ITEM_ID IS NOT NULL
           AND L.ITEM_ID NOT IN ('-1', '0')
         GROUP BY 1, 2, 3, 4, 5

         UNION ALL

         -- 노출
         SELECT  L.BASIS_DT AS BASIS_DT
              , L.PLATFORM AS PLATFORM
              , MP.COUNTRY_NM AS COUNTRY_NM
              , MP.CITY_NM AS CITY_NM
              , MP.MRT_TYPE AS MRT_TYPE
              , NULL AS TOTAL_RESERVATION_CNT
              , NULL AS TOTAL_RESERVATION_USER_CNT
              , NULL AS TOTAL_SALE_PRICE
              , COUNT(DISTINCT CASE WHEN L.ITEM_KIND = 'offer' THEN L.PID END) AS OFFER_IMPRESSION
              , NULL AS OFFER_CLICK
              , NULL AS OFFER_DETAIL_UV
              , NULL AS VIEW_ITEM_CNT
              , NULL AS CHECKOUT_UV
              , NULL AS CHECKOUT_COMPLETE_UV
         FROM {{ ref("DW_BIZ_LOG_VIEW") }} L
         LEFT JOIN {{ source("products", "products") }} P ON L.ITEM_ID = CONCAT('BNB', P.ID)
         LEFT JOIN {{ source ('mrt_mart_view', 'MART_PRODUCT_D') }} MP ON CASE WHEN L.ITEM_ID LIKE '%BNB%' THEN CAST(P.UNION_PRODUCT_ID AS STRING) ELSE L.ITEM_ID END = MP.GID
         WHERE L.BASIS_DT = '{{ var("logical_start_date_kst") }}'
           AND L.event_type = 'impression'
           AND L.ITEM_ID IS NOT NULL
           AND L.ITEM_ID NOT IN ('-1', '0')
         GROUP BY 1, 2, 3, 4, 5
     ) T
GROUP BY T.BASIS_DT, T.COUNTRY_NM, T.CITY_NM, T.PLATFORM, T.MRT_TYPE
