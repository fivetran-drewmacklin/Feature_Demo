with source as (
    select *
    from {{ source('crm', 'contacts') }}
),

renamed as (
    select
        contact_id,
        account_id,
        {{ clean_string('first_name') }} as first_name,
        {{ clean_string('last_name') }} as last_name,
        {{ normalize_email('email') }} as email,
        {{ clean_string('job_title') }} as job_title,
        is_primary,
        created_at,
        updated_at,
        is_deleted,
        _loaded_at
    from source
)

select *
from renamed
