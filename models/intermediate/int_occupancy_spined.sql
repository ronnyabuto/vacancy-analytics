-- One row per (property, occupied night), for confirmed/completed bookings.
-- Feeds fct_occupancy_daily, which fills in the vacant nights.
-- Portable: a date spine joined to each stay — works on Postgres and Snowflake,
-- replacing the Postgres-only generate_series.

with bookings as (
    select
        booking_id,
        property_id,
        check_in_date,
        check_out_date
    from {{ ref('int_bookings_enriched') }}
    where booking_status in ('confirmed', 'completed')
),

spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2024-01-01' as date)",
        end_date="cast('2027-01-01' as date)"
    ) }}
),

occupied as (
    select
        b.property_id,
        cast(s.date_day as date) as occupied_date,
        b.booking_id
    from bookings b
    join spine s
      on cast(s.date_day as date) >= b.check_in_date
     and cast(s.date_day as date) <  b.check_out_date    -- checkout day is not occupied
)

-- Dedupe to the daily grain: a property is occupied or not on a date, regardless of
-- how many bookings overlap. group-by + min() is portable (no DISTINCT ON / QUALIFY).
select
    property_id,
    occupied_date,
    min(booking_id) as booking_id
from occupied
group by property_id, occupied_date
