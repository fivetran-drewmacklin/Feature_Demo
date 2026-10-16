{% macro normalize_domain(column_name) -%}
    nullif(
        regexp_replace(
            regexp_replace(lower(trim({{ column_name }})), '^https?://(www\\.)?', ''),
            '/+$',
            ''
        ),
        ''
    )
{%- endmacro %}
