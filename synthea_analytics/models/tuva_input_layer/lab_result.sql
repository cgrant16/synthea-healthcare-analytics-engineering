-- Tuva Input Layer: lab_result. One row per laboratory observation.
-- Author: Cortwright Grant
--
-- These are the CATEGORY = 'laboratory' rows of Synthea's observations table.
-- Each row is one resulted analyte, so it is mapped as the lab COMPONENT; Synthea
-- has no separate order, accession number or specimen, and those stay null.
-- Only one timestamp exists per row. It is used as the result time, and the
-- collection time is left null rather than guessed.

with labs as (

    select *
    from {{ ref('stg_synthea_2026__observations') }}
    where category = 'laboratory'

),

encounters as (

    select encounter_id, provider_id from {{ ref('stg_synthea_2026__encounters') }}

)

select
    cast(labs.observation_key as varchar)           as lab_result_id,
    cast(labs.patient_id as varchar)                as person_id,
    cast(labs.patient_id as varchar)                as patient_id,
    cast(labs.encounter_id as varchar)              as encounter_id,
    cast(null as varchar)                           as accession_number,
    cast(null as varchar)                           as source_order_type,
    cast(null as varchar)                           as source_order_code,
    cast(null as varchar)                           as source_order_description,
    cast('loinc' as varchar)                        as source_component_type,
    cast(labs.observation_code as varchar)          as source_component_code,
    cast(labs.observation_description as varchar)   as source_component_description,
    cast('final' as varchar)                        as status,
    cast(labs.value as varchar)                     as result,
    cast(labs.observed_at as timestamp_ntz)         as result_datetime,
    cast(null as timestamp_ntz)                     as collection_datetime,
    cast(labs.units as varchar)                     as source_units,
    cast(labs.units as varchar)                     as normalized_units,   -- Synthea already writes UCUM units
    cast(null as varchar)                           as source_reference_range_low,
    cast(null as varchar)                           as source_reference_range_high,
    cast(null as varchar)                           as normalized_reference_range_low,
    cast(null as varchar)                           as normalized_reference_range_high,
    cast(null as varchar)                           as source_abnormal_code,
    cast(null as varchar)                           as normalized_abnormal_code,
    cast(null as varchar)                           as specimen,
    cast(encounters.provider_id as varchar)         as ordering_practitioner_id,
    cast(labs._loaded_at as timestamp_ntz)          as ingest_datetime,
    cast('synthea' as varchar)                      as data_source
from labs
left join encounters
    on encounters.encounter_id = labs.encounter_id
