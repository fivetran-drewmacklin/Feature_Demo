with source as (
    select * from {{ source('erp', 'cost_centers') }}
),

renamed as (
    select
        cost_center_id,
        {{ clean_string('cost_center_name') }} as cost_center_name,
        {{ clean_string('business_unit') }} as business_unit,
        {{ clean_string('manager_name') }} as manager_name,
        effective_from,
        effective_to,
        is_active,
        _loaded_at
    from source
)

select * from renamed
