select unique_id
from {{ info_schema('models') }}
where name like 'stg\_%' escape '\'
  and materialized <> 'view'
