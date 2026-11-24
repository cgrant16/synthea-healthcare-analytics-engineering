-- dim_practitioner - one row per clinician.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's practitioner table, plus the practitioner's facility and
-- sex from staging. This Synthea build generates exactly one practitioner per
-- facility, all GENERAL PRACTICE, so analysis by practitioner is in effect
-- analysis by facility. sub_specialty is left out: it is null on every row.

with practitioners as (

    select * from {{ ref('the_tuva_project', 'core__practitioner') }}

),

source_providers as (

    select
        provider_id,
        organization_id,
        gender
    from {{ ref('stg_synthea_2026__providers') }}

)

select
    practitioners.practitioner_id,
    source_providers.organization_id                                    as location_id,
    practitioners.npi,
    practitioners.first_name,
    practitioners.last_name,
    trim(practitioners.first_name || ' ' || coalesce(practitioners.last_name, '')) as practitioner_name,
    case source_providers.gender
        when 'M' then 'male'
        when 'F' then 'female'
        else 'unknown'
    end                                                                 as sex,
    practitioners.specialty,
    practitioners.practice_affiliation
from practitioners
left join source_providers
    on source_providers.provider_id = practitioners.practitioner_id
