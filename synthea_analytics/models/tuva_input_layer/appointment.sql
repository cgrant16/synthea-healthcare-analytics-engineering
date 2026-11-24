-- Tuva Input Layer: appointment. Deliberately empty.
-- Author: Cortwright Grant
--
-- Synthea has no scheduling data. Tuva still needs this model to exist with the
-- contract's columns and types whenever clinical_enabled is true, so it returns
-- zero rows. core.appointment is therefore empty too.

select
    cast(null as varchar)       as appointment_id,
    cast(null as varchar)       as person_id,
    cast(null as varchar)       as patient_id,
    cast(null as varchar)       as encounter_id,
    cast(null as timestamp_ntz) as start_datetime,
    cast(null as timestamp_ntz) as end_datetime,
    cast(null as integer)       as duration,
    cast(null as varchar)       as location_id,
    cast(null as varchar)       as practitioner_id,
    cast(null as varchar)       as type,
    cast(null as varchar)       as status,
    cast(null as varchar)       as reason,
    cast(null as varchar)       as cancellation_reason,
    cast(null as timestamp_ntz) as ingest_datetime,
    cast(null as varchar)       as data_source
where 1 = 0
