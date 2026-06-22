-- Fails if any booking checks out on or before it checks in.
select booking_id
from {{ ref('stg_rentals__bookings') }}
where check_out_date <= check_in_date
