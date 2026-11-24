-- fct_condition - one row per condition on a patient's problem list.
-- Author: Cortwright Grant
--
-- Built on Tuva Core's condition table. Codes are SNOMED CT. Tuva adds the
-- standard description and, where its grouper covers the code, a condition
-- family and name; conditions without a family are mostly social findings such as
-- employment status.
--
-- A condition has an onset date and, once it resolves, a resolved date. A
-- condition with no resolved date is still active.

select
    -- keys
    condition_id,
    person_id                                               as patient_id,
    encounter_id,                                                           -- the encounter it was diagnosed at

    -- when
    onset_date,
    resolved_date,

    -- what
    status,                                                                 -- active | resolved
    status = 'active'                                       as is_active,
    code_system,
    coalesce(normalized_code, source_code)                  as condition_code,
    coalesce(normalized_description, source_description)    as condition_description,
    condition_family,
    condition_name,

    -- measures
    datediff(day, onset_date, resolved_date)                as days_to_resolution   -- null while active
from {{ ref('the_tuva_project', 'core__condition') }}
