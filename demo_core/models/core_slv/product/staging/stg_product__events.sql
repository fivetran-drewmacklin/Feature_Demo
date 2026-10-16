with source as (
    select * from {{ source('product', 'events') }}
),

parsed as (
    select
        event_id,
        lower(event_name) as event_name,
        account_id,
        contact_id,
        anonymous_id,
        session_id,
        event_timestamp,
        received_at,
        properties as properties_raw,
        try_parse_json(properties) as properties,
        datediff(minute, event_timestamp, received_at) as received_delay_minutes,
        _loaded_at
    from source
)

select * from parsed
