with contacts as (
    select * from {{ ref('stg_crm__contacts') }}
),

account_map as (
    select * from {{ ref('int_sales__account_map') }}
),

active_accounts as (
    select canonical_crm_account_id from {{ ref('int_sales__accounts') }}
)

select
    contacts.contact_id,
    account_map.customer_id,
    account_map.canonical_crm_account_id,
    contacts.account_id as source_crm_account_id,
    contacts.first_name,
    contacts.last_name,
    contacts.email,
    contacts.job_title,
    contacts.is_primary,
    contacts.created_at,
    contacts.updated_at,
    contacts._loaded_at
from contacts
inner join account_map
    on contacts.account_id = account_map.source_crm_account_id
inner join active_accounts
    on account_map.canonical_crm_account_id = active_accounts.canonical_crm_account_id
where not contacts.is_deleted
