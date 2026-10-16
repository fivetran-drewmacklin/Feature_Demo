with customers as (
    select * from {{ ref('stg_billing__customers') }}
)

select
    billing_customer_id,
    crm_account_id,
    customer_name,
    {{ normalize_company_name('customer_name') }} as normalized_customer_name,
    website_domain,
    billing_email,
    billing_country_raw,
    billing_country,
    billing_country_code,
    currency,
    status,
    tax_id,
    created_at,
    updated_at,
    _loaded_at
from customers
