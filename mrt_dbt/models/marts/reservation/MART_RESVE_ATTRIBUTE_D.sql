{{
    config(
        materialized = 'incremental',
        schema='edw_mart',
        alias='MART_RESVE_ATTRIBUTE_D',
        pre_hook = [
            "DELETE FROM {{ this }} A WHERE A.RESVE_ID IN (SELECT B.RESVE_ID FROM {{ ref('resve_attribute') }} B)"
        ]
    )
}}


SELECT RESVE_ID
     , DOMAIN_NM
     , CREATED_KST_DATE
     , UPDATED_KST_DATE
     , FIRST_UTM_MEDIUM
     , FIRST_UTM_SOURCE
     , FIRST_UTM_CAMPAIGN
     , FIRST_UTM_TERM
     , FIRST_UTM_CONTENT
     , UTM_MEDIUM
     , UTM_SOURCE
     , UTM_CAMPAIGN
     , UTM_TERM
     , UTM_CONTENT
     , N_AD
     , N_AD_GROUP
     , N_CAMPAIGN_TYPE
     , N_KEYWORD
     , N_KEYWORD_ID
     , MRT_CONTENTS_VALUE
     , APP_PLATFORM
     , APP_IDFA_VALUE
     , APP_ADID_VALUE
     , APP_DEVICE_TYPE
     , APP_SITE_ID_VALUE
     , APP_SUB_SITE_ID_VALUE
     , APP_ADSET_VALUE
     , APP_AD_VALUE
     , APP_CHANNEL_VALUE
     , DW_LOAD_DT
FROM {{ ref('resve_attribute') }}