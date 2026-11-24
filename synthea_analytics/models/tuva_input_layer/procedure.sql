-- Tuva Input Layer: procedure. One row per procedure.
-- Author: Cortwright Grant
--
-- practitioner_id is the provider of the encounter the procedure happened in;
-- Synthea does not record a clinician per procedure.

with procedures as (

    select * from {{ ref('stg_synthea_2026__procedures') }}

),

encounters as (

    select encounter_id, provider_id from {{ ref('stg_synthea_2026__encounters') }}

)

select
    cast(procedures.procedure_key as varchar)           as source_procedure_id,
    cast(procedures.patient_id as varchar)              as person_id,
    cast(procedures.patient_id as varchar)              as patient_id,
    cast(procedures.encounter_id as varchar)            as encounter_id,
    cast(procedures.started_at as date)                 as procedure_date,
    cast(case procedures.code_system
            when 'SNOMED-CT' then 'snomed-ct'
         end as varchar)                                as code_system,
    cast(procedures.procedure_code as varchar)          as source_code,
    cast(procedures.procedure_description as varchar)   as source_description,
    cast(null as varchar)                               as modifier_1,
    cast(null as varchar)                               as modifier_2,
    cast(null as varchar)                               as modifier_3,
    cast(null as varchar)                               as modifier_4,
    cast(null as varchar)                               as modifier_5,
    cast(encounters.provider_id as varchar)             as practitioner_id,
    cast(procedures._loaded_at as timestamp_ntz)        as ingest_datetime,
    cast('synthea' as varchar)                          as data_source
from procedures
left join encounters
    on encounters.encounter_id = procedures.encounter_id
