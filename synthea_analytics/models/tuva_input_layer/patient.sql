-- Tuva Input Layer: patient. One row per patient.
-- Author: Cortwright Grant
--
-- person_id and patient_id are the same Synthea UUID: there is one source system,
-- so a person never has more than one patient record.

select
    cast(patient_id as varchar)             as person_id,
    cast(patient_id as varchar)             as patient_id,
    cast(first_name as varchar)             as first_name,
    cast(middle_name as varchar)            as middle_name,
    cast(last_name as varchar)              as last_name,
    cast(name_suffix as varchar)            as name_suffix,
    -- Tuva: male | female | unknown
    cast(case gender
            when 'M' then 'male'
            when 'F' then 'female'
            else 'unknown'
         end as varchar)                    as sex,
    -- Tuva expects a race terminology DESCRIPTION
    cast(case race
            when 'white'    then 'white'
            when 'black'    then 'black or african american'
            when 'asian'    then 'asian'
            when 'native'   then 'american indian or alaska native'
            when 'hawaiian' then 'native hawaiian or other pacific islander'
            when 'other'    then 'other race'
            else 'unknown'
         end as varchar)                    as race,
    -- Tuva expects an ethnicity terminology CODE
    cast(case ethnicity
            when 'hispanic'    then '2135-2'    -- Hispanic or Latino
            when 'nonhispanic' then '2186-5'    -- Not Hispanic or Latino
            else 'UNK'
         end as varchar)                    as ethnicity,
    cast(birth_date as date)                as birth_date,
    cast(death_date as date)                as death_date,
    cast(iff(death_date is not null, 1, 0) as integer) as death_flag,
    cast(ssn as varchar)                    as social_security_number,
    cast(address as varchar)                as address,
    cast(city as varchar)                   as city,
    cast(state as varchar)                  as state,
    cast(zip_code as varchar)               as zip_code,
    cast(county as varchar)                 as county,
    cast(latitude as float)                 as latitude,
    cast(longitude as float)                as longitude,
    cast(null as varchar)                   as phone,
    cast(null as varchar)                   as email,
    cast(_loaded_at as timestamp_ntz)       as ingest_datetime,
    cast('synthea' as varchar)              as data_source
from {{ ref('stg_synthea_2026__patients') }}
