with source as (
    select * from {{ source('billing', 'payments') }}
),

renamed as (
    select
        payment_id,
        invoice_id,
        billing_customer_id,
        lower(status) as status,
        amount_cents,
        upper(currency) as currency,
        paid_at,
        lower(payment_method) as payment_method,
        processor_reference,
        updated_at,
        _loaded_at
    from source
)

select * from renamed
