select
    event_id,
    account_id,
    contact_id,
    anonymous_id,
    session_id,
    event_name,
    event_timestamp,
    received_at,
    _loaded_at
from {{ ref('stg_product__events') }}
where (account_id is null and contact_id is null and anonymous_id is null)
   or (event_name <> 'api_call' and session_id is null)
   or received_at < event_timestamp
   or _loaded_at < received_at
   or received_at > dateadd(day, 4, event_timestamp)
