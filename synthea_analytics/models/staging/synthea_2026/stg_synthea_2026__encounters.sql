-- stg_synthea_2026__encounters - one row per encounter, typed and renamed.
-- Timestamps arrive as ISO 8601 in UTC ('2006-06-13T09:02:48Z') and are kept in UTC.
-- Author: Cortwright Grant

with source as (

    select * from {{ source('synthea_2026_raw', 'encounters') }}

)

select
    id                                          as encounter_id,
    try_to_timestamp_ntz("START")               as started_at,
    try_to_timestamp_ntz(stop)                  as stopped_at,
    patient                                     as patient_id,
    organization                                as organization_id,
    provider                                    as provider_id,
    payer                                       as payer_id,
    encounterclass                              as encounter_class,
    code                                        as encounter_code,         -- SNOMED CT
    description                                 as encounter_description,
    try_to_number(base_encounter_cost, 38, 2)   as base_encounter_cost,
    try_to_number(total_claim_cost, 38, 2)      as total_claim_cost,
    try_to_number(payer_coverage, 38, 2)        as payer_coverage,
    reasoncode                                  as reason_code,            -- SNOMED CT
    reasondescription                           as reason_description,
    _source_file,
    _source_row,
    _loaded_at
from source
