with date_spine as (

    {{
        dbt.date_spine(
            'day',
            "to_date('2020-01-01')",
            "to_date('2036-01-01')"
        )
    }}

)

select cast(date_day as date) as date_day
from date_spine
