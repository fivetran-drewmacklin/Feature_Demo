with source as (
    select *
    from {{ source('crm', 'opportunities') }}
),

renamed as (
    select
        opportunity_id,
        account_id,
        owner_sales_rep_id,
        {{ clean_string('opportunity_name') }} as opportunity_name,
        lower({{ clean_string('stage') }}) as stage,
        amount_cents,
        upper(currency) as currency,
        probability,
        close_date,
        created_at,
        updated_at,
        is_deleted,
        _loaded_at
    from source
)

select *
from renamed
