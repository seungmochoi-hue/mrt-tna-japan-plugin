{% macro mylink_conversion_purchase_select(item_id_expr, domain_nm_expr, platform_expr, mylink_item_flag_expr, extra_where, group_by_exprs) %}
SELECT
    '{{ var("logical_start_date_kst") }}' AS BASIS_DATE
  , {{ item_id_expr }} AS ITEM_ID
  , {{ domain_nm_expr }} AS DOMAIN_NM
  , L.MYLINK_ID
  , {{ platform_expr }} AS PLATFORM
  , {{ mylink_item_flag_expr }} AS MYLINK_ITEM_FLAG
  , COUNT(DISTINCT CASE WHEN P.INCOMING_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS TODAY_OFFER_DETAIL
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS TODAY_CHECKOUT
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS TODAY_CHECKOUT_COMPLETE
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS TODAY_CHECKOUT_WITHOUT_INFLOW
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("logical_start_date_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS TODAY_CHECKOUT_COMPLETE_WITHOUT_INFLOW
  , COUNT(DISTINCT CASE WHEN P.INCOMING_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS WEEKLY_OFFER_DETAIL
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS WEEKLY_CHECKOUT
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS WEEKLY_CHECKOUT_COMPLETE
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS WEEKLY_CHECKOUT_WITHOUT_INFLOW
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("before_7_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS WEEKLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW
  , COUNT(DISTINCT CASE WHEN P.INCOMING_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS MONTHLY_OFFER_DETAIL
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS MONTHLY_CHECKOUT
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' AND P.INCOMING_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS MONTHLY_CHECKOUT_COMPLETE
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS MONTHLY_CHECKOUT_WITHOUT_INFLOW
  , COUNT(DISTINCT CASE WHEN L.CHECKOUT_COMPLETE_KST_DT BETWEEN '{{ var("before_30_days_kst") }} 00:00:00' AND '{{ var("logical_start_date_kst") }} 23:59:59' THEN L.PID ELSE NULL END) AS MONTHLY_CHECKOUT_COMPLETE_WITHOUT_INFLOW
FROM {{ ref('MART_BIZ_LOG_MYLINK_ROW_D') }} L
LEFT JOIN INCOMING_LOG_PID_DT P
  ON L.PID = P.PID
 AND L.ITEM_ID = P.ITEM_ID
 AND L.MYLINK_ID = P.MYLINK_ID
LEFT JOIN {{ source('partners', 'mylink') }} M
  ON L.MYLINK_ID = CAST(M.id AS STRING)
LEFT JOIN {{ source('commons', 'short_url') }} S
  ON M.short_url_id = S.id
WHERE L.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}'
{% if extra_where %}  {{ extra_where }}{% endif %}
GROUP BY {{ group_by_exprs | join(', ') }}
{% endmacro %}

{% macro mylink_conversion_sale_select(gid_expr, domain_nm_expr, platform_expr, mylink_item_flag_expr, domain_where_condition, group_by_exprs) %}
SELECT
    '{{ var("logical_start_date_kst") }}' AS BASIS_DATE
  , S.MARKETING_LINK_ID
  , {{ gid_expr }} AS GID
  , {{ domain_nm_expr }} AS DOMAIN_NM
  , {{ platform_expr }} AS PLATFORM
  , {{ mylink_item_flag_expr }} AS MYLINK_ITEM_FLAG
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS TODAY_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS TODAY_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS TODAY_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS TODAY_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS TODAY_SALE_COMMISSION_PRICE
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS TODAY_CANCEL_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS TODAY_CANCEL_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS TODAY_CANCEL_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS TODAY_CANCEL_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("logical_start_date_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS TODAY_CANCEL_SALE_COMMISSION_PRICE
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS WEEKLY_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS WEEKLY_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS WEEKLY_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS WEEKLY_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS WEEKLY_SALE_COMMISSION_PRICE
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS WEEKLY_CANCEL_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS WEEKLY_CANCEL_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS WEEKLY_CANCEL_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS WEEKLY_CANCEL_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_7_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS WEEKLY_CANCEL_SALE_COMMISSION_PRICE
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS MONTHLY_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS MONTHLY_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS MONTHLY_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS MONTHLY_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 1 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS MONTHLY_SALE_COMMISSION_PRICE
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.USER_ID ELSE NULL END) AS MONTHLY_CANCEL_RESVE_USER_CNT
  , COUNT(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.ORDER_ID ELSE NULL END) AS MONTHLY_CANCEL_RESVE_QUANTITY_CNT
  , SUM(DISTINCT CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.RESVE_PRSNL_CNT ELSE NULL END) AS MONTHLY_CANCEL_SALE_QUANTITY_CNT
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN S.SALES_PRICE ELSE NULL END) AS MONTHLY_CANCEL_SALE_PRICE
  , SUM(CASE WHEN S.KIND = 2 AND S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}' THEN C.SALE_COMMISSION_PRICE ELSE NULL END) AS MONTHLY_CANCEL_SALE_COMMISSION_PRICE
FROM {{ ref('MART_SALE_D') }} S
LEFT JOIN {{ source('partners', 'mylink') }} M
  ON S.MARKETING_LINK_ID = CAST(M.ID AS STRING)
LEFT JOIN {{ source('commons', 'short_url') }} U
  ON M.short_url_id = U.id
LEFT JOIN COMMISION_PRICE C
  ON S.RESVE_ID = C.RESVE_ID
 AND S.KIND = C.KIND
WHERE S.BASIS_DATE BETWEEN '{{ var("before_30_days_kst") }}' AND '{{ var("logical_start_date_kst") }}'
  AND {{ domain_where_condition }}
  AND M.ID IS NOT NULL
GROUP BY {{ group_by_exprs | join(', ') }}
{% endmacro %}

