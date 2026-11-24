-- stg_synthea_2026__observations - one row per observation (vitals, labs, surveys, ...).
-- The source has no id, and about 1.6 M rows repeat the natural key (patient,
-- encounter, code, date), so observation_key includes an occurrence number.
-- Author: Cortwright Grant

with source as (

    select
        *,
        row_number() over (
            partition by patient, encounter, code, "DATE"
            order by _source_file, _source_row
        ) as occurrence
    from {{ source('synthea_2026_raw', 'observations') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['patient', 'encounter', 'code', '"DATE"', 'occurrence']) }} as observation_key,
    try_to_timestamp_ntz("DATE")    as observed_at,
    patient                         as patient_id,
    encounter                       as encounter_id,        -- null on the yearly QALY / DALY / QOLS scores
    category,                                               -- laboratory, vital-signs, survey, ... ; null on those scores
    code                            as observation_code,    -- LOINC for all but a few SNOMED CT and Synthea-internal codes
    description                     as observation_description,
    "VALUE"                         as value,               -- text: numeric or coded, see value_type
    units,
    "TYPE"                          as value_type,          -- numeric | text
    _source_file,
    _source_row,
    _loaded_at
from source
