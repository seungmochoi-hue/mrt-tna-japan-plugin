{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='edw_mart',
        alias='MART_MYLINK_REFER_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['PARTNER_ID']
    )
}}

WITH LOG_PID_ROW AS (
    SELECT T.BASIS_DATE
        ,  CAST(T.PID AS STRING) AS PID
        ,  CAST(T.GID AS STRING) AS GID
        ,  T.PLATFORM
        ,  T.REF_URL
        ,  CAST(T.MYLINK_ID AS STRING) AS MYLINK_ID
    FROM (
        SELECT l.basis_dt AS BASIS_DATE
            ,  l.pid AS PID
            ,  l.item_id AS GID
            ,  l.platform AS PLATFORM
            ,  l.ref_url AS REF_URL
            ,  l.mylink_id AS MYLINK_ID
            ,  ROW_NUMBER() OVER (PARTITION BY l.basis_dt, l.pid ORDER BY l.event_timestamp_kst) AS RN
        FROM {{ ref('DW_BIZ_LOG_VIEW') }} l
        WHERE l.basis_dt = '{{ var("logical_start_date_kst") }}'
          AND l.mylink_id IS NOT NULL
        ) T
    WHERE T.RN = 1
),
REFERER AS (
  SELECT R.short_url_id
      ,  CASE WHEN lower(R.referer_url) LIKE '%naver%' THEN 'NAVER'
              WHEN lower(R.referer_url) LIKE '%insta%' THEN 'INSTA'
              WHEN lower(R.referer_url) LIKE '%youtube%' THEN 'YOUTUBE'
              ELSE 'ETC' END AS referer
      ,  MIN(R.referer_url)
    FROM {{ source('commons','short_url_referer') }} R
    WHERE R.referer_url IS NOT NULL
    GROUP BY R.short_url_id, CASE WHEN lower(R.referer_url) LIKE '%naver%' THEN 'NAVER' WHEN lower(R.referer_url) LIKE '%insta%' THEN 'INSTA'
              WHEN lower(R.referer_url) LIKE '%youtube%' THEN 'YOUTUBE' ELSE 'ETC' END
)
SELECT CAST(L.BASIS_DATE AS DATE) AS BASIS_DATE
     ,  CAST(A.partner_id AS STRING) AS PARTNER_ID
     ,  P.name AS PARTNER_NM
     ,  CAST(L.GID AS STRING) AS GID
     ,  ups.title AS PRODUCT_NM
     ,  L.PLATFORM AS PLATFORM
     ,  R.referer AS REFERER_URL
     ,  COUNT(DISTINCT L.PID) AS PID_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM LOG_PID_ROW L
JOIN {{ source('partners', 'mylink') }} A ON L.MYLINK_ID = CAST(A.id AS STRING)
LEFT JOIN {{ source('commons','short_url') }} S ON A.short_url_id = S.id
LEFT JOIN {{ source('partners', 'partner_account') }} P ON A.partner_id = P.partner_id
LEFT JOIN REFERER R ON A.short_url_id = R.short_url_id
LEFT JOIN {{ source('ups', 'union_product_v3') }} ups ON L.GID = CAST(ups.id AS STRING)
WHERE R.short_url_id IS NOT NULL
  AND L.GID = CAST(S.GID AS STRING)
GROUP BY L.BASIS_DATE, A.partner_id, P.name, L.PLATFORM, R.referer, L.GID, ups.title

UNION ALL

SELECT CAST(L.BASIS_DATE AS DATE) AS BASIS_DATE
     ,  CAST(A.partner_id AS STRING) AS PARTNER_ID
     ,  P.name AS PARTNER_NM
     ,  'TOTAL' AS GID
     ,  'TOTAL' AS PRODUCT_NM
     ,  L.PLATFORM AS PLATFORM
     ,  R.referer AS REFERER_URL
     ,  COUNT(DISTINCT L.PID) AS PID_CNT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM LOG_PID_ROW L
JOIN {{ source('partners', 'mylink') }} A ON L.MYLINK_ID = CAST(A.id AS STRING)
LEFT JOIN {{ source('commons','short_url') }} S ON A.short_url_id = S.id
LEFT JOIN {{ source('partners', 'partner_account') }} P ON A.partner_id = P.partner_id
LEFT JOIN REFERER R ON A.short_url_id = R.short_url_id
LEFT JOIN {{ source('ups', 'union_product_v3') }} ups ON L.GID = CAST(ups.id AS STRING)
WHERE R.short_url_id IS NOT NULL
  AND L.GID = CAST(S.GID AS STRING)
GROUP BY L.BASIS_DATE, A.partner_id, P.name, L.PLATFORM, R.referer