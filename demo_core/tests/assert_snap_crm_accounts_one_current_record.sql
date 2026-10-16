select
    account_id,
    count_if(dbt_valid_to is null) as current_record_count
from {{ ref('snap_crm_accounts') }}
group by account_id
having count_if(dbt_valid_to is null) <> 1
