with sales_accounts as (
    select * from {{ ref('int_sales__accounts') }}
),

billing_customers as (
    select * from {{ ref('int_core__customer_matches') }}
),

billing_rollup as (
    select
        customer_id,
        listagg(billing_customer_id, ',') within group (order by billing_customer_id) as billing_customer_ids,
        max_by(customer_name, updated_at) as billing_customer_name,
        max_by(website_domain, updated_at) as billing_website_domain,
        max_by(billing_country, updated_at) as billing_country,
        max_by(billing_country_code, updated_at) as billing_country_code,
        max_by(currency, updated_at) as billing_currency,
        max_by(status, updated_at) as billing_status,
        min(created_at) as first_billing_created_at,
        max(updated_at) as last_billing_updated_at
    from billing_customers
    group by customer_id
)

select
    coalesce(sales_accounts.customer_id, billing_rollup.customer_id) as customer_id,
    sales_accounts.canonical_crm_account_id,
    sales_accounts.source_crm_account_ids,
    billing_rollup.billing_customer_ids,
    coalesce(sales_accounts.account_name, billing_rollup.billing_customer_name) as customer_name,
    coalesce(sales_accounts.website_domain, billing_rollup.billing_website_domain) as website_domain,
    coalesce(sales_accounts.billing_country, billing_rollup.billing_country) as billing_country,
    coalesce(sales_accounts.billing_country_code, billing_rollup.billing_country_code) as billing_country_code,
    sales_accounts.industry,
    sales_accounts.employee_count,
    sales_accounts.annual_revenue,
    coalesce(sales_accounts.account_currency, billing_rollup.billing_currency) as currency,
    sales_accounts.account_tier,
    billing_rollup.billing_status,
    case
        when sales_accounts.customer_id is not null and billing_rollup.customer_id is not null then 'crm_and_billing'
        when sales_accounts.customer_id is not null then 'crm_only'
        else 'billing_only'
    end as customer_source,
    least_ignore_nulls(sales_accounts.created_at, billing_rollup.first_billing_created_at) as created_at,
    greatest_ignore_nulls(sales_accounts.updated_at, billing_rollup.last_billing_updated_at) as updated_at
from sales_accounts
full outer join billing_rollup using (customer_id)
