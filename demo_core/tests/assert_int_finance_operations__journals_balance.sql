{{ config(severity = 'warn', store_failures = true) }}

select
    journal_id,
    currency,
    sum(debit_cents) as debit_cents,
    sum(credit_cents) as credit_cents,
    sum(signed_amount_cents) as imbalance_cents
from {{ ref('int_finance_operations__gl_entries') }}
group by journal_id, currency
having sum(signed_amount_cents) <> 0
