{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set environment = target.name | upper -%}
    {%- if environment not in ['DEV', 'TST', 'PRD'] -%}
        {{ exceptions.raise_compiler_error(
            "Unsupported target '" ~ target.name ~ "'. Use DEV, TST, or PRD."
        ) }}
    {%- endif -%}

    {%- set custom_schema = custom_schema_name | trim | upper if custom_schema_name is not none else none -%}
    {%- set target_schema = target.schema | trim | upper -%}
    {%- set invocation_context = env_var('DBT_CLOUD_INVOCATION_CONTEXT', '') | trim | lower -%}
    {%- set job_id = env_var('DBT_CLOUD_JOB_ID', '') | trim | upper | replace('-', '_') -%}
    {%- if environment == 'TST' -%}
        {%- if target_schema.startswith('DBT_CLOUD_PR_') or invocation_context != 'ci' -%}
            {{ target_schema }}
        {%- elif job_id -%}
            DBT_CLOUD_CI_{{ job_id }}
        {%- else -%}
            {{ exceptions.raise_compiler_error(
                "TST CI runs require DBT_CLOUD_JOB_ID when no DBT_CLOUD_PR_* schema is provided."
            ) }}
        {%- endif -%}
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
