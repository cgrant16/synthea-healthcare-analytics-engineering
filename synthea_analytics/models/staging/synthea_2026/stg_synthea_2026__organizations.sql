-- stg_synthea_2026__organizations - one row per provider organization, typed and renamed.
-- Author: Cortwright Grant

with source as (

    select * from {{ source('synthea_2026_raw', 'organizations') }}

)

select
    id                              as organization_id,
    name                            as organization_name,
    address,
    city,
    state,
    zip                             as zip_code,
    try_to_double(lat)              as latitude,
    try_to_double(lon)              as longitude,
    phone,
    try_to_number(revenue, 38, 2)   as revenue,
    try_to_number(utilization)      as utilization,
    npi,
    _source_file,
    _source_row,
    _loaded_at
from source
