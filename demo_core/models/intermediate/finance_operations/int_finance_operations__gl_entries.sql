with gl_entries as (
    select * from {{ ref('stg_erp__gl_entries') }}
),

accounts as (
    select * from {{ ref('chart_of_accounts') }}
),

invoices as (
    select invoice_id, customer_id from {{ ref('int_billing__invoices') }}
)

select
    gl_entries.gl_entry_id,
    gl_entries.journal_id,
    gl_entries.line_number,
    gl_entries.posted_date,
    gl_entries.account_code,
    accounts.account_name,
    accounts.account_type,
    accounts.financial_statement,
    accounts.sign_convention,
    gl_entries.cost_center_id,
    gl_entries.invoice_id,
    invoices.customer_id,
    gl_entries.description,
    gl_entries.debit_cents,
    gl_entries.credit_cents,
    gl_entries.signed_amount_cents,
    gl_entries.currency,
    gl_entries.created_at,
    gl_entries._loaded_at
from gl_entries
inner join accounts using (account_code)
left join invoices using (invoice_id)
