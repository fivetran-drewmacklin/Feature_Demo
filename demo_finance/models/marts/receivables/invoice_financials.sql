with invoices as (

    select
        invoice_id,
        invoice_number,
        customer_id,
        billing_customer_id,
        subscription_id,
        status,
        issue_date,
        due_date,
        paid_at,
        currency,
        subtotal_cents,
        discount_cents,
        tax_cents,
        total_cents,
        amount_due_cents,
        calculated_subtotal_cents,
        calculated_discount_cents,
        calculated_tax_cents,
        calculated_total_cents,
        successful_payment_cents,
        successful_refund_cents,
        net_collections_cents,
        is_reconciled,
        reconciliation_difference_cents,
        record_updated_at,
        _loaded_at
    from {{ ref('demo_core', 'invoices') }}

),

fx_rates as (

    select
        rate_date,
        from_currency,
        rate,
        source_rate_date,
        used_prior_rate,
        provider
    from {{ ref('demo_core', 'fx_rates') }}

),

invoices_with_fx as (

    select
        invoices.*,
        case
            when invoices.currency = 'USD' then cast(1 as number(18, 8))
            else fx_rates.rate
        end as fx_rate_to_usd,
        case
            when invoices.currency = 'USD' then invoices.issue_date
            else fx_rates.source_rate_date
        end as fx_rate_source_date,
        case
            when invoices.currency = 'USD' then false
            else fx_rates.used_prior_rate
        end as used_prior_fx_rate,
        case
            when invoices.currency = 'USD' then 'identity'
            else fx_rates.provider
        end as fx_provider
    from invoices
    left join fx_rates
        on invoices.issue_date = fx_rates.rate_date
        and invoices.currency = fx_rates.from_currency

)

select
    invoice_id,
    invoice_number,
    customer_id,
    billing_customer_id,
    subscription_id,
    status,
    issue_date,
    due_date,
    paid_at,
    currency as source_currency,
    fx_rate_to_usd,
    fx_rate_source_date,
    used_prior_fx_rate,
    fx_provider,
    subtotal_cents,
    discount_cents,
    tax_cents,
    total_cents,
    amount_due_cents,
    calculated_subtotal_cents,
    calculated_discount_cents,
    calculated_tax_cents,
    calculated_total_cents,
    successful_payment_cents,
    successful_refund_cents,
    net_collections_cents,
    cast(total_cents / 100.0 as number(38, 2)) as invoice_amount,
    cast(amount_due_cents / 100.0 as number(38, 2)) as outstanding_receivable_amount,
    cast(successful_payment_cents / 100.0 as number(38, 2)) as successful_payment_amount,
    cast(successful_refund_cents / 100.0 as number(38, 2)) as refund_amount,
    cast(net_collections_cents / 100.0 as number(38, 2)) as net_collections_amount,
    cast(round((total_cents / 100.0) * fx_rate_to_usd, 2) as number(38, 2)) as invoice_amount_usd,
    cast(round((amount_due_cents / 100.0) * fx_rate_to_usd, 2) as number(38, 2)) as outstanding_receivable_amount_usd,
    cast(round((successful_payment_cents / 100.0) * fx_rate_to_usd, 2) as number(38, 2)) as successful_payment_amount_usd,
    cast(round((successful_refund_cents / 100.0) * fx_rate_to_usd, 2) as number(38, 2)) as refund_amount_usd,
    cast(round((net_collections_cents / 100.0) * fx_rate_to_usd, 2) as number(38, 2)) as net_collections_amount_usd,
    is_reconciled,
    reconciliation_difference_cents,
    record_updated_at,
    _loaded_at
from invoices_with_fx
