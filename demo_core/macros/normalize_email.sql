{% macro normalize_email(column_name) -%}
    lower({{ clean_string(column_name) }})
{%- endmacro %}
