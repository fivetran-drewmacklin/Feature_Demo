{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'invoice_id',
    on_schema_change = 'sync_all_columns'
) }}

with invoices as (
    select * from {{ ref('stg_billing__invoices') }}
),

invoice_lines as (
    select * from {{ ref('stg_billing__invoice_lines') }}
),

payments as (
    select * from {{ ref('stg_billing__payments') }}
),

refunds as (
    select * from {{ ref('stg_billing__refunds') }}
),

changed_invoice_ids as (
    {% if is_incremental() %}
    select invoice_id from invoices
    where updated_at >= (select coalesce(max(record_updated_at), '1900-01-01'::timestamp_tz) from {{ this }})
    union
    select invoice_id from invoice_lines
    where updated_at >= (select coalesce(max(record_updated_at), '1900-01-01'::timestamp_tz) from {{ this }})
    union
    select invoice_id from payments
    where updated_at >= (select coalesce(max(record_updated_at), '1900-01-01'::timestamp_tz) from {{ this }})
    union
    select invoice_id from refunds
    where updated_at >= (select coalesce(max(record_updated_at), '1900-01-01'::timestamp_tz) from {{ this }})
    {% else %}
    select invoice_id from invoices
    {% endif %}
),

selected_invoices as (
    select invoices.*
    from invoices
    inner join changed_invoice_ids using (invoice_id)
),

line_summary as (
    select
        invoice_id,
        sum(iff(line_type in ('subscription', 'services'), line_amount_cents, 0)) as calculated_subtotal_cents,
        abs(sum(iff(line_type = 'credit', line_amount_cents, 0))) as calculated_discount_cents,
        sum(iff(line_type = 'tax', line_amount_cents, 0)) as calculated_tax_cents,
        max(updated_at) as lines_updated_at
    from invoice_lines
    where invoice_id in (select invoice_id from changed_invoice_ids)
    group by invoice_id
),

payment_summary as (
    select
        invoice_id,
        sum(iff(status = 'succeeded', amount_cents, 0)) as successful_payment_cents,
        max(updated_at) as payments_updated_at
    from payments
    where invoice_id in (select invoice_id from changed_invoice_ids)
    group by invoice_id
),

refund_summary as (
    select
        invoice_id,
        sum(iff(status = 'succeeded', amount_cents, 0)) as successful_refund_cents,
        max(updated_at) as refunds_updated_at
    from refunds
    where invoice_id in (select invoice_id from changed_invoice_ids)
    group by invoice_id
),

customer_matches as (
    select * from {{ ref('int_core__customer_matches') }}
),

calculated as (
    select
        selected_invoices.*,
        customer_matches.customer_id,
        line_summary.calculated_subtotal_cents,
        line_summary.calculated_discount_cents,
        line_summary.calculated_tax_cents,
        line_summary.calculated_subtotal_cents
            - line_summary.calculated_discount_cents
            + line_summary.calculated_tax_cents as calculated_total_cents,
        coalesce(payment_summary.successful_payment_cents, 0) as successful_payment_cents,
        coalesce(refund_summary.successful_refund_cents, 0) as successful_refund_cents,
        coalesce(payment_summary.successful_payment_cents, 0)
            - coalesce(refund_summary.successful_refund_cents, 0) as net_collections_cents,
        greatest_ignore_nulls(
            selected_invoices.updated_at,
            line_summary.lines_updated_at,
            payment_summary.payments_updated_at,
            refund_summary.refunds_updated_at
        ) as record_updated_at
    from selected_invoices
    inner join customer_matches using (billing_customer_id)
    left join line_summary using (invoice_id)
    left join payment_summary using (invoice_id)
    left join refund_summary using (invoice_id)
)

select
    *,
    subtotal_cents = calculated_subtotal_cents
        and discount_cents = calculated_discount_cents
        and tax_cents = calculated_tax_cents
        and total_cents = calculated_total_cents as is_reconciled,
    total_cents - calculated_total_cents as reconciliation_difference_cents
from calculated
