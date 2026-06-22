# Vacancy

A dimensional warehouse over short-term-rental booking data, built with dbt on PostgreSQL. Raw booking feeds (Airbnb, Booking.com, Vrbo, direct) land as sources; dbt turns them into a tested, documented star schema that answers revenue, channel-mix, and occupancy questions without hand-written reporting SQL.

Runs entirely on **synthetic data**. The included generator (`scripts/generate_synthetic_data.py`) fabricates realistic bookings, properties, and guests — seasonality, a believable channel mix, repeat guests, regional rate tiers — with seeded, reproducible RNG. No real guests or hosts, nothing to expose. The modeling is what's on display, and it behaves identically on real data.

> Status: complete. `dbt build` runs green end to end — 1 seed + 1 snapshot + 12 models + 48 tests — and reproduces from raw in a single command. Numbers below are real output from a 150,000-booking build.

## What it does

- Ingests raw bookings, properties, guests, and channel data into a staging layer.
- Tracks property attribute history (rate, status, listing details) with an SCD2 snapshot, so revenue attributes to the property state at booking time.
- Builds two facts at different grains: bookings (one row per booking) and daily occupancy (one row per property per date).
- Enforces data-quality contracts with dbt tests so a bad upstream feed fails the build instead of silently corrupting a dashboard.

## Architecture

```mermaid
flowchart LR
  subgraph raw["Raw sources (Postgres)"]
    s1[(bookings)]
    s2[(properties)]
    s3[(guests)]
    s4[(channels)]
  end

  subgraph stg["staging — stg_*"]
    g1[stg_rentals__bookings]
    g2[stg_rentals__properties]
    g3[stg_rentals__guests]
    g4[stg_rentals__channels]
  end

  snap[[property_snapshot<br/>SCD2]]

  subgraph int["intermediate — int_*"]
    i1[int_bookings_enriched]
    i2[int_occupancy_spined]
  end

  subgraph marts["marts"]
    d1[dim_property]
    d2[dim_channel]
    d3[dim_guest]
    d4[dim_date]
    f1[fct_bookings]
    f2[fct_occupancy_daily]
  end

  s1 --> g1
  s2 --> g2
  s3 --> g3
  s4 --> g4
  s2 --> snap

  g1 --> i1
  g2 --> snap
  snap --> d1
  g4 --> d2
  g3 --> d3

  i1 --> f1
  i1 --> i2
  i2 --> f2
  d1 --> f2
  d4 --> f2

  d1 --> f1
  d2 --> f1
  d3 --> f1
  d4 --> f1
```

Full lineage, the star-schema ER diagram, and the modeling rationale live in [`docs/architecture.md`](docs/architecture.md).

## Modeling decisions

The decisions worth defending in an interview:

- **SCD2 on `dim_property`.** Nightly rate, status, and listing attributes change over the life of a listing. A booking made in March must attribute to the property's March state, not today's. The snapshot uses the `check` strategy on the volatile columns, with `hard_deletes: new_record` so delisted properties stay queryable in history.
- **Two facts, two grains.** `fct_bookings` is one row per booking (revenue, fees, nights). `fct_occupancy_daily` is one row per property per calendar date (occupied flag), derived by exploding each booking into its occupied nights. Mixing both grains in one table would force non-additive measures and break simple aggregation.
- **Incremental `fct_bookings`.** Bookings mutate after creation (status changes, cancellations, payout adjustments), so the fact is incremental on `booking_id` with `delete+insert`, which is safe on Postgres without requiring a merge. Late-arriving updates are caught by a lookback window rather than a full rebuild.
- **ELT, not ETL.** Raw data lands first; all transformation is SQL in the warehouse, version-controlled and tested. Reprocessing is a `dbt build`, not a re-extraction.

## Data quality

Tests are contracts, not decoration. What the build guarantees:

- **Generic tests** (`data_tests:` in the model YAML): `unique` + `not_null` on every surrogate and natural key; `relationships` from each fact foreign key to its dimension; `accepted_values` on `booking_status`.
- **Singular tests** (`tests/`): no booking with `check_out <= check_in`; no negative `net_revenue`.
- **Unit tests** (dbt 1.8+): the net-revenue and nights calculations in `int_bookings_enriched` are unit-tested against fixed inputs, so a logic regression fails in CI before it touches data.

A failing test fails `dbt build`. Nothing downstream runs on data that broke a contract.

## Project structure

```
vacancy-analytics/
├── dbt_project.yml
├── packages.yml
├── profiles.example.yml
├── scripts/
│   ├── generate_synthetic_data.py
│   └── requirements.txt
├── models/
│   ├── staging/rentals/
│   │   ├── _rentals__sources.yml
│   │   ├── _rentals__models.yml
│   │   ├── stg_rentals__bookings.sql
│   │   ├── stg_rentals__properties.sql
│   │   ├── stg_rentals__guests.sql
│   │   └── stg_rentals__channels.sql
│   ├── intermediate/
│   │   ├── int_bookings_enriched.sql
│   │   ├── int_occupancy_spined.sql
│   │   └── _int__models.yml
│   └── marts/
│       ├── _marts__models.yml
│       ├── dim_property.sql
│       ├── dim_channel.sql
│       ├── dim_guest.sql
│       ├── dim_date.sql
│       ├── fct_bookings.sql
│       └── fct_occupancy_daily.sql
├── snapshots/
│   └── property_snapshot.yml
├── seeds/
│   └── channel_fee_rates.csv
├── tests/
│   ├── assert_checkout_after_checkin.sql
│   └── assert_non_negative_net_revenue.sql
├── macros/
└── docs/
    └── architecture.md
```

