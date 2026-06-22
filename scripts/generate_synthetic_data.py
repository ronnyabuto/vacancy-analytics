#!/usr/bin/env python3
"""Generate synthetic short-term-rental data into the `raw` schema.

Nothing here is real. Guests, hosts, properties, and bookings are fabricated
with Faker and a seeded RNG, so the warehouse can be demonstrated and
open-sourced without exposing anyone's data. Emails use example.com on purpose.

Usage:
    export DATABASE_URL=postgresql://user:pass@localhost:5432/<db>

    # full load (drops and recreates raw tables)
    python scripts/generate_synthetic_data.py --seed 42

    # later, to create SCD2 history the snapshot can capture:
    dbt snapshot
    python scripts/generate_synthetic_data.py --mutate
    dbt snapshot      # property_snapshot now has a second version per changed row
"""
from __future__ import annotations

import argparse
import os
import random
from datetime import date, datetime, timedelta
from decimal import Decimal

import psycopg
from faker import Faker

CHANNELS = [
    ("airbnb", "Airbnb"),
    ("booking_com", "Booking.com"),
    ("vrbo", "Vrbo"),
    ("direct", "Direct"),
]
CHANNEL_WEIGHTS = [0.45, 0.30, 0.10, 0.15]

STATUSES = ["confirmed", "completed", "cancelled", "pending"]
STATUS_WEIGHTS = [0.55, 0.30, 0.10, 0.05]

# (city, nightly base rate in USD) — a regional mix, no real listings.
CITIES = [
    ("Nairobi", 70), ("Mombasa", 85), ("Diani", 110), ("Nanyuki", 95),
    ("Naivasha", 80), ("Zanzibar", 130), ("Kampala", 60), ("Kigali", 75),
    ("Cape Town", 120), ("Dar es Salaam", 65),
]
GUEST_COUNTRIES = ["KE", "US", "GB", "DE", "ZA", "TZ", "UG", "FR", "NL", "AE"]

# Higher weight = busier month (peak Dec–Jan and Jul–Aug).
MONTH_WEIGHTS = {1: 1.4, 2: 0.9, 3: 0.8, 4: 0.8, 5: 0.9, 6: 1.0,
                 7: 1.3, 8: 1.3, 9: 0.9, 10: 0.9, 11: 1.0, 12: 1.5}

DDL = """
create schema if not exists raw;

drop table if exists raw.bookings;
drop table if exists raw.properties;
drop table if exists raw.guests;
drop table if exists raw.channels;

create table raw.channels (
    channel_code text,
    channel_name text
);
create table raw.properties (
    property_id  text,
    name         text,
    status       text,
    nightly_rate numeric(12,2),
    city         text,
    bedrooms     int,
    created_at   timestamp,
    updated_at   timestamp
);
create table raw.guests (
    guest_id   text,
    full_name  text,
    email      text,
    country    text,
    created_at timestamp
);
create table raw.bookings (
    booking_id   text,
    property_id  text,
    guest_id     text,
    channel      text,
    status       text,
    check_in     date,
    check_out    date,
    gross_amount numeric(12,2),
    currency     text,
    created_at   timestamp,
    updated_at   timestamp
);
"""


def month_range(start: date, end: date) -> list[date]:
    months, cur = [], start.replace(day=1)
    while cur <= end:
        months.append(cur)
        cur = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
    return months


