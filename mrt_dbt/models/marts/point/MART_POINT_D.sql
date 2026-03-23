{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_POINT_D'
    )
}}


WITH POINT_HISTORY AS (
    SELECT CAST(H.created_at AS DATE) AS BASIS_DATE
         ,  H.point_id AS POINT_ID
         ,  H.user_id AS USER_ID
         ,  CASE WHEN H.action_type IN ('SAVE_UP_ORDER_LEGACY', 'SAVE_UP_ORDER', 'SAVE_UP', 'SAVE_UP_FLIGHT') THEN 'save_up'
                 WHEN H.action_type IN ('CANCEL_ORDER_LEGACY', 'CANCEL_ORDER', 'PARTIAL_CANCEL_ORDER_LEGACY', 'PARTIAL_CANCEL_ORDER', 'PARTIAL_CANCEL_FLIGHT') THEN 'cancel'
                 WHEN H.action_type IN ('USE_ORDER', 'USE_ORDER_LEGACY', 'USE_FLIGHT') THEN 'used'
                 WHEN H.action_type = 'EXPIRE' THEN 'expire'
                 WHEN H.action_type = 'RETRIEVE' THEN 'retrieve'
                 ELSE 'etc' END AS STATUS
         ,  CONCAT(CASE WHEN H.action_type LIKE '%FLIGHT%' THEN 'f' ELSE '' END, CAST(H.action_type_reference_key AS STRING)) AS RESVE_ID
         ,  H.action_amount AS ACTION_AMOUNT
         ,  SUM(H.action_amount) OVER(ORDER BY H.created_at) AS AFTER_ACTION_AMOUNT
    ,  H.created_at AS CREATED_KST_DT
         ,  H.updated_at AS UPDATED_KST_DT
    FROM {{ source('points', 'point_action_histories') }} H
             LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON H.user_id = U.USER_ID
    WHERE H.deleted_at IS NULL
      AND (U.TEST_FLAG <> true OR U.USER_ID IS NULL)
),
-- TARGET_POINT_ID AS (
--     SELECT DISTINCT A.POINT_ID
--     FROM POINT_HISTORY_BEFORE A
--              LEFT JOIN (
--         SELECT DISTINCT P.POINT_ID
--         FROM POINT_HISTORY_BEFORE P
--         WHERE P.STATUS = 'save_up'
--     ) B ON A.POINT_ID = B.POINT_ID
--     WHERE B.POINT_ID IS NULL
-- ),
-- POINT_HISTORY AS (
--     SELECT H.BASIS_DATE
--          ,  H.POINT_ID
--          ,  H.USER_ID
--          ,  H.STATUS
--          ,  H.RESVE_ID
--          ,  H.ACTION_AMOUNT
--          ,  H.AFTER_ACTION_AMOUNT
--          ,  H.CREATED_KST_DT
--          ,  H.UPDATED_KST_DT
--     FROM POINT_HISTORY H
--
--     UNION ALL
--
--     SELECT CAST(P.created_at AS DATE) AS BASIS_DATE
--          ,  S.POINT_ID AS POINT_ID
--          ,  P.user_id AS USER_ID
--          ,  'save_up' AS STATUS
--          ,  CAST(null AS STRING) AS RESVE_ID
--          ,  P.initial_amount AS ACTION_AMOUNT
--          ,  null AS AFTER_ACTION_AMOUNT
--          ,  P.created_at AS CREATED_KST_DT
--          ,  P.updated_at AS UPDATED_KST_DT
--     FROM TARGET_POINT_ID S
--              LEFT JOIN edw.DW_MRT_POINT_POINTS P ON S.POINT_ID = P.ID
-- ),
POINT_EXIST_DATE AS (
    SELECT H.POINT_ID
         ,  H.USER_ID
         ,  MIN(CASE WHEN H.STATUS = 'save_up' THEN H.CREATED_KST_DT ELSE null END) AS POINT_CREATED_DATE
         ,  MAX(CASE WHEN H.AFTER_ACTION_AMOUNT = 0 THEN H.CREATED_KST_DT ELSE NULL END) AS POINT_ENDED_DATE
    FROM POINT_HISTORY H
    LEFT JOIN {{ source('points', 'points') }} P ON H.POINT_ID = P.id
    WHERE P.remain_amount = 0
    GROUP BY H.POINT_ID, H.USER_ID
),
POINT_EXIST_FLAG AS (
    SELECT P.id AS POINT_ID
         ,  MAX(CASE WHEN E.POINT_ID IS NOT NULL THEN 1 ELSE 0 END) AS POINT_EXIST_FLAG
    FROM {{ source('points', 'points') }} P
    LEFT JOIN POINT_EXIST_DATE E ON P.user_id = E.USER_ID AND P.created_at BETWEEN E.POINT_CREATED_DATE AND E.POINT_ENDED_DATE AND P.id <> E.POINT_ID
    WHERE P.deleted_at IS NULL
    GROUP BY P.id
),
FLIGHT_FLAG AS (
    SELECT DISTINCT H.point_id AS POINT_ID
    FROM {{ source('points', 'point_action_histories') }} H
    WHERE H.action_type LIKE '%FLIGHT%'
)
SELECT H.BASIS_DATE AS BASIS_DATE
     ,  CAST(H.POINT_ID AS STRING) AS POINT_ID
     ,  CAST(PT.id AS STRING) AS TEMPLATE_ID
     ,  PT.template_name AS TEMPLATE_NM
     ,  PT.point_category AS POINT_CATEGORY_NM
     ,  CAST(H.USER_ID AS STRING) AS USER_ID
     ,  CASE WHEN F.POINT_ID IS NOT NULL THEN 'Y' ELSE 'N' END AS FLIGHT_FLAG
     ,  P.point_status AS POINT_RECENT_STATUS
     ,  P.initial_amount AS INITIAL_AMOUNT
     ,  H.STATUS AS POINT_HISTORY_STATUS
     ,  H.RESVE_ID AS RESVE_ID
     ,  S.GID AS RESVE_GID
     ,  S.PRODUCT_TITLE AS RESVE_PRODUCT_TITLE
     ,  S.STANDARD_CATEGORY_LV_1_CD AS STANDARD_CATEGORY_LV_1_CD
     ,  S.STANDARD_CATEGORY_LV_1_NM AS STANDARD_CATEGORY_LV_1_NM
     ,  S.STANDARD_CATEGORY_LV_2_CD AS STANDARD_CATEGORY_LV_2_CD
     ,  S.STANDARD_CATEGORY_LV_2_NM AS STANDARD_CATEGORY_LV_2_NM
     ,  S.STANDARD_CATEGORY_LV_3_CD AS STANDARD_CATEGORY_LV_3_CD
     ,  S.STANDARD_CATEGORY_LV_3_NM AS STANDARD_CATEGORY_LV_3_NM
     ,  H.ACTION_AMOUNT AS ACTION_AMOUNT
     ,  H.AFTER_ACTION_AMOUNT AS AFTER_ACTION_AMOUNT
     ,  H.CREATED_KST_DT AS CREATED_KST_DT
     ,  H.UPDATED_KST_DT AS UPDATED_KST_DT
     ,  DATE(P.created_at) AS POINT_CREATED_DATE
     ,  P.expire_date AS EXPIRE_DT
     ,  DATE_DIFF(H.BASIS_DATE, DATE(P.created_at), DAY) AS DAYS_SINCE_POINT_CREATED_DATE
     ,  PT.publish_start_date AS TEMPLATE_START_KST_DT
     ,  PT.publish_expire_date AS TEMPLATE_EXPIRE_KST_DT
     ,  CASE WHEN E.POINT_EXIST_FLAG = 1 THEN 'Y' ELSE 'N' END AS POINT_EXIST_FLAG
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM POINT_HISTORY H
LEFT JOIN {{ source('points', 'points') }} P ON H.point_id = P.id
LEFT JOIN {{ source('points', 'point_templates') }} PT ON P.template_id = PT.id
LEFT JOIN POINT_EXIST_FLAG E ON H.POINT_ID = E.POINT_ID
LEFT JOIN FLIGHT_FLAG F ON H.POINT_ID = F.POINT_ID
LEFT JOIN {{ ref('MART_SALE_D') }} S ON H.RESVE_ID = S.RESVE_ID AND S.KIND = 1
WHERE P.deleted_at IS NULL