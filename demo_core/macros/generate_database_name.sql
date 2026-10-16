{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- set environment = target.name | upper -%}
    {%- if environment not in ['DEV', 'TST', 'PRD'] -%}
        {{ exceptions.raise_compiler_error(
            "Unsupported target '" ~ target.name ~ "'. Use DEV, TST, or PRD."
        ) }}
    {%- endif -%}

    {%- if custom_database_name is none -%}
        {{ target.database }}
    {%- else -%}
        {%- set logical_database = custom_database_name | trim | upper -%}
        {%- set prefix = 'PRD_' if environment == 'PRD' else 'DEV_' -%}
        {%- if logical_database.startswith('DEV_') or logical_database.startswith('PRD_') -%}
            {{ logical_database }}
        {%- else -%}
            {{ prefix }}{{ logical_database }}
        {%- endif -%}
    {%- endif -%}
{%- endmacro %}
