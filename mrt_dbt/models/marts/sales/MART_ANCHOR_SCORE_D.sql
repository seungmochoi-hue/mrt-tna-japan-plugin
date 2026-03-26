{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_ANCHOR_SCORE_D',
        tags=['ANCHOR_SCORE'],
        labels={'domain': 'sales', 'priority': 'p2'}
    )
}}

/*
  MART_ANCHOR_SCORE_D — T&A 상품별 Anchor Score + 4-Tier 자동 분류

  Anchor Score = 첫구매율(%) × 크로스셀유발율(%) / 100
  - 첫구매율: TRAVEL_ID 내 CREATE_KST_DT ASC 기준 첫 번째 T&A 구매 비율
  - 크로스셀유발율: 해당 상품 포함 여행에서 2개+ 상이 GID 구매 비율

  Tier: S(핵심앵커) / A(성장후보) / B(매출기반) / C(일반)
  경계: AS >= 15 & FoM/T >= 20,000 = S
  뱃지: TR% >= 15% = HM (High Margin)
  볼륨: L(1000+) / M(100-999) / S(<100)

  Grain: COUNTRY_NM × CITY_NM × GID (일별 갱신, rolling 90일)
  대상: T&A 카테고리 (TOUR/TICKET/ACTIVITY/CLASS/CONVENIENCE/SNAP), KIND=1
*/

WITH
-- 기본 데이터: T&A 결제행, rolling 90일
base AS (
  SELECT
    TRAVEL_ID,
    USER_ID,
    COUNTRY_NM,
    CITY_NM,
    GID,
    PRODUCT_TITLE,
    STANDARD_CATEGORY_LV_1_CD AS cat1,
    SALES_KRW_PRICE,
    COALESCE(COMMISSION_PRICE, 0) AS margin,
    CREATE_KST_DT,
    ORDER_ID
  FROM {{ ref('MART_SALE_D') }}
  WHERE BASIS_DATE BETWEEN DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 91 DAY)
                       AND DATE_SUB(CURRENT_DATE('Asia/Seoul'), INTERVAL 1 DAY)
    AND KIND = 1
    AND STANDARD_CATEGORY_LV_1_CD IN ('TOUR', 'TICKET', 'ACTIVITY', 'CLASS', 'CONVENIENCE', 'SNAP')
    AND TRAVEL_ID IS NOT NULL
),

-- 상품별 GMV, 마진 집계
product_gmv AS (
  SELECT
    COUNTRY_NM,
    CITY_NM,
    GID,
    ANY_VALUE(PRODUCT_TITLE) AS product_title,
    ANY_VALUE(cat1) AS category,
    SUM(SALES_KRW_PRICE) AS gmv,
    SUM(margin) AS direct_margin,
    COUNT(DISTINCT ORDER_ID) AS order_cnt
  FROM base
  GROUP BY COUNTRY_NM, CITY_NM, GID
),

-- 도시별 GMV 순위 + 누적 비중 (상위 80% 커버 상품 선별)
product_ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY COUNTRY_NM, CITY_NM ORDER BY gmv DESC) AS gmv_rank,
    SUM(gmv) OVER (PARTITION BY COUNTRY_NM, CITY_NM ORDER BY gmv DESC ROWS UNBOUNDED PRECEDING) AS cumul_gmv,
    SUM(gmv) OVER (PARTITION BY COUNTRY_NM, CITY_NM) AS city_total_gmv
  FROM product_gmv
),

top_products AS (
  SELECT
    *,
    ROUND(gmv / NULLIF(city_total_gmv, 0) * 100, 2) AS gmv_share_pct,
    ROUND(cumul_gmv / NULLIF(city_total_gmv, 0) * 100, 2) AS cum_gmv_pct
  FROM product_ranked
  WHERE SAFE_DIVIDE(cumul_gmv - gmv, city_total_gmv) < 0.80
),

-- TRAVEL_ID별 시간순 첫 구매 GID
travel_first_purchase AS (
  SELECT TRAVEL_ID, GID AS first_gid
  FROM (
    SELECT
      TRAVEL_ID,
      GID,
      ROW_NUMBER() OVER (PARTITION BY TRAVEL_ID ORDER BY CREATE_KST_DT ASC) AS rn
    FROM base
  )
  WHERE rn = 1
),

-- TRAVEL × GID 유니크 조합
travel_gid AS (
  SELECT DISTINCT TRAVEL_ID, COUNTRY_NM, CITY_NM, GID
  FROM base
),

-- TRAVEL별 상이 GID 수
travel_product_cnt AS (
  SELECT TRAVEL_ID, COUNT(DISTINCT GID) AS product_cnt
  FROM base
  GROUP BY TRAVEL_ID
),

-- 상품별 앵커 지표: 첫구매율, 크로스셀율
anchor_stats AS (
  SELECT
    tg.COUNTRY_NM,
    tg.CITY_NM,
    tg.GID,
    COUNT(DISTINCT tg.TRAVEL_ID) AS travel_cnt,
    COUNT(DISTINCT CASE WHEN tfp.first_gid = tg.GID THEN tg.TRAVEL_ID END) AS first_purchase_cnt,
    COUNT(DISTINCT CASE WHEN tpc.product_cnt >= 2 THEN tg.TRAVEL_ID END) AS cross_sell_cnt
  FROM travel_gid tg
  INNER JOIN top_products tp
    ON tg.COUNTRY_NM = tp.COUNTRY_NM AND tg.CITY_NM = tp.CITY_NM AND tg.GID = tp.GID
  LEFT JOIN travel_first_purchase tfp
    ON tg.TRAVEL_ID = tfp.TRAVEL_ID
  LEFT JOIN travel_product_cnt tpc
    ON tg.TRAVEL_ID = tpc.TRAVEL_ID
  GROUP BY tg.COUNTRY_NM, tg.CITY_NM, tg.GID
),

