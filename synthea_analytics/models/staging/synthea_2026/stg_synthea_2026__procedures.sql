-- stg_synthea_2026__procedures - one row per procedure, typed and renamed.
-- The source has no id; procedure_key is a surrogate (see stg_synthea_2026__conditions).
-- Author: Cortwright Grant

with source as (

    select
        *,
        row_number() over (
            partition by patient, encounter, code, "START"
            order by _source_file, _source_row
        ) as occurrence
    from {{ source('synthea_2026_raw', 'procedures') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['patient', 'encounter', 'code', '"START"', 'occurrence']) }} as procedure_key,
    try_to_timestamp_ntz("START")       as started_at,
    try_to_timestamp_ntz(stop)          as stopped_at,
    patient                             as patient_id,
    encounter                           as encounter_id,
    "SYSTEM"                            as code_system,
    code                                as procedure_code,
    description                         as procedure_description,
    try_to_number(base_cost, 38, 2)     as base_cost,
    reasoncode                          as reason_code,
    reasondescription                   as reason_description,
    _source_file,
    _source_row,
    _loaded_at
from source
