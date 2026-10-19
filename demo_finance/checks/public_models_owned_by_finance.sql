select unique_id
from {{ info_schema('models') }}
where unique_id like 'model.demo_finance.%'
  and access = 'public'
  and ("group" is null or "group" <> 'finance')
