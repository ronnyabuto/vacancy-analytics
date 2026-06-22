with source as (
    select * from {{ source('rentals', 'channels') }}
)

select
    lower(channel_code)::varchar as channel_code,
    channel_name::varchar        as channel_name
from source
