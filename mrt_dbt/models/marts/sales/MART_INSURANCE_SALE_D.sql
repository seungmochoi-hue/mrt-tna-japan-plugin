{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_INSURANCE_SALE_D'
    )
}}


WITH NODUP_CHUBB_POLICYLIST AS (
    SELECT T.appDate
        ,  T.registerId
        ,  T.policyUniqNo
        ,  T.insuredPlan
        ,  T.status
        ,  T.updateDate
        ,  split(T.policyStartDate, ':')[offset(0)] AS travel_start_kst_date
        ,  split(T.policyEndDate, ':')[offset(0)] AS travel_end_kst_date
        ,  T.totalPremium
        ,  T.countryCode
        ,  T.travelPlace
        ,  T.insuredNum
        ,  T.registerPid
    FROM (
             SELECT *, ROW_NUMBER() OVER (PARTITION BY P.policyUniqNo ORDER BY P.updateDate DESC) AS rn
             FROM {{ source('external', 'chubb_policylist') }} P
         ) T
    WHERE T.rn = 1
),
CHUBB_TB AS (
    SELECT DATE(C.appDate) AS create_date
         , CASE WHEN C.registerId != '' AND C.registerId IS NOT NULL AND C.registerId != 'smart_guest' THEN registerId
                WHEN C.registerId = '' OR C.registerId IS NULL OR C.registerId = 'smart_guest' THEN M.user_id END AS user_id
         , C.policyUniqNo AS id
         , C.insuredPlan AS product_title
         , CASE WHEN C.status NOT IN ('정상', '만기') THEN CAST(C.updateDate AS TIMESTAMP) END AS cancel_kst_dt
         , CASE WHEN C.status IN ('정상', '만기') THEN 'confirm' ELSE 'cancel' END AS recent_status
         , C.appDate AS created_at
         , C.travel_start_kst_date AS travel_start_kst_date
         , C.travel_end_kst_date AS travel_end_kst_date
         , CAST(SPLIT(C.totalPremium, '.')[offset(0)] AS INT64) AS total_price
         , CT.country
         , CT.city
         , CT.region
         , C.countryCode
         , C.travelPlace
         , C.insuredNum AS resve_prsnl_cnt
    FROM NODUP_CHUBB_POLICYLIST C
    LEFT JOIN {{ ref('DIM_BIZ_LOG_USER_MAPPING_REFINE') }} M ON C.registerPid = M.pid AND M.start_ts_kst <= CAST(C.appDate AS TIMESTAMP)
                                                    AND CAST(C.appDate AS TIMESTAMP) < M.end_ts_kst
    LEFT JOIN {{ ref("DIM_CITY") }} CT ON C.countryCode = CT.code
),
NODUP_AXA_RESERVATIONS AS (
    SELECT T.MRT_USER_ID
        ,  T.PARTNER_NO
        ,  T.MRT_PID
        ,  T.INSURANCE_PLAN
        ,  T.STATUS
        ,  T.CREATED_AT
        ,  T.CANCELED_AT
        ,  T.AGRM_START_DATE
        ,  T.AGRM_END_DATE
        ,  T.TOTAL_PRICE
        ,  T.INSURED_NUM
    FROM (
          SELECT *, ROW_NUMBER() OVER (PARTITION BY A.PARTNER_NO ORDER BY A.STATUS DESC) AS rn
          FROM {{ source('external', 'DW_INSURANCE_AXA_RESERVATIONS') }} A
    ) T
    WHERE T.rn = 1
      AND T.CREATED_AT IS NOT NULL
),
AXA_TB AS (
  SELECT CASE WHEN A.MRT_USER_ID IS NOT NULL AND A.MRT_USER_ID != '' AND A.MRT_USER_ID != 'SMARTGT' THEN A.MRT_USER_ID
                     WHEN A.MRT_USER_ID = '' OR A.MRT_USER_ID IS NULL OR A.MRT_USER_ID = 'SMARTGT' THEN M.USER_ID END AS USER_ID
       , A.PARTNER_NO AS ID
       , A.INSURANCE_PLAN AS PRODUCT_TITLE
       , CASE WHEN A.STATUS = '취소' AND DATE(A.CREATED_AT) = A.CANCELED_AT THEN TIMESTAMP(A.CREATED_AT)
              WHEN A.STATUS = '취소' THEN TIMESTAMP(A.CANCELED_AT) END AS CANCEL_KST_DT
       , CASE WHEN A.STATUS = '취소' THEN 'cancel' ELSE 'confirm' END AS RECENT_STATUS
       , A.CREATED_AT AS CREATED_AT
       , A.AGRM_START_DATE AS TRAVEL_START_KST_DATE
       , A.AGRM_END_DATE AS TRAVEL_END_KST_DATE
       , A.TOTAL_PRICE AS TOTAL_PRICE
       , A.INSURED_NUM AS RESVE_PRSNL_CNT
  FROM NODUP_AXA_RESERVATIONS A
  LEFT JOIN {{ ref('DIM_BIZ_LOG_USER_MAPPING_REFINE') }} M ON A.MRT_PID = M.pid AND M.start_ts_kst <= TIMESTAMP(A.CREATED_AT)
                                                  AND TIMESTAMP(A.CREATED_AT) < M.end_ts_kst
),
MERITZ_TB AS (
  SELECT DISTINCT CASE WHEN A.USER_ID IS NOT NULL AND A.USER_ID != '' AND A.USER_ID != 'smart_guest' THEN A.USER_ID
              WHEN A.USER_ID = '' OR A.USER_ID IS NULL OR A.USER_ID = 'smart_guest' THEN M.USER_ID END AS USER_ID
      ,  A.POLICY_ID AS ID
      ,  A.PLAN_CD AS PRODUCT_TITLE
      ,  TIMESTAMP(A.CANCELED_DATE) AS CANCEL_KST_DT
      ,  CASE WHEN A.STATUS = 'canceled' THEN 'cancel' ELSE 'confirm' END AS RECENT_STATUS
      ,  A.CONTRACT_DATE AS CREATED_AT
      ,  A.AGRM_START_DATE AS TRAVEL_START_KST_DATE
      ,  A.AGRM_END_DATE AS TRAVEL_END_KST_DATE
      ,  A.SALES_PRICE AS TOTAL_PRICE
      ,  1 AS RESVE_PRSNL_CNT
    FROM {{ source('external', 'DW_INSURANCE_MERITZ_RESERVATIONS') }} A
  LEFT JOIN {{ ref('DIM_BIZ_LOG_USER_MAPPING_REFINE') }} M ON A.PID = M.pid AND M.start_ts_kst <= TIMESTAMP(A.CONTRACT_DATE)
                                                  AND TIMESTAMP(A.CONTRACT_DATE) < M.end_ts_kst
),
INSURNACE AS (
      -- insurance_old
      SELECT CONCAT('o', CAST(i.int64_field_0 AS STRING)) as id
           , TIMESTAMP(i.reservation_date) as created_at
           , 'confirm' AS recent_status
           , i.reservation_date as create_date
           , NULL AS cancel_kst_dt
           , 'guest' as user_id
           , NULL AS product_title
           , 'NORMAL' AS manage
           , CAST(null AS STRING) as country
           , CAST(null AS STRING) AS city
           , CAST(null AS STRING) AS region
           , i.begin_at
           , null AS end_at
           , null as num_of_people
           , i.sales as total_price
      FROM {{ source('insurance', 'insurance_old') }} i

      UNION ALL

      -- insurance_raw
      SELECT CONCAT('n', CAST(i.id AS STRING)) AS ID
           , TIMESTAMP(i.created_at) AS created_at
           , 'confirm' AS recent_status
           , date(i.created_at) as create_date
           , NULL AS cancel_kst_dt
           , if(i.user_id='NA', 'guest', user_id) as user_id
           , CAST(null AS STRING) AS product_title
           , 'NORMAL' AS manage
           , i.country
           , CAST(null AS STRING) AS city
           , CAST(null AS STRING) AS region
           , i.begin_at
           , null AS end_at
           , i.num_of_people
           , i.total_price
      FROM{{ source('insurance', 'insurance_raw') }} i

      UNION ALL

      SELECT CONCAT('c', C.id) AS id
           , CAST(C.created_at AS TIMESTAMP) AS created_at
           , C.recent_status AS recent_status
           , C.create_date AS create_date
           , C.cancel_kst_dt AS cancel_kst_dt
           , IFNULL(C.user_id, 'guest') AS user_id
           , C.product_title AS product_title
           , 'CHUBB' AS manage
           , C.country AS country
           , C.city AS city
           , C.region AS region
           , CAST(C.travel_start_kst_date AS DATE) AS begin_at
           , CAST(C.travel_end_kst_date AS DATE) AS end_at
           , CAST(C.resve_prsnl_cnt AS INT64) AS num_of_people
           , C.total_price AS total_price
      FROM CHUBB_TB C

      UNION ALL

      SELECT CONCAT('a', A.ID) as id
           , TIMESTAMP(A.CREATED_AT) AS created_at
           , A.RECENT_STATUS AS recent_status
           , DATE(A.CREATED_AT) AS create_date
           , A.CANCEL_KST_DT AS cancel_kst_dt
           , IFNULL(A.user_id, 'guest') AS user_id
           , A.PRODUCT_TITLE AS product_title
           , 'AXA' AS manage
           , null AS country
           , null AS city
           , null AS region
           , CAST(A.TRAVEL_START_KST_DATE AS DATE) AS begin_at
           , CAST(A.TRAVEL_END_KST_DATE AS DATE) AS end_at
           , CAST(A.RESVE_PRSNL_CNT AS INT64) AS num_of_people
           , CAST(A.TOTAL_PRICE AS INT64) AS total_price
      FROM AXA_TB A

      UNION ALL

      SELECT CONCAT('m', A.ID) as id
           , TIMESTAMP(A.CREATED_AT) AS created_at
           , A.RECENT_STATUS AS recent_status
           , DATE(A.CREATED_AT) AS create_date
           , A.CANCEL_KST_DT AS cancel_kst_dt
           , IFNULL(A.user_id, 'guest') AS user_id
           , A.PRODUCT_TITLE AS product_title
           , 'MERITZ' AS manage
           , null AS country
           , null AS city
           , null AS region
           , CAST(A.TRAVEL_START_KST_DATE AS DATE) AS begin_at
           , CAST(A.TRAVEL_END_KST_DATE AS DATE) AS end_at
           , CAST(A.RESVE_PRSNL_CNT AS INT64) AS num_of_people
           , CAST(A.TOTAL_PRICE AS INT64) AS total_price
      FROM MERITZ_TB A
)
SELECT I.create_date AS BASIS_DATE
     , I.user_id AS USER_ID
     , CAST(I.id AS STRING) AS RESVE_ID
     , '100000003' AS OFFER_ID
     , 1 AS KIND
     , I.cancel_kst_dt AS CANCEL_KST_DT
     , I.recent_status AS RECENT_STATUS
     , I.product_title AS PRODUCT_TITLE
     , I.created_at AS CREATE_KST_DT
     , I.begin_at AS TRAVEL_START_KST_DATE
     , CAST(I.end_at AS DATE) AS TRAVEL_END_KST_DATE
     , 'insurance' AS RESVE_TYPE
     , manage AS MANAGE_TYPE
     , abs(I.total_price) AS SALES_PRICE
     , 'KRW' AS SALES_PRICE_CUR_TYPE
     , abs(I.total_price) AS PAID_PRICE
     , 'KRW' AS PAID_PRICE_CUR_VALUE
     , 0 AS COUPON_PRICE
     , 0 AS POINT_PRICE
     , I.country AS COUNTRY_NM
     , I.city AS CITY_NM
     , I.region AS REGION_NM
     , 0 AS CHILD_RESVE_PRSNL_CNT
     , I.num_of_people AS ADULT_RESVE_PRSNL_CNT
     , I.num_of_people AS RESVE_PRSNL_CNT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM INSURNACE I
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON I.user_id = U.USER_ID
WHERE (U.TEST_FLAG <> true OR U.USER_ID IS NULL)

