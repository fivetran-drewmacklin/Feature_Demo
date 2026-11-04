{{ config(static_analysis='strict') }}


-- Intentional typo. Compile only on demo/v2-errors; never merge to main.
select invoice_id, invoice_amout_usd
from {{ ref('invoice_financials') }}
