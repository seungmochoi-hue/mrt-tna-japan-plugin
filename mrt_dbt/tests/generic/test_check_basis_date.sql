{% test check_basis_date(model, column_name) %}

with validation as (

    select
        {{ column_name }} as {{ column_name }}

    from {{ model }}

),

validation_errors as (

    select
        {{ column_name }}
    from validation
    where not {{ column_name }} between '{{ var("start_date") }}' and '{{ var("end_date") }}'
)

select *
from validation_errors

{% endtest %}
