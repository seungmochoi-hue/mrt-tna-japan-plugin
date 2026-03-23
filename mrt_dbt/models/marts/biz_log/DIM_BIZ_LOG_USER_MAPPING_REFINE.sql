{{
    config(
        materialized='table',
        schema='edw_biz_log',
        alias='DIM_BIZ_LOG_USER_MAPPING_REFINE',
        require_partition_filter = true
    )
}}

WITH TBL AS (
    SELECT
        *
         , SUM(same_user) OVER (PARTITION BY pid ORDER BY min_event_timestamp_kst) AS running_sum
         , CONCAT(user_id, "-", (SUM(same_user) OVER (PARTITION BY pid ORDER BY min_event_timestamp_kst))) AS user_id_num
    FROM (
             SELECT
                 pid
                  , user_id
                  , min_event_timestamp_kst
                  , LAG(user_id) OVER(PARTITION BY pid ORDER BY min_event_timestamp_kst) AS before_user_id
                  , CASE WHEN user_id=(LAG(user_id) OVER(PARTITION BY pid ORDER BY min_event_timestamp_kst)) THEN 0 ELSE 1 END AS same_user
             FROM {{ ref('DIM_BIZ_LOG_USER_MAPPING') }}
         )
)
SELECT
    pid
     , user_id
     , user_id_num
     , running_sum
     , min_start_ts_kst
     , CASE WHEN running_sum = 1 THEN TIMESTAMP '2021-01-01' ELSE min_start_ts_kst END AS start_ts_kst
     , end_ts_kst
FROM (
    SELECT *, IFNULL(LEAD(min_start_ts_kst) OVER(PARTITION BY pid ORDER BY min_start_ts_kst), current_timestamp()) AS end_ts_kst
    FROM (
        SELECT
            pid
             , user_id
             , user_id_num
             , running_sum
             , MIN(min_event_timestamp_kst) AS min_start_ts_kst
        FROM TBL
        GROUP BY 1, 2, 3, 4
    )
)