-- Tuva Input Layer: encounter. One row per encounter.
-- Author: Cortwright Grant
--
-- encounter_type: Synthea's ENCOUNTERCLASS mapped to Tuva's encounter types.
--   ambulatory, wellness -> office visit          (clinic visits and check-ups)
--   outpatient           -> outpatient hospital or clinic
--   emergency            -> emergency department
--   urgentcare           -> urgent care
--   inpatient            -> acute inpatient
--   snf                  -> inpatient skilled nursing
--   hospice              -> inpatient hospice     (judgement call: Synthea does not say
--                                                  whether hospice care is facility- or home-based)
--   home                 -> home health
--   virtual              -> telehealth
--
-- Not mapped, because the source has nothing to map:
--   admit source / admit type / discharge disposition, DRG.
--   primary diagnosis: the reason code is SNOMED CT, and Tuva accepts only ICD here.
--   allowed_amount: Synthea has charges and what the payer covered, but no allowed amount.

with encounters as (

    select * from {{ ref('stg_synthea_2026__encounters') }}

),

organizations as (

    select * from {{ ref('stg_synthea_2026__organizations') }}

),

providers as (

    select * from {{ ref('stg_synthea_2026__providers') }}

)

select
    cast(encounters.encounter_id as varchar)        as encounter_id,
    cast(encounters.patient_id as varchar)          as person_id,
    cast(encounters.patient_id as varchar)          as patient_id,
    cast(case encounters.encounter_class
            when 'ambulatory' then 'office visit'
            when 'wellness'   then 'office visit'
            when 'outpatient' then 'outpatient hospital or clinic'
            when 'emergency'  then 'emergency department'
            when 'urgentcare' then 'urgent care'
            when 'inpatient'  then 'acute inpatient'
            when 'snf'        then 'inpatient skilled nursing'
            when 'hospice'    then 'inpatient hospice'
            when 'home'       then 'home health'
            when 'virtual'    then 'telehealth'
         end as varchar)                            as encounter_type,
    cast(encounters.started_at as date)             as encounter_start_date,
    cast(encounters.stopped_at as date)             as encounter_end_date,
    cast(null as varchar)                           as admit_source_code,
    cast(null as varchar)                           as admit_type_code,
    cast(null as varchar)                           as discharge_disposition_code,
    cast(encounters.provider_id as varchar)         as attending_provider_id,   -- = practitioner.practitioner_id
    cast(providers.provider_name as varchar)        as attending_provider_name,
    cast(organizations.npi as varchar)              as facility_npi,
    cast(organizations.organization_name as varchar) as facility_name,
    cast(null as varchar)                           as primary_diagnosis_code_type,
    cast(null as varchar)                           as primary_diagnosis_code,
    cast(null as varchar)                           as drg_code_type,
    cast(null as varchar)                           as drg_code,
    cast(encounters.payer_coverage as number(38, 2))    as paid_amount,     -- what the payer covered
    cast(null as number(38, 2))                         as allowed_amount,
    cast(encounters.total_claim_cost as number(38, 2))  as charge_amount,   -- encounter plus all its line items
    cast(encounters._loaded_at as timestamp_ntz)    as ingest_datetime,
    cast('synthea' as varchar)                      as data_source
from encounters
left join organizations
    on organizations.organization_id = encounters.organization_id
left join providers
    on providers.provider_id = encounters.provider_id