-- Follow-on Margin 계산 (앵커 상품 제외 다른 상품의 커미션 합계)
travel_gid_margin AS (
  SELECT TRAVEL_ID, COUNTRY_NM, CITY_NM, GID, SUM(margin) AS gid_margin
  FROM base
  GROUP BY TRAVEL_ID, COUNTRY_NM, CITY_NM, GID
),

follow_on AS (
  SELECT
    tgm_anchor.COUNTRY_NM,
    tgm_anchor.CITY_NM,
    tgm_anchor.GID AS anchor_gid,
    SUM(tgm_other.gid_margin) AS follow_on_margin,
    COUNT(DISTINCT tgm_anchor.TRAVEL_ID) AS fo_travel_cnt
  FROM travel_gid_margin tgm_anchor
  INNER JOIN top_products tp
    ON tgm_anchor.COUNTRY_NM = tp.COUNTRY_NM
    AND tgm_anchor.CITY_NM = tp.CITY_NM
    AND tgm_anchor.GID = tp.GID
  JOIN travel_gid_margin tgm_other
    ON tgm_anchor.TRAVEL_ID = tgm_other.TRAVEL_ID
    AND tgm_anchor.COUNTRY_NM = tgm_other.COUNTRY_NM
    AND tgm_anchor.CITY_NM = tgm_other.CITY_NM
  WHERE tgm_other.GID != tgm_anchor.GID
  GROUP BY tgm_anchor.COUNTRY_NM, tgm_anchor.CITY_NM, tgm_anchor.GID
),

-- 최종 산출: Anchor Score + 4-Tier + 뱃지 + 볼륨
final AS (
  SELECT
    -- 식별
    CURRENT_DATE('Asia/Seoul') AS basis_date,
    tp.COUNTRY_NM,
    tp.CITY_NM,
    tp.GID,
    tp.product_title,
    tp.category,

    -- GMV 지표
    tp.gmv_rank,
    ROUND(tp.gmv) AS gmv,
    tp.gmv_share_pct,
    tp.cum_gmv_pct,
    ROUND(tp.direct_margin) AS direct_margin,
    ROUND(SAFE_DIVIDE(tp.direct_margin, tp.gmv) * 100, 2) AS tr_pct,
    tp.order_cnt,

    -- 앵커 지표
    a.travel_cnt,
    ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * 100, 2) AS first_purchase_rate,
    ROUND(SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) AS cross_sell_rate,
    ROUND(
      SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt)
      * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt)
      * 100,
      2
    ) AS anchor_score,

    -- Follow-on Margin
    COALESCE(ROUND(f.follow_on_margin), 0) AS follow_on_margin,
    COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) AS fo_margin_per_travel,

    -- Total Value
    ROUND(tp.direct_margin + COALESCE(f.follow_on_margin, 0)) AS total_value,

    -- 4-Tier 분류
    CASE
      WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) >= 15
        AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) >= 20000
        THEN 'S'
      WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) >= 15
        AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) < 20000
        THEN 'A'
      WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) < 15
        AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) >= 20000
        THEN 'B'
      ELSE 'C'
    END AS tier,

    -- High Margin 뱃지
    CASE
      WHEN SAFE_DIVIDE(tp.direct_margin, tp.gmv) * 100 >= 15 THEN 'HM'
      ELSE ''
    END AS margin_badge,

    -- 볼륨 태그
    CASE
      WHEN a.travel_cnt >= 1000 THEN 'L'
      WHEN a.travel_cnt >= 100 THEN 'M'
      ELSE 'S'
    END AS volume_tag,

    -- 통합 라벨 (예: S-L-HM)
    CONCAT(
      CASE
        WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) >= 15
          AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) >= 20000
          THEN 'S'
        WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) >= 15
          AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) < 20000
          THEN 'A'
        WHEN ROUND(SAFE_DIVIDE(a.first_purchase_cnt, a.travel_cnt) * SAFE_DIVIDE(a.cross_sell_cnt, a.travel_cnt) * 100, 2) < 15
          AND COALESCE(ROUND(SAFE_DIVIDE(f.follow_on_margin, f.fo_travel_cnt)), 0) >= 20000
          THEN 'B'
        ELSE 'C'
      END,
      '-',
      CASE WHEN a.travel_cnt >= 1000 THEN 'L' WHEN a.travel_cnt >= 100 THEN 'M' ELSE 'S' END,
      CASE WHEN SAFE_DIVIDE(tp.direct_margin, tp.gmv) * 100 >= 15 THEN '-HM' ELSE '' END
    ) AS label

  FROM top_products tp
  LEFT JOIN anchor_stats a
    ON tp.COUNTRY_NM = a.COUNTRY_NM AND tp.CITY_NM = a.CITY_NM AND tp.GID = a.GID
  LEFT JOIN follow_on f
    ON tp.COUNTRY_NM = f.COUNTRY_NM AND tp.CITY_NM = f.CITY_NM AND tp.GID = f.anchor_gid
)

SELECT * FROM final
