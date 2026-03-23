{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PRODUCT_ORIGINAL_D'
    )
}}

WITH CITY_NODUP AS (
    SELECT CAST(t.offer_id AS STRING) AS PRODUCT_ID
         ,  t.is_representative -- 신규 추가
         ,  t.city_key_name AS CITY_CD
    FROM (
             SELECT c.offer_id
                  ,  c.is_representative
                  ,  c.city_key_name
                  ,  ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY is_representative DESC, city_key_name DESC) AS RN
             FROM {{ ref('city_to_region') }} c
             WHERE city_info_id IS NOT NULL
         ) t
    WHERE t.RN = 1

    UNION ALL
    -- 22.04.14 입점숙소 gid 기준 추가
    SELECT CAST(p.union_product_id AS STRING) AS PRODUCT_ID
         , CAST(NULL AS BOOL) AS is_representative
         , MAX(lc.key_name) AS CITY_CD
    FROM {{ source('products', 'products') }} p
    LEFT JOIN {{ source('products', 'product_city_mappings') }} cp ON p.id = cp.product_id AND cp.deleted_at IS NULL
    LEFT JOIN {{ source('products', 'location_cities') }} lc ON cp.location_city_id = lc.id
    GROUP BY p.union_product_id
),
EXPERIENCES_CITY_NODUP AS (
    SELECT t.product_id AS product_id
         ,  t.representative
         ,  t.city AS code
    FROM (
             SELECT  c.product_id
                  ,  c.representative
                  ,  c.city
                  ,  ROW_NUMBER() OVER (PARTITION BY c.product_id ORDER BY c.representative DESC, c.city DESC) AS RN
             FROM {{ source('experiences', 'product_legacy_locations') }} c
             WHERE c.city IS NOT NULL
               AND c.deleted_at IS NULL
         ) t
    WHERE t.RN = 1
),
PRODUCT_MART AS (
    SELECT CAST(O.id AS STRING) AS GID
         ,  '2.0 PRODUCT' AS DOMAIN_NM
         ,  O.title AS PRODUCT_NM
         ,  CAST(O.id AS STRING) AS PRODUCT_ID
         ,  CAST(O.guide_id AS STRING) AS PARTNER_ID
         ,  A.name AS PARTNER_NM
         ,  CAST(NULL AS STRING) AS AGENCY_ID
         ,  CAST(NULL AS STRING) AS AGENCY_NM
         ,  CASE WHEN O.status = 'temp' THEN 'temp'
                 WHEN O.status = 'reject' THEN 'not_sale'
                 WHEN O.status = 'onsale' THEN 'onsale'
                 WHEN O.status IN ('hold', 'HOLD') THEN 'hold'
                 WHEN O.status = 'ready' THEN 'ready' END AS RECENT_STATUS
         ,  O.created_at_kst AS CREATE_KST_DT
         ,  O.updated_at_kst AS UPDATE_KST_DT
         ,  CASE WHEN O.type IN ('Hotel', 'Pension', 'Lodging') THEN 'accommodation'
                 ELSE 'touractivity' END AS PRODUCT_TYPE
         ,  O.first_published_at_kst AS FIRST_PUBLISHED_KST_DT
         ,  O.lat AS LATITUDE_COORDINATE
         ,  O.lng AS LONGITUDE_COORDINATE
         ,  C.CITY_CD AS CITY_CD
         ,  CASE WHEN C.is_representative = TRUE THEN 'Y' WHEN C.is_representative = FALSE THEN 'N' ELSE NULL END AS CITY_REPRESENTATIVE_FLAG
         ,  IF(O.commission_rate IS NOT NULL, O.commission_rate/ 100, NULL) AS COMMISSION_RATE
         ,  O.duration_unit AS DURATION_UNIT
         ,  O.duration_size AS DURATION_SIZE
         ,  O.allow_quick_reservation AS ALLOW_QUICK_RESERVATION
         ,  O.locale AS LOCALE
         ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
    FROM {{ source('mrt_20', 'offers') }} O
    LEFT JOIN {{ source('partners', 'partner') }} G ON O.guide_id = G.id
    LEFT JOIN {{ source('partners', 'partner_account') }} A ON G.id = A.partner_id AND A.type = 'MASTER'
    LEFT JOIN CITY_NODUP C ON CAST(O.id AS STRING) = C.PRODUCT_ID
    WHERE O.deleted_at_kst IS NULL

    UNION ALL

    SELECT CAST(UPS.ID AS STRING) AS GID
        ,  '3.0 PRODUCT' AS DOMAIN_NM
        ,  UPS.title AS PRODUCT_NM
        ,  COALESCE(CONCAT('BNB', P.id), CAST(V.id AS STRING), CONCAT('STY', L.osp_id), CAST(PT.property_id AS STRING), CAST(EP.id AS STRING), CAST(UPS.ID AS STRING)) AS PRODUCT_ID
        ,  CASE WHEN V.id IS NOT NULL THEN '16737'
                WHEN PT.provider_code = 'EPS' THEN '19260'
                WHEN PT.provider_code = 'AGODA' THEN '21205'
                WHEN PT.provider_code = 'STAYNET' THEN CAST(G4.id AS STRING)
                ELSE CAST(COALESCE(P.partner_id, L.partner_id, EP.partner_id) AS STRING) END AS PARTNER_ID
        ,  CASE WHEN V.id IS NOT NULL THEN 'zzimcar'
                WHEN PT.provider_code = 'STAYNET' THEN G4.nickname
                ELSE COALESCE(A.name, A2.name, A3.name, CAST(PT.provider_code AS STRING)) END AS PARTNER_NM
        ,  CAST(V.AGENCY_ID AS STRING) AS AGENCY_ID
        ,  COALESCE(MG.name, CAST(PT.provider_code AS STRING)) AS AGENCY_NM
        ,  CASE WHEN V.id IS NOT NULL THEN CASE WHEN V.status = 'DISABLE' THEN 'not_sale' WHEN V.status = 'ENABLE' THEN 'onsale' END
             WHEN L.lodging_id IS NOT NULL THEN CASE WHEN L.mrt_status = 'ENABLED' AND L.onda_status = 'ENABLED' THEN 'onsale' ELSE 'not_sale' END
             WHEN PT.property_id IS NOT NULL THEN CASE WHEN PT.provider_property_status = 'ON_SALE' AND PT.mrt_property_status = 'ON_SALE' THEN 'onsale' ELSE 'not_sale' END
             WHEN EP.id IS NOT NULL THEN EP.status
             ELSE LOWER(UPS.product_status) END AS RECENT_STATUS
         ,  DATETIME_ADD(UPS.created_at, INTERVAL 9 HOUR) AS CREATE_KST_DT
         ,  DATETIME_ADD(UPS.updated_at, INTERVAL 9 HOUR) AS UPDATE_KST_DT
        ,  CASE WHEN V.id IS NOT NULL THEN 'transport' WHEN EP.id IS NOT NULL THEN 'touractivity'
                ELSE 'accommodation' END AS PRODUCT_TYPE
         ,  COALESCE(DATETIME_ADD(PS.first_sale_start_at, INTERVAL 9 HOUR), DATETIME_ADD(V.created_at, INTERVAL 9 HOUR), DATETIME_ADD(L.created_at, INTERVAL 9 HOUR), DATETIME_ADD(PT.created_at, INTERVAL 9 HOUR), DATETIME_ADD(EPM.offer_created_at, INTERVAL 9 HOUR)) AS FIRST_PUBLISHED_KST_DT
         ,  COALESCE(CAST(REGEXP_EXTRACT(P.location, '[(](.*?)[ ]') AS FLOAT64), MG.latitude, L.latitude, PT.latitude, EPR.latitude) AS LATITUDE_COORDINATE
         ,  COALESCE(CAST(REGEXP_EXTRACT(P.location, '[ ](.*?)[)]') AS FLOAT64), MG.longitude, L.longitude, PT.longitude, EPR.longitude) AS LONGITUDE_COORDINATE
         ,  COALESCE(C.CITY_CD, MG.mrt_city, L.mrt_city_key_name, PR.city_key_name, EPRC.code) AS CITY_CD
         ,  CASE WHEN P.id IS NOT NULL THEN CASE WHEN C.is_representative = TRUE THEN 'Y' WHEN C.is_representative = FALSE THEN 'N' END
                 WHEN EP.id IS NOT NULL THEN CASE WHEN EPRC.representative = TRUE THEN 'Y' WHEN EPRC.representative = FALSE THEN 'N' END
                 ELSE NULL END AS CITY_REPRESENTATIVE_FLAG
         ,  CASE WHEN P.id IS NULL THEN P.commission_rate/ 100 ELSE NULL END AS COMMISSION_RATE
         ,  NULL AS DURATION_UNIT
         ,  NULL AS DURATION_SIZE
         ,  CASE WHEN P.id IS NULL THEN P.immediate_confirm END AS ALLOW_QUICK_RESERVATION
         ,  NULL AS LOCALE
         ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('ups', 'union_product_v3') }} UPS
