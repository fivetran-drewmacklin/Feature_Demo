select
    customer_id,
    customer_name,
    updated_at
from {{ ref('demo_core', 'customers') }}
