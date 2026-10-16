with source as (
    select * from {{ source('billing', 'refunds') }}
),

renamed as (
    select
        refund_id,
        payment_id,
        invoice_id,
        amount_cents,
        upper(currency) as currency,
        lower({{ clean_string('reason') }}) as reason,
        lower(status) as status,
        refunded_at,
        updated_at,
        _loaded_at
    from source
)

select * from renamed
