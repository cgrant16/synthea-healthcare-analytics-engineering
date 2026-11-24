-- fct_medication - one row per medication order.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's medication table, which adds the RxNorm description and
-- the ATC drug class. Staging adds what Tuva's model has no column for: the stop
-- date, the reason, the payer and the costs.
--
-- A Synthea medication row is an order that was also filled. dispenses is the
-- number of fills, and total_cost = base_cost x dispenses on every row.
--
-- payer_id is the same payer as the encounter's on every row in this dataset. It
-- is carried here so medication cost by payer needs no join through fct_encounter.

with medications as (

    select * from {{ ref('the_tuva_project', 'core__medication') }}

),

source_medications as (

    select
        medication_key,
        payer_id,
        started_at,
        stopped_at,
        reason_code,
        reason_description,
        dispenses,
        base_cost,
        total_cost,
        payer_coverage
    from {{ ref('stg_synthea_2026__medications') }}

)

select
    -- keys
    medications.medication_id,
    medications.person_id                                                   as patient_id,
    medications.encounter_id,
    source_medications.payer_id,

    -- when
    medications.prescribing_date                                            as start_date,
    cast(source_medications.stopped_at as date)                             as stop_date,
    source_medications.started_at,                                                              -- UTC
    source_medications.stopped_at,                                                              -- UTC
    source_medications.stopped_at is null                                   as is_active,

    -- what
    medications.rxnorm_code,
    coalesce(medications.rxnorm_description, medications.source_description) as medication_description,
    medications.atc_code,
    medications.atc_description,
    source_medications.reason_code,                                                             -- SNOMED CT
    source_medications.reason_description,

    -- measures
    source_medications.dispenses,
    source_medications.base_cost,
    source_medications.total_cost,
    source_medications.payer_coverage                                       as payer_covered_amount,
    source_medications.total_cost - source_medications.payer_coverage       as uncovered_amount
from medications
left join source_medications
    on source_medications.medication_key = medications.medication_id
