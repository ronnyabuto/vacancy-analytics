-- SCD2 property dimension, read from the snapshot.
-- One row per property version; property_key is unique per (property_id, valid_from).

with snapshot as (
    select * from {{ ref('property_snapshot') }}
),

versioned as (
    select
        property_id,
        property_name,
        status,
        nightly_rate,
        city,
        bedrooms,
        -- Initial-load backfill: the first version's valid_from is the first snapshot
        -- time, so a fact dated before then would match no version (NULL key). Set the
        -- earliest version per property to a far-past date so it covers all history up
        -- to its first observed change. (Use a true source-effective date if you have one.)
        case
            when valid_from = min(valid_from) over (partition by property_id)
            then cast('1900-01-01' as timestamp)
            else valid_from
        end as valid_from,
        valid_to,
        is_deleted
    from snapshot
)

select
    {{ dbt_utils.generate_surrogate_key(['property_id', 'valid_from']) }} as property_key,
    property_id,
    property_name,
    status,
    nightly_rate,
    city,
    bedrooms,
    valid_from,
    valid_to,
    (valid_to = cast('9999-12-31' as timestamp)) as is_current,
    -- dbt stores dbt_is_deleted as text ('True'/'False'), so coerce it to boolean
    (lower(coalesce(is_deleted, 'false')) = 'true') as is_deleted
from versioned
