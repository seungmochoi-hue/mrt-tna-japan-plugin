-- 데이터 완결성 검증: 최소 1행 이상 존재
SELECT COUNT(*) AS row_count
FROM {{ ref('MART_ANCHOR_SCORE_D') }}
HAVING COUNT(*) = 0
