-- Tuva Input Layer: observation. One row per non-laboratory observation.
-- Author: Cortwright Grant
--
-- Synthea puts vitals, labs, surveys and more in one observations table, with a
-- CATEGORY column. Laboratory rows go to lab_result; everything else comes here.
--
-- observation_type: Synthea's categories are already Tuva's observation types
-- (vital-signs, survey, social-history, exam, imaging, procedure, therapy). The
-- yearly QALY / DALY / QOLS scores have no category and become 'other'.
--
-- source_code_type: LOINC for nearly every row. A few exam codes are SNOMED CT, and
-- Synthea invents some codes of its own (QALY, X9999-1, 99999-11, ...): those are
-- labelled 'synthea' so they are never mistaken for a standard code.

select
    cast(observation_key as varchar)            as observation_id,
    cast(patient_id as varchar)                 as person_id,
    cast(patient_id as varchar)                 as patient_id,
    cast(encounter_id as varchar)               as encounter_id,
    cast(null as varchar)                       as panel_id,
    cast(observed_at as date)                   as observation_date,
    cast(coalesce(category, 'other') as varchar) as observation_type,
    cast(case
            when regexp_like(observation_code, '[0-9]+-[0-9]') and observation_code not like '99999-%' then 'loinc'
            when regexp_like(observation_code, '[0-9]+') then 'snomed-ct'
            else 'synthea'
         end as varchar)                        as source_code_type,
    cast(observation_code as varchar)           as source_code,
    cast(observation_description as varchar)    as source_description,
    cast(value as varchar)                      as result,
    cast(units as varchar)                      as source_units,
    cast(units as varchar)                      as normalized_units,   -- Synthea already writes UCUM units
    cast(null as varchar)                       as source_reference_range_low,
    cast(null as varchar)                       as source_reference_range_high,
    cast(null as varchar)                       as normalized_reference_range_low,
    cast(null as varchar)                       as normalized_reference_range_high,
    cast(_loaded_at as timestamp_ntz)           as ingest_datetime,
    cast('synthea' as varchar)                  as data_source
from {{ ref('stg_synthea_2026__observations') }}
where category is distinct from 'laboratory'
