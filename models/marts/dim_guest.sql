with guests as (
    select * from {{ ref('stg_rentals__guests') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['guest_id']) }} as guest_key,
    guest_id,
    full_name,
    email,
    country
from guests
