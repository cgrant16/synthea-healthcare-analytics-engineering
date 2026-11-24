-- fct_immunization - one row per vaccine administered.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's immunization table, plus the timestamp and base cost from
-- staging. Codes are CVX. Synthea only records vaccines that were given, so there
-- is no status column: every row is a completed administration.

with immunizations as (

    select * from {{ ref('the_tuva_project', 'core__immunization') }}

),

source_immunizations as (

    select
        immunization_key,
        administered_at,
        base_cost
    from {{ ref('stg_synthea_2026__immunizations') }}

)

select
    -- keys
    immunizations.immunization_id,
    immunizations.person_id                                                         as patient_id,
    immunizations.encounter_id,

    -- when
    immunizations.occurrence_date                                                   as immunization_date,
    source_immunizations.administered_at,                                                               -- UTC

    -- what
    coalesce(immunizations.normalized_code, immunizations.source_code)              as cvx_code,
    coalesce(immunizations.normalized_description, immunizations.source_description) as vaccine_description,

    -- measures
    source_immunizations.base_cost
from immunizations
left join source_immunizations
    on source_immunizations.immunization_key = immunizations.immunization_id
