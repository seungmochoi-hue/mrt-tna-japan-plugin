{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PACKAGE_OPTION_SALE_D'
    )
}}

WITH ORIGIN_DATA AS (
    SELECT
        s.RESVE_MAPPING_ID
      , s.KIND
      , s.OPTION_PRODUCT_ID
      , s.PAYMENT_COMMISSION_RATE
      , s.PAYMENT_COMMISSION_PRICE
      , s.RESVE_MAPPING_CHANGE_ID
      , s.SUPPLY_PRICE
    FROM {{ ref('MART_PACKAGE_OPTION_RESVE_D') }} AS s
    WHERE s.RESVE_TYPE = 'ORIGIN'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY s.RESVE_MAPPING_ID, s.KIND, s.OPTION_PRODUCT_ID
        ORDER BY CASE
            WHEN s.RESVE_MAPPING_CHANGE_ID IS NULL THEN '999999999'
            ELSE s.RESVE_MAPPING_CHANGE_ID
        END DESC
    ) = 1
)
, ACM_RESVE_DATA AS (
    SELECT
        pkg_opt.id AS option_reservation_id
      , pkg_opt.link_id AS acm_reservation_id
      , acm_res.total_supply_price AS supply_price
    FROM {{ source('orders', 'option_reservations') }} AS pkg_opt
    LEFT JOIN {{ source('orders', 'reservations') }} AS acm_res
      ON pkg_opt.link_id = acm_res.id
    WHERE pkg_opt.link_id IS NOT NULL
)
SELECT
    r.BASIS_DATE
  , r.ORDER_ID
  , r.RESVE_ID
  , r.OPTION_ID
  , r.RESVE_OPTION_ID
  , r.KIND
  , r.RESVE_MAPPING_ID
  , r.RESVE_MAPPING_TYPE
  , r.RESVE_MAPPING_CHANGE_ID
  , r.RESVE_VERSION_VALUE
  , r.PRODUCT_ID
  , r.OPTION_PRODUCT_ID
  , r.PACKAGE_GID
  , r.PACKAGE_OPTION_GID
  , r.LINK_ID
  , r.CANCELED_AT
  , r.CANCEL_REASON_TYPE
  , r.PAYMENT_ID
  , r.RESVE_TITLE
  , r.OPTION_RESVE_TITLE
  , r.RESVE_TYPE
  , r.OPTION_RESVE_TYPE
  , r.RECENT_RESVE_STATUS
  , r.RECENT_OPTION_RESVE_STATUS
  , r.RESVE_TRAVEL_START_KST_DATE
  , r.TRAVEL_START_KST_DATE
  , r.TRAVEL_END_KST_DATE
  , r.PG_NM
  , r.PLATFORM
  , r.RESVE_PAID_KST_DT
  , r.PACKAGE_STANDARD_CATEGORY_LV_1_CD
  , r.PACKAGE_STANDARD_CATEGORY_LV_1_NM
  , r.PACKAGE_STANDARD_CATEGORY_LV_2_CD
  , r.PACKAGE_STANDARD_CATEGORY_LV_2_NM
  , r.PACKAGE_STANDARD_CATEGORY_LV_3_CD
  , r.PACKAGE_STANDARD_CATEGORY_LV_3_NM
  , r.AIR_PNR_NO
  , r.CREATE_KST_DT
  , r.UPDATE_KST_DT
  , r.PACKAGE_PARTNER_ID
  , r.PACKAGE_OPTION_PARTNER_ID
  , r.PAYMENT_METHOD_VALUE
  , r.SALES_PRICE
  , r.PAID_PRICE
  , r.COUPON_PRICE
  , r.POINT_PRICE
  , COALESCE(
        ROUND(
            SAFE_DIVIDE(
                COALESCE(pcr.supply_price, IF(sp.total_supply_price = 0, r.SALES_PRICE, sp.total_supply_price))
                - CASE
                    WHEN r.OPTION_RESVE_TYPE = 'ACCOMMODATION_MRT'
                      THEN COALESCE(acm.supply_price, pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
                    ELSE COALESCE(pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
                  END
              , CASE
                    WHEN r.OPTION_RESVE_TYPE = 'ACCOMMODATION_MRT'
                      THEN COALESCE(acm.supply_price, pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
                    ELSE COALESCE(pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
                END
            )
          , 2
        ) * IF(r.KIND = 1, 1, -1)
      , r.PAYMENT_COMMISSION_RATE
    ) AS PAYMENT_COMMISSION_RATE
  , COALESCE(
        (
            COALESCE(pcr.supply_price, IF(sp.total_supply_price = 0, r.SALES_PRICE, sp.total_supply_price))
            - CASE
                WHEN r.OPTION_RESVE_TYPE = 'ACCOMMODATION_MRT'
                  THEN COALESCE(acm.supply_price, pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
                ELSE COALESCE(pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
              END
        ) * IF(r.KIND = 1, 1, -1)
      , r.PAYMENT_COMMISSION_PRICE
    ) AS PAYMENT_COMMISSION_PRICE
  , r.SETTLEMENT_COMMISSION_RATE
  , r.SETTLEMENT_COMMISSION_PRICE
  , CASE
        WHEN r.OPTION_RESVE_TYPE = 'ACCOMMODATION_MRT'
          THEN COALESCE(acm.supply_price, pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
        ELSE COALESCE(pcr.accommodation_supply_price, IF(sp.origin_total_supply_price = 0, NULL, sp.origin_total_supply_price), o.SUPPLY_PRICE, r.SUPPLY_PRICE)
    END AS SUPPLY_PRICE
  , r.CITY_NM
  , r.COUNTRY_NM
  , r.REGION_NM
  , r.RESVE_PURPOSE_TYPE
  , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('MART_PACKAGE_OPTION_RESVE_D') }} AS r
LEFT JOIN ORIGIN_DATA AS o
  ON r.RESVE_MAPPING_ID = o.RESVE_MAPPING_ID
 AND r.OPTION_PRODUCT_ID = o.OPTION_PRODUCT_ID
 AND r.KIND = o.KIND
LEFT JOIN ACM_RESVE_DATA AS acm
  ON SAFE_CAST(r.RESVE_OPTION_ID AS INT64) = acm.option_reservation_id
LEFT JOIN {{ source('package_solution', 'mypack_package_component_reservation') }} AS pcr
  ON r.RESVE_OPTION_ID = CAST(pcr.option_reservation_id AS STRING)
 AND pcr.deleted_at IS NULL
LEFT JOIN {{ source('package_solution', 'mypack_component_product_daily_stock_price') }} AS sp
  ON pcr.component_product_daily_stock_price_id = sp.id
 AND sp.deleted_at IS NULL
WHERE r.RESVE_TYPE <> 'ORIGIN'
