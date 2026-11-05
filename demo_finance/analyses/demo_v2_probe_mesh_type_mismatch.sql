{{ config(static_analysis='strict') }}

-- Temporary editor diagnostic probe: published Core interface, no local refs.
-- Intentional NUMBER-to-ARRAY comparison. Compile only on demo/v2-errors.
select invoice_id, total_cents
from {{ ref('demo_core', 'invoices') }}
where total_cents > array_construct(1, 2)
