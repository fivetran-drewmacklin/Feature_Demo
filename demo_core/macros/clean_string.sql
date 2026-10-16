{% macro clean_string(column_name) -%}
    nullif(trim({{ column_name }}), '')
{%- endmacro %}
