{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}
    {%- set target_name = target.name -%}

    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- else -%}

        {%- if target_name == 'prod' -%}

            {{ custom_schema_name | trim }}

        {%- else -%}

            {{ custom_schema_name | trim }}_{{ target_name }}

        {%- endif -%}
    {%- endif -%}

{%- endmacro %}
