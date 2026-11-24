-- stg_synthea_2026__immunizations - one row per vaccine administration, typed and renamed.
-- The source has no id; immunization_key is a surrogate (see stg_synthea_2026__conditions).
-- Author: Cortwright Grant

with source as (

    select
        *,
        row_number() over (
            partition by patient, encounter, code, "DATE"
            order by _source_file, _source_row
        ) as occurrence
    from {{ source('synthea_2026_raw', 'immunizations') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['patient', 'encounter', 'code', '"DATE"', 'occurrence']) }} as immunization_key,
    try_to_timestamp_ntz("DATE")        as administered_at,
    patient                             as patient_id,
    encounter                           as encounter_id,
    code                                as vaccine_code,        -- CVX
    description                         as vaccine_description,
    try_to_number(base_cost, 38, 2)     as base_cost,
    _source_file,
    _source_row,
    _loaded_at
from source
