{{ config(
    materialized='view',
    schema='edw_intermediate'
) }}

/*
  [INT_FPNA_AGENCY_COMMISSION] 예약별 제휴여행사/마케팅 파트너 수수료
  - payment_product_closing에서 예약 단위로 partnership_commission, marketing_partnership_commission을 합산
  - 삭제(deleted_at IS NOT NULL) 건 제외
  - Grain: RESVE_ID (예약당 1행)
*/

SELECT
    c.RESERVATION_NO                                                                         AS RESVE_ID
  , SUM(IFNULL(c.PARTNERSHIP_COMMISSION, 0))                                                 AS PARTNERSHIP_COMMISSION
  , SUM(IFNULL(c.MARKETING_PARTNERSHIP_COMMISSION, 0))                                       AS MARKETING_PARTNERSHIP_COMMISSION
FROM {{ source('settles', 'payment_product_closing') }} c
WHERE c.DELETED_AT IS NULL
GROUP BY c.RESERVATION_NO
