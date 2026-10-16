with source as (
    select * from {{ source('billing', 'invoice_lines') }}
),

renamed as (
    select
        invoice_line_id,
        invoice_id,
        upper(plan_code) as plan_code,
        lower(line_type) as line_type,
        {{ clean_string('description') }} as description,
        quantity,
        unit_amount_cents,
        line_amount_cents,
        service_period_start,
        service_period_end,
        updated_at,
        _loaded_at
    from source
)

select * from renamed
