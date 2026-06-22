with source as (
    select * from {{ source('rentals', 'guests') }}
)

select
    guest_id::varchar       as guest_id,
    full_name::varchar      as full_name,
    lower(email)::varchar   as email,
    upper(country)::varchar as country,
    created_at::timestamp   as created_at
from source
