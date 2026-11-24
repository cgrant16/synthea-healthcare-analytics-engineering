-- Tuva Input Layer: practitioner. One row per clinician.
-- Author: Cortwright Grant
--
-- Synthea names are 'First Last' in one column. This build generates one provider
-- per organization, all GENERAL PRACTICE, each with a synthetic NPI (9999...) that
-- is not in the national registry; the NPI is passed through as the source has it.

with providers as (

    select * from {{ ref('stg_synthea_2026__providers') }}

),

organizations as (

    select organization_id, organization_name from {{ ref('stg_synthea_2026__organizations') }}

)

select
    cast(providers.provider_id as varchar)                              as practitioner_id,
    cast(providers.npi as varchar)                                      as npi,
    cast(split_part(providers.provider_name, ' ', 1) as varchar)        as first_name,
    cast(nullif(trim(substr(providers.provider_name,
                            position(' ' in providers.provider_name) + 1)), '') as varchar) as last_name,
    cast(organizations.organization_name as varchar)                    as practice_affiliation,
    cast(lower(providers.specialty) as varchar)                         as specialty,
    cast(null as varchar)                                               as sub_specialty,
    cast(providers._loaded_at as timestamp_ntz)                         as ingest_datetime,
    cast('synthea' as varchar)                                          as data_source
from providers
left join organizations
    on organizations.organization_id = providers.organization_id
