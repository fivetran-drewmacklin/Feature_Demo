select unique_id
from {{ info_schema('models') }}
where unique_id like 'model.demo_finance.%'
  and access = 'public'
  and not contract_enforced
