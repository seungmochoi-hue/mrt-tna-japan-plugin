{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_RESVE_TYPE'
    )
}}

/*
  [DIM_RESVE_TYPE] 예약 기준 상품 유형 분류 dimension
  - INT_SALE_BASE_D 기준으로 PRODUCT_ID + DOMAIN_NM 단위의 상품 유형을 분류
  - BIG_TYPE: 예약 타입 기반 대분류
  - MRT_TYPE: classify_mrt_type 매크로 기반 상세 분류 (13개 유형)
  - TEAM_DIVISION: 팀 배분 분류
  - downstream: MART_SALE_D
*/

WITH temp_resve_type AS (
    SELECT S.PRODUCT_ID                                                AS PRODUCT_ID
         , S.DOMAIN_NM                                                 AS DOMAIN_NM
         -- BIG_TYPE: T&A 연동 상품은 offer type 기준, 그 외는 예약 타입 기준
         , CASE WHEN S.DOMAIN_NM = '3.0 PRODUCT' AND S.RESVE_TYPE = 'touractivity' THEN
                    CASE WHEN O.type IN ('deliveryTicket', 'eticket', 'istanbulticket') THEN 'ticket' ELSE LOWER(O.type) END
                ELSE CASE WHEN S.RESVE_TYPE IN ('deliveryTicket', 'eticket', 'istanbulticket') THEN 'ticket' ELSE S.RESVE_TYPE END
           END                                                         AS BIG_TYPE
         -- MRT_TYPE: classify_mrt_type 매크로 호출
         , {{ classify_mrt_type(
                product_id='S.PRODUCT_ID',
                domain_nm='S.DOMAIN_NM',
                partner_id='S.PARTNER_ID',
                resve_type='S.RESVE_TYPE',
                offer_type='O.type',
                offer_title='O.title',
                product_title='P.product_title',
                product_category='P.product_category',
                product_type='P.product_type',
                sub_category_cd='CD.SUB_CATEGORY_CD',
                category_cd='CD.CATEGORY_CD',
                standard_category_lv_2_cd='S.STANDARD_CATEGORY_LV_2_CD',
                trimo_res_id='R.res_id'
           ) }}                                                        AS MRT_TYPE
         -- TEAM_DIVISION: classify_team_division 매크로 호출
         , {{ classify_team_division(
                domain_nm='S.DOMAIN_NM',
                partner_id='S.PARTNER_ID',
                product_id='S.PRODUCT_ID',
                guide_id='TM.guide_id',
                biz_type='TM.biz_type',
                offer_type='O.type',
                offer_id='O.id',
                offer_guide_id='O.guide_id',
                product_type='P.product_type',
                sub_category_cd='CD.SUB_CATEGORY_CD',
                vehicle_id='V.ID',
                hocance_offer_id='H.offer_id',
                trimo_res_id='R.res_id',
                resve_type='S.RESVE_TYPE'
           ) }}                                                        AS TEAM_DIVISION
         ,  ROW_NUMBER() OVER (PARTITION BY S.DOMAIN_NM, S.PRODUCT_ID ORDER BY S.CREATE_KST_DT DESC) AS row_num
    FROM {{ ref('INT_SALE_BASE_D') }} S
    LEFT JOIN {{ ref('DIM_PRODUCT_CATEGORY') }} CD ON S.PRODUCT_ID = CD.PRODUCT_ID AND (S.DOMAIN_NM = '2.0 PRODUCT'  OR (S.DOMAIN_NM = '3.0 PRODUCT' AND S.RESVE_TYPE = 'touractivity'))
    LEFT JOIN {{ ref('hocance_info') }} H ON S.PRODUCT_ID = H.offer_id
    LEFT JOIN {{ source('orders', 'reservations') }} P ON S.DOMAIN_NM = '3.0 PRODUCT' AND S.RESVE_ID = CAST(P.reservation_no AS STRING)
    LEFT JOIN {{ source('mrt_20', 'offers') }} O ON (S.DOMAIN_NM = '2.0 PRODUCT'  OR (S.DOMAIN_NM = '3.0 PRODUCT' AND S.RESVE_TYPE = 'touractivity')) AND S.PRODUCT_ID = CAST(O.ID AS STRING)
    LEFT JOIN {{ source('products', 'products') }} PP ON P.PRODUCT_ID = CONCAT('BNB', PP.ID)
    LEFT JOIN {{ ref('temp_fpna_team_mapping') }} TM ON S.PARTNER_ID = CAST(TM.guide_id AS STRING)
    LEFT JOIN {{ source('mustang', 'mst_vehicle') }} V ON S.PRODUCT_ID = CAST(V.ID AS STRING)
    LEFT JOIN {{ source('external', 'DW_MRT_TRIMO_RESERVATION') }} R ON S.RESVE_ID = ('CAR-' || FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP(R.created_date)) || '-' || R.res_id)
)
SELECT DISTINCT
        t.PRODUCT_ID
     ,  t.DOMAIN_NM
     ,  t.BIG_TYPE
     ,  t.MRT_TYPE
     ,  t.TEAM_DIVISION
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM temp_resve_type t
WHERE t.row_num = 1
