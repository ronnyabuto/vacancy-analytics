-- Conformed date dimension. Fixed range covers the business history with headroom.

with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2020-01-01' as date)",
        end_date="cast('2030-01-01' as date)"
    ) }}
)

select
    cast(to_char(date_day, 'YYYYMMDD') as integer) as date_key,
    date_day::date                                 as calendar_date,
    extract(year  from date_day)::int              as year,
    extract(month from date_day)::int              as month,
    extract(day   from date_day)::int              as day_of_month,
    extract(dow   from date_day)::int              as day_of_week,
    extract(dow   from date_day) in (0, 6)         as is_weekend
from spine
