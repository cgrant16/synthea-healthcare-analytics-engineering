-- Tuva Input Layer: immunization. One row per vaccine administration.
-- Author: Cortwright Grant
--
-- Codes are CVX. Synthea only records vaccines that were given, so every row is
-- 'completed'. Location and practitioner come from the encounter.

with immunizations as (

    select * from {{ ref('stg_synthea_2026__immunizations') }}

),

encounters as (

    select encounter_id, organization_id, provider_id from {{ ref('stg_synthea_2026__encounters') }}

)

select
    cast(immunizations.immunization_key as varchar)     as immunization_id,
    cast(immunizations.patient_id as varchar)           as person_id,
    cast(immunizations.patient_id as varchar)           as patient_id,
    cast(immunizations.encounter_id as varchar)         as encounter_id,
    cast('cvx' as varchar)                              as source_code_type,
    cast(immunizations.vaccine_code as varchar)         as source_code,
    cast(immunizations.vaccine_description as varchar)  as source_description,
    cast('completed' as varchar)                        as status,
    cast(null as varchar)                               as status_reason,
    cast(immunizations.administered_at as date)         as occurrence_date,
    cast(null as varchar)                               as source_dose,
    cast(null as varchar)                               as lot_number,
    cast(null as varchar)                               as body_site,
    cast(null as varchar)                               as route,
    cast(encounters.organization_id as varchar)         as location_id,
    cast(encounters.provider_id as varchar)             as practitioner_id,
    cast(immunizations._loaded_at as timestamp_ntz)     as ingest_datetime,
    cast('synthea' as varchar)                          as data_source
from immunizations
left join encounters
    on encounters.encounter_id = immunizations.encounter_id