UNION ALL

SELECT CAST(I.cancel_kst_dt AS DATE) AS BASIS_DATE
     , I.user_id AS USER_ID
     , CAST(I.id AS STRING) AS RESVE_ID
     , '100000003' AS OFFER_ID
     , 2 AS KIND
     , I.cancel_kst_dt AS CANCEL_KST_DT
     , I.recent_status AS RECENT_STATUS
     , I.product_title AS PRODUCT_TITLE
     , I.created_at AS CREATE_KST_DT
     , I.begin_at AS TRAVEL_START_KST_DATE
     , CAST(I.end_at AS DATE) AS TRAVEL_END_KST_DATE
     , 'insurance' AS RESVE_TYPE
     , I.manage AS MANAGE_TYPE
     , abs(I.total_price) * -1 AS SALES_PRICE
     , 'KRW' AS SALES_PRICE_CUR_TYPE
     , abs(I.total_price) * -1 AS PAID_PRICE
     , 'KRW' AS PAID_PRICE_CUR_VALUE
     , 0 AS COUPON_PRICE
     , 0 AS POINT_PRICE
     , I.country AS COUNTRY_NM
     , I.city AS CITY_NM
     , I.region AS REGION_NM
     , 0 AS CHILD_RESVE_PRSNL_CNT
     , I.num_of_people AS ADULT_RESVE_PRSNL_CNT
     , I.num_of_people AS RESVE_PRSNL_CNT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM INSURNACE I
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON I.user_id = U.USER_ID
WHERE I.cancel_kst_dt IS NOT NULL
  AND (U.TEST_FLAG <> true OR U.USER_ID IS NULL)