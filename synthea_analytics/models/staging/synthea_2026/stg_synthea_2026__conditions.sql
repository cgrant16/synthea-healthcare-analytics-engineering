-- stg_synthea_2026__conditions - one row per condition record, typed and renamed.
--
-- The source has no id. condition_key is a surrogate built from the natural key
-- (patient, encounter, code, start) plus an occurrence number, so it stays unique
-- even if the generator ever repeats a natural key.
-- Author: Cortwright Grant

with source as (

    select
        *,
        row_number() over (
            partition by patient, encounter, code, "START"
            order by _source_file, _source_row
        ) as occurrence
    from {{ source('synthea_2026_raw', 'conditions') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['patient', 'encounter', 'code', '"START"', 'occurrence']) }} as condition_key,
    try_to_date("START")    as started_on,
    try_to_date(stop)       as stopped_on,
    patient                 as patient_id,
    encounter               as encounter_id,
    "SYSTEM"                as code_system,
    code                    as condition_code,
    description             as condition_description,
    _source_file,
    _source_row,
    _loaded_at
from source
