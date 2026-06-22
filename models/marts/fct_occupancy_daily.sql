-- Grain: one row per current property per calendar date, over the operating window.
-- The grid (properties x dates) is left-joined to occupied nights so vacant
-- nights surface as is_occupied = false rather than missing rows.

with properties as (
    select property_key, property_id
    from {{ ref('dim_property') }}
    where is_current and not is_deleted
),

occupancy as (
    select * from {{ ref('int_occupancy_spined') }}
),

date_bounds as (
    select min(occupied_date) as min_date, max(occupied_date) as max_date
    from occupancy
),

calendar as (
    select date_key, calendar_date
    from {{ ref('dim_date') }}
    where calendar_date between (select min_date from date_bounds)
                            and (select max_date from date_bounds)
),

grid as (
    select
        p.property_key,
        p.property_id,
        c.date_key,
        c.calendar_date
    from properties p
    cross join calendar c
)

select
    {{ dbt_utils.generate_surrogate_key(['g.property_key', 'g.date_key']) }} as occupancy_key,
    g.property_key,
    g.date_key,
    (o.booking_id is not null) as is_occupied,
    o.booking_id
from grid g
left join occupancy o
       on g.property_id  = o.property_id
      and g.calendar_date = o.occupied_date
