{% macro normalize_airport_city_name_expr(expr) -%}
NULLIF(
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE({{ expr }}, r',.*$', ''),
                            r'\?\([^)]+\)\s*$',
                            ''
                        ),
                        r'\?[A-Z]{2}\s*$',
                        ''
                    ),
                    r'\s*\([^)]*\)$',
                    ''
                ),
                r'([A-Za-z])\?([A-Z][a-z])',
                '\\1 \\2'
            ),
            r'[?.]+$',
            ''
        )
    ),
    ''
)
{%- endmacro %}

{% macro normalize_airport_city_lookup_key_expr(expr) -%}
REGEXP_REPLACE(LOWER({{ expr }}), r'[^a-z0-9]', '')
{%- endmacro %}

{% macro cleanup_airport_name_suffix_expr(expr) -%}
NULLIF(
    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE({{ expr }}, r'\??official website$', ''),
            r'\s*\(closed\)$',
            ''
        )
    ),
    ''
)
{%- endmacro %}
