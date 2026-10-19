select unique_id
from {{ info_schema('models') }}
where access = 'public'
  and not contract_enforced
