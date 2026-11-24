-- fct_procedure - one row per procedure performed.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's procedure table, plus the timestamps, reason and base cost
-- from staging. Codes are SNOMED CT. procedure_family and the modifiers are left
-- out: Tuva's grouper covers ICD-10-PCS and HCPCS only, so they are null on every
-- row.
--
-- Joining back to staging: Tuva does not keep the source row's id. It replaces it
-- with a hash of ('clinical procedure', data_source, source id). The
-- source_procedures CTE below builds the same hash with Tuva's own macro so the
-- two line up. If a Tuva upgrade changes that recipe the join stops matching, and
-- the not_null test on procedure_started_at fails to say so.

with procedures as (

    select * from {{ ref('the_tuva_project', 'core__procedure') }}

),

source_procedures as (

    select
        {{ the_tuva_project.stable_id_hash(["'clinical procedure'", "'synthea'", 'procedure_key']) }} as procedure_id,
        started_at,
        stopped_at,
        reason_code,
        reason_description,
        base_cost
    from {{ ref('stg_synthea_2026__procedures') }}

)

select
    -- keys
    procedures.procedure_id,
    procedures.person_id                                                        as patient_id,
    procedures.encounter_id,

    -- when
    procedures.procedure_date,
    source_procedures.started_at                                                as procedure_started_at,    -- UTC
    source_procedures.stopped_at                                                as procedure_stopped_at,    -- UTC

    -- what
    procedures.code_system,
    coalesce(procedures.normalized_code, procedures.source_code)                as procedure_code,
    coalesce(procedures.normalized_description, procedures.source_description)  as procedure_description,
    source_procedures.reason_code,                                                                          -- SNOMED CT
    source_procedures.reason_description,

    -- measures
    source_procedures.base_cost
from procedures
left join source_procedures
    on source_procedures.procedure_id = procedures.procedure_id
