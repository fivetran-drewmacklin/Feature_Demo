with source as (
    select * from {{ source('billing', 'subscriptions') }}
),

renamed as (
    select
        subscription_id,
        billing_customer_id,
        upper(plan_code) as plan_code,
        lower(status) as status,
        started_at,
        current_period_start,
        current_period_end,
        canceled_at,
        quantity,
        unit_price_cents,
        upper(currency) as currency,
        updated_at,
        _loaded_at
    from source
)

select * from renamed
