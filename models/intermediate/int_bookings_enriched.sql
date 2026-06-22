with bookings as (
    select * from {{ ref('stg_rentals__bookings') }}
),

fees as (
    select * from {{ ref('channel_fee_rates') }}
),

enriched as (
    select
        b.booking_id,
        b.property_id,
        b.guest_id,
        b.channel_code,
        b.booking_status,
        b.check_in_date,
        b.check_out_date,
        (b.check_out_date - b.check_in_date)              as nights,
        b.gross_amount,
        coalesce(f.fee_rate, 0)                           as fee_rate,
        round(b.gross_amount * coalesce(f.fee_rate, 0), 2) as channel_fee,
        round(b.gross_amount * (1 - coalesce(f.fee_rate, 0)), 2) as net_revenue,
        b.updated_at
    from bookings b
    left join fees f on b.channel_code = f.channel_code
)

select * from enriched
