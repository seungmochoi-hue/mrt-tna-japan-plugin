{% macro generate_alias_name(custom_alias_name=none, node=none) -%}

    {%- if custom_alias_name -%}

        {{ custom_alias_name | trim }}

    {%- elif node.version -%}

        {{ return(node.name ~ "_v" ~ (node.version | replace(".", "_"))) }}

    {%- else -%}

        {{ node.name }}

    {%- endif -%}

{%- endmacro %}


{% macro make_temp_relation(base_relation, suffix='__dbt_tmp') %}
  {% set date_suffix = var("logical_start_date_kst", "default") %}
  {% set new_suffix = suffix ~ "__" ~ date_suffix %}
  {{ return(adapter.dispatch('make_temp_relation')(base_relation, new_suffix)) }}
{% endmacro %}