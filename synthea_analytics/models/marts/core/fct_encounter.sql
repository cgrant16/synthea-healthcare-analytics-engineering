-- fct_encounter - one row per encounter. The hub of the star schema.
-- Author: Cortwright Grant
--
-- Tuva Core's encounter table supplies the standardized encounter type, encounter
-- group and length of stay. Staging supplies what Tuva's clinical model has no
-- column for: the payer, the facility's id, exact timestamps, Synthea's own
-- encounter class, the visit reason and the base encounter cost.
--
-- The other fact tables carry encounter_id, so facility, practitioner and payer
-- for a condition, procedure, medication and so on are reached through this table.
--
-- Costs are Synthea's simulated figures:
--   total_cost            what the encounter's claim came to
--   payer_covered_amount  the part the payer covered
--   uncovered_amount      the rest
-- total_cost is Synthea's own number and is not a strict sum of the line items in
-- the other facts, so use it as given instead of rebuilding it from them.

with encounters as (

    select * from {{ ref('the_tuva_project', 'core__encounter') }}

),

source_encounters as (

    select
        encounter_id,
        organization_id,
        payer_id,
        started_at,
        stopped_at,
        encounter_class,
        encounter_code,
        encounter_description,
        reason_code,
        reason_description,
        base_encounter_cost
    from {{ ref('stg_synthea_2026__encounters') }}

),

patients as (

    select patient_id, birth_date from {{ ref('dim_patient') }}

)

select
    -- keys
    encounters.encounter_id,
    encounters.person_id                                as patient_id,
    source_encounters.organization_id                   as location_id,
    encounters.attending_provider_id                    as practitioner_id,
    source_encounters.payer_id,

    -- when
    encounters.encounter_start_date,
    encounters.encounter_end_date,
    source_encounters.started_at                        as encounter_started_at,    -- UTC
    source_encounters.stopped_at                        as encounter_stopped_at,    -- UTC

    -- what
    encounters.encounter_type,                                                      -- Tuva: office visit, acute inpatient, ...
    encounters.encounter_group,                                                     -- Tuva: office based | outpatient | inpatient
    source_encounters.encounter_class,                                              -- Synthea: ambulatory, wellness, ...
    source_encounters.encounter_code,                                               -- SNOMED CT
    source_encounters.encounter_description,
    source_encounters.reason_code,                                                  -- SNOMED CT; null where the source gives no reason
    source_encounters.reason_description,

    -- measures
    {{ age_in_years('patients.birth_date', 'encounters.encounter_start_date') }} as patient_age_at_encounter,
    encounters.length_of_stay,                                                      -- days, minimum 1
    datediff(minute, source_encounters.started_at, source_encounters.stopped_at) as duration_minutes,
    source_encounters.base_encounter_cost,
    encounters.charge_amount                            as total_cost,
    encounters.paid_amount                              as payer_covered_amount,
    encounters.charge_amount - encounters.paid_amount   as uncovered_amount
from encounters
left join source_encounters
    on source_encounters.encounter_id = encounters.encounter_id
left join patients
    on patients.patient_id = encounters.person_id
