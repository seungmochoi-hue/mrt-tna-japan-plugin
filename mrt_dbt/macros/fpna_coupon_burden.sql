{% macro fpna_coupon_burden_price(amount_expr, coupon_info_alias, coupon_extra_alias, fallback_expr=None) -%}
IFNULL(
    CAST(
        SAFE_DIVIDE(
            CASE
                WHEN {{ coupon_info_alias }}.COUPON_ID IS NOT NULL
                     AND {{ coupon_info_alias }}.MRT_RATE IS NOT NULL
                    THEN {{ coupon_info_alias }}.MRT_RATE * {{ amount_expr }}
                WHEN {{ coupon_info_alias }}.COUPON_ID IS NOT NULL
                     AND {{ coupon_info_alias }}.MRT_VALUE IS NOT NULL
                    THEN {{ coupon_info_alias }}.MRT_VALUE
                WHEN {{ coupon_extra_alias }}.COUPON_ID IS NOT NULL
                     AND {{ coupon_extra_alias }}.MRT_VALUE IS NOT NULL
                    THEN {{ coupon_extra_alias }}.MRT_VALUE
                WHEN {{ coupon_extra_alias }}.COUPON_ID IS NOT NULL
                     AND {{ coupon_extra_alias }}.MRT_CONTRIBUTION_RATE IS NOT NULL
                    THEN SAFE_DIVIDE({{ coupon_extra_alias }}.MRT_CONTRIBUTION_RATE, 100) * {{ amount_expr }}
                ELSE
                    {% if fallback_expr is none -%}
                        {{ amount_expr }}
                    {%- else -%}
                        {{ fallback_expr }}
                    {%- endif %}
            END,
            1.1
        ) AS INT64
    ),
    0
)
{%- endmacro %}
