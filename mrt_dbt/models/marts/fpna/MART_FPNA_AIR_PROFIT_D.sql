{{
    config(
        materialized='table',
        schema='edw_fpna',
        alias='MART_FPNA_AIR_PROFIT_D'
    )
}}


WITH AIR_PNR_INFO AS (
    SELECT DISTINCT CONCAT('f', a.PNR_NO)                                                                AS RESVE_ID
         , a.STOCK_AIRLINE_CD
         , a.RESVE_PRSNL_CNT
         , a.DOMESTIC_INTERNATIONAL_DIV_CD
         , a.DEPART_CITY_CD
         , DEPART_CITY.CITY_NM                                                                         AS DEPART_CITY_NM       -- 출발도시
         , DEPART_CITY.COUNTRY_NM                                                                      AS DEPART_COUNTRY_NM    -- 출발국가
         , DEPART_CITY.REGION_NM                                                                       AS DEPART_REGION_NM     -- 출발지역
         , a.ARRIVE_CITY_CD
         , ARRIVE_CITY.CITY_NM                                                                         AS ARRIVE_CITY_NM       -- 도착도시
         , ARRIVE_CITY.COUNTRY_NM                                                                      AS ARRIVE_COUNTRY_NM    -- 도착국가
         , ARRIVE_CITY.REGION_NM                                                                       AS ARRIVE_REGION_NM     -- 도착지역
         , a.TRIP_TYPE_CD
         , a.GDS_CD
    FROM {{ ref('MART_AIR_PNR_SALE_D') }} a
    LEFT JOIN {{ ref('DIM_AIRPORT_CITY_MAPPING') }} DEPART_CITY ON DEPART_CITY.AIRPORT_CODE = a.DEPART_CITY_CD
    LEFT JOIN {{ ref('DIM_AIRPORT_CITY_MAPPING') }} ARRIVE_CITY ON ARRIVE_CITY.AIRPORT_CODE = a.ARRIVE_CITY_CD
    WHERE a.KIND = 1
),
RSV_CANCEL AS (
    SELECT RESVE_ID                                                                                        AS RESVE_ID
         , DATE(CANCEL_KST_DT)                                                                             AS CANCEL_DATE
    FROM {{ ref('MART_SALE_D') }}
    WHERE KIND = 2
),
AIR_SALE_INFO AS (
    WITH MAX_MONTH_DOMESTIC AS (SELECT MAX(TRAVEL_DATE) AS MAX_MONTH FROM {{ ref('FPNA_AIR_DOMESTIC_VI') }}),
         MAX_MONTH_INTERNATIONAL AS (SELECT MAX(TRAVEL_DATE) AS MAX_MONTH FROM {{ ref('FPNA_AIR_INTERNATIONAL_VI') }})
    SELECT CONCAT('f', a.PNR_NO)                                                                          AS RESVE_ID
         , SUM(a.SALE_TOTAL_PRICE)                                                                        AS SALES_KRW_PRICE
         , SUM(a.DISCOUNT_BEFORE_NET_PRICE)                                                               AS DISCOUNT_BEFORE_NET_PRICE
         , SUM(a.DISCOUNT_AFTER_NET_PRICE)                                                                AS DISCOUNT_AFTER_NET_PRICE
           --항공사 VI
         , SUM(IFNULL(CASE  WHEN a.DOMESTIC_INTERNATIONAL_DIV_CD = 'D' AND dvi.ACTUAL_VI_RATE IS NOT NULL
                                    THEN dvi.ACTUAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
                            WHEN a.DOMESTIC_INTERNATIONAL_DIV_CD = 'D' AND dvi.ACTUAL_VI_RATE IS NULL
                                    THEN dvi_est.ACTUAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
                            WHEN a.DOMESTIC_INTERNATIONAL_DIV_CD = 'I' AND ivi.ACTUAL_VI_RATE IS NOT NULL
                                    THEN ivi.ACTUAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
                            WHEN a.DOMESTIC_INTERNATIONAL_DIV_CD = 'I' AND ivi.ACTUAL_VI_RATE IS NULL
                                    THEN ivi_est.ACTUAL_VI_RATE * a.DISCOUNT_AFTER_NET_PRICE
                            ELSE 0 END,0))                                                                                      AS VI_COMMISSION
    FROM {{ ref('MART_AIR_SALE_D') }} a /* 메인 테이블 */
    LEFT JOIN {{ ref('FPNA_AIR_DOMESTIC_VI') }} dvi /* 국내선 VI 맵핑 */
              ON DATE_TRUNC(DATE(a.DEPART_KST_DT), MONTH) = DATE_TRUNC(dvi.TRAVEL_DATE, MONTH)
                  AND a.STOCK_AIRLINE_CD = dvi.STOCK_AIRLINE_CD
                  AND a.DOMESTIC_INTERNATIONAL_DIV_CD = 'D'
    LEFT JOIN {{ ref('FPNA_AIR_INTERNATIONAL_VI') }} ivi /* 국제선 VI 맵핑 */
              ON DATE_TRUNC(DATE(a.DEPART_KST_DT), MONTH) = DATE_TRUNC(ivi.TRAVEL_DATE, MONTH)
                  AND a.STOCK_AIRLINE_CD = ivi.STOCK_AIRLINE_CD
                  AND a.DOMESTIC_INTERNATIONAL_DIV_CD = 'I'
    LEFT JOIN MAX_MONTH_DOMESTIC ON DATE_TRUNC(DATE(a.DEPART_KST_DT), MONTH) > MAX_MONTH_DOMESTIC.MAX_MONTH
    LEFT JOIN MAX_MONTH_INTERNATIONAL ON DATE_TRUNC(DATE(a.DEPART_KST_DT), MONTH) > MAX_MONTH_INTERNATIONAL.MAX_MONTH
    LEFT JOIN {{ ref('FPNA_AIR_DOMESTIC_VI') }} dvi_est /* 국내선 VI 맵핑 - NULL 값일 경우, 참조값*/
              ON a.STOCK_AIRLINE_CD = dvi_est.STOCK_AIRLINE_CD
                  AND MAX_MONTH_DOMESTIC.MAX_MONTH = DATE_TRUNC(dvi_est.TRAVEL_DATE, MONTH)
                  AND a.DOMESTIC_INTERNATIONAL_DIV_CD = 'D'
    LEFT JOIN {{ ref('FPNA_AIR_INTERNATIONAL_VI') }} ivi_est /* 국제선 VI 맵핑 - NULL 값일 경우, 참조값*/
              ON a.STOCK_AIRLINE_CD = ivi_est.STOCK_AIRLINE_CD
                  AND MAX_MONTH_INTERNATIONAL.MAX_MONTH = DATE_TRUNC(ivi_est.TRAVEL_DATE, MONTH)
                  AND a.DOMESTIC_INTERNATIONAL_DIV_CD = 'I'
    WHERE a.KIND = 1
      AND a.REISUE_FLAG <> 'R'
    GROUP BY a.PNR_NO
),
CARD_CASH_BACK AS (
    SELECT CONCAT('f', t1.pnr_seqno)    AS RESVE_ID
         , SUM(t3.cash_back)             AS CARD_CASH_BACK_PRICE
     FROM {{ source('air', 'TB_AIR_RV100') }} t1
     LEFT JOIN {{ source('air', 'TB_ANO_RV130') }} t2 --결제요청 테이블도 pax 기준
                   ON t1.PNR_SEQNO = t2.PNR_SEQNO
     LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} t3 ON t3.pnr_seqno = t2.pnr_seqno AND t2.pay_rq_seqno = t3.pax_no --더블링 방지 조건
                                             AND (t3.atc_reissue_flag = 'RI' OR t3.atc_reissue_flag IS NULL)
    WHERE t1.issue_status_cd = 'TKKY' AND t1.on_off_rsv_flag = 'ON'
      AND t1.CANCEL_YN IN ('N')
      AND t3.cash_back IS NOT NULL
    GROUP BY t1.pnr_seqno
),
NPAY AS (
    SELECT CONCAT('f', t1.pnr_seqno)              AS RESVE_ID
         , COUNT(DISTINCT t1.pnr_seqno) * 750     AS NPAY_PRICE
    FROM {{ source('air', 'TB_AIR_RV100') }} t1
    LEFT JOIN {{ source('air', 'TB_ANO_RV130') }} t3 ON t3.pnr_seqno = t1.pnr_seqno
    WHERE t1.issue_status_cd = 'TKKY'
      AND t1.on_off_rsv_flag = 'ON'
      AND t1.di_flag = 'D'
      AND t1.BPLC_CD = 'N00001'
      AND t1.cancel_yn = 'N'
      AND t3.pay_mth_cd = 'CCNP'
    GROUP BY t1.pnr_seqno
),
DISCOUNT_AMOUNT AS (
    WITH FEE_INFO AS (
        SELECT DISTINCT a.pnr_seqno                                     AS pnr_seqno
             , r.fee_seqno                                               AS pax_no
             , CASE WHEN r.fee_cd = '1' THEN r.fee END                  AS repurchase_fee
             , CASE WHEN r.fee_cd = '4' THEN r.fee END                  AS refund_fee
             , CASE WHEN r.fee_cd NOT IN ('1', '4') THEN r.fee END      AS other_fee
             , r.air_fee                                                 AS air_fee_etc
        FROM {{ source('air', 'TB_VOF_AC110') }} a
        LEFT JOIN {{ source('air', 'TB_ANO_RV310') }} r ON a.pnr_seqno = r.pnr_seqno
        LEFT JOIN {{ source('air', 'TB_AIR_RV100') }} i ON i.pnr_seqno = a.pnr_seqno AND a.data_flag = 'AIRCM'
        WHERE a.deposit_date = DATE(r.reg_dtm)
    )
    SELECT CONCAT('f', t1.PNR_SEQNO)                                      AS RESVE_ID
         , SUM((-1) * (t2.PROMTN_DSCNT_FARE + t2.add_promtn_dscnt_fare)) AS DISCOUNT_AMT
    FROM {{ source('air', 'TB_AIR_RV100') }} t1
    LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} t2 ON t2.PNR_SEQNO = t1.PNR_SEQNO AND (t2.atc_reissue_flag = 'RI' OR t2.atc_reissue_flag IS NULL)
    LEFT JOIN FEE_INFO fi ON t1.PNR_SEQNO = fi.pnr_seqno AND t2.pax_no = fi.pax_no
    WHERE t1.ISSUE_STATUS_CD = 'TKKY'
      AND t1.CANCEL_YN <> 'Y'
    GROUP BY t1.PNR_SEQNO
),
BSP_COM AS (
    SELECT CONCAT('f', r.PNR_SEQNO)                                         AS RESVE_ID
         , SUM(CASE WHEN r.CANCEL_YN = 'N' THEN (tk.FEE + tk.FEE_VAT) END) AS validCOMM
    FROM {{ source('air', 'TB_AIR_RV100') }} r
    LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} f ON r.PNR_SEQNO = f.PNR_SEQNO AND (f.atc_reissue_flag = 'RI' OR f.atc_reissue_flag IS NULL)
    INNER JOIN {{ source('air', 'TB_AIR_TK110') }} tk ON f.PNR_SEQNO = tk.PNR_SEQNO AND f.PAX_NO = tk.PAX_NO
    WHERE r.ON_OFF_RSV_FLAG <> 'OFF'
      AND r.DI_FLAG = 'I'
      AND r.ISSUE_STATUS_CD = 'TKKY'
    GROUP BY r.PNR_SEQNO
),
I_TASF AS (
    SELECT t.resve_id
         , SUM(CASE WHEN fee_cd = 'TASF' THEN t.fee ELSE 0 END)    AS I_TASF_COMMISSION
         , SUM(CASE WHEN fee_cd = '환불' THEN t.fee ELSE 0 END)    AS I_CANCEL_COMMISSION
         , SUM(CASE WHEN fee_cd = '재발행' THEN t.fee ELSE 0 END)  AS I_REISSUE_COMMISSION
    FROM (
        -- tasf
        SELECT CONCAT('f', t1.pnr_seqno) AS resve_id
             , 'TASF'                     AS fee_cd
             , SUM(t2.TASF)               AS fee
        FROM {{ source('air', 'TB_AIR_RV100') }} t1
        LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} t2 ON t1.pnr_seqno = t2.pnr_seqno AND (t2.atc_reissue_flag = 'RI' OR t2.atc_reissue_flag IS NULL)
        LEFT JOIN {{ source('air', 'TB_ANO_RV410') }} t3 ON t1.pnr_seqno = t3.pnr_seqno
        WHERE t1.issue_date >= '2022-09-27' -- 22년 9월 27일 이후로 TASF / 취소 / 재발행 수수료로 구분이 될 수 있게 변경
          AND t1.PNR_SEAT_STATUS_CD IN ('RK', 'RX') -- 좌석 : RK(확약) RX(취소)
          AND t1.issue_status_cd = 'TKKY'           --발권완료
          AND t1.ON_OFF_RSV_FLAG = 'ON'
          AND t1.DI_FLAG = 'I'
        GROUP BY t1.pnr_seqno

        UNION ALL

        -- 발권일 기준 환불 수수료
        SELECT CONCAT('f', t1.pnr_seqno) AS resve_id
             , CASE WHEN r.fee_cd = '1' THEN '재발행'
                    WHEN r.fee_cd = '4' THEN '환불' END AS fee_cd
             , SUM(r.fee)                 AS fee
        FROM {{ source('air', 'TB_AIR_RV100') }} t1
        LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} t2 ON t1.pnr_seqno = t2.pnr_seqno AND (t2.atc_reissue_flag = 'RI' OR t2.atc_reissue_flag IS NULL)
        LEFT JOIN {{ source('air', 'TB_ANO_RV310') }} r ON t2.pnr_seqno = r.pnr_seqno
        LEFT JOIN {{ source('air', 'TB_ANO_RV410') }} t3 ON t1.pnr_seqno = t3.pnr_seqno
        WHERE r.fee_cd IN ('1', '4')
          AND t1.DI_FLAG = 'I'
          AND t1.PNR_SEAT_STATUS_CD = 'RK' -- 좌석 : 확약
          AND t1.issue_status_cd = 'TKKY'  --발권완료
        GROUP BY t1.pnr_seqno, r.fee_cd
    ) t
    GROUP BY t.resve_id
),
D_TASF AS (
    SELECT CONCAT('f', t1.pnr_seqno)    AS RESVE_ID
         , SUM(t2.TASF)                  AS D_TASF_COMMISSION
    FROM {{ source('air', 'TB_AIR_RV100') }} t1
    LEFT JOIN {{ source('air', 'TB_AIR_RV110') }} t2 ON t1.pnr_seqno = t2.pnr_seqno AND (t2.atc_reissue_flag = 'RI' OR t2.atc_reissue_flag IS NULL)
    WHERE t1.PNR_SEAT_STATUS_CD IN ('RK','RX')  -- 좌석 : RK(확약) RX(취소)
      AND t1.issue_status_cd = 'TKKY'  --발권완료
      AND t1.ON_OFF_RSV_FLAG = 'ON'
      AND t1.DI_FLAG = 'D'
    GROUP BY t1.pnr_seqno
),
GDS_COM_INFO AS (
    WITH GDS_INFO AS (
            SELECT G.basis_date
                 , G.airline_type
                 , (G.SEG_TYPE_USD_AMOUNT * G.CURRENCY_RATE) AS gds_com_krw
              FROM {{ ref('FPNA_AIR_GDS_INFO') }} G
    )
    SELECT CONCAT('f', t1.PNR_SEQNO) AS resve_id
         , SUM((SAFE_DIVIDE(LENGTH(REPLACE(REPLACE(t1.ALL_ITIN_CONTENT,'-',''),'/','')),3)-1) * (t1.rsv_inwon)) AS seg_cnt
         , SUM((SAFE_DIVIDE(LENGTH(REPLACE(REPLACE(t1.ALL_ITIN_CONTENT,'-',''),'/','')),3)-1) * (t1.rsv_inwon) * (CASE WHEN t1.stock_air_cd IN ('LJ','ZE') THEN gi2.gds_com_krw WHEN t1.stock_air_cd NOT IN ('LJ','ZE','KE','7C') THEN gi3.gds_com_krw ELSE gi.gds_com_krw END)) AS gds_com
    FROM {{ source('air', 'TB_AIR_RV100') }} t1
    LEFT JOIN GDS_INFO gi ON gi.basis_date = DATE_TRUNC(t1.issue_date, MONTH) AND gi.airline_type = t1.STOCK_AIR_CD
    LEFT JOIN (SELECT * FROM GDS_INFO WHERE airline_type = 'LJ/ZE') gi2 ON gi2.basis_date = DATE_TRUNC(t1.issue_date, MONTH) AND t1.STOCK_AIR_CD IN ('LJ','ZE')
    LEFT JOIN (SELECT * FROM GDS_INFO WHERE airline_type = 'OAL') gi3 ON gi3.basis_date = DATE_TRUNC(t1.issue_date, MONTH) AND t1.STOCK_AIR_CD NOT IN ('LJ','ZE','KE','7C')
    WHERE t1.ISSUE_STATUS_CD = 'TKKY'
      AND t1.di_flag = 'I'
      AND t1.gds_cd = 'T'
      AND t1.cancel_yn = 'N'
      AND t1.on_off_rsv_flag = 'ON'
      AND t1.STOCK_AIR_CD NOT IN ('TW','RS','BX', 'QR')
    GROUP BY t1.PNR_SEQNO
)
-- 여기서부터 쿼리 본문
SELECT S.BASIS_DATE
     , S.TRAVEL_START_KST_DATE                                                                          AS TRAVEL_START_DATE
     , S.TRAVEL_END_KST_DATE                                                                            AS TRAVEL_END_DATE
     , DATE_DIFF(S.TRAVEL_END_KST_DATE, S.TRAVEL_START_KST_DATE, DAY)                                   AS TRAVEL_DAYS
     , RC.CANCEL_DATE                                                                                   AS CANCEL_DATE
     , DATE_DIFF(RC.CANCEL_DATE, S.BASIS_DATE, DAY)                                                     AS RESVE_CANCEL_DAY_DIFF
     , S.RECENT_STATUS
     , S.RESVE_ID
     , S.RESVE_PRSNL_CNT
     , S.TRAVEL_ID
     , U.MRT_STAFF_FLAG                                                                                 AS MRT_STAFF_FLAG
     , S.USER_ID
     , S.MRT_TYPE
     , S.PARTNER_ID
     , CASE WHEN S.PARTNER_ID = 'SKY001' THEN 'SKYSCANNER'
            WHEN S.PARTNER_ID = 'N00001' THEN 'NAVER'
            WHEN S.PARTNER_ID = 'KAO001' THEN 'KAKAO'
            WHEN S.PARTNER_ID IS NULL THEN 'MRT' END                                                     AS PARTNER_NM
     , API.STOCK_AIRLINE_CD                                                                             AS STOCK_AIRLINE_CD
     , API.DOMESTIC_INTERNATIONAL_DIV_CD                                                                AS DI_FLAG
     , CASE WHEN S.COUNTRY_NM = 'Korea, Republic of' THEN 'Domestic'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' AND S.COUNTRY_NM IS NOT NULL THEN 'Outbound'
            ELSE 'Outbound' END                                                                            AS REGION_TYPE
     , S.PRODUCT_ID
     , S.REGION_NM
     , CASE WHEN S.COUNTRY_NM IS NULL THEN 'Others'
            ELSE S.COUNTRY_NM END                                                                          AS COUNTRY_NM
     , CASE WHEN S.CITY_NM IS NULL THEN 'Others'
            ELSE S.CITY_NM END                                                                             AS CITY_NM
     , CASE WHEN S.CITY_NM = 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'Y'
            WHEN S.CITY_NM != 'Jeju' AND S.COUNTRY_NM = 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM != 'Korea, Republic of' THEN 'N'
            WHEN S.COUNTRY_NM IS NULL THEN 'N' END                                                      AS JEJU_FLAG
     , API.TRIP_TYPE_CD                                                                                 AS TRIP_TYPE_CD
     , API.DEPART_CITY_CD                                                                               AS DEPART_AIRPORT_CD
     , API.DEPART_CITY_NM                                                                               AS DEPART_CITY_NM
     , API.DEPART_COUNTRY_NM                                                                            AS DEPART_COUNTRY_NM
     , API.DEPART_REGION_NM                                                                             AS DEPART_REGION_NM
     , API.ARRIVE_CITY_CD                                                                               AS ARRIVE_CITY_CD
     , API.ARRIVE_CITY_NM                                                                               AS ARRIVE_CITY_NM
     , API.ARRIVE_COUNTRY_NM                                                                            AS ARRIVE_COUNTRY_NM
     , API.ARRIVE_REGION_NM                                                                             AS ARRIVE_REGION_NM
     , API.GDS_CD                                                                                       AS GDS_CD
     , CASE WHEN API.GDS_CD = 'T' THEN
               (CASE WHEN API.STOCK_AIRLINE_CD = 'KE' THEN 'KE'
                     WHEN API.STOCK_AIRLINE_CD = '7C' THEN '7C'
                     WHEN API.STOCK_AIRLINE_CD = 'LJ' THEN 'LJ'
                     WHEN API.STOCK_AIRLINE_CD = 'ZE' THEN 'ZE'
                     WHEN API.STOCK_AIRLINE_CD in ('TW','RS','BX') THEN API.STOCK_AIRLINE_CD
                     ELSE 'OAL' END) ELSE NULL END                                                      AS GDS_AIRLINE_TYPE
     , S.SALES_KRW_PRICE
     , ASI.DISCOUNT_AFTER_NET_PRICE                                                                     AS DISCOUNT_AFTER_NET_PRICE
     , IFNULL(CASE WHEN S.RECENT_STATUS IN ('confirm','finish') THEN ASI.VI_COMMISSION
                   ELSE 0 END, 0)                                                                       AS VI_COMMISSION_PRICE
     , IFNULL(CASE WHEN S.RECENT_STATUS IN ('confirm','finish') THEN GCI.gds_com
                   ELSE 0 END, 0)                                                                       AS GDS_VI_COMMISSION_PRICE
     , IFNULL(CASE WHEN S.RECENT_STATUS IN ('confirm','finish') THEN CAST(BC.validCOMM AS INT64)
                   ELSE 0 END, 0)                                                                       AS BSP_COMMISSION_PRICE
     , IFNULL(SAFE_DIVIDE(DT.D_TASF_COMMISSION,1.1),0)                                                  AS D_TASF_COMMISSION_PRICE
     , IFNULL(SAFE_DIVIDE(IT.I_TASF_COMMISSION,1.1),0)                                                  AS I_TASF_COMMISSION_PRICE
     , IFNULL(SAFE_DIVIDE(IT.I_REISSUE_COMMISSION,1.1),0)                                               AS REISSUE_COMMISSION_PRICE
     , IFNULL(SAFE_DIVIDE(IT.I_CANCEL_COMMISSION,1.1),0)                                                AS CANCEL_COMMISSION_PRICE
     , IFNULL(DA.DISCOUNT_AMT,0)                                                                        AS DISCOUNT_PRICE
     , IFNULL(CCB.CARD_CASH_BACK_PRICE,0)                                                               AS CARD_CASH_BACK_PRICE
     , IFNULL(NP.NPAY_PRICE,0)                                                                          AS D_NPAY_PRICE
     , IFNULL(CASE WHEN S.PARTNER_ID = 'SKY001' AND S.USER_ID = 'smart_guest' THEN 0
                   WHEN S.PARTNER_ID = 'SKY001' AND RC.CANCEL_DATE IS NOT NULL AND DATE_TRUNC(S.BASIS_DATE,MONTH) = DATE_TRUNC(RC.CANCEL_DATE,MONTH) THEN 0
                   WHEN S.PARTNER_ID = 'SKY001' THEN ASI.DISCOUNT_AFTER_NET_PRICE * 0.02
                   WHEN S.PARTNER_ID = 'N00001' AND API.DOMESTIC_INTERNATIONAL_DIV_CD = 'I' THEN ASI.DISCOUNT_AFTER_NET_PRICE * 0.01
                   WHEN S.PARTNER_ID = 'N00001' AND API.DOMESTIC_INTERNATIONAL_DIV_CD = 'D' THEN ASI.DISCOUNT_AFTER_NET_PRICE * 0.009
                   ELSE 0 END, 0)                                                                       AS CHANNEL_FEE_PRICE
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR)                                               AS DW_LOAD_DT
FROM {{ ref('MART_SALE_D') }} S
LEFT JOIN {{ ref('MART_USER_D') }} U ON S.USER_ID = U.USER_ID
LEFT JOIN AIR_PNR_INFO API ON S.RESVE_ID = API.RESVE_ID /* PNR 기타정보 맵핑 */
LEFT JOIN AIR_SALE_INFO ASI ON S.RESVE_ID = ASI.RESVE_ID /* AIR_SALE_D를 통한 정보 맵핑 */
LEFT JOIN RSV_CANCEL RC ON S.RESVE_ID = RC.RESVE_ID /* 취소 정보 맵핑 */
LEFT JOIN CARD_CASH_BACK CCB ON CCB.RESVE_ID = S.RESVE_ID /* 국내선 카드 캐시백 비용 맵핑 */
LEFT JOIN NPAY NP ON NP.RESVE_ID = S.RESVE_ID /* 네이버페이 비용 맵핑 */
LEFT JOIN DISCOUNT_AMOUNT DA ON DA.RESVE_ID = S.RESVE_ID /* 할인 비용 맵핑 */
LEFT JOIN BSP_COM BC ON BC.RESVE_ID = S.RESVE_ID /* 국제선 커미션 맵핑 */
LEFT JOIN D_TASF DT ON DT.RESVE_ID = S.RESVE_ID /* 국내선 TASF 맵핑 */
LEFT JOIN I_TASF IT ON IT.RESVE_ID = S.RESVE_ID /* 국제선 TASF/취소/재발행 수수료 맵핑 */
LEFT JOIN GDS_COM_INFO GCI ON GCI.RESVE_ID = S.RESVE_ID /* GDS 수수료 맵핑 */
WHERE S.KIND = 1
  AND S.MRT_TYPE = 'flight'