{% macro country_join_key(column_name) -%}
    lower(trim({{ column_name }}))
{%- endmacro %}
