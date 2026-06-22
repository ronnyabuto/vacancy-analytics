with channels as (
    select * from {{ ref('stg_rentals__channels') }}
),

fees as (
    select * from {{ ref('channel_fee_rates') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['c.channel_code']) }} as channel_key,
    c.channel_code,
    c.channel_name,
    coalesce(f.fee_rate, 0) as fee_rate
from channels c
left join fees f on c.channel_code = f.channel_code
