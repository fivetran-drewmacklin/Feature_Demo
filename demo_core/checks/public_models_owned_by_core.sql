select unique_id
from {{ info_schema('models') }}
where access = 'public'
  and ("group" is null or "group" <> 'core')
