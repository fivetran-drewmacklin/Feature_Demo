select unique_id
from {{ info_schema('models') }}
where "group" = 'finance'
  and (
    (access = 'public' and materialized not in ('table', 'incremental'))
    or (access = 'protected' and materialized <> 'table')
  )
