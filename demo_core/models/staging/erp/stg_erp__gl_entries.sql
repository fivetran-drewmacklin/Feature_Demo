with source as (
    select * from {{ source('erp', 'gl_entries') }}
),

renamed as (
    select
        gl_entry_id,
        journal_id,
        line_number,
        posted_date,
        upper(account_code) as account_code,
        cost_center_id,
        invoice_id,
        {{ clean_string('description') }} as description,
        debit_cents,
        credit_cents,
        debit_cents - credit_cents as signed_amount_cents,
        upper(currency) as currency,
        created_at,
        _loaded_at
    from source
)

select * from renamed
