-- Tuva Input Layer: location. One row per provider organization.
-- Author: Cortwright Grant
--
-- Synthea organizations carry an NPI; 1,116 of 1,144 exist in Tuva's NPI registry
-- extract and the other 28 are synthetic. The source has no facility type or
-- parent organization.

select
    cast(organization_id as varchar)        as location_id,
    cast(npi as varchar)                    as npi,
    cast(organization_name as varchar)      as name,
    cast(null as varchar)                   as facility_type,
    cast(null as varchar)                   as parent_organization,
    cast(address as varchar)                as address,
    cast(city as varchar)                   as city,
    cast(state as varchar)                  as state,
    cast(zip_code as varchar)               as zip_code,
    cast(latitude as float)                 as latitude,
    cast(longitude as float)                as longitude,
    cast(_loaded_at as timestamp_ntz)       as ingest_datetime,
    cast('synthea' as varchar)              as data_source
from {{ ref('stg_synthea_2026__organizations') }}
