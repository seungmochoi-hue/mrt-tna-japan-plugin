{{ config(
    materialized='view',
    schema='edw_intermediate'
) }}

/*
  [INT_FPNA_POINT_DETAIL] 예약별 제외 포인트 금액 및 B2B 포인트 예약 식별
  - POINT_OTHERS: FPNA_EXCEPTED_POINT_INFO에 정의된 특정 template의 포인트 사용 금액을 예약 단위로 합산
  - B2B_POINT_RSV: B2B 포인트(point_category LIKE '%B2B%')를 사용한 예약을 식별
  - Grain: RESVE_ID (예약당 1행)
  - 두 결과를 FULL OUTER JOIN으로 통합하여 하나의 모델로 제공
*/

-- 비용 제외 대상 포인트 합산 (FPNA_EXCEPTED_POINT_INFO의 template_id에 해당)
WITH POINT_OTHERS AS (
    SELECT
        s.RESVE_ID
      , SUM(ph.ACTION_AMOUNT) * -1                                                          AS POINT_SUM
    FROM {{ ref('MART_SALE_D') }} s
    LEFT JOIN {{ source('orders', 'reservations') }} r
        ON s.RESVE_ID = r.RESERVATION_NO
    LEFT JOIN {{ source('orders', 'orders') }} o
        ON r.ORDER_ID = o.ID
    LEFT JOIN {{ source('points', 'point_action_histories') }} ph
        ON o.ORDER_NO = CAST(ph.ACTION_TYPE_RELATED_ID AS STRING)
       AND ph.ACTION_TYPE LIKE '%USE%'
    LEFT JOIN {{ source('points', 'points') }} p
        ON ph.POINT_ID = p.ID
    LEFT JOIN {{ source('points', 'point_templates') }} pt
        ON p.TEMPLATE_ID = pt.ID
    LEFT JOIN (
        SELECT DISTINCT TEMPLATE_ID
        FROM {{ ref('FPNA_EXCEPTED_POINT_INFO') }}
    ) pi
        ON p.TEMPLATE_ID = pi.TEMPLATE_ID
    WHERE s.KIND = 1
      AND p.ID IS NOT NULL
      AND pi.TEMPLATE_ID IS NOT NULL
    GROUP BY s.RESVE_ID
    HAVING SUM(ph.ACTION_AMOUNT) IS NOT NULL
)

-- B2B 포인트 사용 예약 식별 (point_category LIKE '%B2B%')
, B2B_POINT_RSV AS (
    WITH USED_POINT AS (
        SELECT
            ro.RESERVATION_NO
          , ph.BEFORE_ACTION_AMOUNT
          , ph.ACTION_AMOUNT
          , ph.AFTER_ACTION_AMOUNT
          , p.TEMPLATE_ID
          , pt.TEMPLATE_NAME
          , pt.POINT_CATEGORY
        FROM {{ source('orders', 'orders') }} o
        LEFT JOIN {{ source('orders', 'reservations') }} ro
            ON o.ID = ro.ORDER_ID
        LEFT JOIN {{ source('points', 'point_action_histories') }} ph
            ON o.ORDER_NO = CAST(ph.ACTION_TYPE_RELATED_ID AS STRING)
           AND ph.ACTION_TYPE LIKE '%USE%'
        LEFT JOIN {{ source('points', 'points') }} p
            ON ph.POINT_ID = p.ID
        LEFT JOIN {{ source('points', 'point_templates') }} pt
            ON p.TEMPLATE_ID = pt.ID
        WHERE p.ID IS NOT NULL
    )
    SELECT DISTINCT
        s.RESVE_ID
    FROM {{ ref('MART_SALE_D') }} s
    LEFT JOIN USED_POINT up
        ON s.RESVE_ID = up.RESERVATION_NO
    WHERE s.KIND = 1
      AND up.POINT_CATEGORY LIKE '%B2B%'
      AND s.POINT_PRICE IS NOT NULL
      AND s.POINT_PRICE != 0
)

-- 두 결과를 FULL OUTER JOIN으로 통합
SELECT
    COALESCE(po.RESVE_ID, bp.RESVE_ID)                                                      AS RESVE_ID
  , po.POINT_SUM
  , CASE WHEN bp.RESVE_ID IS NOT NULL THEN TRUE ELSE FALSE END                              AS IS_B2B_POINT_RSV
FROM POINT_OTHERS po
FULL OUTER JOIN B2B_POINT_RSV bp
    ON po.RESVE_ID = bp.RESVE_ID
