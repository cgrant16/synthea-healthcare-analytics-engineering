# Core mart data model (`SYNTHEA.MARTS`)

**Author:** Cortwright Grant

A star schema with five dimensions and seven facts, built on Tuva Core. `fct_encounter` is the hub. Each of the six clinical-event facts points at it through `encounter_id`, which is how an event reaches its facility, practitioner and payer.

Column names and types are as built in Snowflake. Definitions of each column are in [`_core__models.yml`](../synthea_analytics/models/marts/core/_core__models.yml) and in the dbt docs site (`dbtf docs serve`).

## Entity-relationship diagram

```mermaid
erDiagram
    dim_patient      ||--o{ fct_encounter    : "patient_id"
    dim_location     ||--o{ fct_encounter    : "location_id"
    dim_practitioner ||--o{ fct_encounter    : "practitioner_id"
    dim_payer        ||--o{ fct_encounter    : "payer_id"
    dim_date         ||--o{ fct_encounter    : "encounter_start_date"
    dim_location     ||--o{ dim_practitioner : "location_id"

    fct_encounter ||--o{ fct_condition    : "encounter_id"
    fct_encounter ||--o{ fct_procedure    : "encounter_id"
    fct_encounter ||--o{ fct_medication   : "encounter_id"
    fct_encounter ||--o{ fct_immunization : "encounter_id"
    fct_encounter ||--o{ fct_lab_result   : "encounter_id"
    fct_encounter ||--o{ fct_observation  : "encounter_id"

    dim_payer ||--o{ fct_medication : "payer_id"

    dim_patient {
        TEXT    patient_id PK
        TEXT    sex
        TEXT    race
        TEXT    ethnicity
        TEXT    marital_status
        DATE    birth_date
        DATE    death_date
        BOOLEAN is_deceased
        NUMBER  age
        TEXT    age_group
        TEXT    city
        TEXT    state
        TEXT    zip_code
        TEXT    county
        TEXT    county_fips
        NUMBER  income
        NUMBER  lifetime_healthcare_expenses
        NUMBER  lifetime_healthcare_coverage
    }

    dim_location {
        TEXT   location_id PK
        TEXT   location_name
        TEXT   npi
        TEXT   address
        TEXT   city
        TEXT   state
        TEXT   zip_code
        NUMBER latitude
        NUMBER longitude
    }

    dim_practitioner {
        TEXT practitioner_id PK
        TEXT location_id FK
        TEXT npi
        TEXT first_name
        TEXT last_name
        TEXT practitioner_name
        TEXT sex
        TEXT specialty
        TEXT practice_affiliation
    }

    dim_payer {
        TEXT    payer_id PK
        TEXT    payer_name
        TEXT    payer_type
        BOOLEAN is_insured
    }

    dim_date {
        DATE    date_day PK
        NUMBER  year_number
        NUMBER  quarter_number
        NUMBER  month_number
        TEXT    month_name
        TEXT    year_month
        TEXT    year_quarter
        NUMBER  iso_week_number
        NUMBER  day_of_month
        NUMBER  day_of_year
        NUMBER  iso_day_of_week
        TEXT    day_name
        BOOLEAN is_weekend
        DATE    month_start_date
        DATE    quarter_start_date
        DATE    year_start_date
    }

    fct_encounter {
        TEXT          encounter_id PK
        TEXT          patient_id FK
        TEXT          location_id FK
        TEXT          practitioner_id FK
        TEXT          payer_id FK
        DATE          encounter_start_date FK
        DATE          encounter_end_date
        TIMESTAMP_NTZ encounter_started_at
        TIMESTAMP_NTZ encounter_stopped_at
        TEXT          encounter_type
        TEXT          encounter_group
        TEXT          encounter_class
        TEXT          encounter_code
        TEXT          encounter_description
        TEXT          reason_code
        TEXT          reason_description
        NUMBER        patient_age_at_encounter
        NUMBER        length_of_stay
        NUMBER        duration_minutes
        NUMBER        base_encounter_cost
        NUMBER        total_cost
        NUMBER        payer_covered_amount
        NUMBER        uncovered_amount
    }

    fct_condition {
        TEXT    condition_id PK
        TEXT    patient_id FK
        TEXT    encounter_id FK
        DATE    onset_date FK
        DATE    resolved_date
        TEXT    status
        BOOLEAN is_active
        TEXT    code_system
        TEXT    condition_code
        TEXT    condition_description
        TEXT    condition_family
        TEXT    condition_name
        NUMBER  days_to_resolution
    }

    fct_procedure {
        TEXT          procedure_id PK
        TEXT          patient_id FK
        TEXT          encounter_id FK
        DATE          procedure_date FK
        TIMESTAMP_NTZ procedure_started_at
        TIMESTAMP_NTZ procedure_stopped_at
        TEXT          code_system
        TEXT          procedure_code
        TEXT          procedure_description
        TEXT          reason_code
        TEXT          reason_description
        NUMBER        base_cost
    }

    fct_medication {
        TEXT          medication_id PK
        TEXT          patient_id FK
        TEXT          encounter_id FK
        TEXT          payer_id FK
        DATE          start_date FK
        DATE          stop_date
        TIMESTAMP_NTZ started_at
        TIMESTAMP_NTZ stopped_at
        BOOLEAN       is_active
        TEXT          rxnorm_code
        TEXT          medication_description
        TEXT          atc_code
        TEXT          atc_description
        TEXT          reason_code
        TEXT          reason_description
        NUMBER        dispenses
        NUMBER        base_cost
        NUMBER        total_cost
        NUMBER        payer_covered_amount
        NUMBER        uncovered_amount
    }

    fct_immunization {
        TEXT          immunization_id PK
        TEXT          patient_id FK
        TEXT          encounter_id FK
        DATE          immunization_date FK
        TIMESTAMP_NTZ administered_at
        TEXT          cvx_code
        TEXT          vaccine_description
        NUMBER        base_cost
    }

    fct_lab_result {
        TEXT          lab_result_id PK
        TEXT          patient_id FK
        TEXT          encounter_id FK
        DATE          result_date FK
        TIMESTAMP_NTZ resulted_at
        TEXT          loinc_code
        TEXT          lab_description
        TEXT          result
        FLOAT         result_numeric
        TEXT          units
    }

    fct_observation {
        TEXT  observation_id PK
        TEXT  patient_id FK
        TEXT  encounter_id FK
        DATE  observation_date FK
        TEXT  observation_type
        TEXT  code_type
        TEXT  observation_code
        TEXT  observation_description
        TEXT  result
        FLOAT result_numeric
        TEXT  units
    }
```

