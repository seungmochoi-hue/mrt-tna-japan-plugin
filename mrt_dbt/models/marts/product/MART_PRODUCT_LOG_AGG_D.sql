{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_PRODUCT_LOG_AGG_D',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by = ['GID']
    )
}}




SELECT L.BASIS_DT
     , L.GID
     , SUM(L.OFFER_IMPRESSION_CNT) AS OFFER_IMPRESSION_CNT
     , SUM(L.OFFER_CLICK_CNT) AS OFFER_CLICK_CNT
     , SUM(L.OFFER_DETAIL_UV) AS OFFER_DETAIL_UV
     , SUM(L.CHECKOUT_UV) AS CHECKOUT_UV
     , SUM(L.CHECKOUT_COMPLETE_UV) AS CHECKOUT_COMPLETE_UV
FROM {{ ref('MART_PRODUCT_LOG_D') }} L
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON L.GID = TP.GID
WHERE L.basis_dt = '{{ var("logical_start_date_kst") }}'
  AND TP.GID IS NULL
GROUP BY L.BASIS_DT, L.GID