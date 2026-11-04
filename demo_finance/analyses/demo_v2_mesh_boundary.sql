{{ config(static_analysis='strict') }}


-- Finance owns USD valuation; Core's public invoice interface has no USD amount.
select invoice_id, invoice_amount_usd
from {{ ref('demo_core', 'invoices') }}
