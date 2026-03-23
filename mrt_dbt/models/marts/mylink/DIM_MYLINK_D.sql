{{
    config(
        materialized='table',
        schema='edw_mart',
        alias='DIM_MYLINK_D',
        cluster_by=['PARTNER_ID']
    )
}}


SELECT CAST(M.id AS STRING) AS MYLINK_ID
     ,  CAST(M.partner_id AS STRING) AS PARTNER_ID
     ,  P.name AS PARTNER_NAME
     ,  CAST(M.partner_account_id AS STRING) AS PARTNER_ACCOUNT_ID
     ,  CAST(S.id AS STRING) AS SHORT_URL_ID
     ,  S.target_url_web AS TARGET_WEB_URL
     ,  S.target_url_mobile AS TARGET_MOBILE_URL
     ,  CAST(S.gid AS STRING) AS GID
     ,  S.created_at AS CREATED_KST_AT
     ,  S.updated_at AS UPDATED_KST_AT
     ,  S.expire_at AS EXPIRE_KST_AT
     ,  DATETIME_ADD(CURRENT_TIMESTAMP(), INTERVAL 9 HOUR) AS DW_LOAD_DT
FROM {{ source('partners', 'mylink') }} M
LEFT JOIN {{ source('commons','short_url') }} S ON M.short_url_id = S.id
LEFT JOIN {{ source('partners', 'partner_account') }} P ON M.partner_id = P.partner_id
WHERE M.deleted = false AND S.deleted = false