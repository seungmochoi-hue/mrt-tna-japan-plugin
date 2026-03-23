{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_ETC_ADJUSTMENT_D',
        tags=[ 'MART', 'FPNA', 'SHEET' ]
    )
}}

/* [시트 원천] FPNA 기타조정 수수료(원화) 상세.
   FP&A 팀이 파트너/일자 기준으로 REVENUE 후처리 합산할 수 있도록 최소 컬럼만 제공한다. */

SELECT
    E.adjustment_date AS ADJUSTMENT_DATE
  , E.id AS ADJUSTMENT_ID
  , E.partner_id AS PARTNER_ID
  , E.ups_id AS GID
  , E.product_title AS PRODUCT_TITLE
  , E.adjustment_commission AS ADJUSTMENT_COMMISSION_KRW
FROM {{ source('settles', 'etc_adjustments') }} E
WHERE E.deleted_at IS NULL
  AND COALESCE(E.adjustment_commission, 0) != 0
