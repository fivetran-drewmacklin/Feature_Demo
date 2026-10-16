with events as (
    select * from {{ ref('stg_product__events') }}
),

account_map as (
    select * from {{ ref('int_sales__account_map') }}
),

contacts as (
    select * from {{ ref('int_sales__contacts') }}
),

resolved as (
    select
        coalesce(account_map.customer_id, contacts.customer_id) as customer_id,
        to_date(convert_timezone('UTC', events.event_timestamp)) as event_date,
        events.event_name,
        events.received_delay_minutes
    from events
    left join account_map
        on events.account_id = account_map.source_crm_account_id
    left join contacts
        on events.contact_id = contacts.contact_id
)

select
    customer_id,
    event_date,
    count(*) as event_count,
    count_if(event_name = 'login') as login_count,
    count_if(event_name = 'feature_used') as feature_used_count,
    count_if(event_name = 'report_created') as report_created_count,
    count_if(event_name = 'export_completed') as export_completed_count,
    count_if(received_delay_minutes >= 1440) as late_event_count,
    max(received_delay_minutes) as max_received_delay_minutes
from resolved
where customer_id is not null
group by 1, 2
