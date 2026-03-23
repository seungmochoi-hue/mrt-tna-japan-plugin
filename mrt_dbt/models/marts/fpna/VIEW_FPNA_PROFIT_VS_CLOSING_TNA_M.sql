{{
    config(
        materialized='view',
        schema='edw_fpna',
        alias='VIEW_FPNA_PROFIT_VS_CLOSING_TNA_M',
        tags=[ 'MART', 'FPNA', 'VIEW' ]
    )
}}

/*
  T&A 월별 CGMV/Revenue를 FPNA(Profit) vs 매관(Closing) 기준으로 나란히 비교한다.
  그레인: 월 x 파트너 x 정산타입

  원천:
  - Profit: MART_FPNA_NONAIR_PROFIT_M (FPNA_TYPE_LV_1 = 'T&A')
  - Closing: MART_FPNA_CONFIRMATION_CLOSING_D (전체 NONAIR, vertical 컬럼 없음)

  주요 로직:
  - Profit 환불 이벤트월: REFUND_MONTH(매관 확정일 기준) 사용
  - Closing 이벤트월: 결제/환불 모두 확정일(BASIS_DATE) 기준
  - 양쪽 모두 매관 확정일 기준이므로 환불 월 배정 차이 최소화
  - CGMV 구성: ORDER_PRICE 대신 구성요소 합산 (여행종료 후 부분환불 대응)
  - Closing Revenue: SALE_COMMISSION + MRT_CANCEL_COMMISSION (매관 기준)
  - Profit Revenue: CONFIRM은 SHEET_SOURCE REVENUE(VAT 포함), CANCEL은 REFUND_REVENUE(VAT 포함) 사용
*/

