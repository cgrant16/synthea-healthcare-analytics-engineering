-- stg_synthea_2026__medications - one row per medication order, typed and renamed.
-- The source has no id, and 3,595 rows repeat the natural key (patient, encounter,
-- code, start), so medication_key includes an occurrence number.
-- Author: Cortwright Grant

with source as (

    select
        *,
        row_number() over (
            partition by patient, encounter, code, "START"
            order by _source_file, _source_row
        ) as occurrence
    from {{ source('synthea_2026_raw', 'medications') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['patient', 'encounter', 'code', '"START"', 'occurrence']) }} as medication_key,
    try_to_timestamp_ntz("START")           as started_at,
    try_to_timestamp_ntz(stop)              as stopped_at,
    patient                                 as patient_id,
    payer                                   as payer_id,
    encounter                               as encounter_id,
    code                                    as medication_code,          -- RxNorm
    description                             as medication_description,
    try_to_number(base_cost, 38, 2)         as base_cost,
    try_to_number(payer_coverage, 38, 2)    as payer_coverage,
    try_to_number(dispenses)                as dispenses,                -- number of fills, not a quantity
    try_to_number(totalcost, 38, 2)         as total_cost,
    reasoncode                              as reason_code,
    reasondescription                       as reason_description,
    _source_file,
    _source_row,
    _loaded_at
from source