def sample_checkin(start: date, end: date, months: list[date], fake: Faker) -> date:
    weights = [MONTH_WEIGHTS[m.month] for m in months]
    base = random.choices(months, weights=weights, k=1)[0]
    last_day = (base.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
    lo = max(start, base)
    hi = min(end, last_day)
    return fake.date_between_dates(date_start=lo, date_end=hi)


def gen_channels() -> list[tuple]:
    return [(code, name) for code, name in CHANNELS]


def gen_properties(n: int, start: date, fake: Faker) -> list[dict]:
    props = []
    for i in range(1, n + 1):
        city, base = random.choice(CITIES)
        bedrooms = random.choices([1, 2, 3, 4, 5], weights=[3, 4, 3, 2, 1])[0]
        rate = round(base * (0.85 + 0.30 * bedrooms) * random.uniform(0.9, 1.2), 2)
        created = fake.date_time_between_dates(
            datetime_start=datetime.combine(start - timedelta(days=180), datetime.min.time()),
            datetime_end=datetime.combine(start, datetime.min.time()),
        )
        props.append({
            "property_id": f"PROP-{i:05d}",
            "name": f"{fake.street_name()} {random.choice(['Villa', 'Apartment', 'Cottage', 'Suite', 'Bungalow'])}",
            "status": random.choices(["active", "inactive"], weights=[0.9, 0.1])[0],
            "nightly_rate": Decimal(str(rate)),
            "city": city,
            "bedrooms": bedrooms,
            "created_at": created,
            "updated_at": created,
        })
    return props


def gen_guests(n: int, start: date, end: date, fake: Faker) -> list[dict]:
    guests = []
    for i in range(1, n + 1):
        first, last = fake.first_name(), fake.last_name()
        guests.append({
            "guest_id": f"GST-{i:06d}",
            "full_name": f"{first} {last}",
            "email": f"{first}.{last}{i}@example.com".lower(),
            "country": random.choice(GUEST_COUNTRIES),
            "created_at": fake.date_time_between_dates(
                datetime_start=datetime.combine(start - timedelta(days=180), datetime.min.time()),
                datetime_end=datetime.combine(end, datetime.min.time()),
            ),
        })
    return guests


def gen_bookings(n: int, props: list[dict], guests: list[dict],
                 start: date, end: date, fake: Faker) -> list[dict]:
    months = month_range(start, end)
    now = datetime.now()
    rows = []
    for i in range(1, n + 1):
        prop = random.choice(props)
        guest = random.choice(guests)
        check_in = sample_checkin(start, end, months, fake)
        nights = random.choices(range(1, 15),
                                weights=[8, 7, 6, 5, 4, 3, 3, 2, 2, 1, 1, 1, 1, 1])[0]
        check_out = check_in + timedelta(days=nights)

        status = random.choices(STATUSES, weights=STATUS_WEIGHTS)[0]
        # A stay can only be "completed" once it's in the past.
        if status == "completed" and check_out >= now.date():
            status = "confirmed"

        gross = Decimal(str(round(nights * float(prop["nightly_rate"]) * random.uniform(0.95, 1.2), 2)))
        created_at = datetime.combine(check_in, datetime.min.time()) - timedelta(
            days=random.randint(1, 120), hours=random.randint(0, 23))
        updated_at = created_at + timedelta(days=random.randint(0, nights + 5))

        rows.append({
            "booking_id": f"BKG-{i:07d}",
            "property_id": prop["property_id"],
            "guest_id": guest["guest_id"],
            "channel": random.choices([c for c, _ in CHANNELS], weights=CHANNEL_WEIGHTS)[0],
            "status": status,
            "check_in": check_in,
            "check_out": check_out,
            "gross_amount": gross,
            "currency": "USD",
            "created_at": created_at,
            "updated_at": updated_at,
        })
    return rows


def full_load(conn, args, fake: Faker) -> None:
    props = gen_properties(args.properties, args.start, fake)
    guests = gen_guests(args.guests, args.start, args.end, fake)
    bookings = gen_bookings(args.bookings, props, guests, args.start, args.end, fake)

    with conn.cursor() as cur:
        cur.execute(DDL)

        with cur.copy("copy raw.channels (channel_code, channel_name) from stdin") as cp:
            for row in gen_channels():
                cp.write_row(row)

        with cur.copy("copy raw.properties (property_id, name, status, nightly_rate, "
                      "city, bedrooms, created_at, updated_at) from stdin") as cp:
            for p in props:
                cp.write_row((p["property_id"], p["name"], p["status"], p["nightly_rate"],
                              p["city"], p["bedrooms"], p["created_at"], p["updated_at"]))

        with cur.copy("copy raw.guests (guest_id, full_name, email, country, created_at) "
                      "from stdin") as cp:
            for g in guests:
                cp.write_row((g["guest_id"], g["full_name"], g["email"],
                              g["country"], g["created_at"]))

        with cur.copy("copy raw.bookings (booking_id, property_id, guest_id, channel, status, "
                      "check_in, check_out, gross_amount, currency, created_at, updated_at) "
                      "from stdin") as cp:
            for b in bookings:
                cp.write_row((b["booking_id"], b["property_id"], b["guest_id"], b["channel"],
                              b["status"], b["check_in"], b["check_out"], b["gross_amount"],
                              b["currency"], b["created_at"], b["updated_at"]))
    conn.commit()
    print(f"Loaded {len(props)} properties, {len(guests)} guests, "
          f"{len(bookings)} bookings into schema raw.")


def mutate(conn, fraction: float) -> None:
    """Change a slice of properties so the next `dbt snapshot` records SCD2 history."""
    with conn.cursor() as cur:
        cur.execute("select property_id, nightly_rate from raw.properties")
        rows = cur.fetchall()
        if not rows:
            raise SystemExit("No properties found — run a full load first.")
        chosen = random.sample(rows, k=max(1, int(len(rows) * fraction)))
        now = datetime.now()
        for property_id, rate in chosen:
            new_rate = round(float(rate) * random.uniform(0.8, 1.25), 2)
            new_status = random.choices(["active", "inactive"], weights=[0.85, 0.15])[0]
            cur.execute(
                "update raw.properties set nightly_rate = %s, status = %s, updated_at = %s "
                "where property_id = %s",
                (Decimal(str(new_rate)), new_status, now, property_id),
            )
    conn.commit()
    print(f"Mutated {len(chosen)} properties. Run `dbt snapshot` to capture the new versions.")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--properties", type=int, default=60)
    p.add_argument("--guests", type=int, default=900)
    p.add_argument("--bookings", type=int, default=6000)
    p.add_argument("--start", type=date.fromisoformat, default=date(2025, 1, 1))
    p.add_argument("--end", type=date.fromisoformat, default=date(2026, 6, 30))
    p.add_argument("--seed", type=int, default=42, help="RNG seed for reproducible data")
    p.add_argument("--mutate", action="store_true",
                   help="Change ~30%% of properties to create SCD2 history (no full reload)")
    p.add_argument("--dsn", default=os.environ.get("DATABASE_URL"),
                   help="libpq connection string; defaults to $DATABASE_URL")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if not args.dsn:
        raise SystemExit("Set DATABASE_URL or pass --dsn (e.g. "
                         "postgresql://user:pass@localhost:5432/db).")

    random.seed(args.seed)
    fake = Faker()
    fake.seed_instance(args.seed)

    with psycopg.connect(args.dsn) as conn:
        if args.mutate:
            mutate(conn, fraction=0.30)
        else:
            full_load(conn, args, fake)


if __name__ == "__main__":
    main()
