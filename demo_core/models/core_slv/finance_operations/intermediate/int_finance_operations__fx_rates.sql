with rates as (
    select * from {{ ref('stg_market__fx_rates') }}
),

dates as (
    select distinct rate_date from rates
),

currencies as (
    select distinct from_currency from rates
),

date_currency_spine as (
    select dates.rate_date, currencies.from_currency
    from dates
    cross join currencies
),

joined as (
    select
        spine.rate_date,
        spine.from_currency,
        'USD' as to_currency,
        rates.rate as exact_rate,
        rates.provider,
        rates._loaded_at
    from date_currency_spine as spine
    left join rates
        on spine.rate_date = rates.rate_date
       and spine.from_currency = rates.from_currency
       and rates.to_currency = 'USD'
)

select
    rate_date,
    from_currency,
    to_currency,
    last_value(exact_rate ignore nulls) over (
        partition by from_currency
        order by rate_date
        rows between unbounded preceding and current row
    ) as rate,
    last_value(iff(exact_rate is not null, rate_date, null) ignore nulls) over (
        partition by from_currency
        order by rate_date
        rows between unbounded preceding and current row
    ) as source_rate_date,
    exact_rate is null as used_prior_rate,
    last_value(provider ignore nulls) over (
        partition by from_currency
        order by rate_date
        rows between unbounded preceding and current row
    ) as provider,
    last_value(_loaded_at ignore nulls) over (
        partition by from_currency
        order by rate_date
        rows between unbounded preceding and current row
    ) as _loaded_at
from joined
