-- dim_patient - one row per patient, living or deceased.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's patient table, with three changes:
--
--   1. De-identified. Names, SSN, street address and coordinates are left out:
--      analysts read this schema, and none of those are needed for analysis.
--      City, ZIP code and county stay.
--   2. Age is recalculated. Tuva's age is "as of the last run" for everyone, so
--      a patient who died in 1990 keeps getting older. Here age stops at the
--      date of death. Tuva also counts a year as 365 days, which turns people a
--      year older a few days before their birthday; this uses the calendar.
--   3. Marital status, county FIPS, income and Synthea's lifetime cost totals are
--      added from staging. Tuva's patient model has no place for them.
--
-- patient_id is Tuva's person_id. There is one source system, so the two are the
-- same Synthea UUID.

with patients as (

    select * from {{ ref('the_tuva_project', 'core__patient') }}

),

source_patients as (

    select
        patient_id,
        marital_status,
        county_fips,
        income,
        healthcare_expenses,
        healthcare_coverage
    from {{ ref('stg_synthea_2026__patients') }}

),

ethnicities as (

    select code, description from {{ ref('the_tuva_project', 'terminology__ethnicity') }}

),

joined as (

    select
        patients.person_id                                      as patient_id,
        patients.sex,
        patients.race,
        -- Tuva stores the ethnicity code (2135-2, 2186-5); analysts want the words.
        coalesce(lower(ethnicities.description), 'unknown')     as ethnicity,
        case source_patients.marital_status
            when 'M' then 'married'
            when 'S' then 'single'
            when 'D' then 'divorced'
            when 'W' then 'widowed'
            else 'unknown'                                      -- blank in the source, mostly children
        end                                                     as marital_status,
        patients.birth_date,
        patients.death_date,
        patients.death_flag = 1                                 as is_deceased,
        {{ age_in_years('patients.birth_date', 'coalesce(patients.death_date, current_date)') }} as age,
        patients.city,
        patients.state,
        patients.zip_code,
        patients.county,
        source_patients.county_fips,
        source_patients.income,
        source_patients.healthcare_expenses                     as lifetime_healthcare_expenses,
        source_patients.healthcare_coverage                     as lifetime_healthcare_coverage
    from patients
    left join source_patients
        on source_patients.patient_id = patients.person_id
    left join ethnicities
        on ethnicities.code = patients.ethnicity

)

select
    patient_id,
    sex,
    race,
    ethnicity,
    marital_status,
    birth_date,
    death_date,
    is_deceased,
    age,
    case
        when age < 10 then '0-9'
        when age < 20 then '10-19'
        when age < 30 then '20-29'
        when age < 40 then '30-39'
        when age < 50 then '40-49'
        when age < 60 then '50-59'
        when age < 70 then '60-69'
        when age < 80 then '70-79'
        when age < 90 then '80-89'
        else '90+'
    end                                                         as age_group,
    city,
    state,
    zip_code,
    county,
    county_fips,
    income,
    lifetime_healthcare_expenses,
    lifetime_healthcare_coverage
from joined
