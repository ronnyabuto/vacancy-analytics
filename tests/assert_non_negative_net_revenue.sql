-- Fails if any booking carries negative net revenue (fee exceeded gross).
select booking_id
from {{ ref('fct_bookings') }}
where net_revenue < 0
