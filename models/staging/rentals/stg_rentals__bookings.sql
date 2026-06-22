with source as (
    select * from {{ source('rentals', 'bookings') }}
)

select
    booking_id::varchar          as booking_id,
    property_id::varchar         as property_id,
    guest_id::varchar            as guest_id,
    lower(channel)::varchar      as channel_code,
    lower(status)::varchar       as booking_status,
    check_in::date               as check_in_date,
    check_out::date              as check_out_date,
    gross_amount::numeric(12,2)  as gross_amount,
    upper(currency)::varchar     as currency,
    created_at::timestamp        as created_at,
    updated_at::timestamp        as updated_at
from source
