with source_invoices as (

    select invoice_id
    from {{ ref('demo_core', 'invoices') }}

),

finance_invoices as (

    select invoice_id
    from {{ ref('invoice_financials') }}

),

missing_in_finance as (

    select
        'missing_in_finance' as failure_type,
        source_invoices.invoice_id
    from source_invoices
    left join finance_invoices
        on source_invoices.invoice_id = finance_invoices.invoice_id
    where finance_invoices.invoice_id is null

),

unexpected_in_finance as (

    select
        'unexpected_in_finance' as failure_type,
        finance_invoices.invoice_id
    from finance_invoices
    left join source_invoices
        on finance_invoices.invoice_id = source_invoices.invoice_id
    where source_invoices.invoice_id is null

)

select * from missing_in_finance
union all
select * from unexpected_in_finance
