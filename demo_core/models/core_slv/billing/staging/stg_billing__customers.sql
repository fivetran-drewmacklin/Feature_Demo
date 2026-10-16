with source as (
    select * from {{ source('billing', 'customers') }}
),

country_codes as (
    select * from {{ ref('int_core__country_codes') }}
),

cleaned as (
    select
        source.billing_customer_id,
        source.crm_account_id,
        {{ clean_string('source.customer_name') }} as customer_name,
        {{ normalize_domain('source.website_domain') }} as website_domain,
        {{ normalize_email('source.billing_email') }} as billing_email,
        source.billing_country as billing_country_raw,
        case when source.billing_country is null then null else coalesce(country_codes.country_name, 'UNKNOWN') end as billing_country,
        case when source.billing_country is null then null else coalesce(country_codes.country_code, 'UNKNOWN') end as billing_country_code,
        upper(source.currency) as currency,
        lower(source.status) as status,
        {{ clean_string('source.tax_id') }} as tax_id,
        source.created_at,
        source.updated_at,
        source._loaded_at
    from source
    left join country_codes
        on {{ country_join_key('source.billing_country') }} = country_codes.normalized_country
)

select * from cleaned
