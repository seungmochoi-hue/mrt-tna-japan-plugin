{{
    config(
        materialized = 'incremental',
        schema='edw_mart',
        alias='MART_STOCK_ROW_SNP',
        pre_hook=[
            "DELETE FROM {{ this }} A WHERE A.BASIS_DATE = CAST('{{ var('logical_start_date_kst') }}' AS DATE)"
        ]
    )
}}

SELECT  CAST('{{ var("logical_start_date_kst") }}' AS DATE) AS BASIS_DATE
     ,  r.id AS RECORD_ID
     ,  CAST(op.offer_id AS STRING) AS PRODUCT_ID
     ,  CAST(r.offer_price_id AS STRING) AS OPTION_ID
     ,  op.title AS OPTION_NM
     ,  CASE WHEN r.deleted_at IS NOT NULL THEN 'delete' ELSE r.status END AS RECORD_RECENT_STATUS
     ,  rg.voucher_type AS VOUCHER_TYPE
     ,  IFNULL(rg.unit_price_amount, 0) AS STOCK_UNIT_PRICE
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('mrt_20_stream', 'bulk_invoice_file_records') }} r
LEFT JOIN {{ source('mrt_20_stream', 'offer_prices') }} op ON op.deleted_at IS NULL AND op.id = r.offer_price_id
LEFT JOIN {{ source('mrt_20_stream', 'bulk_invoice_record_groups') }} rg ON r.record_group_id = rg.id
WHERE op.id IS NOT NULL
  AND r.status IS NOT NULL