## Stack

| Component | Version | Note |
|---|---|---|
| dbt-postgres (adapter) | `~=1.10` (1.10.1 latest stable) | what you `pip install`; the 1.11 adapter line is still beta |
| dbt Core | 1.11+ (pulled by the adapter) | v2.0/Fusion is alpha as of June 2026 — staying on the 1.x line |
| dbt-utils | `>=1.3.0,<2.0.0` (1.4.0 current) | `generate_surrogate_key`, `date_spine` |
| PostgreSQL | 15+ | local warehouse for Phase 1 |
| psycopg / Faker | psycopg 3, Faker | only for the synthetic-data generator |

This project moves to Snowflake + Airflow orchestration in the next portfolio piece; the models here are written to port with minimal change.

## Run it

```bash
# 1. Install dbt + the generator's deps (use a virtualenv)
pip install "dbt-postgres~=1.10"
pip install -r scripts/requirements.txt

# 2. Generate synthetic source data into Postgres
export DATABASE_URL=postgresql://user:pass@localhost:5432/vacancy_analytics
python scripts/generate_synthetic_data.py --seed 42

# 3. Point dbt at the same Postgres
cp profiles.example.yml ~/.dbt/profiles.yml   # then export DBT_PG_USER / DBT_PG_PASSWORD
dbt debug                                       # confirms the connection

# 4. Packages, then build
dbt deps
dbt seed          # static reference data (channel fee rates)
dbt snapshot      # capture current property state into SCD2 history
dbt build         # runs models + tests + seeds + snapshots in DAG order

# 5. (optional) mutate properties, then re-snapshot to see SCD2 history accrue
python scripts/generate_synthetic_data.py --mutate
dbt snapshot

# 6. Docs
dbt docs generate && dbt docs serve
```

`profiles.example.yml` ships with the structure; real credentials stay out of git.

## Sample questions it answers

Real output from a 150,000-booking build.

**Net revenue by channel** (confirmed + completed):
```sql
select c.channel_name, count(*) as bookings, round(sum(f.net_revenue), 2) as net_revenue
from   fct_bookings f
join   dim_channel  c on c.channel_key = f.channel_key
where  f.booking_status in ('confirmed','completed')
group  by c.channel_name
order  by net_revenue desc;
```
```
channel_name | bookings | net_revenue
Airbnb       |   57560  | 37,968,816.41
Booking.com  |   38337  | 25,416,199.78
Direct       |   18922  | 14,632,730.20
Vrbo         |   12666  |  9,018,629.75
```

**Occupancy rate per property per month** (top 5):
```sql
select p.property_id, to_char(d.calendar_date, 'YYYY-MM') as month,
       round(100.0 * avg(case when f.is_occupied then 1 else 0 end), 1) as occupancy_pct
from   fct_occupancy_daily f
join   dim_property p on p.property_key = f.property_key
join   dim_date     d on d.date_key     = f.date_key
group  by p.property_id, to_char(d.calendar_date, 'YYYY-MM')
order  by occupancy_pct desc
limit  5;
```
```
property_id | month   | occupancy_pct
PROP-00003  | 2025-01 | 100.0
PROP-00003  | 2025-02 | 100.0
PROP-00002  | 2026-01 | 100.0
```

**The SCD2 payoff — revenue attributed to the rate _at booking time_:**
```sql
-- a property with rate history: each booking attributes to the version whose
-- validity window contains its check-in date (point-in-time join in fct_bookings)
select p.property_id, p.nightly_rate, p.valid_from::date, p.valid_to::date,
       count(f.booking_key) as bookings, round(sum(f.net_revenue), 2) as net_revenue
from   dim_property p
left join fct_bookings f on f.property_key = p.property_key
where  p.property_id = 'PROP-00064'
group  by p.property_id, p.nightly_rate, p.valid_from, p.valid_to
order  by p.valid_from;
```
```
property_id | nightly_rate | valid_from | valid_to   | bookings | net_revenue
PROP-00064  |   101.85     | 1900-01-01 | 2026-06-22 |   202    | 92,902.99
PROP-00064  |    92.33     | 2026-06-22 | 9999-12-31 |     3    |  1,758.35
```
202 historical bookings attribute to the rate in effect then; the 3 most recent to the new rate. A Type-1 overwrite would have collapsed both into today's rate — destroying the historical attribution.

## Notes

- **Build:** `dbt build` → 1 seed + 1 snapshot + 12 models + 48 tests, all green; reproduces from raw in one command (seconds on the 150k-row dataset).
- **Row counts** (150k-booking build): `fct_bookings` 150,000 · `fct_occupancy_daily` 446,400 · `dim_property` 1,040 (800 current + 240 SCD2 versions) · `dim_guest` 15,000 · `dim_date` 3,653 · `dim_channel` 4.
- **Lineage:** the pipeline and star-schema diagrams are in [`docs/architecture.md`](docs/architecture.md); `dbt docs generate && dbt docs serve` renders the interactive DAG.
