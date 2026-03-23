{{ config(
    materialized='view',
    schema='edw_intermediate'
) }}

/*
  [INT_FPNA_RSV_CANCEL] 예약별 취소 정보
  - MART_SALE_D에서 KIND=2(취소행)인 건의 취소일자, 취소 GMV를 추출
  - Grain: RESVE_ID (예약당 1행)
*/

SELECT
    RESVE_ID                                                                                 AS RESVE_ID
  , DATE(CANCEL_KST_DT)                                                                     AS CANCEL_DATE
  , SALES_KRW_PRICE                                                                          AS CANCEL_GMV
FROM {{ ref('MART_SALE_D') }}
WHERE KIND = 2
