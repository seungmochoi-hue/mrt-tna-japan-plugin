{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_ETC_ADJUSTMENT_M',
        tags=[ 'MART', 'FPNA', 'SHEET' ]
    )
}}

/* [시트 원천] FPNA 기타조정 수수료(원화) 월 집계.
   파트너별 월 단위 합산값을 제공해 Revenue 후처리 월마감을 단순화한다. */

SELECT
    DATE_TRUNC(ADJUSTMENT_DATE, MONTH) AS BASIS_MONTH
  , PARTNER_ID
  , SUM(ADJUSTMENT_COMMISSION_KRW) AS ADJUSTMENT_COMMISSION_KRW
  , COUNT(*) AS ADJUSTMENT_ROW_COUNT
FROM {{ ref('MART_FPNA_ETC_ADJUSTMENT_D') }}
GROUP BY 1, 2
