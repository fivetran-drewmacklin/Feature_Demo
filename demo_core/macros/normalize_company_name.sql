{% macro normalize_company_name(column_name) -%}
    nullif(
        regexp_replace(
            regexp_replace(
                regexp_replace(
                    lower({{ clean_string(column_name) }}),
                    '\\s*\\(self serve\\)\\s*$',
                    ''
                ),
                '\\s+(incorporated|inc|llc|ltd|limited|gmbh|b\\.?v\\.?|corp|corporation)\\.?$',
                ''
            ),
            '[^a-z0-9]',
            ''
        ),
        ''
    )
{%- endmacro %}
