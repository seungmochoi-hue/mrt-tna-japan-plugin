{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_CONFIRMATION_CLOSING_D',
        partition_by={"field": "BASIS_DATE", "data_type": "date"},
        cluster_by=["PARTNER_ID", "GID", "PRODUCT_NO", "RESERVATION_NO"]
    )
}}

/*
  [매출관리팀] NONAIR 정산 확정일 기준 (옵션/상품 단위)
  - 기준일: confirmation_product_closing.confirmation_date (BASIS_DATE, 정산 확정일)
    주의: 예약 시스템의 확정일(orders.reservations.confirmed_at)과 다름.
    정산 시스템에서 해당 건을 확정 처리한 날짜이며, 예약 확정일보다 늦을 수 있음.
  - CGMV = SUM(ORDER_PRICE) — ORDER_PRICE에 부호 포함 (결제 양수, 환불 음수)
  - 매출 = SUM(SALE_COMMISSION) (VAT 포함)
*/

{% set date_start = var('date_start', '2023-01-01') %}
{% set date_end = var('date_end', '2999-12-31') %}
{% set settlement_type = var('settlement_type', 'all') %}
{% set partner_id = var('partner_id', 'all') %}
{% set gid = var('gid', 0) | int %}
{% set product_no = var('product_no', 'all') %}
{% set reservation_no = var('reservation_no', 'all') %}

SELECT
    cp.confirmation_date AS BASIS_DATE
    , CASE
        WHEN pc.settlement_type = 'INTERNAL' THEN '내부정산'
        ELSE '외부정산'
      END AS SETTLEMENT_TYPE
    , dc.order_no AS ORDER_NO
    , pc.reservation_no AS RESERVATION_NO
    , pc.claim_id AS CLAIM_ID
    , CASE
        WHEN pc.closing_type = 'PAYMENT' THEN '결제'
        WHEN pc.closing_type = 'PAYMENT_OF_REFUND' THEN '결제'
        WHEN pc.closing_type = 'REFUND' THEN '전체환불'
        WHEN pc.closing_type = 'PARTIAL_REFUND' THEN '부분환불'
        WHEN pc.closing_type = 'PARTIAL_REFUND_AFTER_FINISH' THEN '여행종료 후 부분환불'
        WHEN pc.closing_type = 'PARTNER_DEDUCTION' THEN '파트너 공제'
        ELSE '여행자 보상'
      END AS ORDER_TYPE
    , pc.partner_id AS PARTNER_ID
    , p.partner_name AS PARTNER_NAME
    , pc.union_product_id AS GID
    , pc.product_no AS PRODUCT_NO
    , pc.product_title AS PRODUCT_TITLE
    , pc.option_id AS OPTION_ID
    , orv.option_title AS OPTION_TITLE
    , rv.merchant_uid AS MERCHANT_UID
    , rv.trip_started_at AS TRIP_STARTED_AT
    , rv.trip_ended_at AS TRIP_ENDED_AT
    , rv.settlement_criteria_type AS SETTLEMENT_CRITERIA_TYPE
    , pc.quantity AS QUANTITY
    , pc.sale_price AS SALE_PRICE
    , pc.order_price AS ORDER_PRICE
    , pc.sale_type AS SALE_TYPE
    , pc.commission_condition_type AS COMMISSION_CONDITION_TYPE
    , pc.sale_commission_rate AS SALE_COMMISSION_RATE
    , pc.sale_commission AS SALE_COMMISSION
    , pc.etc_commission AS ETC_COMMISSION
    , pc.total_coupon_discount_amount AS TOTAL_COUPON_DISCOUNT_AMOUNT
    , pc.mrt_coupon_discount_amount AS MRT_COUPON_DISCOUNT_AMOUNT
    , pc.partner_coupon_discount_amount AS PARTNER_COUPON_DISCOUNT_AMOUNT
    , pc.instant_discount_amount AS INSTANT_DISCOUNT_AMOUNT
    , pc.mrt_instant_discount_amount AS MRT_INSTANT_DISCOUNT_AMOUNT
    , (COALESCE(pc.margin_discount_amount, 0) + COALESCE(pc.corp_partnership_discount_amount, 0)) AS MARGIN_DISCOUNT_AMOUNT
    , pc.affiliate_instant_discount_amount AS AFFILIATE_INSTANT_DISCOUNT_AMOUNT
    , pc.mrt_cancel_commission AS MRT_CANCEL_COMMISSION
    , pc.partner_cancel_commission AS PARTNER_CANCEL_COMMISSION
    , pc.mrt_traveler_compensation AS MRT_TRAVELER_COMPENSATION
    , pc.partner_traveler_compensation AS PARTNER_TRAVELER_COMPENSATION
    , pc.payment_amount AS PAYMENT_AMOUNT
    , pc.free_point_amount AS FREE_POINT_AMOUNT
    , pc.pg_amount AS PG_AMOUNT
    , pc.supply_price AS SUPPLY_PRICE
    , pc.mrt_sales_channel_commission AS MRT_SALES_CHANNEL_COMMISSION
    , pc.partner_sales_channel_commission AS PARTNER_SALES_CHANNEL_COMMISSION
    , pc.partnership_commission AS PARTNERSHIP_COMMISSION
    , pc.marketing_partnership_commission AS MARKETING_PARTNERSHIP_COMMISSION
    , rv.order_id AS ORDER_ID
    , rv.user_id AS USER_ID
    , rv.status AS RESERVATION_STATUS
    , rv.canceled_at AS CANCELED_AT
    , CASE
        WHEN cs.commission_settlement_type = 'CASHBACK' THEN pc.order_price
          + pc.partner_cancel_commission
          + pc.mrt_cancel_commission
          - pc.partner_traveler_compensation
          - pc.partner_coupon_discount_amount
        ELSE pc.order_price
          - pc.sale_commission
          + pc.partner_cancel_commission
          - pc.partner_traveler_compensation
          - pc.partner_coupon_discount_amount
      END AS PARTNER_SETTLE_AMOUNT
    , CASE
        WHEN pc.closing_type IN ('PAYMENT', 'PAYMENT_OF_REFUND') THEN rv.settled_at
        WHEN pc.closing_type IN ('TRAVELER_COMPENSATION', 'PARTNER_DEDUCTION') THEN TIMESTAMP(pc.payment_date)
        ELSE rr.refund_settled_at
      END AS EXPECTED_SALES_AT
