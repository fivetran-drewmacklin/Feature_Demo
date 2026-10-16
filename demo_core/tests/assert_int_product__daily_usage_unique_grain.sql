select
    customer_id,
    event_date,
    count(*) as row_count
from {{ ref('int_product__daily_usage') }}
group by 1, 2
having count(*) > 1
