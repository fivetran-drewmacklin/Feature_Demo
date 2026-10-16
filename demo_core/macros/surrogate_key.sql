{% macro surrogate_key(fields) -%}
    md5(
        concat_ws(
            '||'
            {%- for field in fields %}
            , coalesce(cast({{ field }} as varchar), '_dbt_null_')
            {%- endfor %}
        )
    )
{%- endmacro %}