FROM {{ source('settles', 'confirmation_product_closing') }} cp
INNER JOIN {{ source('settles', 'payment_product_closing') }} pc
    ON pc.id = cp.payment_product_closing_id
INNER JOIN {{ source('settles', 'payment_daily_closing') }} dc
    ON pc.payment_daily_closing_id = dc.id
INNER JOIN {{ source('settles', 'reservations_v2') }} rv
    ON pc.reservation_id = rv.id
INNER JOIN {{ source('orders', 'option_reservations') }} orv
    ON orv.id = pc.option_reservation_id
INNER JOIN {{ source('settles', 'settlements_partners') }} p
    ON p.id = pc.partner_snapshot_id
LEFT OUTER JOIN {{ source('settles', 'reservation_refunds_v2') }} rr
    ON rr.id = pc.reservation_refund_id
INNER JOIN {{ source('settles', 'partner_settlement_config_snapshots') }} cs
    ON pc.partner_settlement_config_snapshot_id = cs.id
WHERE cp.deleted_at IS NULL
  AND cp.confirmation_date BETWEEN DATE('{{ date_start }}') AND DATE('{{ date_end }}')
  AND ('{{ settlement_type }}' = 'all' OR pc.settlement_type = '{{ settlement_type }}')
  AND ('{{ partner_id }}' = 'all' OR pc.partner_id = '{{ partner_id }}')
  AND ({{ gid }} = 0 OR pc.union_product_id = {{ gid }})
  AND ('{{ product_no }}' = 'all' OR pc.product_no = '{{ product_no }}')
  AND ('{{ reservation_no }}' = 'all' OR pc.reservation_no = '{{ reservation_no }}')

