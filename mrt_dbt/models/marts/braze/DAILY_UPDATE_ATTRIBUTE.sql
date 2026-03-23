{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        schema='braze',
        alias='DAILY_UPDATE_ATTRIBUTE',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day',
            'copy_partitions': true
        },
        cluster_by=['USER_ID'],
        require_partition_filter = true
    )
}}
    
WITH TARGET_USER AS (
    SELECT T.USER_ID                      AS USER_ID
         , IF(U.STATUS IN ('ACTIVE'), 'N', IF(U.STATUS IN ('NEW', 'RETURN'), 'U', 'Y')) AS EXCLUDED_USER
         , US.username AS USERNAME
         , US.email AS EMAIL
         , P.phone_number AS PHONE_NUMBER
         , MAX(T.UPDATE_KST_DT) AS UPDATE_KST_DT
    FROM (
             SELECT S.USER_ID AS USER_ID
                 ,  MAX(S.UPDATE_KST_DT) AS UPDATE_KST_DT
             FROM {{ ref('MART_SALE_D') }} S
             WHERE S.UPDATE_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00'
               AND '{{ var("logical_start_date_kst") }} 23:59:59'
               AND S.USER_ID IS NOT NULL
             GROUP BY S.USER_ID

             UNION ALL

             SELECT U.USER_ID AS USER_ID
                 ,  U.UPDATE_KST_DT AS UPDATE_KST_DT
             FROM {{ ref('DIM_USER_INFO') }} U
             WHERE (U.UPDATE_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00'
               AND '{{ var("logical_start_date_kst") }} 23:59:59')
               or (U.STATUS IN ('NEW', 'RETURN'))

             UNION ALL

             SELECT CAST(P.user_id AS STRING) AS USER_ID
                 ,  MAX(P.updated_at) AS UPDATE_KST_DT
             FROM {{ source('coupon', 'coupon_user_mapping') }} P
             WHERE P.updated_at BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00'
               AND '{{ var("logical_start_date_kst") }} 23:59:59'
               AND P.user_id IS NOT NULL
               AND P.deleted_at IS NULL
               AND P.updated_by <> 'SYSTEM_MIGRATION'
               -- D-1 이전 만료된 케이스 제외
               AND P.expire_date >= '{{ var("logical_start_date_kst") }} 00:00:00'
             GROUP BY P.user_id

             UNION ALL

             SELECT S.USER_ID AS USER_ID
                  ,  CAST(MAX(IFNULL(TRAVEL_END_KST_DATE, TRAVEL_START_KST_DATE)) AS TIMESTAMP) AS UPDATE_KST_DT
             FROM {{ ref('MART_SALE_D') }} S
             WHERE IFNULL(TRAVEL_END_KST_DATE, TRAVEL_START_KST_DATE) = '{{ var("start_date_kst") }}'
               AND S.USER_ID IS NOT NULL
             GROUP BY S.USER_ID

             UNION ALL

             SELECT CAST(R.sender_id AS STRING) AS USER_ID
                  , MAX(R.updated_at) AS UPDATE_KST_DT
             FROM {{ source('members', 'giftcard_receiver') }} R
             WHERE R.updated_at between '{{ var("logical_start_date_kst") }} 00:00:00'
               and '{{ var("logical_start_date_kst") }} 23:59:59'
               AND R.deleted_at IS NULL
             GROUP BY R.sender_id

             UNION ALL

             SELECT CAST(h.user_id AS STRING) AS USER_ID
                 ,  MAX(h.updated_at) AS UPDATE_KST_DT
             FROM {{ source('members', 'user_mileage_history') }} h
             WHERE h.updated_at between  '{{ var("logical_start_date_kst") }} 00:00:00'
               AND '{{ var("logical_start_date_kst") }} 23:59:59'
               AND h.deleted_at IS NULL
             GROUP BY h.user_id
         ) T
    LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON T.USER_ID = U.USER_ID
    LEFT JOIN {{ source('members', 'users') }} US ON T.USER_ID = CAST(US.id AS STRING)
    LEFT JOIN {{ source('members', 'user_privacies') }} P ON US.id = P.user_id
    GROUP BY T.USER_ID, IF(U.STATUS IN ('ACTIVE'), 'N', IF(U.STATUS IN ('NEW', 'RETURN'), 'U', 'Y')), US.username, US.email, P.phone_number
),
COUPON_INFO AS (
    SELECT C.user_id
         , MIN(CASE WHEN C.template_id = 506 THEN C.expire_date END) AS coupon_signup_expire
         , MIN(CASE WHEN C.template_id = 316 THEN C.expire_date END) AS coupon_review_expire
         , MIN(CASE WHEN C.template_id = 256 THEN C.expire_date END) AS coupon_first_review_expire
    FROM TARGET_USER T
    LEFT JOIN {{ source('coupon', 'coupon_user_mapping') }} C ON T.USER_ID = CAST(C.user_id AS STRING)
    WHERE C.used_at IS NULL
      AND C.use_status IN ('PUBLISHED')
      AND C.expire_date >= '{{ var("logical_start_date_kst") }} 00:00:00'
      AND T.EXCLUDED_USER IN ('U', 'N')
      AND C.user_id IS NOT NULL
    GROUP BY C.user_id
),
GIFT_INFO AS (
    SELECT CAST(S.user_id AS STRING) AS USER_ID
         , COUNT(DISTINCT R.user_id) AS GIFTCARD_SUCCESS_CNT
    FROM TARGET_USER T
    LEFT JOIN {{ source('members', 'giftcard_sender') }} S ON T.USER_ID = CAST(S.user_id AS STRING)
    LEFT JOIN {{ source('members', 'giftcard_receiver') }} R ON S.id = R.sender_id
    WHERE S.deleted_at IS NULL
      AND R.deleted_at IS NULL
    GROUP BY S.user_id
),
MILEAGE_INFO AS (
    -- 일반 유저의 경우 최근 적립된 마일리지의 합
    SELECT CAST(ug.user_id AS STRING) AS USER_ID
         , ugm.code AS GRADE_CD
         , SUM(mu.action_amount) AS CURRENT_MILEAGE_PRICE
    FROM TARGET_USER T
    LEFT JOIN {{ source('members', 'user_grade') }} ug ON T.USER_ID = CAST(ug.user_id AS STRING)
    LEFT JOIN {{ source('members', 'user_mileage_history') }} mu ON ug.user_id = mu.user_id AND mu.action_amount IS NOT NULL AND mu.deleted_at IS NULL
    LEFT JOIN {{ source('members', 'grade_meta') }} ugm ON ug.grade_meta_id = ugm.id AND ugm.deleted_at IS NULL
    WHERE mu.reserved_at between '{{ var("before_one_year") }} 00:00:00'
      and '{{ var("logical_start_date_kst") }} 23:59:59'
    AND ug.grade_meta_id = 1
    AND ug.deleted_at IS NULL
    GROUP BY ug.user_id, ugm.code

    UNION ALL

    -- 사모아 유저의 경우 등급 변경 후 만료 전까지 마일리지의 합
    SELECT CAST(ug.user_id AS STRING) AS USER_ID
         , ugm.code AS GRADE_CD
         , SUM(action_amount) AS CURRENT_MILEAGE_PRICE
    FROM TARGET_USER T
    LEFT JOIN {{ source('members', 'user_grade') }} ug ON T.USER_ID = CAST(ug.user_id AS STRING)
    LEFT JOIN {{ source('members', 'user_mileage_history') }} mu ON ug.user_id = mu.user_id AND mu.action_amount IS NOT NULL AND mu.deleted_at IS NULL
    LEFT JOIN {{ source('members', 'grade_meta') }} ugm ON ug.grade_meta_id = ugm.id AND ugm.deleted_at IS NULL
    WHERE ug.grade_meta_id = 2
      AND ug.deleted_at IS NULL
      AND mu.reserved_at between ug.start_at AND ug.end_at
    GROUP BY ug.user_id, ugm.code
)
SELECT DATE('{{ var("logical_start_date_kst") }}') AS BASIS_DT
     , T.USER_ID
     , T.EXCLUDED_USER
     , M.JOIN_KST_DT
     , T.username                   AS USERNAME
     , M.MRT_STAFF_FLAG
     , M.REP_AGE
     , T.email                      AS EMAIL
     , T.phone_number               AS PHONE_NUMBER
     , M.APP_INSTALL_FLAG

     , M.SMS_RECV_AGREE
     , M.MAIL_RECV_AGREE
     , M.PUSH_RECV_AGREE
     , M.PHONE_VALID_FLAG

     , M.DORMANT_FLAG
     , M.DORMANT_KST_DT
     , M.LEAVE_FLAG
     , M.LEAVE_KST_DT

     , M.OWN_COUPON_NO
     , M.OWN_COUPON_CNT
     , C.coupon_signup_expire       AS COUPON_SIGNUP_EXPIRE_DATE
     , C.coupon_review_expire       AS COUPON_REVIEW_EXPIRE_DATE
     , C.coupon_first_review_expire AS COUPON_FIRST_REVIEW_EXPIRE_DATE
     , M.TOTAL_BUY_CNT
     , M.TOTAL_BUY_PRICE
     , M.FIRST_BUY_KST_DT
     , M.FIRST_BUY_TYPE

     , M.RECENT_TRAVEL_RESVE_ID
     , M.RECENT_TRAVEL_PRODUCT_ID
     , M.RECENT_TRAVEL_MRT_TYPE
     , M.RECENT_TRAVEL_DEPART_KST_DT
     , M.RECENT_TRAVEL_ARRIVE_KST_DT
     , M.RECENT_TRAVEL_RESVE_PURPOSE
     , M.RECENT_TRAVEL_CITY
     , M.RECENT_TRAVEL_COUNTRY
     , RT.STANDARD_CATEGORY_LV_1_CD AS RECENT_TRAVEL_STANDARD_CATEGORY_LV_1_CD
     , RT.STANDARD_CATEGORY_LV_2_CD AS RECENT_TRAVEL_STANDARD_CATEGORY_LV_2_CD
     , RT.STANDARD_CATEGORY_LV_3_CD AS RECENT_TRAVEL_STANDARD_CATEGORY_LV_3_CD

     , M.EXPT_TRAVEL_RESVE_ID
     , M.EXPT_TRAVEL_PRODUCT_ID
     , M.EXPT_TRAVEL_MRT_TYPE
     , M.EXPT_TRAVEL_DEPART_KST_DT
     , M.EXPT_TRAVEL_ARRIVE_KST_DT
     , M.EXPT_TRAVEL_RESVE_PURPOSE
     , M.EXPT_TRAVEL_CITY
     , M.EXPT_TRAVEL_COUNTRY
     , ET.STANDARD_CATEGORY_LV_1_CD AS EXPT_TRAVEL_STANDARD_CATEGORY_LV_1_CD
     , ET.STANDARD_CATEGORY_LV_2_CD AS EXPT_TRAVEL_STANDARD_CATEGORY_LV_2_CD
     , ET.STANDARD_CATEGORY_LV_3_CD AS EXPT_TRAVEL_STANDARD_CATEGORY_LV_3_CD

     , M.EXPT_FLIGHT_TRAVEL_RESVE_ID
     , M.EXPT_FLIGHT_TRAVEL_PRODUCT_ID
     , M.EXPT_FLIGHT_TRAVEL_MRT_TYPE
     , CD140.AIR_CD AS EXPT_FLIGHT_TRAVEL_AIRLINE_CD
     , M.EXPT_FLIGHT_TRAVEL_DEPART_KST_DATE
     , M.EXPT_FLIGHT_TRAVEL_ARRIVE_KST_DT AS EXPT_FLIGHT_TRAVEL_ARRIVE_KST_DATE
     , F.FLIGHT_PURPOSE_TYPE AS EXPT_FLIGHT_TRAVEL_RESVE_PURPOSE
     , M.EXPT_FLIGHT_TRAVEL_CITY
     , M.EXPT_FLIGHT_TRAVEL_COUNTRY
     , F.CREATE_KST_DATE AS EXPT_FLIGHT_TRAVEL_RESVE_DATE
     , RV120.DEP_AIRPORT_CD AS EXPT_FLIGHT_TRAVEL_DEPART_AIRPORT
     , F.CITY_CD AS EXPT_FLIGHT_TRAVEL_ARRIVE_AIRPORT
     , CASE WHEN RV120.cabin_seat_grad IN ('C', 'F') THEN '비즈니스'
            WHEN RV120.cabin_seat_grad IN ('S', 'E') THEN '특가'
            WHEN RV120.pnr_seqno is not null THEN '일반' END AS EXPT_FLIGHT_SEAT_GRAD
     , CAST(LEAST(EXTRACT(YEAR FROM CURRENT_DATE) - CAST(M.REP_AGE AS int), 65) AS STRING) AS EXPT_FLIGHT_USER_AGE
     , M.USER_GENDER_NM AS EXPT_FLIGHT_USER_GENDER

     , M.EXPT_STAY_TRAVEL_RESVE_ID
     , M.EXPT_STAY_TRAVEL_PRODUCT_ID
     , M.EXPT_STAY_TRAVEL_MRT_TYPE
     , M.EXPT_STAY_TRAVEL_DEPART_KST_DATE
     , M.EXPT_STAY_TRAVEL_ARRIVE_KST_DT AS EXPT_STAY_TRAVEL_ARRIVE_KST_DATE
     , M.EXPT_STAY_TRAVEL_RESVE_PURPOSE
     , M.EXPT_STAY_TRAVEL_CITY
     , M.EXPT_STAY_TRAVEL_COUNTRY
     , S.HOTEL_AFFILIATE_NM
     , S.CREATE_KST_DATE AS EXPT_STAY_TRAVEL_RESVE_DATE
     , S.STANDARD_CATEGORY_LV_1_CD AS EXPT_STAY_STANDARD_CATEGORY_LV_1_CD
     , S.STANDARD_CATEGORY_LV_1_NM AS EXPT_STAY_STANDARD_CATEGORY_LV_1_NM
     , S.STANDARD_CATEGORY_LV_2_CD AS EXPT_STAY_STANDARD_CATEGORY_LV_2_CD
     , S.STANDARD_CATEGORY_LV_2_NM AS EXPT_STAY_STANDARD_CATEGORY_LV_2_NM
     , S.STANDARD_CATEGORY_LV_3_CD AS EXPT_STAY_STANDARD_CATEGORY_LV_3_CD
     , S.STANDARD_CATEGORY_LV_3_NM AS EXPT_STAY_STANDARD_CATEGORY_LV_3_NM

     , M.EXPT_RIDE_TRAVEL_RESVE_ID
     , M.EXPT_RIDE_TRAVEL_PRODUCT_ID
     , M.EXPT_RIDE_TRAVEL_MRT_TYPE
     , M.EXPT_RIDE_TRAVEL_DEPART_KST_DATE
     , M.EXPT_RIDE_TRAVEL_ARRIVE_KST_DT AS EXPT_RIDE_TRAVEL_ARRIVE_KST_DATE
     , M.EXPT_RIDE_TRAVEL_RESVE_PURPOSE
     , M.EXPT_RIDE_TRAVEL_CITY
     , M.EXPT_RIDE_TRAVEL_COUNTRY
     , R.CREATE_KST_DATE AS EXPT_RIDE_TRAVEL_RESVE_DATE
     , R.STANDARD_CATEGORY_LV_1_CD AS EXPT_RIDE_STANDARD_CATEGORY_LV_1_CD
     , R.STANDARD_CATEGORY_LV_1_NM AS EXPT_RIDE_STANDARD_CATEGORY_LV_1_NM
     , R.STANDARD_CATEGORY_LV_2_CD AS EXPT_RIDE_STANDARD_CATEGORY_LV_2_CD
     , R.STANDARD_CATEGORY_LV_2_NM AS EXPT_RIDE_STANDARD_CATEGORY_LV_2_NM
     , R.STANDARD_CATEGORY_LV_3_CD AS EXPT_RIDE_STANDARD_CATEGORY_LV_3_CD
     , R.STANDARD_CATEGORY_LV_3_NM AS EXPT_RIDE_STANDARD_CATEGORY_LV_3_NM

     , M.EXPT_TNA_TRAVEL_RESVE_ID
     , M.EXPT_TNA_TRAVEL_PRODUCT_ID
     , M.EXPT_TNA_TRAVEL_MRT_TYPE
     , M.EXPT_TNA_TRAVEL_DEPART_KST_DATE
     , M.EXPT_TNA_TRAVEL_ARRIVE_KST_DT AS EXPT_TNA_TRAVEL_ARRIVE_KST_DATE
     , M.EXPT_TNA_TRAVEL_RESVE_PURPOSE
     , M.EXPT_TNA_TRAVEL_CITY
     , M.EXPT_TNA_TRAVEL_COUNTRY
     , TN.CREATE_KST_DATE AS EXPT_TNA_TRAVEL_RESVE_DATE
     , TN.STANDARD_CATEGORY_LV_1_CD AS EXPT_TNA_STANDARD_CATEGORY_LV_1_CD
     , TN.STANDARD_CATEGORY_LV_1_NM AS EXPT_TNA_STANDARD_CATEGORY_LV_1_NM
     , TN.STANDARD_CATEGORY_LV_2_CD AS EXPT_TNA_STANDARD_CATEGORY_LV_2_CD
     , TN.STANDARD_CATEGORY_LV_2_NM AS EXPT_TNA_STANDARD_CATEGORY_LV_2_NM
     , TN.STANDARD_CATEGORY_LV_3_CD AS EXPT_TNA_STANDARD_CATEGORY_LV_3_CD
     , TN.STANDARD_CATEGORY_LV_3_NM AS EXPT_TNA_STANDARD_CATEGORY_LV_3_NM

     , M.EXPT_ETC_TRAVEL_RESVE_ID
     , M.EXPT_ETC_TRAVEL_PRODUCT_ID
     , M.EXPT_ETC_TRAVEL_MRT_TYPE
     , M.EXPT_ETC_TRAVEL_DEPART_KST_DATE
     , M.EXPT_ETC_TRAVEL_ARRIVE_KST_DT AS EXPT_ETC_TRAVEL_ARRIVE_KST_DATE
     , M.EXPT_ETC_TRAVEL_RESVE_PURPOSE
     , M.EXPT_ETC_TRAVEL_CITY
     , M.EXPT_ETC_TRAVEL_COUNTRY
     , E.CREATE_KST_DATE AS EXPT_ETC_TRAVEL_RESVE_DATE
     , E.STANDARD_CATEGORY_LV_1_CD AS EXPT_ETC_STANDARD_CATEGORY_LV_1_CD
     , E.STANDARD_CATEGORY_LV_1_NM AS EXPT_ETC_STANDARD_CATEGORY_LV_1_NM
     , E.STANDARD_CATEGORY_LV_2_CD AS EXPT_ETC_STANDARD_CATEGORY_LV_2_CD
     , E.STANDARD_CATEGORY_LV_2_NM AS EXPT_ETC_STANDARD_CATEGORY_LV_2_NM
     , E.STANDARD_CATEGORY_LV_3_CD AS EXPT_ETC_STANDARD_CATEGORY_LV_3_CD
     , E.STANDARD_CATEGORY_LV_3_NM AS EXPT_ETC_STANDARD_CATEGORY_LV_3_NM

     , G.GIFTCARD_SUCCESS_CNT

     , L.GRADE_CD
     , L.CURRENT_MILEAGE_PRICE

     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM TARGET_USER T
