with subscriptions as (
    select * from {{ ref('stg_billing__subscriptions') }}
),

customer_matches as (
    select * from {{ ref('int_core__customer_matches') }}
),

plans as (
    select * from {{ ref('plan_catalog') }}
)

select
    subscriptions.subscription_id,
    customer_matches.customer_id,
    subscriptions.billing_customer_id,
    subscriptions.plan_code,
    plans.plan_name,
    plans.product_family,
    plans.billing_interval,
    subscriptions.status,
    subscriptions.started_at,
    subscriptions.current_period_start,
    subscriptions.current_period_end,
    subscriptions.canceled_at,
    subscriptions.quantity,
    subscriptions.unit_price_cents,
    subscriptions.currency,
    subscriptions.updated_at,
    subscriptions._loaded_at
from subscriptions
inner join customer_matches using (billing_customer_id)
inner join plans using (plan_code)
