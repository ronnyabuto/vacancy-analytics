with source as (
    select * from {{ source('rentals', 'properties') }}
)

select
    property_id::varchar         as property_id,
    name::varchar                as property_name,
    lower(status)::varchar       as status,
    nightly_rate::numeric(12,2)  as nightly_rate,
    city::varchar                as city,
    bedrooms::int                as bedrooms,
    created_at::timestamp        as created_at,
    updated_at::timestamp        as updated_at
from source
