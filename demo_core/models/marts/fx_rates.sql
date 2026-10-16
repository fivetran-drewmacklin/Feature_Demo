select
    rate_date,
    from_currency,
    to_currency,
    rate,
    source_rate_date,
    used_prior_rate,
    provider,
    _loaded_at
from {{ ref('int_finance_operations__fx_rates') }}
