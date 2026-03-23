{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PRODUCT_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['GID']
    )
}}

SELECT T.BASIS_DT AS BASIS_DT
     ,  T.GID AS GID
     ,  MAX(T.TOTAL_RESERVATION_CNT) AS TOTAL_RESERVATION_CNT
     ,  MAX(T.TOTAL_RESERVATION_USER_CNT) AS TOTAL_RESERVATION_USER_CNT
     ,  MAX(T.TOTAL_SALE_PRICE) AS TOTAL_SALE_PRICE
     ,  MAX(T.OFFER_IMPRESSION_CNT) AS OFFER_IMPRESSION_CNT
     ,  MAX(T.OFFER_CLICK_CNT) AS OFFER_CLICK_CNT
     ,  SAFE_DIVIDE(MAX(OFFER_CLICK_CNT), MAX(OFFER_IMPRESSION_CNT)) * 100 AS OFFER_CLICK_RT
     ,  MAX(OFFER_DETAIL_UV) AS OFFER_DETAIL_UV
     ,  SAFE_DIVIDE(MAX(CHECKOUT_UV), MAX(OFFER_DETAIL_UV)) * 100 AS OFFER_TO_CHECKOUT_RT
     ,  MAX(CHECKOUT_UV) AS CHECKOUT_UV
     ,  SAFE_DIVIDE(MAX(CHECKOUT_COMPLETE_UV), MAX(CHECKOUT_UV)) * 100 AS CHECKOUT_TO_COMPLETE_RT
     ,  MAX(CHECKOUT_COMPLETE_UV) AS CHECKOUT_COMPLETE_UV
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         --예약
         SELECT S.BASIS_DATE AS BASIS_DT
              ,  COALESCE(S.GID, p.union_product_id) AS GID
              ,  COUNT(DISTINCT S.RESVE_ID) AS TOTAL_RESERVATION_CNT
              ,  COUNT(DISTINCT S.USER_ID) AS TOTAL_RESERVATION_USER_CNT
              ,  CAST(SUM(S.SALES_KRW_PRICE) AS BIGINT) AS TOTAL_SALE_PRICE
              ,  NULL AS OFFER_IMPRESSION_CNT
              ,  NULL AS OFFER_CLICK_CNT
              ,  NULL AS OFFER_DETAIL_UV
              ,  NULL AS CHECKOUT_UV
              ,  NULL AS CHECKOUT_COMPLETE_UV
         FROM {{ ref('MART_SALE_D') }} S
                  LEFT JOIN {{ source('products', 'products') }} AS p
                            ON S.PRODUCT_ID = CONCAT('BNB' , p.id)
                                AND S.DOMAIN_NM = '3.0 PRODUCT' AND S.CATEGORY_NM = 'LODGING'
         WHERE kind = 1
           AND S.DOMAIN_NM NOT IN ('AIR', 'HOTEL', 'INSURANCE')
         GROUP BY S.BASIS_DATE, COALESCE(S.GID, p.union_product_id)

         UNION ALL

         --로그
         SELECT L.BASIS_DT
              , L.GID
              , NULL AS TOTAL_RESERVATION_CNT
              , NULL AS TOTAL_RESERVATION_USER_CNT
              , NULL AS TOTAL_SALE_PRICE
              , SUM(L.OFFER_IMPRESSION_CNT) AS OFFER_IMPRESSION_CNT
              , SUM(L.OFFER_CLICK_CNT) AS OFFER_CLICK_CNT
              , SUM(L.OFFER_DETAIL_UV) AS OFFER_DETAIL_UV
              , SUM(L.CHECKOUT_UV) AS CHECKOUT_UV
              , SUM(L.CHECKOUT_COMPLETE_UV) AS CHECKOUT_COMPLETE_UV
         FROM {{ ref('MART_PRODUCT_LOG_D') }} L
         GROUP BY L.BASIS_DT, L.GID
     ) T
GROUP BY T.BASIS_DT, T.GID