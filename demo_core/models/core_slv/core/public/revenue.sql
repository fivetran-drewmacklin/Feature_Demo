with invoices as (
    select * from {{ ref('int_billing__invoices') }}
),

fx_rates as (
    select * from {{ ref('int_finance_operations__fx_rates') }}
)

select
    invoices.invoice_id,
    invoices.invoice_number,
    invoices.customer_id,
    invoices.billing_customer_id,
    invoices.subscription_id,
    invoices.status,
    invoices.issue_date,
    invoices.due_date,
    invoices.paid_at,
    invoices.currency,
    invoices.subtotal_cents,
    invoices.discount_cents,
    invoices.tax_cents,
    invoices.total_cents,
    invoices.amount_due_cents,
    invoices.successful_payment_cents,
    invoices.successful_refund_cents,
    invoices.net_collections_cents,
    fx_rates.rate as usd_exchange_rate,
    fx_rates.source_rate_date,
    fx_rates.used_prior_rate,
    round(invoices.total_cents * fx_rates.rate)::number(18, 0) as total_usd_cents,
    round(invoices.net_collections_cents * fx_rates.rate)::number(18, 0) as net_collections_usd_cents,
    invoices.is_reconciled,
    invoices.record_updated_at
from invoices
inner join fx_rates
    on invoices.issue_date = fx_rates.rate_date
   and invoices.currency = fx_rates.from_currency
