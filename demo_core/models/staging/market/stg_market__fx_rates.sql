with source as (
    select * from {{ source('market', 'fx_rates') }}
),

renamed as (
    select
        rate_date,
        upper(from_currency) as from_currency,
        upper(to_currency) as to_currency,
        rate,
        {{ clean_string('provider') }} as provider,
        _loaded_at
    from source
)

select * from renamed
