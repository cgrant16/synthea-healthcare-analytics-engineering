-- dim_location - one row per care facility (a Synthea provider organization).
-- Author: Cortwright Grant
--
-- Built on Tuva Core's location table. facility_type and parent_organization are
-- left out because the source has neither, so both are null on every row.

select
    location_id,
    name                as location_name,
    npi,
    address,
    city,
    state,
    zip_code,
    latitude,
    longitude
from {{ ref('the_tuva_project', 'core__location') }}
