-- fct_observation - one row per non-laboratory observation.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's observation table: vital signs, survey answers, social
-- history, exams and Synthea's yearly quality-of-life scores. Lab results are in
-- fct_lab_result.
--
-- Two things to know before using it:
--   * encounter_id is null on about 10% of rows. Those are the yearly QALY, DALY
--     and QOLS scores (observation_type 'other'), which Synthea records outside
--     any encounter.
--   * code_type says which vocabulary observation_code belongs to. Most are LOINC.
--     'synthea' marks codes Synthea invented, which exist in no standard.
--
-- result is text because many observations are answers in words. result_numeric
-- is the same value as a number, and null when it is not one.

select
    -- keys
    observation_id,
    person_id                                                       as patient_id,
    encounter_id,

    -- when
    observation_date,

    -- what
    observation_type,                                                               -- vital-signs, survey, social-history, ...
    coalesce(normalized_code_type, source_code_type)                as code_type,   -- loinc | snomed-ct | synthea
    coalesce(normalized_code, source_code)                          as observation_code,
    coalesce(normalized_description, source_description)            as observation_description,

    -- measures
    result,
    try_to_double(result)                                           as result_numeric,
    coalesce(normalized_units, source_units)                        as units
from {{ ref('the_tuva_project', 'core__observation') }}
