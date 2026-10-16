select
    rate_date,
    from_currency,
    to_currency,
    count(*) as row_count
from {{ ref('int_finance_operations__fx_rates') }}
group by 1, 2, 3
having count(*) > 1