WITH PROFIT_SOURCE AS (
    SELECT
        s.CONFIRM_MONTH       AS CONFIRM_MONTH
      , s.REFUND_MONTH        AS REFUND_MONTH
      , s.PARTNER_ID          AS PARTNER_ID
      , CASE
            WHEN LOWER(s.PARTNER_SETTLE_TYPE) LIKE '%internal%' THEN 'internal'
            WHEN LOWER(s.PARTNER_SETTLE_TYPE) LIKE '%external%' THEN 'external'
            ELSE 'unknown'
        END                   AS SETTLE_TYPE_KEY
      , s.GMV                 AS GMV
      , s.REFUND_GMV          AS REFUND_GMV
      , s.REVENUE             AS REVENUE_INC_VAT
      , s.REFUND_REVENUE      AS REFUND_REVENUE_INC_VAT
      , s.ORDER_CNT           AS ORDER_CNT
      , s.C_ORDER_CNT         AS C_ORDER_CNT
    FROM {{ ref('MART_FPNA_NONAIR_PROFIT_M') }} s
    WHERE s.FPNA_TYPE_LV_1 = 'T&A'
)
, PROFIT_EVENT AS (
    SELECT
        s.CONFIRM_MONTH                              AS EVENT_MONTH
      , s.PARTNER_ID                                 AS PARTNER_ID
      , s.SETTLE_TYPE_KEY                            AS SETTLE_TYPE_KEY
      , 'CONFIRM'                                    AS EVENT_TYPE
      , s.GMV                                        AS CGMV
      , s.REVENUE_INC_VAT                             AS REVENUE_INC_VAT          -- SHEET_SOURCE에서 * 1.1 적용 완료 (VAT 포함)
      , CAST(NULL AS FLOAT64)                        AS REFUND_REVENUE_INC_VAT
      , s.C_ORDER_CNT                                AS ORDER_CNT
    FROM PROFIT_SOURCE s
    WHERE s.CONFIRM_MONTH IS NOT NULL

    UNION ALL

    SELECT
        s.REFUND_MONTH                               AS EVENT_MONTH
      , s.PARTNER_ID                                 AS PARTNER_ID
      , s.SETTLE_TYPE_KEY                            AS SETTLE_TYPE_KEY
      , 'CANCEL'                                     AS EVENT_TYPE
      , s.REFUND_GMV                                 AS CGMV
      , CAST(NULL AS FLOAT64)                        AS REVENUE_INC_VAT
      , s.REFUND_REVENUE_INC_VAT                     AS REFUND_REVENUE_INC_VAT
      , s.ORDER_CNT                                  AS ORDER_CNT
    FROM PROFIT_SOURCE s
    WHERE s.REFUND_MONTH IS NOT NULL
      AND s.CONFIRM_MONTH IS NOT NULL
)
, PROFIT_AGG AS (
    SELECT
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
      , SUM(CASE WHEN EVENT_TYPE = 'CONFIRM' THEN CGMV ELSE 0 END) AS PROFIT_CONFIRM_CGMV
      , SUM(CASE WHEN EVENT_TYPE = 'CANCEL'  THEN CGMV ELSE 0 END) AS PROFIT_CANCEL_CGMV
      , SUM(CGMV) AS PROFIT_NET_CGMV
      -- Revenue: SHEET_SOURCE에서 이미 VAT 포함 (*1.1 적용 완료)
      , SUM(CASE WHEN EVENT_TYPE = 'CONFIRM' THEN REVENUE_INC_VAT ELSE 0 END)
          AS PROFIT_CONFIRM_REVENUE_INC_VAT
      , SUM(CASE WHEN EVENT_TYPE = 'CANCEL' THEN REFUND_REVENUE_INC_VAT ELSE 0 END)
          AS PROFIT_CANCEL_REVENUE_INC_VAT
      , SUM(CASE WHEN EVENT_TYPE = 'CONFIRM' THEN REVENUE_INC_VAT ELSE 0 END)
          + SUM(CASE WHEN EVENT_TYPE = 'CANCEL' THEN REFUND_REVENUE_INC_VAT ELSE 0 END)
          AS PROFIT_NET_REVENUE_INC_VAT
      , SUM(CASE WHEN EVENT_TYPE = 'CONFIRM' THEN ORDER_CNT ELSE 0 END) AS PROFIT_CONFIRM_ORDER_CNT
      , SUM(CASE WHEN EVENT_TYPE = 'CANCEL'  THEN ORDER_CNT ELSE 0 END) AS PROFIT_CANCEL_ORDER_CNT
      , SUM(ORDER_CNT) AS PROFIT_NET_ORDER_CNT
    FROM PROFIT_EVENT
    GROUP BY
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
)
, CLOSING_EVENT AS (
    SELECT
        DATE_TRUNC(c.BASIS_DATE, MONTH)        AS EVENT_MONTH
      , c.PARTNER_ID                           AS PARTNER_ID
      , CASE
            WHEN c.SETTLEMENT_TYPE = '내부정산' THEN 'internal'
            ELSE 'external'
        END                                    AS SETTLE_TYPE_KEY
      , 'PAYMENT'                              AS EVENT_TYPE
      , c.ORDER_NO                             AS ORDER_NO
      -- CGMV: ORDER_PRICE 대신 구성요소 합산 (여행종료 후 부분환불 대응)
      , c.MRT_COUPON_DISCOUNT_AMOUNT
          + c.PARTNER_COUPON_DISCOUNT_AMOUNT
          + c.MRT_INSTANT_DISCOUNT_AMOUNT
          + c.MARGIN_DISCOUNT_AMOUNT
          + c.AFFILIATE_INSTANT_DISCOUNT_AMOUNT
          + c.FREE_POINT_AMOUNT
          + c.PG_AMOUNT                        AS CGMV
      , c.SALE_COMMISSION
          + c.MRT_CANCEL_COMMISSION               AS REVENUE_INC_VAT   -- 매관 기준: 판매수수료 + 취소수수료
      , c.SALE_TYPE                               AS SALE_TYPE          -- 판매유형: TOTAL=사입, COMMISSION=위탁
    FROM {{ ref('MART_FPNA_CONFIRMATION_CLOSING_D') }} c
    WHERE c.ORDER_TYPE = '결제'

    UNION ALL

    -- REFUND 이벤트월: 결제와 동일하게 확정일(BASIS_DATE) 기준
    SELECT
        DATE_TRUNC(c.BASIS_DATE, MONTH)        AS EVENT_MONTH
      , c.PARTNER_ID                           AS PARTNER_ID
      , CASE
            WHEN c.SETTLEMENT_TYPE = '내부정산' THEN 'internal'
            ELSE 'external'
        END                                    AS SETTLE_TYPE_KEY
      , 'REFUND'                               AS EVENT_TYPE
      , c.ORDER_NO                             AS ORDER_NO
      -- CGMV: ORDER_PRICE 대신 구성요소 합산 (여행종료 후 부분환불 대응)
      , c.MRT_COUPON_DISCOUNT_AMOUNT
          + c.PARTNER_COUPON_DISCOUNT_AMOUNT
          + c.MRT_INSTANT_DISCOUNT_AMOUNT
          + c.MARGIN_DISCOUNT_AMOUNT
          + c.AFFILIATE_INSTANT_DISCOUNT_AMOUNT
          + c.FREE_POINT_AMOUNT
          + c.PG_AMOUNT                        AS CGMV
      , c.SALE_COMMISSION
          + c.MRT_CANCEL_COMMISSION               AS REVENUE_INC_VAT   -- 매관 기준: 판매수수료 + 취소수수료
      , c.SALE_TYPE                               AS SALE_TYPE          -- 판매유형: TOTAL=사입, COMMISSION=위탁
    FROM {{ ref('MART_FPNA_CONFIRMATION_CLOSING_D') }} c
    WHERE c.ORDER_TYPE IN ('전체환불', '부분환불', '여행종료 후 부분환불')
)
, CLOSING_AGG AS (
    SELECT
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
      , SUM(CASE WHEN EVENT_TYPE = 'PAYMENT' THEN CGMV ELSE 0 END) AS CLOSING_PAYMENT_CGMV
      , SUM(CASE WHEN EVENT_TYPE = 'REFUND'  THEN CGMV ELSE 0 END) AS CLOSING_REFUND_CGMV
      , SUM(CGMV) AS CLOSING_NET_CGMV
      , SUM(CASE WHEN EVENT_TYPE = 'PAYMENT' THEN REVENUE_INC_VAT ELSE 0 END) AS CLOSING_PAYMENT_REVENUE_INC_VAT
      , SUM(CASE WHEN EVENT_TYPE = 'REFUND'  THEN REVENUE_INC_VAT ELSE 0 END) AS CLOSING_REFUND_REVENUE_INC_VAT
      , SUM(REVENUE_INC_VAT) AS CLOSING_NET_REVENUE_INC_VAT
      , COUNT(DISTINCT CASE WHEN EVENT_TYPE = 'PAYMENT' THEN ORDER_NO ELSE NULL END) AS CLOSING_PAYMENT_ORDER_CNT
      , COUNT(DISTINCT CASE WHEN EVENT_TYPE = 'REFUND'  THEN ORDER_NO ELSE NULL END) AS CLOSING_REFUND_ORDER_CNT
      , COUNT(DISTINCT ORDER_NO) AS CLOSING_NET_ORDER_CNT
      , MAX(SALE_TYPE)           AS CLOSING_SALE_TYPE  -- 파트너 단위 판매유형 (TOTAL/COMMISSION)
    FROM CLOSING_EVENT
    WHERE EVENT_MONTH IS NOT NULL
    GROUP BY
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
)
, KEYS AS (
    SELECT
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
    FROM PROFIT_AGG
    UNION DISTINCT
    SELECT
        EVENT_MONTH
      , PARTNER_ID
      , SETTLE_TYPE_KEY
    FROM CLOSING_AGG
)
SELECT
    k.EVENT_MONTH                            AS EVENT_MONTH
  , k.PARTNER_ID                             AS PARTNER_ID
  , k.SETTLE_TYPE_KEY                        AS SETTLE_TYPE_KEY

  , p.PROFIT_CONFIRM_CGMV                    AS PROFIT_CONFIRM_CGMV
  , p.PROFIT_CANCEL_CGMV                     AS PROFIT_CANCEL_CGMV
  , p.PROFIT_NET_CGMV                        AS PROFIT_NET_CGMV

  , p.PROFIT_CONFIRM_REVENUE_INC_VAT         AS PROFIT_CONFIRM_REVENUE_INC_VAT
  , p.PROFIT_CANCEL_REVENUE_INC_VAT          AS PROFIT_CANCEL_REVENUE_INC_VAT
  , p.PROFIT_NET_REVENUE_INC_VAT             AS PROFIT_NET_REVENUE_INC_VAT

  , c.CLOSING_PAYMENT_CGMV                   AS CLOSING_PAYMENT_CGMV
  , c.CLOSING_REFUND_CGMV                    AS CLOSING_REFUND_CGMV
  , c.CLOSING_NET_CGMV                       AS CLOSING_NET_CGMV

  , c.CLOSING_PAYMENT_REVENUE_INC_VAT        AS CLOSING_PAYMENT_REVENUE_INC_VAT
  , c.CLOSING_REFUND_REVENUE_INC_VAT         AS CLOSING_REFUND_REVENUE_INC_VAT
  , c.CLOSING_NET_REVENUE_INC_VAT            AS CLOSING_NET_REVENUE_INC_VAT

  , p.PROFIT_CONFIRM_ORDER_CNT               AS PROFIT_CONFIRM_ORDER_CNT
  , p.PROFIT_CANCEL_ORDER_CNT                AS PROFIT_CANCEL_ORDER_CNT
  , p.PROFIT_NET_ORDER_CNT                   AS PROFIT_NET_ORDER_CNT

  , c.CLOSING_PAYMENT_ORDER_CNT              AS CLOSING_PAYMENT_ORDER_CNT
  , c.CLOSING_REFUND_ORDER_CNT               AS CLOSING_REFUND_ORDER_CNT
  , c.CLOSING_NET_ORDER_CNT                  AS CLOSING_NET_ORDER_CNT

  , c.CLOSING_SALE_TYPE                      AS CLOSING_SALE_TYPE
FROM KEYS k
LEFT JOIN PROFIT_AGG p
    USING (EVENT_MONTH, PARTNER_ID, SETTLE_TYPE_KEY)
LEFT JOIN CLOSING_AGG c
    USING (EVENT_MONTH, PARTNER_ID, SETTLE_TYPE_KEY)
WHERE k.EVENT_MONTH >= DATE_TRUNC(DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 3 YEAR), YEAR)
