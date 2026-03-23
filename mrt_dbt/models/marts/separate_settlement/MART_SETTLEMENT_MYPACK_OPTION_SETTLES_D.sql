{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_SETTLEMENT_MYPACK_OPTION_SETTLES_D'
    )
}}


WITH WITH_CONFIRMATION_CLOSING AS
         (SELECT cps.*
          FROM {{ source('settles', 'confirmation_product_closing') }} cps
                   JOIN {{ source('settles', 'reservations_v2') }} r ON r.version = 2 AND r.system_provider = 'PKG' AND r.id = cps.reservation_id
          WHERE r.deleted_at IS NULL)

SELECT DISTINCT  mypack_ppc.payment_date                                      AS BASIS_DATE, -- 결제일/매출일
                  '결제일'                                                        AS TYPE,-- `조회 기준`
                  '마이팩예약'                                                      AS VIEW_TYPE, -- 조회 구분
                  IF(mypack_ppc.option_type LIKE '%FLIGHT%', '항공', '숙소 혹은 그외') AS OPTION_TYPE, -- `구성상품 유형`
                  mypack_ppc.closing_type                                      AS CLOSING_TYPE_CD, -- `마감유형`,
                  mypack_pdc.order_id                                          AS ORDER_ID, --`주문ID`,
                  CAST(mypack_pdc.order_no AS INT64)                                          AS ORDER_NO, -- `주문번호`,
                  mypack_pdc.order_group_no                                    AS ORDER_GROUP_NO, -- `이벤트넘버`,
                  mypack_pdc.partner_id                                        AS MYPACK_PARTNER_ID, --`마이팩 파트너 ID`,
                  mypack_ppc.partner_id                                        AS PARTNER_ID, --`원예약 파트너 ID`,
                  mypack_ppc.union_product_id                                  AS GID, -- `GID`,
                  mypack_ppc.reservation_id                                    AS MYPACK_RESERVATION_ID, -- `마이팩예약ID`,
                  mypack_ppc.reservation_no                                    AS MYPACK_RESERVATION_NO, -- `마이팩예약NO`,
                  mypack_ppc.option_reservation_id                             AS MYPACK_OPTION_RESERVATION_ID, --`마이팩옵션예약ID`,
                  mypack_ppc.reservation_id                                    AS RESERVATION_ID, --`예약ID`,
                  mypack_ppc.reservation_no                                    AS RESERVATION_NO, --`예약NO`,
                  mypack_ppc.reservation_refund_id                             AS RESERVATION_REFUND_ID, --`예약환불ID`,
                  mypack_ppc.option_reservation_id                             AS OPTION_RESERVATION_ID, --`옵션ID`,
                  mypack_ppc.option_reservation_refund_id                      AS OPTION_RESERVATION_REFUND_ID, --`옵션환불 ID`,
                  CAST(NULL AS STRING)                                         AS ORIGINAL_RESERVATION_STATUS, --`원예약 상태`,
                  mypack_ppc.option_id                                         AS OPTION_ID, --`상품의옵션ID`,
                  mypack_ppc.product_title                                     AS PRODUCT_TITLE, --`상품명`,
                  mypack_ppc.settlement_type                                   AS SETTLEMENT_TYPE, --`별도 내부정산`,
                  sale_type                                                    AS SALE_TYPE, --`매출타입`,
                  mypack_ppc.system_provider                                   AS SYSTEM_PROVIDER, --`버티컬`,
                  pscs.accounting_project_code                                 AS ACCOUNTING_PROJECT_CD, --`회계프로젝트코드`,
                  r.status                                                     AS STATUS, --`여행상태값`,
                  mypack_ppc.sale_price                                        AS SALE_PRICE, --`판매금액`,
                  mypack_ppc.supply_price                                      AS SUPPLY_PRICE, --`공급가`,
                  mypack_ppc.product_price                                     AS PRODUCT_PRICE, --`주문금액 상품가`,
                  mypack_ppc.pg_amount                                         AS PG_AMOUNT, --`pg결제금액`,
                  mypack_ppc.affiliate_instant_discount_amount                 AS AFFILIATE_INSTANT_DISCOUNT_AMOUNT, --`즉시할인_카드사`,
                  mypack_ppc.mrt_instant_discount_amount                       AS MRT_INSTANT_DISCOUNT_AMOUNT, --`즉시할인_마리트`,
                  mypack_ppc.mrt_coupon_discount_amount                        AS MRT_COUPON_DISCOUNT_AMOUNT, --`마리트 부담쿠폰`,
                  mypack_ppc.partner_coupon_discount_amount                    AS PARTNER_COUPON_DISCOUNT_AMOUNT, --`파트너 부담쿠폰`,
                  0                                                            AS PAID_POINT_PAYMENT_PRICE, --`유료포인트결제금액 현재없음`,
                  mypack_ppc.free_point_amount                                 AS FREE_POINT_AMOUNT, --`무료포인트결제금액`,
                  mypack_ppc.sale_commission_rate                              AS SALE_COMMISSION_RATE, --`수수료율`,
                  mypack_ppc.sale_commission                                   AS SALE_COMMISSION, --`판매수수료`,
                  mypack_ppc.mrt_cancel_commission                             AS MRT_CANCEL_COMMISSION, --`마리트취소수수료`,
                  CASE
                      WHEN mypack_ppc.option_type LIKE '%FLIGHT%' THEN mypack_ppc.partner_cancel_commission
                      ELSE mypack_ppc.partner_cancel_commission
                      END                                                      AS PARTNER_CANCEL_COMMISSION, --`파트너취소수수료`,
                  CASE
                      WHEN mypack_ppc.option_type LIKE '%FLIGHT%' THEN
                          (CASE
                               WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                                   mypack_ppc.product_price - mypack_ppc.sale_commission -
                                   mypack_ppc.partner_sales_channel_commission -
                                   mypack_ppc.partner_coupon_discount_amount + mypack_ppc.partner_cancel_commission)
                               WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                                   mypack_ppc.product_price + mypack_ppc.partner_cancel_commission +
                                   mypack_ppc.mrt_cancel_commission -
                                   mypack_ppc.partner_coupon_discount_amount)
                               ELSE 0 END)
                      ELSE
                          (CASE
                               WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                                   mypack_ppc.product_price - mypack_ppc.sale_commission -
                                   mypack_ppc.partner_sales_channel_commission -
                                   mypack_ppc.partner_coupon_discount_amount + mypack_ppc.partner_cancel_commission)
                               WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                                   mypack_ppc.product_price + mypack_ppc.partner_cancel_commission +
                                   mypack_ppc.mrt_cancel_commission -
                                   mypack_ppc.partner_coupon_discount_amount)
                               ELSE 0 END)
                      END
                                                                               AS PARTNER_SETTLE_MAYMENT, --`파트너정산대금`,
                  pscs.commission_settlement_type                              AS COMMISSION_SETTLE_TYPE, --`대금정산방법 상계 캐쉬백`,
                  pscs.payment_type                                            AS PAYMENT_TYPE, --`지급방법`,
                  r.trip_started_at                                            AS TRIP_STARTED_AT, --`여행시작일`,
                  r.kst_trip_started_at                                        AS TRIP_STARTED_AT_KST, --`여행시작일(KST)`,
                  r.trip_ended_at                                              AS TRIP_ENDED_AT, --`여행종료일`,
                  r.kst_trip_ended_at                                          AS TRIP_ENDED_AT_KST, --`여행종료일(KST)`,
                  r.settled_at                                                 AS SETTLED_AT_KST, --`정산기준일`,
                  r.finished_at                                                AS FINISHED_AT_KST, --`마감일`,
                  r.canceled_at                                                AS CANCELED_AT_KST, --`취소일`,
                  CAST(NULL AS STRING)                                         AS PAYMENT_DUE_DATE,-- `지급예정일`,
                  (SELECT STRING_AGG(CAST(es.id AS STRING), ',')
                   FROM {{ source('settles', 'erp_slips') }} es
                   WHERE es.partner_id = mypack_pdc.partner_id
                     AND es.slip_date = mypack_pdc.payment_date
                     AND slip_type = 'PACKAGE_PAYMENT_V2'
                     AND es.deleted_at IS NULL)                                AS SLIP_NO, --`전표번호`,
                  mypack_ppc.id                                                AS PAYMENT_PRODUCT_CLOSING_ID, --`기초데이터 ID`,
                  mypack_ppc.created_at                                        AS CREATED_AT_KST, --`기초데이터_생성시점`,
                  mypack_ppc.updated_at                                        AS UPDATED_AT_KST, -- `기초데이터_수정시점`
  FROM {{ source('settles', 'payment_product_closing') }} mypack_ppc
           JOIN {{ source('settles', 'payment_daily_closing') }} mypack_pdc
                ON mypack_ppc.payment_daily_closing_id = mypack_pdc.id AND mypack_pdc.deleted_at IS NULL
           JOIN {{ source('settles', 'partner_settlement_config_snapshots') }} pscs
                ON mypack_ppc.partner_settlement_config_snapshot_id = pscs.id
           JOIN {{ source('settles', 'reservations_v2') }} r ON r.id = mypack_ppc.reservation_id AND r.deleted_at IS NULL
  WHERE mypack_pdc.reservation_type != 'ORIGIN'
    AND r.system_provider = 'PKG'
    AND r.version = 2
    AND mypack_ppc.deleted_at IS NULL
  UNION ALL
  SELECT DISTINCT origin_ppc.payment_date,
                  '결제일',
                  '원예약',
                  IF(origin_ppc.option_type LIKE '%FLIGHT%', '항공', '숙소 혹은 그외'),
                  origin_ppc.closing_type,
                  mypack_pdc.order_id,
                  CAST(mypack_pdc.order_no AS INT64),
                  mypack_pdc.order_group_no,
                  mypack_pdc.partner_id,
                  origin_ppc.partner_id,
                  origin_ppc.union_product_id,
                  mypack_ppc.reservation_id,
                  mypack_ppc.reservation_no,
                  mypack_ppc.option_reservation_id,
                  origin_ppc.reservation_id,
                  origin_ppc.reservation_no,
                  origin_ppc.reservation_refund_id,
                  origin_ppc.option_reservation_id,
                  origin_ppc.option_reservation_refund_id,
                  IF(mypack_ppc.origin_link_id = origin_ppc.reservation_id, '링크', '원예약취소됨'),
                  origin_ppc.option_id,
                  origin_ppc.product_title,
                  origin_ppc.settlement_type,
                  origin_ppc.sale_type,
                  origin_ppc.system_provider,
                  pscs.accounting_project_code,
                  r.status,
                  origin_ppc.sale_price,
                  origin_ppc.supply_price,
                  origin_ppc.product_price,
                  origin_ppc.pg_amount,
                  origin_ppc.affiliate_instant_discount_amount,
                  origin_ppc.mrt_instant_discount_amount,
                  origin_ppc.mrt_coupon_discount_amount,
                  origin_ppc.partner_coupon_discount_amount,
                  0,
                  origin_ppc.free_point_amount,
                  origin_ppc.sale_commission_rate,
                  origin_ppc.sale_commission,
                  origin_ppc.mrt_cancel_commission,
                  origin_ppc.partner_cancel_commission,
                  CASE
                      WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                          origin_ppc.product_price - origin_ppc.sale_commission -
                          origin_ppc.partner_sales_channel_commission -
                          origin_ppc.partner_coupon_discount_amount + origin_ppc.partner_cancel_commission)
                      WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                          origin_ppc.product_price + origin_ppc.partner_cancel_commission +
                          origin_ppc.mrt_cancel_commission -
                          origin_ppc.partner_coupon_discount_amount)
                      ELSE 0
                  END,
                  pscs.commission_settlement_type,
                  pscs.payment_type,
                  r.trip_started_at,
                  r.kst_trip_started_at,
                  r.trip_ended_at,
                  r.kst_trip_ended_at,
                  r.settled_at,
                  r.finished_at,
                  r.canceled_at,
                  CAST(NULL AS STRING),
                  CAST(NULL AS STRING),
                  origin_ppc.id,
                  origin_ppc.created_at,
                  origin_ppc.updated_at
  FROM {{ source('settles', 'payment_product_closing') }} origin_ppc
           JOIN {{ source('settles', 'payment_daily_closing') }} origin_pdc
                ON origin_ppc.payment_daily_closing_id = origin_pdc.id AND origin_pdc.deleted_at IS NULL
           JOIN {{ source('settles', 'payment_product_closing') }} mypack_ppc
                ON mypack_ppc.option_reservation_id = origin_ppc.pkg_link_id AND mypack_ppc.deleted_at IS NULL
           JOIN {{ source('settles', 'payment_daily_closing') }} mypack_pdc
                ON mypack_ppc.payment_daily_closing_id = mypack_pdc.id AND mypack_pdc.deleted_at IS NULL
           JOIN {{ source('settles', 'partner_settlement_config_snapshots') }} pscs
                ON origin_ppc.partner_settlement_config_snapshot_id = pscs.id
           JOIN {{ source('settles', 'reservations_v2') }} r ON r.id = origin_ppc.reservation_id AND r.deleted_at IS NULL
  WHERE origin_pdc.reservation_type = 'ORIGIN'
    AND r.system_provider != 'PKG'
    AND r.version = 2
    AND origin_ppc.deleted_at IS NULL
  UNION ALL

  SELECT DISTINCT cps.confirmation_date,
                  '매출일',
                  '마이팩예약',
                  IF(mypack_ppc.option_type LIKE '%FLIGHT%', '항공', '숙소 혹은 그외') AS `구성상품 유형`,
                  mypack_ppc.closing_type                                      AS `마감유형`,
                  mypack_pdc.order_id                                          AS `주문ID`,
                  CAST(mypack_pdc.order_no AS INT64)                                          AS `주문번호`,
                  mypack_pdc.order_group_no                                    AS `이벤트넘버`,
                  mypack_pdc.partner_id                                        AS `마이팩 파트너 ID`,
                  mypack_ppc.partner_id                                        AS `원예약 파트너 ID`,
                  mypack_ppc.union_product_id                                  AS GID,
                  mypack_ppc.reservation_id                                    AS `마이팩예약ID`,
                  mypack_ppc.reservation_no                                    AS `마이팩예약NO`,
                  mypack_ppc.option_reservation_id                             AS `마이팩옵션예약ID`,
                  mypack_ppc.reservation_id                                    AS `예약ID`,
                  mypack_ppc.reservation_no                                    AS `예약NO`,
                  mypack_ppc.reservation_refund_id                             AS `예약환불ID`,
                  mypack_ppc.option_reservation_id                             AS `옵션ID`,
                  mypack_ppc.option_reservation_refund_id                      AS `옵션환불 ID`,
                  CAST(NULL AS STRING)                                                         AS `원예약 상태`,
                  mypack_ppc.option_id                                         AS `상품의옵션ID`,
                  mypack_ppc.product_title                                     AS `상품명`,
                  mypack_ppc.settlement_type                                   AS `별도/내부정산`,
                  sale_type                                                    AS `매출타입`,
                  mypack_ppc.system_provider                                   AS `버티컬`,
                  pscs.accounting_project_code                                 AS `회계프로젝트코드`,
                  r.status                                                     AS `여행상태값`,
                  mypack_ppc.sale_price                                        AS `판매금액`,
                  mypack_ppc.supply_price                                      AS `공급가`,
                  mypack_ppc.product_price                                     AS `주문금액(상품가)`,
                  mypack_ppc.pg_amount                                         AS `pg결제금액`,
                  mypack_ppc.affiliate_instant_discount_amount                 AS `즉시할인_카드사`,
                  mypack_ppc.mrt_instant_discount_amount                       AS `즉시할인_마리트`,
                  mypack_ppc.mrt_coupon_discount_amount                        AS `마리트 부담쿠폰`,
                  mypack_ppc.partner_coupon_discount_amount                    AS `파트너 부담쿠폰`,
                  0                                                            AS `유료포인트결제금액(현재없음)`,
                  mypack_ppc.free_point_amount                                 AS `무료포인트결제금액`,
                  mypack_ppc.sale_commission_rate                              AS `수수료율`,
                  mypack_ppc.sale_commission                                   AS `판매수수료`,
                  mypack_ppc.mrt_cancel_commission                             AS `마리트취소수수료`,
                  CASE
                      WHEN mypack_ppc.option_type LIKE '%FLIGHT%' THEN mypack_ppc.partner_cancel_commission
                      ELSE mypack_ppc.partner_cancel_commission
                      END                                                      AS `파트너취소수수료`,
                  CASE
                      WHEN mypack_ppc.option_type LIKE '%FLIGHT%' THEN
                          (CASE
                               WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                                   mypack_ppc.product_price - mypack_ppc.sale_commission -
                                   mypack_ppc.partner_sales_channel_commission -
                                   mypack_ppc.partner_coupon_discount_amount + mypack_ppc.partner_cancel_commission)
                               WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                                   mypack_ppc.product_price + mypack_ppc.partner_cancel_commission +
                                   mypack_ppc.mrt_cancel_commission -
                                   mypack_ppc.partner_coupon_discount_amount)
                               ELSE 0 END)
                      ELSE
                          (CASE
                               WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                                   mypack_ppc.product_price - mypack_ppc.sale_commission -
                                   mypack_ppc.partner_sales_channel_commission -
                                   mypack_ppc.partner_coupon_discount_amount + mypack_ppc.partner_cancel_commission)
                               WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                                   mypack_ppc.product_price + mypack_ppc.partner_cancel_commission +
                                   mypack_ppc.mrt_cancel_commission -
                                   mypack_ppc.partner_coupon_discount_amount)
                               ELSE 0 END)
                      END
                                                                               AS `파트너정산대금`,
                  pscs.commission_settlement_type                              AS `대금정산방법(상계/캐쉬백)`,
                  pscs.payment_type                                            AS `지급방법`,
                  r.trip_started_at                                            AS `여행시작일`,
                  r.kst_trip_started_at                                            AS `여행시작일(KST)`,
                  r.trip_ended_at                                              AS `여행종료일`,
                  r.kst_trip_ended_at                                              AS `여행종료일(KST)`,
                  r.settled_at                                                 AS `정산기준일`,
                  r.finished_at                                                AS `마감일`,
                  r.canceled_at                                                AS `취소일`,
                  (SELECT STRING_AGG(DISTINCT CAST(pps.payment_due_date AS STRING), ',')
                   FROM {{ source('settles', 'reservation_settlement_mapping') }} rsm
                            JOIN {{ source('settles', 'payment_product_closing') }} origin_ppc
                                 ON mypack_ppc.option_reservation_id = origin_ppc.pkg_link_id AND
                                    mypack_ppc.deleted_at IS NULL
                                     AND rsm.reservation_id = origin_ppc.reservation_id
                                     AND IF(origin_ppc.reservation_refund_id IS NULL, TRUE,
                                            origin_ppc.reservation_refund_id =
                                            rsm.reservation_refund_id)
                            JOIN {{ source('settles', 'partner_periodic_settlements') }} pps
                                 ON pps.id = rsm.target_id AND pps.deleted_at IS NULL
                   WHERE rsm.deleted_at IS NULL
                     AND rsm.target_type = 'PARTNER_SETTLEMENT')               AS `지급예정일`,
                  (SELECT STRING_AGG(DISTINCT CAST(es.id AS STRING), ',')
                   FROM {{ source('settles', 'erp_slips') }} es
                   WHERE es.reservation_id = mypack_pdc.reservation_id
                     AND es.deleted_at IS NULL
                     AND slip_type != 'PACKAGE_PAYMENT_V2')                     AS `전표번호`,
                  mypack_ppc.id,
                  mypack_ppc.created_at                                        AS `기초데이터_생성시점`,
                  mypack_ppc.updated_at                                        AS `기초데이터_수정시점`
  FROM WITH_CONFIRMATION_CLOSING cps
           JOIN {{ source('settles', 'payment_product_closing') }} mypack_ppc
                ON cps.payment_product_closing_id = mypack_ppc.id AND cps.deleted_at IS NULL
           JOIN {{ source('settles', 'payment_daily_closing') }} mypack_pdc
                ON mypack_ppc.payment_daily_closing_id = mypack_pdc.id AND mypack_pdc.deleted_at IS NULL
           JOIN {{ source('settles', 'partner_settlement_config_snapshots') }} pscs
                ON mypack_ppc.partner_settlement_config_snapshot_id = pscs.id
           JOIN {{ source('settles', 'reservations_v2') }} r ON r.reservation_no = mypack_ppc.reservation_no
  WHERE mypack_pdc.reservation_type != 'ORIGIN'
    AND r.system_provider = 'PKG'
    AND r.version = 2
    AND mypack_ppc.deleted_at IS NULL
  AND r.deleted_at IS NULL
  UNION ALL
  SELECT DISTINCT cps.confirmation_date,
                  '매출일',
                  '원예약',
                  IF(origin_ppc.option_type LIKE '%FLIGHT%', '항공', '숙소 혹은 그외'),
                  origin_ppc.closing_type,
                  mypack_pdc.order_id,
                  CAST(mypack_pdc.order_no AS INT64),
                  mypack_pdc.order_group_no,
                  mypack_pdc.partner_id           AS `마이팩 파트너 ID`,
                  origin_ppc.partner_id           AS `원예약 파트너 ID`,
                  origin_ppc.union_product_id,
                  mypack_ppc.reservation_id,
                  mypack_ppc.reservation_no,
                  mypack_ppc.option_reservation_id,
                  origin_ppc.reservation_id,
                  origin_ppc.reservation_no,
                  origin_ppc.reservation_refund_id,
                  origin_ppc.option_reservation_id,
                  origin_ppc.option_reservation_refund_id,
                  IF(mypack_ppc.origin_link_id = origin_ppc.reservation_id, '링크', '원예약취소됨'),
                  origin_ppc.option_id,
                  origin_ppc.product_title,
                  origin_ppc.settlement_type,
                  origin_ppc.sale_type,
                  origin_ppc.system_provider,
                  pscs.accounting_project_code,
                  r.status,
                  origin_ppc.sale_price,
                  origin_ppc.supply_price,
                  origin_ppc.product_price,
                  origin_ppc.pg_amount,
                  origin_ppc.affiliate_instant_discount_amount,
                  origin_ppc.mrt_instant_discount_amount,
                  origin_ppc.mrt_coupon_discount_amount,
                  origin_ppc.partner_coupon_discount_amount,
                  0,
                  origin_ppc.free_point_amount,
                  origin_ppc.sale_commission_rate,
                  origin_ppc.sale_commission,
                  origin_ppc.mrt_cancel_commission,
                  origin_ppc.partner_cancel_commission,
                  CASE
                      WHEN pscs.commission_settlement_type = 'SET_OFF' THEN (
                          origin_ppc.product_price - origin_ppc.sale_commission -
                          origin_ppc.partner_sales_channel_commission -
                          origin_ppc.partner_coupon_discount_amount + origin_ppc.partner_cancel_commission)
                      WHEN pscs.commission_settlement_type = 'CASHBACK' THEN (
                          origin_ppc.product_price + origin_ppc.partner_cancel_commission +
                          origin_ppc.mrt_cancel_commission -
                          origin_ppc.partner_coupon_discount_amount)
                      ELSE 0 END
                                                  AS `파트너정산대금`,
                  pscs.commission_settlement_type AS `대금정산방법(상계/캐쉬백)`,
                  pscs.payment_type               AS `지급방법`,
                  r.trip_started_at               AS `여행시작일`,
                  r.kst_trip_started_at               AS `여행시작일(KST)`,
                  r.trip_ended_at                 AS `여행종료일`,
                  r.kst_trip_ended_at                 AS `여행종료일(KST)`,
                  r.settled_at                    AS `정산기준일`,
                  r.finished_at                   AS `마감일`,
                  r.canceled_at                   AS `취소일`,

                  (SELECT STRING_AGG(DISTINCT CAST(pps.payment_due_date AS STRING), ',')
                   FROM {{ source('settles', 'reservation_settlement_mapping') }} rsm
                            JOIN {{ source('settles', 'partner_periodic_settlements') }} pps
                                 ON pps.id = rsm.target_id AND pps.deleted_at IS NULL
                   WHERE rsm.deleted_at IS NULL
                     AND rsm.target_type = 'PARTNER_SETTLEMENT'
                     AND rsm.reservation_id = origin_ppc.reservation_id
                     AND IF(origin_ppc.reservation_refund_id IS NULL, TRUE,
                            origin_ppc.reservation_refund_id =
                            rsm.reservation_refund_id)) AS `지급예정일`,
                  CAST(NULL AS STRING)                            AS `전표번호`,
                  origin_ppc.id,
                  origin_ppc.created_at           AS `기초데이터_생성시점`,
                  origin_ppc.updated_at           AS `기초데이터_수정시점`
  FROM WITH_CONFIRMATION_CLOSING cps
           JOIN {{ source('settles', 'payment_product_closing') }} mypack_ppc
                ON cps.payment_product_closing_id = mypack_ppc.id AND cps.deleted_at IS NULL
           JOIN {{ source('settles', 'payment_product_closing') }} origin_ppc
                ON mypack_ppc.option_reservation_id = origin_ppc.pkg_link_id AND mypack_ppc.deleted_at IS NULL
           JOIN {{ source('settles', 'payment_daily_closing') }} origin_pdc
                ON origin_ppc.reservation_id = origin_pdc.reservation_id AND
                   IF(origin_ppc.reservation_refund_id IS NULL, TRUE,
                      origin_ppc.reservation_refund_id = origin_pdc.reservation_refund_id)
           JOIN {{ source('settles', 'reservations_v2') }} r
                ON r.reservation_no = origin_pdc.reservation_no
           JOIN {{ source('settles', 'payment_daily_closing') }} mypack_pdc
                ON mypack_ppc.payment_daily_closing_id = mypack_pdc.id AND mypack_pdc.deleted_at IS NULL
           JOIN {{ source('settles', 'partner_settlement_config_snapshots') }} pscs
                ON origin_ppc.partner_settlement_config_snapshot_id = pscs.id
  WHERE origin_pdc.reservation_type = 'ORIGIN'
    AND r.system_provider != 'PKG'
    AND r.version = 2
    AND r.deleted_at IS NULL
    AND origin_ppc.deleted_at IS NULL
    AND origin_pdc.deleted_at IS NULL
    AND r.deleted_at IS NULL