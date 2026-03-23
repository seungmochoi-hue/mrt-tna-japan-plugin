{% macro remove_date_suffix(table_id) %}
  {{ return((table_id|string)[:-10] + "_*`") }}
{% endmacro %}