LEFT JOIN {{ ref('MART_USER_D') }} M on T.USER_ID = M.USER_ID
LEFT JOIN COUPON_INFO C ON T.USER_ID = CAST (C.user_id AS STRING)
LEFT JOIN GIFT_INFO G ON T.USER_ID = G.USER_ID
LEFT JOIN MILEAGE_INFO L ON T.USER_ID = L.USER_ID
LEFT JOIN {{ ref('MART_SALE_D') }} F on M.EXPT_FLIGHT_TRAVEL_RESVE_ID = F.RESVE_ID AND F.KIND = 1
LEFT JOIN {{ source('air', 'TB_AIR_RV120') }} RV120 on F.RESVE_ID = CONCAT('f', CAST(RV120.pnr_seqno AS INT)) AND RV120.ITIN_NO = 1.0
LEFT JOIN {{ source('air', 'TB_COM_CD140') }} CD140 on F.PROVIDER_CD = CD140.AIR_NO_CD AND CD140.AIR_NO_CD <> 'NULL' AND CD140.AIR_NO_CD IS NOT NULL
LEFT JOIN {{ ref('MART_SALE_D') }} S on M.EXPT_STAY_TRAVEL_RESVE_ID = S.RESVE_ID AND S.KIND = 1
LEFT JOIN {{ ref('MART_SALE_D') }} R on M.EXPT_RIDE_TRAVEL_RESVE_ID = R.RESVE_ID AND R.KIND = 1
LEFT JOIN {{ ref('MART_SALE_D') }} TN on M.EXPT_TNA_TRAVEL_RESVE_ID = TN.RESVE_ID AND TN.KIND = 1
LEFT JOIN {{ ref('MART_SALE_D') }} E on M.EXPT_ETC_TRAVEL_RESVE_ID = E.RESVE_ID AND E.KIND = 1
LEFT JOIN {{ ref('MART_SALE_D') }} RT on M.RECENT_TRAVEL_RESVE_ID = RT.RESVE_ID AND RT.KIND = 1
LEFT JOIN {{ ref('MART_SALE_D') }} ET on M.EXPT_TRAVEL_RESVE_ID = ET.RESVE_ID AND ET.KIND = 1
WHERE M.USER_ID IS NOT NULL