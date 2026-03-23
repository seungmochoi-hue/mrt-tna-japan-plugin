{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'merge',
        schema='edw_mart',
        alias='DIM_USER_INFO_HIST',
        partition_by={
            'field': 'BASIS_DT',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by=['USER_ID'],
        pre_hook="DELETE FROM {{ this }} WHERE BASIS_DT = '{{ var('logical_start_date_kst') }}'"
    )
}}



SELECT
    DATE('{{ var("logical_start_date_kst") }}') AS BASIS_DT
    , *

FROM {{ ref('DIM_USER_INFO') }}