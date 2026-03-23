{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_OVERSEAS_RENTALCAR_SALE_D'
    )
}}


WITH TRIMO_DATA AS (
SELECT R.res_id
     , R.created_date AS created_at
     , CASE WHEN R.status = 'booked' THEN 'confirm' ELSE 'cancel' END AS status
     , DATE(R.created_date) AS created_date
     , R.canceled_date AS cancel_kst_dt
     , IFNULL(M.user_id, 'guest') AS user_id
     , R.pickup_city
     , D.code
     , D.city
     , D.country
     , D.region
     , DATE(R.pickup_datetime) AS begin_at
     , DATE(R.return_datetime) AS end_at
     , R.total_amount
FROM {{ source('external', 'DW_MRT_TRIMO_RESERVATION') }} R
LEFT JOIN {{ ref('DIM_BIZ_LOG_USER_MAPPING_REFINE') }} M ON TIMESTAMP(R.created_date) >= M.start_ts_kst
                                               AND TIMESTAMP(R.created_date) < M.end_ts_kst
                                               AND json_value(R.agent_data, '$.pid') = M.pid
LEFT JOIN {{ ref('ST_DIM_CITY') }} D ON R.pickup_city = D.code
)
SELECT CASE WHEN C.IDX = 2 THEN CAST(PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.cancel_kst_dt) AS DATE)
            ELSE R.created_date END AS BASIS_DATE
     , R.user_id AS USER_ID
     , 'CAR-' || FORMAT_TIMESTAMP('%Y%m%d', R.created_date) || '-' || R.res_id AS RESVE_ID
     ,  R.res_id AS ORDER_ID
     , '100000004' AS PRODUCT_ID
     , CAST(NULL AS STRING) AS GID
     , CAST(NULL AS STRING) AS GPID
     , CASE WHEN C.IDX IS NOT NULL THEN C.IDX
            ELSE 1 END AS KIND
     , R.status AS RECENT_STATUS
     , PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.cancel_kst_dt) AS CANCEL_KST_DT
     , 'TRIMO' AS COMPANY_NM
     , 'transport' AS PRODUCT_TYPE
     , 'RENTER_CAR' AS CATEGORY_NM
     , PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.created_at) AS CREATE_KST_DT
     , IFNULL(PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.cancel_kst_dt), PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.created_at)) AS UPDATE_KST_DT
     , CAST(NULL AS STRING) AS PLATFORM
     , PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.created_at) AS RESVE_PAID_KST_DT
     , PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', R.created_at) AS RESVE_CONFIRM_KST_DT
     , R.begin_at AS TRAVEL_START_KST_DATE
     , DATE_DIFF(R.end_at, R.begin_at, DAY) AS TRAVEL_DURATION_VALUE
     , R.end_at AS TRAVEL_END_KST_DATE
     , CAST(NULL AS STRING) AS PG_NM
     , CAST(NULL AS STRING) AS PARTNER_ID
     , R.city AS CITY_CD
     , CAST(CASE WHEN C.IDX = 2 THEN -1 * R.total_amount
                 ELSE R.total_amount END AS INT64) AS SALES_PRICE
     , CAST(NULL AS float64) AS COMMISSION_RATE
     , CAST(NULL AS STRING) AS PAYMENT_METHOD_VALUE
     , CAST(CASE WHEN C.IDX = 2 THEN -1 * R.total_amount
                 ELSE R.total_amount END AS INT64) AS PAID_PRICE
     , 0 AS COUPON_PRICE
     , 0 AS POINT_PRICE
     , CAST(NULL AS INT64) AS COMMISSION_PRICE
     , 0 AS CHILD_RESVE_PRSNL_CNT
     , 1 AS ADULT_RESVE_PRSNL_CNT
     , 1 AS RESVE_PRSNL_CNT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM TRIMO_DATA R
LEFT JOIN (SELECT 1 AS idx UNION ALL SELECT 2 AS idx) C ON R.CANCEL_KST_DT IS NOT NULL
LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON R.user_id = U.USER_ID
WHERE (U.TEST_FLAG <> true OR U.USER_ID IS NULL)