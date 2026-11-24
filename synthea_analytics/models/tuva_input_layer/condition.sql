-- Tuva Input Layer: condition. One row per condition record.
-- Author: Cortwright Grant
--
-- Synthea conditions behave like a problem list: each has a start date and, once
-- it resolves, a stop date. They are mapped as condition_type 'problem', with
-- status derived from the stop date. Codes are SNOMED CT, which Tuva accepts as is.

select
    cast(condition_key as varchar)              as source_condition_id,
    cast(patient_id as varchar)                 as person_id,
    cast(patient_id as varchar)                 as patient_id,
    cast(encounter_id as varchar)               as encounter_id,
    cast(started_on as date)                    as recorded_date,
    cast(started_on as date)                    as onset_date,
    cast(stopped_on as date)                    as resolved_date,
    cast(iff(stopped_on is null, 'active', 'resolved') as varchar) as status,
    cast('problem' as varchar)                  as condition_type,
    cast(case code_system
            when 'SNOMED-CT' then 'snomed-ct'
            else 'unknown'
         end as varchar)                        as code_system,
    cast(condition_code as varchar)             as source_code,
    cast(condition_description as varchar)      as source_description,
    cast(null as integer)                       as condition_rank,
    cast(null as varchar)                       as present_on_admit_code,
    cast(_loaded_at as timestamp_ntz)           as ingest_datetime,
    cast('synthea' as varchar)                  as data_source
from {{ ref('stg_synthea_2026__conditions') }}
