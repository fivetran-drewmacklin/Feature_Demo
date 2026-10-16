with country_codes as (
    select
        {{ country_join_key('raw_country') }} as normalized_country,
        country_code,
        country_name
    from {{ ref('country_codes') }}
),

one_row_per_normalized_country as (
    select
        normalized_country,
        max(country_code) as country_code,
        max(country_name) as country_name
    from country_codes
    group by normalized_country
)

select *
from one_row_per_normalized_country
