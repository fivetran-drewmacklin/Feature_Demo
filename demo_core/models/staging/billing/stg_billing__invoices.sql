with source as (
    select * from {{ source('billing', 'invoices') }}
),

cleaned as (
    select
        invoice_id,
        invoice_number,
        billing_customer_id,
        subscription_id,
        status as status_raw,
        case
            when lower(status) in ('paid', 'paid_late', 'complete') then 'paid'
            else lower(status)
        end as status,
        issue_date,
        due_date,
        paid_at,
        subtotal_cents,
        discount_cents,
        tax_cents,
        total_cents,
        amount_due_cents,
        upper(currency) as currency,
        updated_at,
        _loaded_at
    from source
)

select * from cleaned
