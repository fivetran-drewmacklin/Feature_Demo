select
    customer_id,
    canonical_crm_account_id,
    source_crm_account_ids,
    customer_name,
    website_domain,
    billing_country,
    billing_country_code,
    industry,
    employee_count,
    annual_revenue,
    currency,
    account_tier,
    created_at,
    updated_at
from {{ ref('customers', v=2) }}
