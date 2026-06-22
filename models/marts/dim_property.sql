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
    (valid_to = cast('9999-12-31' as timestamp)) as is_current,
    -- dbt stores dbt_is_deleted as text ('True'/'False'), so coerce it to boolean
    (lower(coalesce(is_deleted, 'false')) = 'true') as is_deleted
from snapshot
