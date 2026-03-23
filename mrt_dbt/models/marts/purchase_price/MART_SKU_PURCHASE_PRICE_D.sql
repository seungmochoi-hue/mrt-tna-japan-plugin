{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_SKU_PURCHASE_PRICE_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        enabled=false

    )
}}



SELECT CAST('{{ var("before_hour_33") }}' AS DATE) AS BASIS_DATE
     ,  T.SKU_ID AS SKU_ID
     ,  SUM(T.TICKET_AMOUNT) AS TOTAL_TICKET_AMOUNT
     ,  SUM(ABS(T.TICKET_AMOUNT) * T.STOCK_UNIT_PRICE) AS STOCK_TOTAL_PRICE
     ,  ROUND(CASE WHEN SUM(T.TICKET_AMOUNT) <> 0 THEN SUM(ABS(T.TICKET_AMOUNT) * T.STOCK_UNIT_PRICE) / SUM(T.TICKET_AMOUNT) ELSE 0 END, 2) AS AVG_TICKET_UNIT_PRICE
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT P.SKU_ID
              ,  P.TICKET_AMOUNT AS TICKET_AMOUNT
              ,  P.STOCK_UNIT_PRICE AS STOCK_UNIT_PRICE
         FROM {{ ref('MART_SKU_STOCK_HISTORY_D') }} P
         WHERE P.SNP_DATE = '{{ var("logical_start_date_kst") }}'

         UNION ALL

         SELECT C.SKU_ID
              , C.TICKET_AMOUNT AS TICKET_AMOUNT
              , C.STOCK_UNIT_PRICE AS STOCK_UNIT_PRICE
         FROM {{ ref('MART_SKU_STOCK_CANCEL_HISTORY_D') }} C
         WHERE C.BASIS_DATE <= '{{ var("logical_start_date_kst") }}'
           AND C.SKU_ID IS NOT NULL
     ) T
GROUP BY SKU_ID