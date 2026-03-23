{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_PRODUCT_TYPE',
        cluster_by=['DOMAIN_NM']
    )
}}

/*
  [DIM_PRODUCT_TYPE] 상품 기준 상품 유형 분류 dimension
  - MART_PRODUCT_ORIGINAL_D 기준으로 GID + DOMAIN_NM 단위의 상품 유형을 분류
  - MRT_TYPE: classify_mrt_type 매크로 기반 상세 분류 (13개 유형)
  - TEAM_DIVISION: 팀 배분 분류
  - downstream: DIM_PRODUCT_FPNA_TYPE
*/

SELECT DISTINCT
               P.GID                                              AS GID
             , P.DOMAIN_NM                                        AS DOMAIN_NM
             -- MRT_TYPE: classify_mrt_type 매크로 호출
             -- rentalcar_check_id: 원본에서 ticket_rentalcar 파트너 비교에 GID 사용
             , {{ classify_mrt_type(
                    product_id='P.GID',
                    domain_nm='P.DOMAIN_NM',
                    partner_id='P.PARTNER_ID',
                    rentalcar_check_id='P.GID',
                    resve_type='',
                    offer_type='O.type',
                    offer_title='O.title',
                    product_title='P.PRODUCT_NM',
                    product_category='P.PRODUCT_CATEGORY_NM',
                    product_type='P.product_type',
                    sub_category_cd='CD.SUB_CATEGORY_CD',
                    category_cd='CD.CATEGORY_CD',
                    standard_category_lv_2_cd='P.STANDARD_CATEGORY_LV_2_CD',
                    standard_category_lv_3_cd='P.STANDARD_CATEGORY_LV_3_CD',
                    offer_scale='O.scale'
               ) }}                                               AS MRT_TYPE
             -- TEAM_DIVISION: classify_team_division 매크로 호출
             , {{ classify_team_division(
                    domain_nm='P.DOMAIN_NM',
                    partner_id='P.PARTNER_ID',
                    product_id='P.GID',
                    guide_id='TM.guide_id',
                    biz_type='TM.biz_type',
                    offer_type='O.type',
                    offer_id='O.id',
                    offer_guide_id='O.guide_id',
                    product_type='P.product_type',
                    sub_category_cd='CD.SUB_CATEGORY_CD',
                    vehicle_id='V.ID'
               ) }}                                                AS TEAM_DIVISION
             , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ ref('MART_PRODUCT_ORIGINAL_D') }} P
LEFT JOIN {{ ref('DIM_PRODUCT_CATEGORY') }} CD ON P.GID = CD.PRODUCT_ID AND (P.DOMAIN_NM = '2.0 PRODUCT' OR
                                                                        (P.DOMAIN_NM = '3.0 PRODUCT' AND P.PRODUCT_TYPE = 'touractivity'))
LEFT JOIN {{ source('mrt_20', 'offers') }} O ON (P.DOMAIN_NM = '2.0 PRODUCT' OR
                                         (P.DOMAIN_NM = '3.0 PRODUCT' AND P.PRODUCT_TYPE = 'touractivity')) AND
                                         P.GID = CAST(O.ID AS STRING)
LEFT JOIN {{ ref('temp_fpna_team_mapping') }} TM ON P.PARTNER_ID = CAST(TM.guide_id AS STRING)
LEFT JOIN {{ source('mustang', 'mst_vehicle') }} V on P.GID = CAST(V.ID AS STRING)