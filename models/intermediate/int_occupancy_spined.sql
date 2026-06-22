-- Explodes each confirmed booking into one row per occupied night.
-- Feeds fct_occupancy_daily, which fills in the vacant nights.
-- Postgres-native: generate_series over the stay. On Snowflake this becomes a
-- join to a date spine (one of the porting changes noted in docs/architecture.md).

with bookings as (
    select
        booking_id,
        property_id,
        check_in_date,
        check_out_date
    from {{ ref('int_bookings_enriched') }}
    where booking_status in ('confirmed', 'completed')
),

occupied as (
    select
        b.property_id,
        gs::date    as occupied_date,
        b.booking_id
    from bookings b
    cross join lateral generate_series(
        b.check_in_date,
        b.check_out_date - 1,        -- checkout day is not an occupied night
        interval '1 day'
    ) as gs
)

-- One row per (property, date): a property is occupied or not, regardless of how
-- many overlapping bookings cover the night. Dedupe so fct_occupancy_daily keeps
-- its one-row-per-property-per-date grain (overlaps would otherwise duplicate it).
select distinct on (property_id, occupied_date)
    property_id,
    occupied_date,
    booking_id
from occupied
order by property_id, occupied_date, booking_id
