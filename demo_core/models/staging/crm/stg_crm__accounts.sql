with source as (
    select *
    from {{ source('crm', 'accounts') }}
),

country_codes as (
    select *
    from {{ ref('int_core__country_codes') }}
),

cleaned as (
    select
        source.account_id,
        {{ clean_string('source.account_name') }} as account_name,
        {{ normalize_domain('source.website_domain') }} as website_domain,
        source.billing_country as billing_country_raw,
        case
            when source.billing_country is null then null
            else coalesce(country_codes.country_name, 'UNKNOWN')
        end as billing_country,
        case
            when source.billing_country is null then null
            else coalesce(country_codes.country_code, 'UNKNOWN')
        end as billing_country_code,
        {{ clean_string('source.industry') }} as industry,
        source.employee_count,
        source.annual_revenue,
        upper(source.account_currency) as account_currency,
        lower(source.account_tier) as account_tier,
        source.owner_sales_rep_id,
        source.created_at,
        source.updated_at,
        source.is_deleted,
        source.deleted_at,
        source._loaded_at
    from source
    left join country_codes
        on {{ country_join_key('source.billing_country') }} = country_codes.normalized_country
)

select *
from cleaned
