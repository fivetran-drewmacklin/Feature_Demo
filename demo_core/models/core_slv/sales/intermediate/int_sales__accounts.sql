with account_map as (
    select * from {{ ref('int_sales__account_map') }}
),

members as (
    select
        canonical_crm_account_id,
        listagg(source_crm_account_id, ',') within group (order by source_crm_account_id) as source_crm_account_ids
    from account_map
    group by canonical_crm_account_id
),

canonical_accounts as (
    select *
    from account_map
    where is_canonical_account
      and not is_deleted
)

select
    canonical_accounts.customer_id,
    canonical_accounts.canonical_crm_account_id,
    members.source_crm_account_ids,
    canonical_accounts.source_account_count,
    canonical_accounts.company_match_key,
    canonical_accounts.normalized_account_name,
    canonical_accounts.account_name,
    canonical_accounts.website_domain,
    canonical_accounts.billing_country,
    canonical_accounts.billing_country_code,
    canonical_accounts.industry,
    canonical_accounts.employee_count,
    canonical_accounts.annual_revenue,
    canonical_accounts.account_currency,
    canonical_accounts.account_tier,
    canonical_accounts.owner_sales_rep_id,
    canonical_accounts.created_at,
    canonical_accounts.updated_at,
    canonical_accounts._loaded_at
from canonical_accounts
inner join members using (canonical_crm_account_id)
