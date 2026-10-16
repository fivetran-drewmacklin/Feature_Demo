with source as (
    select *
    from {{ source('crm', 'sales_reps') }}
),

renamed as (
    select
        sales_rep_id,
        {{ clean_string('first_name') }} as first_name,
        {{ clean_string('last_name') }} as last_name,
        {{ normalize_email('email') }} as email,
        upper({{ clean_string('region') }}) as region,
        manager_sales_rep_id,
        hire_date,
        is_active,
        _loaded_at
    from source
)

select *
from renamed
