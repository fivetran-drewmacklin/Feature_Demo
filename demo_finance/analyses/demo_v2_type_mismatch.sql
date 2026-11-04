{{ config(static_analysis='strict') }}


-- Intentional NUMBER-to-ARRAY comparison. Compile only on demo/v2-errors.
select invoice_id, invoice_amount_usd
from {{ ref('invoice_financials') }}
where invoice_amount_usd > array_construct(1, 2)
