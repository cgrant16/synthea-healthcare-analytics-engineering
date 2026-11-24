-- Tuva Input Layer: medication. One row per medication order.
-- Author: Cortwright Grant
--
-- Codes are RxNorm. A Synthea medication row is an order that was also filled
-- (DISPENSES counts the fills), so the start date is used as both the prescribing
-- and the dispensing date when at least one fill is recorded.
-- quantity and days_supply stay null: DISPENSES is a number of fills, not a quantity.

with medications as (

    select * from {{ ref('stg_synthea_2026__medications') }}

),

encounters as (

    select encounter_id, provider_id from {{ ref('stg_synthea_2026__encounters') }}

)

select
    cast(medications.medication_key as varchar)         as medication_id,
    cast(medications.patient_id as varchar)             as person_id,
    cast(medications.patient_id as varchar)             as patient_id,
    cast(medications.encounter_id as varchar)           as encounter_id,
    cast(iff(medications.dispenses > 0, medications.started_at, null) as date) as dispensing_date,
    cast(medications.started_at as date)                as prescribing_date,
    cast('rxnorm' as varchar)                           as source_code_type,
    cast(medications.medication_code as varchar)        as source_code,
    cast(medications.medication_description as varchar) as source_description,
    cast(null as varchar)                               as ndc_code,
    cast(medications.medication_code as varchar)        as rxnorm_code,
    cast(null as varchar)                               as atc_code,
    cast(null as varchar)                               as route,
    cast(null as varchar)                               as strength,
    cast(null as number(38, 2))                         as quantity,
    cast(null as varchar)                               as quantity_unit,
    cast(null as number(38, 2))                         as days_supply,
    cast(encounters.provider_id as varchar)             as practitioner_id,
    cast(medications._loaded_at as timestamp_ntz)       as ingest_datetime,
    cast('synthea' as varchar)                          as data_source
from medications
left join encounters
    on encounters.encounter_id = medications.encounter_id
