-- stg_synthea_2026__patients - one row per patient (RAW_2026.PATIENTS), typed and renamed.
-- Author: Cortwright Grant

with source as (

    select * from {{ source('synthea_2026_raw', 'patients') }}

)

select
    id                                      as patient_id,
    try_to_date(birthdate)                  as birth_date,
    try_to_date(deathdate)                  as death_date,
    ssn,
    drivers                                 as drivers_license,
    passport,
    prefix                                  as name_prefix,
    "FIRST"                                 as first_name,
    middle                                  as middle_name,
    "LAST"                                  as last_name,
    suffix                                  as name_suffix,
    maiden                                  as maiden_name,
    marital                                 as marital_status,
    race,
    ethnicity,
    gender,
    birthplace,
    address,
    city,
    state,
    county,
    fips                                    as county_fips,
    -- Synthea writes '00000' when it has no ZIP for the town (those rows have no FIPS either).
    nullif(zip, '00000')                    as zip_code,
    try_to_double(lat)                      as latitude,
    try_to_double(lon)                      as longitude,
    try_to_number(healthcare_expenses, 38, 2) as healthcare_expenses,
    try_to_number(healthcare_coverage, 38, 2) as healthcare_coverage,
    try_to_number(income, 38, 2)            as income,
    _source_file,
    _source_row,
    _loaded_at
from source