LEFT JOIN {{ source('products', 'products') }} P ON CAST(UPS.id AS STRING) = P.union_product_id
LEFT JOIN {{ source('products', 'product_statistics') }} PS ON P.id = PS.id
LEFT JOIN {{ source('partners', 'partner') }} G ON P.partner_id = G.id
LEFT JOIN {{ source('partners', 'partner_account') }} A ON G.id = A.partner_id AND A.type = 'MASTER'
LEFT JOIN CITY_NODUP C ON CAST(UPS.ID AS STRING) = C.PRODUCT_ID

LEFT JOIN {{ source('mustang', 'mst_vehicle') }} V ON UPS.id = V.id
LEFT JOIN {{ source('mustang', 'mst_agency') }} MG ON V.agency_id = MG.id

LEFT JOIN {{ source('localstay', 'lodging') }} L ON UPS.id = L.lodging_id
LEFT JOIN {{ source('partners', 'partner') }} G2 ON L.partner_id = G2.id
LEFT JOIN {{ source('partners', 'partner_account') }} A2 ON G2.id = A2.partner_id AND A2.type = 'MASTER'

LEFT JOIN {{ source('unionstay', 'property') }} PT ON UPS.id = PT.property_id
LEFT JOIN {{ source('unionstay', 'property_represent_mrt_region') }} PR ON PT.property_id = PR.property_id
LEFT JOIN {{ source('partners', 'partner') }} G4 ON PT.partner_id = G4.id

