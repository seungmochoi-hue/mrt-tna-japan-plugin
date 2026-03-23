{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_SKU_STOCK_CANCEL_HISTORY_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        enabled=false
    )
}}


SELECT t.BASIS_DATE AS BASIS_DATE
     , t.SKU_ID AS SKU_ID
     , CASE WHEN t.TYPE = 'Return' THEN ABS(t.TICKET_AMOUNT)
            WHEN t.TYPE = 'Expiration' THEN ABS(t.TICKET_AMOUNT) * -1
            WHEN t.TYPE = 'Retrieved' THEN ABS(t.TICKET_AMOUNT) * -1
            ELSE t.TICKET_AMOUNT END AS TICKET_AMOUNT
     , CASE WHEN t.TYPE = 'Return' THEN ABS(t.UNIT_PRICE)
            WHEN t.TYPE = 'Expiration' THEN ABS(t.UNIT_PRICE) * -1
            WHEN t.TYPE = 'Retrieved' THEN ABS(t.UNIT_PRICE) * -1
            ELSE t.UNIT_PRICE END AS STOCK_UNIT_PRICE
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('FPNA_COMMERCE_ETC') }} t
WHERE t.BASIS_DATE > '2023-03-31'
  AND t.BASIS_DATE = '{{ var("logical_start_date_kst") }}'
  AND t.TICKET_AMOUNT <> 0 AND t.UNIT_PRICE <> 0
  AND t.sku_id IS NOT NULL