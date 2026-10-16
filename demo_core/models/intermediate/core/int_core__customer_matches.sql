with billing_customers as (
    select * from {{ ref('int_billing__customers') }}
),

account_map as (
    select * from {{ ref('int_sales__account_map') }}
),

sales_accounts as (
    select * from {{ ref('int_sales__accounts') }}
),

active_account_map as (
    select
        account_map.source_crm_account_id,
        account_map.canonical_crm_account_id
    from account_map
    inner join sales_accounts using (canonical_crm_account_id)
),

unique_domain_matches as (
    select
        website_domain,
        min(canonical_crm_account_id) as canonical_crm_account_id
    from sales_accounts
    where website_domain is not null
    group by website_domain
    having count(*) = 1
),

unique_name_matches as (
    select
        normalized_account_name,
        min(canonical_crm_account_id) as canonical_crm_account_id
    from sales_accounts
    where normalized_account_name is not null
    group by normalized_account_name
    having count(*) = 1
),

candidates as (
    select
        billing_customers.*,
        direct_match.canonical_crm_account_id as direct_crm_account_id,
        domain_match.canonical_crm_account_id as domain_crm_account_id,
        name_match.canonical_crm_account_id as name_crm_account_id
    from billing_customers
    left join active_account_map as direct_match
        on billing_customers.crm_account_id = direct_match.source_crm_account_id
    left join unique_domain_matches as domain_match
        on billing_customers.website_domain = domain_match.website_domain
    left join unique_name_matches as name_match
        on billing_customers.normalized_customer_name = name_match.normalized_account_name
),

resolved as (
    select
        *,
        case
            when domain_crm_account_id is not null
                and (direct_crm_account_id is null or direct_crm_account_id <> domain_crm_account_id)
                then domain_crm_account_id
            when direct_crm_account_id is not null then direct_crm_account_id
            when domain_crm_account_id is not null then domain_crm_account_id
            when name_crm_account_id is not null then name_crm_account_id
        end as canonical_crm_account_id,
        case
            when domain_crm_account_id is not null
                and direct_crm_account_id is not null
                and direct_crm_account_id <> domain_crm_account_id
                then 'domain_override'
            when direct_crm_account_id is not null then 'direct_crm_id'
            when domain_crm_account_id is not null then 'domain'
            when name_crm_account_id is not null then 'normalized_name'
            else 'billing_only'
        end as match_method,
        crm_account_id is not null
            and (
                direct_crm_account_id is null
                or (
                    domain_crm_account_id is not null
                    and direct_crm_account_id <> domain_crm_account_id
                )
            ) as has_crm_account_id_discrepancy
    from candidates
)

select
    coalesce(
        sales_accounts.customer_id,
        {{ surrogate_key(["'billing'", 'resolved.billing_customer_id']) }}
    ) as customer_id,
    resolved.billing_customer_id,
    resolved.crm_account_id as source_crm_account_id,
    resolved.canonical_crm_account_id,
    resolved.match_method,
    resolved.has_crm_account_id_discrepancy,
    resolved.customer_name,
    resolved.normalized_customer_name,
    resolved.website_domain,
    resolved.billing_email,
    resolved.billing_country,
    resolved.billing_country_code,
    resolved.currency,
    resolved.status,
    resolved.tax_id,
    resolved.created_at,
    resolved.updated_at,
    resolved._loaded_at
from resolved
left join sales_accounts using (canonical_crm_account_id)
