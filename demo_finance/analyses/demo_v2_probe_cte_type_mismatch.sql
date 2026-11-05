{{ config(static_analysis='strict') }}

-- Temporary editor diagnostic probe: no refs or warehouse dependencies.
-- Intentional NUMBER-to-ARRAY comparison. Compile only on demo/v2-errors.
with sample_invoice as (
    select
        cast('probe-1' as varchar) as invoice_id,
        cast(100 as number(38, 2)) as invoice_amount_usd
)

select invoice_id, invoice_amount_usd
from sample_invoice
where invoice_amount_usd > array_construct(1, 2)
