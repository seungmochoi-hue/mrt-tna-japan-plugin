{% macro make_date_partitioned_table_name(table_name, date_var_name="today_utc") %}
    {% set date_value = var(date_var_name, modules.datetime.date.today().strftime('%Y-%m-%d')) %}
    {% set suffix_date = modules.datetime.datetime.strptime(date_value, '%Y-%m-%d').strftime('%Y%m%d') %}

    {{ return(table_name ~ '_' ~ suffix_date) }}
{% endmacro %}