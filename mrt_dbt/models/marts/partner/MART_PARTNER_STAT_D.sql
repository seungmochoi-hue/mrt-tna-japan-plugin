{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='MART_PARTNER_STAT_D'
    )
}}


SELECT T.BASIS_DATE
     , MAX(T.ACTIVE_PARTNER_CNT)                          AS ACTIVE_PARTNER_CNT
     , MAX(T.REST_PARTNER_CNT)                            AS REST_PARTNER_CNT
     , MAX(T.NEW_PARTNER_CNT)                             AS NEW_PARTNER_CNT
     , MAX(T.SALES_PARTNER_CNT)                           AS SALES_PARTNER_CNT
     , MAX(T.RESVE_CONFIRM_PARTNER_CNT)                   AS RESVE_CONFIRM_PARTNER_CNT
     , DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM (
         SELECT S.BASIS_DATE AS BASIS_DATE
              , S.ACTIVE_PARTNER_CNT
              , S.REST_PARTNER_CNT
              , NULL                       AS NEW_PARTNER_CNT
              , NULL                       AS SALES_PARTNER_CNT
              , NULL                       AS RESVE_CONFIRM_PARTNER_CNT
         FROM {{ ref('MART_PARTNER_STAT_SNAPSHOT') }} S

         UNION ALL

         SELECT CAST(P.CREATE_KST_DT AS DATE)             AS BASIS_DATE
              , NULL                         AS ACTIVE_PARTNER_CNT
              , NULL                         AS RESR_PARTNER_CNT
              , COUNT(DISTINCT P.PARTNER_ID) AS NEW_PARTNER_CNT
              , NULL                         AS SALES_PARTNER_CNT
              , NULL                         AS RESVE_CONFIRM_PARTNER_CNT
         FROM {{ ref('MART_PARTNER_ORIGINAL_D') }} P
         GROUP BY P.CREATE_KST_DT

         UNION ALL

         SELECT S.BASIS_DATE                                                        AS BASIS_DATE
              , NULL                                                                AS ACTIVE_PARTNER_CNT
              , NULL                                                                AS RESR_PARTNER_CNT
              , NULL                                                                AS NEW_PARTNER_CNT
              , COUNT(DISTINCT S.PARTNER_ID)                                        AS SALES_PARTNER_CNT
              , COUNT(DISTINCT IF(S.recent_status <> 'cancel', S.PARTNER_ID, NULL)) AS RESVE_CONFIRM_PARTNER_CNT
         FROM {{ ref('MART_SALE_D') }} S
         WHERE S.KIND = 1 AND S.MRT_TYPE NOT IN ('flight', 'hotel')
         GROUP BY S.BASIS_DATE
     ) T
GROUP BY T.BASIS_DATE