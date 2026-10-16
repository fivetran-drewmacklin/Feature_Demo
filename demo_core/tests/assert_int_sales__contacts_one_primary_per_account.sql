select
    source_crm_account_id,
    count_if(is_primary) as primary_contact_count
from {{ ref('int_sales__contacts') }}
group by source_crm_account_id
having count_if(is_primary) > 1

