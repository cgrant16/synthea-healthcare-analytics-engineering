-- stg_synthea_2026__providers - one row per clinician, typed and renamed.
-- This Synthea build generates exactly one provider per organization.
-- Author: Cortwright Grant

with source as (

    select * from {{ source('synthea_2026_raw', 'providers') }}

)

select
    id                              as provider_id,
    organization                    as organization_id,
    name                            as provider_name,
    gender,
    speciality                      as specialty,
    address,
    city,
    state,
    zip                             as zip_code,
    try_to_double(lat)              as latitude,
    try_to_double(lon)              as longitude,
    try_to_number(encounters)       as encounter_count,
    try_to_number(procedures)       as procedure_count,
    npi,
    _source_file,
    _source_row,
    _loaded_at
from source