The diagram leaves out two sets of lines so it stays readable. Every clinical fact also has its own `patient_id` → `dim_patient` and its event date → `dim_date.date_day`, as the table below shows.

## Grain and join keys

| Table | One row per | Primary key | Joins to |
|---|---|---|---|
| `dim_patient` | patient, living or deceased | `patient_id` | — |
| `dim_location` | care facility (Synthea organization) | `location_id` | — |
| `dim_practitioner` | clinician | `practitioner_id` | `dim_location` |
| `dim_payer` | payer, including "No Insurance" | `payer_id` | — |
| `dim_date` | calendar day, 1915-01-01 to end of current year | `date_day` | — |
| `fct_encounter` | encounter | `encounter_id` | `dim_patient`, `dim_location`, `dim_practitioner`, `dim_payer`, `dim_date` on `encounter_start_date` |
| `fct_condition` | condition on a problem list (SNOMED CT) | `condition_id` | `fct_encounter`, `dim_patient`, `dim_date` on `onset_date` |
| `fct_procedure` | procedure performed (SNOMED CT) | `procedure_id` | `fct_encounter`, `dim_patient`, `dim_date` on `procedure_date` |
| `fct_medication` | medication order (RxNorm) | `medication_id` | `fct_encounter`, `dim_patient`, `dim_payer`, `dim_date` on `start_date` |
| `fct_immunization` | vaccine administered (CVX) | `immunization_id` | `fct_encounter`, `dim_patient`, `dim_date` on `immunization_date` |
| `fct_lab_result` | resulted lab analyte (LOINC) | `lab_result_id` | `fct_encounter`, `dim_patient`, `dim_date` on `result_date` |
| `fct_observation` | observation (vitals, surveys, social history) | `observation_id` | `fct_encounter`, `dim_patient`, `dim_date` on `observation_date` |

## Design notes

- **Natural keys.** Keys are Synthea's own UUIDs (or Tuva-generated IDs for conditions and procedures). There is one source system, so no surrogate keys are needed.
- **The encounter is the hub.** A clinical fact reaches its facility, practitioner and payer through `fct_encounter`, not through its own foreign keys. The exception is `fct_medication`, which carries `payer_id` because Synthea bills medications separately. It matches the encounter's payer on every row in this dataset.
- **Practitioner is effectively facility.** This Synthea build has exactly one practitioner per facility, all in general practice. The model allows many practitioners per facility, but analysis by practitioner is in practice analysis by facility.
- **Costs don't roll up.** `fct_encounter.total_cost` is Synthea's claim total. It is not the sum of the line-item costs in the procedure, medication and immunization facts, so use each as given and don't add them together.
- **Every relationship is tested.** Each primary key is tested unique and not null, and each foreign key in the diagram has a `relationships` test. Each fact also has an `equal_rowcount` test against the Tuva Core table it is built on, which proves no join dropped or duplicated a row.
