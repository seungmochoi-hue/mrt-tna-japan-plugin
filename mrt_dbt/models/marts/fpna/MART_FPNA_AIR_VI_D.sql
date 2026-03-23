{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_AIR_VI_D'
    )
}}


SELECT a.PNR_NO
     , CASE WHEN vi.historical_vi_rate IS NOT NULL AND a.basis_date >= DATE(a.depart_kst_dt) THEN vi.HISTORICAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
            WHEN vi.historical_vi_rate IS NULL AND a.basis_date >= DATE(a.depart_kst_dt) THEN vi.ESTIMATED_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
            WHEN vi_est.historical_vi_rate IS NOT NULL AND a.basis_date < DATE(a.depart_kst_dt) THEN vi_est.HISTORICAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
            WHEN vi_est.historical_vi_rate IS NULL AND a.basis_date < DATE(a.depart_kst_dt) THEN vi_est.ESTIMATED_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE END AS VI_COMMISSION_PRICE
     , CASE WHEN DOMESTIC_INTERNATIONAL_DIV_CD <> 'I' THEN NULL
            WHEN gds.historical_vi_rate IS NOT NULL THEN gds.HISTORICAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
            WHEN gds.historical_vi_rate IS NULL THEN gds.ESTIMATED_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE END AS GDS_COMMISSION_PRICE
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('MART_AIR_PNR_SALE_D') }} a
LEFT JOIN {{ ref('fpna_external_commission_flight_vi') }} vi ON vi.travel_date = DATE_TRUNC(DATE(a.DEPART_KST_DT), MONTH)
  AND a.STOCK_AIRLINE_CD = vi.STOCK_AIRLINE_CD
  AND vi.DI_FLAG = a.DOMESTIC_INTERNATIONAL_DIV_CD
LEFT JOIN {{ ref('fpna_external_commission_flight_vi') }} vi_est ON vi_est.travel_date = DATE_TRUNC(DATE(a.BASIS_DATE), MONTH)
  AND a.STOCK_AIRLINE_CD = vi_est.STOCK_AIRLINE_CD
  AND vi_est.DI_FLAG = a.DOMESTIC_INTERNATIONAL_DIV_CD
LEFT JOIN {{ ref('fpna_external_commission_flight_gds_vi') }} gds ON gds.basis_date = DATE_TRUNC(DATE(a.basis_date), MONTH)
WHERE a.kind = 1