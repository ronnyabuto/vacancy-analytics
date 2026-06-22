-- SCD2 property dimension, read from the snapshot.
-- One row per property version; property_key is unique per (property_id, valid_from).

with snapshot as (
    select * from {{ ref('property_snapshot') }}
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
    (valid_to = cast('9999-12-31' as date)) as is_current,
    coalesce(is_deleted, false)             as is_deleted
from snapshot
