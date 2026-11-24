-- fct_lab_result - one row per resulted lab analyte.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's lab_result table. Codes are LOINC. Each row is one
-- component (glucose, hemoglobin A1c, ...), not a whole panel or order: Synthea
-- has no order, accession number, specimen or reference range, so those Tuva
-- columns are null on every row and are left out.
--
-- result is text because some labs report words ("Negative", a blood type).
-- result_numeric is the same value as a number, and null when it is not one
-- (about 19% of rows).

select
    -- keys
    lab_result_id,
    person_id                                                                       as patient_id,
    encounter_id,

    -- when
    cast(result_datetime as date)                                                   as result_date,
    result_datetime                                                                 as resulted_at,     -- UTC

    -- what
    coalesce(normalized_component_code, source_component_code)                      as loinc_code,
    coalesce(normalized_component_description, source_component_description)        as lab_description,

    -- measures
    result,
    try_to_double(result)                                                           as result_numeric,
    coalesce(normalized_units, source_units)                                        as units
from {{ ref('the_tuva_project', 'core__lab_result') }}
