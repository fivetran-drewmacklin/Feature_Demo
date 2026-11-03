{# Intentionally broken, compile-only demo. Never merge this fixture to main. #}
{% set error_case = var('v2_error_case', 'none') %}
{{ config(enabled=(error_case != 'none'), static_analysis='strict') }}

{% if error_case == 'typo' %}

-- invoice_amout_usd is a misspelling of invoice_amount_usd.
select invoice_id, invoice_amout_usd
from {{ ref('invoice_financials') }}

{% elif error_case == 'upstream' %}

-- USD valuation belongs to Finance; the core invoice interface has no such column.
select invoice_id, invoice_amount_usd
from {{ ref('demo_core', 'invoices') }}

{% elif error_case == 'type' %}

-- A numeric invoice amount cannot be ordered against an ARRAY.
select invoice_id, invoice_amount_usd
from {{ ref('invoice_financials') }}
where invoice_amount_usd > array_construct(1, 2)

{% else %}

-- Harmless fallback; the analysis is disabled when v2_error_case is omitted.
select 1 as demo_disabled

{% endif %}