LEFT JOIN {{ source('experiences', 'products') }} EP ON UPS.id = EP.id
LEFT JOIN {{ source('partners', 'partner') }} G3 ON EP.partner_id = G3.id
LEFT JOIN {{ source('partners', 'partner_account') }} A3 ON G3.id = A3.partner_id AND A3.type = 'MASTER'
LEFT JOIN {{ source('experiences', 'product_migration_map') }} EPM ON EP.id = EPM.product_id
LEFT JOIN {{ source('experiences', 'product_regions') }} EPR ON EP.id = EPR.product_id
LEFT JOIN EXPERIENCES_CITY_NODUP EPRC ON EP.id = EPRC.product_id

LEFT JOIN {{ source('mrt_20', 'offers') }} SO ON UPS.id = SO.id
WHERE UPS.deleted_at IS NULL
  AND UPS.product_status <> 'DELETED'
  AND SO.id IS NULL
)
SELECT M.GID
     , UPS.gpid AS GPID
     , M.DOMAIN_NM
     , M.PRODUCT_NM
     , M.PRODUCT_ID
     , M.PARTNER_ID
     , M.PARTNER_NM
     , M.AGENCY_ID
     , M.AGENCY_NM
     , M.RECENT_STATUS
     , M.CREATE_KST_DT
     , M.UPDATE_KST_DT
     , M.PRODUCT_TYPE
     --2023.01.16 표준카테고리 사용하는 오퍼의 경우 category_id로 카테고리 code 매핑해야 함.
     , COALESCE(LOWER(COALESCE(UC.code, U.category, C.CATEGORY_CD)), 'unclassified') AS PRODUCT_CATEGORY_NM
     , IFNULL(SC.LV_1_CD, SC2.LV_1_CD) AS STANDARD_CATEGORY_LV_1_CD
     , IFNULL(SC.LV_2_CD, SC2.LV_2_CD) AS STANDARD_CATEGORY_LV_2_CD
     , IFNULL(SC.LV_3_CD, SC2.LV_3_CD) AS STANDARD_CATEGORY_LV_3_CD
     , M.FIRST_PUBLISHED_KST_DT
     , M.LATITUDE_COORDINATE
     , M.LONGITUDE_COORDINATE
     , M.CITY_CD
     , M.CITY_REPRESENTATIVE_FLAG
     , M.COMMISSION_RATE
     , M.DURATION_UNIT
     , M.DURATION_SIZE
     , M.ALLOW_QUICK_RESERVATION
     , M.LOCALE
     , M.DW_LOAD_DT
FROM PRODUCT_MART M
LEFT JOIN {{ source('ups', 'union_products') }} U ON M.GID = CAST(U.id AS STRING)
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS ON M.gid = CAST(UPS.id AS STRING)
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC ON UPS.standard_category_code = SC.LV_3_CD
LEFT JOIN {{ source('ups', 'categories') }} UC ON U.category_id = UC.id --2023.01.16 표준카테고리 사용하는 오퍼의 경우 category_id로 카테고리 code 매핑해야 함.
LEFT JOIN {{ ref('DIM_PRODUCT_CATEGORY') }} C ON M.GID = C.PRODUCT_ID AND M.PRODUCT_TYPE = 'touractivity'
LEFT JOIN {{ ref('DIM_TEST_PRODUCT') }} TP ON M.GID = TP.GID
LEFT JOIN {{ source('ups', 'union_product_v3') }} UPS2 ON U.PRODUCT_ID = CAST(UPS2.id AS STRING)
LEFT JOIN {{ source('mrt_mart_view','dim_standard_category') }} SC2 ON UPS2.standard_category_code = SC2.LV_3_CD
WHERE TP.GID IS NULL
