{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_PRODUCT_LOG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by = ['GID']
    )
}}


SELECT T.BASIS_DT AS BASIS_DT
     ,  T.PLATFORM AS PLATFORM
     ,  T.GID AS GID
     ,  MAX(T.TOTAL_RESERVATION_CNT) AS TOTAL_RESERVATION_CNT
     ,  MAX(T.TOTAL_RESERVATION_USER_CNT) AS TOTAL_RESERVATION_USER_CNT
     ,  MAX(T.TOTAL_SALE_PRICE) AS TOTAL_SALE_PRICE
     ,  MAX(OFFER_IMPRESSION) AS OFFER_IMPRESSION_CNT
     ,  MAX(OFFER_CLICK) AS OFFER_CLICK_CNT
     ,  SAFE_DIVIDE(MAX(OFFER_CLICK), MAX(OFFER_IMPRESSION)) * 100 AS OFFER_CLICK_RT
     ,  MAX(OFFER_DETAIL_UV) AS OFFER_DETAIL_UV
     ,  SAFE_DIVIDE(MAX(CHECKOUT_UV), MAX(OFFER_DETAIL_UV)) * 100 AS OFFER_TO_CHECKOUT_RT
     ,  MAX(CHECKOUT_UV) AS CHECKOUT_UV
     ,  SAFE_DIVIDE(MAX(CHECKOUT_COMPLETE_UV), MAX(CHECKOUT_UV)) * 100 AS CHECKOUT_TO_COMPLETE_RT
     ,  MAX(CHECKOUT_COMPLETE_UV) AS CHECKOUT_COMPLETE_UV
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         --로그
         SELECT L.basis_dt AS BASIS_DT
              , L.platform AS PLATFORM
              , CASE WHEN item_id LIKE '%BNB%' THEN CAST(P.union_product_id AS STRING)
                     ELSE L.item_id
             END AS GID
              , NULL AS TOTAL_RESERVATION_CNT
              , NULL AS TOTAL_RESERVATION_USER_CNT
              , NULL AS TOTAL_SALE_PRICE
              , NULL AS OFFER_IMPRESSION
              , COUNT(
                 DISTINCT CASE
                              WHEN (L.item_kind = 'offer' OR L.event_name = 'offer')
                                  AND L.event_type = 'click'
                                  THEN L.pid
                     END
             ) AS OFFER_CLICK
              , COUNT(
                 DISTINCT CASE
                              WHEN L.event_type = 'pageview'
                                  AND L.screen_name IN ('offer_detail', 'domestic_accommodation_detail', 'lodging_detail', 'rentacar_detail', 'hotel_offer_detail', 'esim_offer_detail')
                                  THEN L.pid
                     END
             ) AS OFFER_DETAIL_UV
              , COUNT(
                 DISTINCT CASE
                              WHEN L.event_type = 'pageview'
                                  AND L.screen_name IN ('purchase', 'checkout')
                                  THEN L.pid
                     END
             ) AS CHECKOUT_UV
              , COUNT(
                 DISTINCT CASE
                              WHEN L.event_type = 'pageview'
                                  AND L.screen_name IN ('purchase_complete', 'checkout_complete')
                                  THEN L.pid
                     END
             ) AS CHECKOUT_COMPLETE_UV
         FROM {{ ref("DW_BIZ_LOG_VIEW") }} L
                  LEFT JOIN {{ source('products', 'products') }} P
                            ON L.item_id = CONCAT('BNB', P.id)
         WHERE L.basis_dt = '{{ var("logical_start_date_kst") }}'
           AND item_id IS NOT NULL
           AND LENGTH(item_id) > 0
           AND item_id NOT IN ('-1', '0')
         GROUP BY L.basis_dt, L.platform, CASE WHEN item_id LIKE '%BNB%' THEN CAST(P.union_product_id AS STRING) ELSE L.item_id END

         UNION ALL

         -- 노출
         SELECT L.basis_dt AS BASIS_DT
              , L.platform AS PLATFORM
              , CASE WHEN item_id LIKE '%BNB%' THEN CAST(P.union_product_id AS STRING)
                     ELSE L.item_id
             END AS GID
              , NULL AS TOTAL_RESERVATION_CNT
              , NULL AS TOTAL_RESERVATION_USER_CNT
              , NULL AS TOTAL_SALE_PRICE
              , COUNT(
                 DISTINCT CASE
                              WHEN (L.item_kind = 'offer' OR L.event_name = 'offer')
                                  THEN L.pid
                     END
             ) AS OFFER_IMPRESSION
              , NULL AS OFFER_CLICK
              , NULL AS OFFER_DETAIL_UV
              , NULL AS CHECKOUT_UV
              , NULL AS CHECKOUT_COMPLETE_UV
         FROM {{ ref("DW_BIZ_LOG_VIEW") }} L
                  LEFT JOIN {{ source('products', 'products') }} P
                            ON L.item_id = CONCAT('BNB', P.id)
         WHERE L.basis_dt = '{{ var("logical_start_date_kst") }}'
           AND L.event_type = 'impression'
           AND item_id IS NOT NULL
           AND LENGTH(item_id) > 0
           AND item_id NOT IN ('-1', '0')
         GROUP BY L.basis_dt, L.platform, CASE WHEN item_id LIKE '%BNB%' THEN CAST(P.union_product_id AS STRING) ELSE L.item_id END
     ) T
WHERE T.GID IS NOT NULL AND LENGTH(T.GID) > 0
GROUP BY T.BASIS_DT, T.GID, T.PLATFORM