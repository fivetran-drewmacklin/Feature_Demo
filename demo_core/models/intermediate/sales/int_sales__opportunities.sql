with opportunities as (
    select * from {{ ref('stg_crm__opportunities') }}
),

account_map as (
    select * from {{ ref('int_sales__account_map') }}
),

active_accounts as (
    select canonical_crm_account_id from {{ ref('int_sales__accounts') }}
)

select
    opportunities.opportunity_id,
    account_map.customer_id,
    account_map.canonical_crm_account_id,
    opportunities.account_id as source_crm_account_id,
    opportunities.owner_sales_rep_id,
    opportunities.opportunity_name,
    opportunities.stage,
    opportunities.amount_cents,
    opportunities.currency,
    opportunities.probability,
    opportunities.close_date,
    opportunities.created_at,
    opportunities.updated_at,
    opportunities._loaded_at
from opportunities
inner join account_map
    on opportunities.account_id = account_map.source_crm_account_id
inner join active_accounts
    on account_map.canonical_crm_account_id = active_accounts.canonical_crm_account_id
where not opportunities.is_deleted
