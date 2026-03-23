{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_AIR_SALE_D',
        partition_by={
            'field': 'BASIS_DATE',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['SALE_FORM_CD', 'KIND', 'RECENT_STATUS']
    )
}}

-- 항공 예약 모수
WITH AIR_TARGET AS (
SELECT DISTINCT T.pnr_seqno
    ,  T.cancel_yn
    ,  B.dep_airport_cd AS dep_airport_cd
    ,  T.dep_dtm
    ,  T.transit_flag
    ,  T.codeshare_flag
  FROM (
      SELECT A.pnr_seqno
    ,  A.cancel_yn
    ,  MIN(CONCAT(B.dep_date, CASE WHEN LENGTH(B.dep_tm) = 4 THEN B.dep_tm WHEN LENGTH(B.dep_tm) = 6 THEN LEFT(B.dep_tm, 4) END, '&', CAST(B.itin_no AS STRING))) AS dep_dtm
    ,  IF(SUM(IF(B.trnst_yn = 'Y', 1, 0)) > 0, 'Y', 'N') AS transit_flag
    ,  IF(SUM(LENGTH(B.cdshare_content)) > 0, 'Y', 'N') AS codeshare_flag
  FROM {{ source('air', 'TB_AIR_RV100') }} A
  LEFT JOIN {{ source('air', 'TB_AIR_RV120') }} B ON A.pnr_seqno = B.pnr_seqno
  LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON CAST(A.rsv_usr_id AS STRING) = U.USER_ID
  WHERE A.issue_status_cd = 'TKKY'
    AND (U.TEST_FLAG <> true OR U.USER_ID IS NULL)
  GROUP BY A.pnr_seqno, A.cancel_yn
  ) T
  LEFT JOIN {{ source('air', 'TB_AIR_RV120') }} B ON T.pnr_seqno = B.pnr_seqno AND T.dep_dtm = CONCAT(B.dep_date, CASE WHEN LENGTH(B.dep_tm) = 4 THEN B.dep_tm
                                                                                                     WHEN LENGTH(B.dep_tm) = 6 THEN LEFT(B.dep_tm, 4) END, '&', CAST(B.itin_no AS STRING))
),
-- 프로모션 관련
CD100 AS (
SELECT L.promtn_id
    ,  IFNULL(L.promtn_nm, LAST_VALUE(L.promtn_nm IGNORE NULLS) OVER (PARTITION BY CAST(L.promtn_id AS int) ORDER BY L.log_no ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)) AS promtn_nm
    ,  L.reg_dtm AS start_dt
    ,  LEAD (L.reg_dtm, 1, '2999-12-31 23:59:59') OVER (PARTITION BY CAST(L.promtn_id AS int) ORDER BY L.log_no) AS end_dt
    ,  L.fare_kind
    ,  IFNULL(L.adt_apply_amt_rate, 0) AS adt_apply_amt_rate
FROM {{ source('air', 'TB_PRM_CD100_LOG') }} L
WHERE log_creat_flag <> 'D'
),
-- 포인트 소모
POINT AS (
SELECT CAST(RV130.pnr_seqno AS NUMERIC) AS pnr_seqno
     ,  MIN(RV130.GCCT_POINT_AMT) AS POINT_PRICE
FROM {{ source('air', 'TB_ANO_RV130') }} RV130
WHERE RV130.pay_mth_cd = 'CCPT'
GROUP BY RV130.pnr_seqno
),
-- SPLIT SEARCH
SPLIT_SEARCH_PNR_SEQNO AS (
SELECT pnr_seqno, mastr_pnr_seqno
  FROM {{ source('air', 'TB_AIR_RV200') }}
 WHERE pnr_seqno <> mastr_pnr_seqno
),
SPLIT_SEARCH_TARGET AS (
    SELECT pnr_seqno AS pnr_seqno
    FROM SPLIT_SEARCH_PNR_SEQNO

    UNION ALL

    SELECT mastr_pnr_seqno AS pnr_seqno
    FROM SPLIT_SEARCH_PNR_SEQNO
),
AIR_TARGET_STATUS AS (
    SELECT A.issue_date AS basis_date
        ,  T.pnr_seqno
        ,  1 AS kind
        ,  T.dep_airport_cd
        ,  T.dep_dtm
        ,  T.transit_flag
        ,  T.codeshare_flag
      FROM AIR_TARGET T
      LEFT JOIN {{ source('air', 'TB_AIR_RV100') }} A ON T.pnr_seqno = A.pnr_seqno
      WHERE A.issue_date IS NOT NULL

      UNION ALL

    SELECT IFNULL(CAST(A.cancel_dtm AS DATE), A.issue_date) AS basis_date
        ,  T.pnr_seqno
        ,  2 AS kind
        ,  T.dep_airport_cd
        ,  T.dep_dtm
        ,  T.transit_flag
        ,  T.codeshare_flag
      FROM AIR_TARGET T
      LEFT JOIN {{ source('air', 'TB_AIR_RV100') }} A ON T.pnr_seqno = A.pnr_seqno
      WHERE T.cancel_yn = 'Y'
        AND (A.cancel_dtm IS NOT NULL OR A.issue_date IS NOT NULL)
),
-- 항공 패키지
AIRTEL_PACKAGE_PNR_NO AS (
    SELECT DISTINCT D.flight_reservation_no AS PNR_NO
        ,  R.reservation_no AS RESVE_ID
      FROM {{ source('orders', 'option_reservation_details') }} D
      LEFT JOIN {{ source('orders', 'option_reservations') }} O ON D.option_reservation_id = O.id
      LEFT JOIN {{ source('orders', 'reservations') }} R ON O.reservation_id = R.id
      LEFT JOIN {{ ref('DIM_USER_INFO') }} U ON R.user_id = U.USER_ID
    WHERE D.flight_reservation_no IS NOT NULL
      AND D.deleted_at IS NULL
      AND (U.TEST_FLAG <> true OR U.USER_ID IS NULL)
      AND O.option_type = 'INDIVIDUAL_FLIGHT'
      AND R.created_at >= '2025-07-16 20:10:10' -- 마이팩 오픈 시점 : 조건 없을 시 Test 데이터로 인해 PNR 중복이 발생
    QUALIFY ROW_NUMBER() OVER (PARTITION BY R.reservation_no ORDER BY D.created_at DESC) = 1
),
AIR_TYPE_DEFINITION AS (
    SELECT T.basis_date AS BASIS_DATE
        ,  T.pnr_seqno AS PNR_NO
        ,  RV110.pax_no AS PAX_NO
        ,  T.kind AS KIND
        ,  RV100.on_off_rsv_flag AS ON_OFF_RESVE_FLAG
        ,  CASE WHEN RV100.sale_form_cd = 'B2B' AND RV100.bcnc_cd = '38RB00151' THEN 'B2BCON' -- 맞춤여행 발권
                WHEN RV100.sale_form_cd = 'B2B' AND RV100.bcnc_cd = '38RB00133' THEN 'B2BDIR' -- 직판 발권
                ELSE RV100.sale_form_cd END AS SALE_FORM_CD
        ,  RV100.sale_type AS SALE_FORM_TYPE
        ,  CASE WHEN SPLIT.pnr_seqno IS NOT NULL THEN 'Y' ELSE 'N' END AS SPLIT_SEARCH_FLAG
        ,  IFNULL(TK110.reisue_flag, 'N') AS REISUE_FLAG
        ,  RV100.ind_grp_flag AS IND_GROUP_FLAG
        ,  IFNULL(RV100.ndc_rsv_yn, 'N') AS NDC_FLAG
        ,  RV100.bcnc_cd AS BRANCH_CD
        ,  T.dep_airport_cd AS DEPART_AIRPORT_CD
        ,  PARSE_TIMESTAMP('%Y-%m-%d%H%M', REGEXP_EXTRACT(T.dep_dtm, r'^(.*?)&')) AS DEPART_KST_DT
        ,  T.transit_flag AS TRANSIT_FLAG
        ,  T.codeshare_flag AS CODESHARE_FLAG
        ,  CASE WHEN TK110.reisue_flag IS NULL AND RV100.on_off_rsv_flag='OFF' THEN 'N' ELSE 'Y' END AS TK110_MATCH_FLAG
    FROM AIR_TARGET_STATUS T
    LEFT JOIN {{ source('air', 'TB_AIR_RV100') }} RV100 ON T.pnr_seqno = RV100.pnr_seqno
    LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} RV110 ON RV100.pnr_seqno = RV110.pnr_seqno AND (RV110.atc_reissue_flag = 'RI' OR RV110.atc_reissue_flag IS NULL)
    LEFT JOIN {{ source('air', 'TB_AIR_TK110') }} TK110 ON RV110.conj_tkt_bgn_no = TK110.tkt_no AND RV100.issue_date = TK110.issue_date
    LEFT JOIN SPLIT_SEARCH_TARGET SPLIT ON T.pnr_seqno = SPLIT.pnr_seqno
)
SELECT T.BASIS_DATE AS BASIS_DATE
    ,  CAST(T.PNR_NO AS NUMERIC) AS PNR_NO
    ,  RV100.rsv_no AS AIRLINE_RESVE_ID
    ,  T.PAX_NO AS PAX_NO
    ,  TK110.tkt_no AS TICKET_NO
    -- 시리즈 발권의 경우 GID를, 그 외엔 '1000006'을 넣어준다
    ,  CASE WHEN T.SALE_FORM_CD = 'B2C' AND T.ON_OFF_RESVE_FLAG = 'ON' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE = 'GRP' AND T.IND_GROUP_FLAG = 'G' AND T.NDC_FLAG = 'N' THEN CAST(RV100.gid AS STRING)
            WHEN T.SALE_FORM_CD = 'PKG' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG = 'G' AND T.NDC_FLAG = 'N' THEN CAST(RV100.gid AS STRING)
            ELSE '1000006' END AS GID
    ,  T.kind AS KIND
    ,  if(RV100.cancel_yn = 'Y', 'cancel', 'confirm') AS RECENT_STATUS
    ,  IF(T.KIND = 2, RV100.cancel_dtm, null) AS CANCEL_KST_DT
    ,  T.ON_OFF_RESVE_FLAG AS ON_OFF_RESVE_FLAG
    ,  T.REISUE_FLAG AS REISUE_FLAG
    ,  TK110.void_flag AS VOID_FLAG
    ,  T.SPLIT_SEARCH_FLAG AS SPLIT_SEARCH_FLAG
    ,  TK110.orgin_tkt_no AS BEFORE_REISUE_TICKET_NO
    ,  RV100.gds_cd AS GDS_CD
    ,  T.SALE_FORM_CD AS SALE_FORM_CD
    ,  T.SALE_FORM_TYPE AS SALE_FORM_TYPE
    -- 2024. 04. 22 SALE_AGG_TYPE 추가
    ,  CASE WHEN T.SALE_FORM_CD = 'B2C' AND T.ON_OFF_RESVE_FLAG = 'ON' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG = 'I'
                 THEN CASE WHEN T.NDC_FLAG = 'Y' THEN 'B2C_ON' -- 일반 (온라인 발권)
                           WHEN T.NDC_FLAG = 'N' THEN 'B2C_ON' END -- NDC
            -- 시리즈 항공 (온라인 발권)
            WHEN T.SALE_FORM_CD = 'B2C' AND T.ON_OFF_RESVE_FLAG = 'ON' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE = 'GRP' AND T.IND_GROUP_FLAG = 'G' AND T.NDC_FLAG = 'N'
                 THEN 'B2C_ON'
            -- 패키지 발권
            WHEN T.SALE_FORM_CD = 'PKG' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG = 'G' AND T.NDC_FLAG = 'N'
                 THEN 'PACKAGE'
            -- 대리점 발권 (개인, 그룹, ON, OFF 가능)
            WHEN T.SALE_FORM_CD = 'B2B' AND T.ON_OFF_RESVE_FLAG IN ('ON', 'OFF') AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG IN ('I', 'G') AND T.NDC_FLAG = 'N'
                 THEN 'AGENCY'
            -- 맞춤여행 발권 (개인, 그룹)
            WHEN T.SALE_FORM_CD = 'B2BON' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG IN ('I', 'G') AND T.NDC_FLAG = 'N'
                 THEN 'CUSTOMIZED'
            -- 임직원 발권 (개인, 그룹)
            WHEN T.SALE_FORM_CD = 'B2B' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG IN ('I', 'G') AND T.NDC_FLAG = 'N' AND T.BRANCH_CD = '38RB00133'
                 THEN 'EMPLOYEE'
            -- 법인기업 발권 (개인, 그룹)
            WHEN T.SALE_FORM_CD = 'BTMS' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG IN ('I', 'G') AND T.NDC_FLAG = 'N'
                 THEN 'CORPORATION'
            -- 해외제휴
            WHEN T.SALE_FORM_CD = 'B2G' AND T.ON_OFF_RESVE_FLAG = 'OFF' AND T.REISUE_FLAG = 'N'
             AND T.SALE_FORM_TYPE IS NULL AND T.IND_GROUP_FLAG = 'I' AND T.NDC_FLAG = 'N'
                 THEN 'OVERSEA_PARTNER'
            ELSE 'B2C_ON' END AS SALE_AGG_TYPE
    ,  T.BRANCH_CD AS BRANCH_CD
    ,  T.IND_GROUP_FLAG AS IND_GROUP_FLAG
    ,  CAST(RV100.rsv_usr_id AS STRING) AS USER_ID
    ,  RV100.seat_cnt AS SEAT_CNT
    ,  CD100.fare_kind AS FARE_KIND
    ,  RV110.fare_cnd_cd AS FARE_CND_CD
    ,  PRV110.pax_sex AS PAX_GEN
    ,  EXTRACT(YEAR FROM CAST(RV100.issue_date AS DATE)) - CAST(PRV110.PAX_BIRTH_YEAR AS NUMERIC) + 1 AS PAX_AGE
    ,  RV100.bplc_cd AS BPLC_CD
    ,  RV100.alpha_pnr_no AS ALPHA_PNR_NO
    ,  CAST(RV100.old_pnr_seqno AS NUMERIC) AS OLD_PNR_NO
    ,  RV100.fare_confm_yn AS FARE_CONFIRM_FLAG
    ,  RV100.fare_kind_cd AS FARE_KIND_CD
    ,  RV100.fare_kind_detail_cd AS FARE_KIND_DETAIL_CD
    ,  LOWER(RV100.dvice_type) AS PLATFORM
    ,  RV100.rsv_seat_grad AS RESVE_SEAT_GRADE
    ,  RV100.rsv_dtm AS RESVE_KST_DT
    ,  T.DEPART_KST_DT AS DEPART_KST_DT
    ,  RV100.ib_dtm AS RETURN_KST_DT
    ,  RV100.rsv_status_cd AS RESVE_STATUS_CD
    ,  RV100.pay_status_cd AS PAYMENT_STATUS_CD
    ,  RV100.auto_issue_yn AS AUTO_ISSUE_FLAG
    ,  RV100.issue_date AS ISSUE_KST_DATE
    ,  RV100.air_no_cd AS AIRLINE_CD
    ,  RV100.stock_air_cd AS STOCK_AIRLINE_CD
    ,  RV100.all_itin_content AS TOTAL_ITIN_CONTENT
    ,  CASE WHEN RV100.di_flag = 'I' AND SPLIT.pnr_seqno IS NULL THEN RV100.trip_type_cd
            WHEN RV100.di_flag = 'D' AND RV100.super_rsv_no IS NULL THEN 'OW'
            ELSE 'RT' END AS TRIP_TYPE_CD  -- SPRIT TICKET / 국내선 왕복도 RT(roundtrip)로 처리
    ,  RV100.di_flag AS DOMESTIC_INTERNATIONAL_DIV_CD
    ,  RV100.area_route_cd AS LOC_ROUTE_CD
    ,  RV100.dep_city_cd AS DEPART_CITY_CD
    ,  T.DEPART_AIRPORT_CD AS DEPART_AIRPORT_CD
    ,  RV100.dep_city_flag AS DEPART_CITY_FLAG
    ,  RV100.purps_na_cd AS ARRIVE_COUNTRY_CD
    ,  RV100.purps_city_cd AS ARRIVE_CITY_CD
    ,  RV100.arr_airport_cd AS ARRIVE_AIRPORT_CD
    ,  RV100.super_rsv_no AS SUPER_PNR_NO
    ,  T.TRANSIT_FLAG AS TRANSIT_FLAG
    ,  T.CODESHARE_FLAG AS CODESHARE_FLAG
    ,  T.NDC_FLAG AS NDC_FLAG
    ,  RV110.atc_reissue_flag AS ATC_REISSUE_FLAG
    ,  LOWER(RV100.pay_dvice_type) AS PAYMENT_PLATFORM
    ,  RV100.pay_mth_flag AS PAYMENT_METHOD_CD
    ,  IFNULL(RV110.sale_net_amt, 0) * IF(KIND=1, 1, -1) AS DISCOUNT_BEFORE_NET_PRICE
    ,  IFNULL(RV110.sale_dscnt_amt, 0)  * IF(KIND=1, 1, -1) AS DISCOUNT_AFTER_NET_PRICE
    ,  IFNULL(RV110.sale_tax_amt, 0) * IF(KIND=1, 1, -1) AS TAX_PRICE
    ,  IFNULL(RV110.sale_que_amt, 0) * IF(KIND=1, 1, -1) AS SALE_QUEUE_PRICE
    ,  IFNULL(RV110.baf, 0) * IF(KIND=1, 1, -1) AS FUEL_ADD_PRICE
    ,  IFNULL(RV110.tasf, 0) * IF(KIND=1, 1, -1) AS TASF_PRICE
    ,  IFNULL(RV110.sale_tot_amt, 0) * IF(KIND=1, 1, -1) AS SALE_TOTAL_PRICE
    ,  TK110.fee_rate AS FEE_RATE
    ,  IFNULL(CAST(TK110.fee AS NUMERIC), 0) * IF(KIND=1, 1, -1) AS FEE_PRICE
    ,  IFNULL(CAST(TK110.fee_vat AS NUMERIC), 0) * IF(KIND=1, 1, -1) AS FEE_VAT_PRICE
    ,  P.POINT_PRICE AS POINT_PRICE
    ,  RV110.promtn_id AS PROMO_ID
    ,  RV110.promtn_dscnt_fare * IF(KIND=1, -1, 1) AS PROMO_DISCOUNT_PRICE
    ,  SAFE_CAST(RV110.promtn_dscnt_rate AS float64) * -1 AS PROMO_DISCOUNT_RATE
    ,  CD100.promtn_nm AS PROMO_NM
    ,  CAST(CD100.adt_apply_amt_rate AS NUMERIC) AS ADULT_PROMO_APPLY_PRICE_RATE
    ,  RV100.MARKETING_PARTNERSHIP_CODE AS MARKETING_PARTNERSHIP_CD
    ,  CAST(RV100.MARKETING_MYLINK_ID AS STRING) AS MARKETING_LINK_ID
    ,  IF(RV110.fare_cnd_cd in ('CHD', 'INF'), 1, 0) AS CHILD_RESVE_TICKET_CNT
    ,  IF(RV110.fare_cnd_cd in ('CHD', 'INF'), 0, 1) AS ADULT_RESVE_TICKET_CNT
    ,  CAST(RV100.rsv_inwon AS NUMERIC) AS RESVE_PRSNL_CNT
    ,  RV110.conj_tkt_bgn_no AS CONNECT_TICKET_START_NO
    ,  UTM.utm_medium AS UTM_MEDIUM_VALUE
    ,  UTM.utm_source AS UTM_SOURCE_VALUE
    ,  UTM.utm_campaign AS UTM_CAMPAIGN_VALUE
    ,  UTM.utm_term AS UTM_TERM_VALUE
    ,  UTM.utm_content AS UTM_CONTENT_VALUE
    ,  T.TK110_MATCH_FLAG AS TK110_MATCH_FLAG
    ,  AP.RESVE_ID AS PACKAGE_RESVE_ID
    ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
  FROM AIR_TYPE_DEFINITION T
  LEFT JOIN {{ source('air', 'TB_AIR_RV100') }} RV100 ON T.PNR_NO = RV100.pnr_seqno
  LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} RV110 ON RV100.pnr_seqno = RV110.pnr_seqno AND T.PAX_NO = RV110.pax_no AND (RV110.atc_reissue_flag = 'RI' or RV110.atc_reissue_flag is null)
  LEFT JOIN {{ source('air', 'DIM_PREDICTIVE_USR_TB_AIR_RV110') }} PRV110 ON RV110.pnr_seqno = PRV110.PNR_SEQNO AND RV110.pax_no = PRV110.PAX_NO
  LEFT JOIN {{ source('air', 'TB_AIR_TK110') }} TK110 ON RV110.conj_tkt_bgn_no = TK110.tkt_no AND RV100.issue_date = TK110.issue_date
  LEFT JOIN CD100 CD100 ON RV110.promtn_id = CD100.promtn_id AND RV100.rsv_dtm >= CD100.start_dt AND RV100.rsv_dtm < CD100.end_dt
  LEFT JOIN POINT P ON T.PNR_NO = P.pnr_seqno
  LEFT JOIN SPLIT_SEARCH_TARGET SPLIT ON T.PNR_NO = SPLIT.pnr_seqno
  LEFT JOIN AIRTEL_PACKAGE_PNR_NO AP ON T.PNR_NO = CAST(AP.PNR_NO AS FLOAT64)
  LEFT JOIN {{ source('air', 'TB_RESERVATION_UTM_INFOS') }} UTM ON UTM.reservation_id = RV100.pnr_seqno AND UTM.reservation_type = 'PAYMENT'