{{ config(
    materialized='incremental',
    unique_key='booking_id',
    incremental_strategy='delete+insert'
) }}

-- Grain: one row per booking.
-- Property is resolved point-in-time against the SCD2 dimension, so revenue
-- attributes to the property's state at check-in, not its state today.

with bookings as (
    select * from {{ ref('int_bookings_enriched') }}

    {% if is_incremental() %}
    -- 3-day lookback re-pulls recently changed bookings (status flips, payout
    -- adjustments) without a full rebuild.
    where updated_at >= (select max(updated_at) from {{ this }}) - interval '3 days'
    {% endif %}
),

property as (
    select * from {{ ref('dim_property') }}
),

channel as (
    select * from {{ ref('dim_channel') }}
),

guest as (
    select * from {{ ref('dim_guest') }}
),

date_dim as (
    select * from {{ ref('dim_date') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['b.booking_id']) }} as booking_key,
    p.property_key,
    c.channel_key,
    g.guest_key,
    d.date_key                                              as check_in_date_key,
    b.booking_id,
    b.booking_status,
    b.nights,
    b.gross_amount,
    b.channel_fee,
    b.net_revenue,
    b.updated_at
from bookings b
left join property p
       on b.property_id = p.property_id
      and b.check_in_date >= p.valid_from
      and b.check_in_date <  p.valid_to
left join channel  c on b.channel_code = c.channel_code
left join guest    g on b.guest_id     = g.guest_id
left join date_dim d on b.check_in_date = d.calendar_date
