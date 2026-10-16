{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set environment = target.name | upper -%}
    {%- if environment not in ['DEV', 'TST', 'PRD'] -%}
        {{ exceptions.raise_compiler_error(
            "Unsupported target '" ~ target.name ~ "'. Use DEV, TST, or PRD."
        ) }}
    {%- endif -%}

    {%- set custom_schema = custom_schema_name | trim | upper if custom_schema_name is not none else none -%}
    {%- if environment == 'TST' -%}
        {{ target.schema | upper }}
    {%- elif custom_schema is none -%}
        {{ target.schema | upper }}
    {%- elif environment == 'PRD' -%}
        {{ custom_schema }}
    {%- else -%}
        {%- set sandbox = var('sandbox', none) -%}
        {%- if sandbox -%}
            SANDBOX_{{ sandbox | trim | upper | replace('-', '_') }}_{{ custom_schema }}
        {%- else -%}
            {{ custom_schema }}
        {%- endif -%}
    {%- endif -%}
{%- endmacro %}
