select
    rate_date,
    from_currency,
    to_currency,
    count(*) as row_count
from {{ ref('stg_market__fx_rates') }}
group by 1, 2, 3
having count(*) > 1
