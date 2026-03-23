# 매출 조회 규칙

## GMV vs Revenue 반문 규칙

| 사용자 표현 | 의미 | 동작 |
|-----------|------|------|
| "거래액", "GMV" | GMV로 확정 | **반문 없이 바로 `MART_SALE_D`에서 조회** |
| "매출", "매출액", "세일즈" | 모호 (GMV일 수도, Revenue일 수도) | **반드시 반문**: 거래액(GMV)인지 Revenue인지 확인 |
| "Revenue", "레베뉴" | Revenue로 확정 | 바로 `edw_fpna` 등에서 조회 |

| 구분 | 정의 | 소스 테이블 |
|------|------|-----------|
| 거래액(GMV) | 결제행 기준 총 거래 금액 | `edw_mart.MART_SALE_D` |
| Revenue | FP&A/매출관리팀 기준 매출 | `edw_fpna` 등 별도 소스 |

- `MART_SALE_D`로 산출하는 금액은 거래액(GMV)이다. Revenue와 혼동하지 않는다.
- **"거래액"이라고 했으면 이미 GMV를 특정한 것이다. 되묻지 않고 바로 조회한다.**
- "매출"이라고만 했을 때만 반문한다. 결과 응답에서도 "거래액" 요청에 Revenue 언급을 섞지 않는다.

## 거래액 집계 기준

- **집계 일자**: `BASIS_DATE` 기준. `CONFIRM_KST_DATE`(확정일) 기준이 아님.
- **거래액 컬럼**: `SALES_KRW_PRICE` (원화 환산). `SALE_AMT` 컬럼은 존재하지 않음.
  - 다통화 거래액이 필요하면 `SALES_PRICE` + `SALES_PRICE_CUR_TYPE` 사용.
- **거래액 (기본)**: `KIND = 1` (결제행)만 필터하여 합산. 별도 요청 없으면 이것이 기본.
- **순거래액**: `KIND` 1, 2 모두 포함하여 합산 (취소행은 음수로 상계). **사용자가 명시적으로 요청한 경우에만 사용한다. 후속 옵션이나 추가 분석 제안에서 순거래액 분석을 선제적으로 제시하지 않는다.**

## 버티컬 분류

- **기준 컬럼**: `STANDARD_CATEGORY_LV_1_CD` (`DOMAIN_NM`이 아님)
- **그룹핑 규칙**: YAML(`MART_SALE_D.yml`)의 `STANDARD_CATEGORY_LV_1_CD` description 참조.
  - T&A: `TOUR`, `TICKET`, `ACTIVITY`, `CLASS`, `CONVENIENCE`, `SNAP`
  - 숙박: `ACCOMMODATION`
  - 한인 민박: `ACCOMMODATION` + `STANDARD_CATEGORY_LV_3_CD IN ('LODGING_V2', 'LODGE_V2', 'KOREAN_MINBAK', 'LOCAL_ACCOMMODATION_V2')` + `COUNTRY_NM != 'Korea, Republic of'`
- 12개 값 전체 목록은 YAML 참조.

**예시 쿼리 (올바른 버티컬 분류)**:

```sql
-- ✅ 올바른 예: STANDARD_CATEGORY_LV_1_CD 사용
SELECT
  STANDARD_CATEGORY_LV_1_CD,  -- 버티컬 분류 기준
  SUM(SALES_KRW_PRICE) AS gmv
FROM `mrtdata.edw_mart.MART_SALE_D`
WHERE BASIS_DATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND KIND = 1
GROUP BY 1
ORDER BY 2 DESC

-- ❌ 잘못된 예: DOMAIN_NM 사용 (파이프라인 소스 구분용)
-- SELECT DOMAIN_NM, SUM(SALES_KRW_PRICE) ...
```

## 드릴다운 분석 축

- 버티컬(T&A, 숙박, 항공 등) 분석에서 **드릴다운 축**은 카테고리 계층(`STANDARD_CATEGORY_LV_1_CD` → `LV_2_CD` → `LV_3_CD`)이다.
- `DOMAIN_NM`은 파이프라인 소스 구분용 컬럼이므로, 버티컬 분석의 드릴다운 축이나 후속 분석 옵션으로 제안하지 않는다.
- 후속 분석 옵션에서 세부 분해를 제안할 때는 `STANDARD_CATEGORY_LV_2_CD`, `STANDARD_CATEGORY_LV_3_CD` 기준을 사용한다.
