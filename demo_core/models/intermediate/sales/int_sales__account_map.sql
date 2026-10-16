with accounts as (
    select
        *,
        {{ normalize_company_name('account_name') }} as normalized_account_name,
        coalesce(
            'domain:' || website_domain,
            'name:' || {{ normalize_company_name('account_name') }}
        ) as company_match_key
    from {{ ref('stg_crm__accounts') }}
),

ranked as (
    select
        *,
        first_value(account_id) over (
            partition by company_match_key
            order by is_deleted, created_at, account_id
        ) as canonical_crm_account_id,
        count(*) over (partition by company_match_key) as source_account_count,
        row_number() over (
            partition by company_match_key
            order by is_deleted, created_at, account_id
        ) as canonical_rank
    from accounts
),

final as (
    select
        {{ surrogate_key(["'crm'", 'canonical_crm_account_id']) }} as customer_id,
        account_id as source_crm_account_id,
        canonical_crm_account_id,
        canonical_rank = 1 as is_canonical_account,
        source_account_count,
        company_match_key,
        normalized_account_name,
        account_name,
        website_domain,
        billing_country_raw,
        billing_country,
        billing_country_code,
        industry,
        employee_count,
        annual_revenue,
        account_currency,
        account_tier,
        owner_sales_rep_id,
        created_at,
        updated_at,
        is_deleted,
        deleted_at,
        _loaded_at
    from ranked
)

select * from final
