# Synthea Healthcare Analytics Engineering Project — Context & Dependencies

**Purpose**: This document captures the full context of a personal learning project to build a production-style healthcare analytics pipeline using **dbt Core** on **Snowflake**, with data landed in **Amazon S3**. It serves as the implementation brief for the project.

**Author**: Cortwright Grant  
**Environment**: Personal Snowflake account + Amazon S3 bucket  
**Primary Machine**: Mac (for dbt Core development)  
**Secondary Machine**: Windows (AWS CLI was installed here for initial S3 work)  
**Date Started**: November 2026

---

## 1. Project Goal

Build a high-quality, portfolio-ready **Analytics Engineering** project in the healthcare domain using:

- **dbt Core** (not dbt Cloud)
- **Snowflake** as the data warehouse
- **Amazon S3** as the landing zone
- **Synthea / SyntheticMass** synthetic patient data

The project should demonstrate professional Analytics Engineering practices:

- Medallion architecture (RAW → Staging → Intermediate → Marts)
- Clean data modeling (star schema or similar)
- Data quality tests
- Documentation
- Clear RBAC and infrastructure separation
- Reproducible, well-structured dbt project

This is a **skill-building and portfolio** project, not a production system for a client.

---

## 2. Data Source

**Dataset**: SyntheticMass Data, Version 2 (24 May 2017)  
**Source**: https://synthea.mitre.org/downloads (or the Box link previously used)  
**Size**: ~21 GB archive  
**Contents**: ~1 million synthetic patients encoded in:
- FHIR 3.0.1
- C-CDA
- **CSV** (this is what we will use)

**Important**: Only the **CSV files** are needed for this project. FHIR and C-CDA can be ignored.

### Expected CSV Files (typical for this version)
- `patients.csv`
- `encounters.csv`
- `conditions.csv`
- `medications.csv`
- `procedures.csv`
- `observations.csv`
- `immunizations.csv`
- `allergies.csv`
- `careplans.csv`
- `organizations.csv` / `providers.csv` (may or may not be present depending on exact extract)

Primary keys are UUIDs. Dates are mostly `YYYY-MM-DD` or ISO-8601.

**Reference**: Official CSV data dictionary lives in the Synthea GitHub wiki:  
https://github.com/synthetichealth/synthea/wiki/CSV-File-Data-Dictionary

---

## 3. Target Architecture

```
Amazon S3 (landing zone)
    ↓
Snowflake External Stage + Storage Integration
    ↓
Snowflake RAW schema (loaded tables)
    ↓
dbt Core project
    ├── Staging models (stg_*)
    ├── Intermediate models (int_*)
    └── Marts (dim_* / fct_*)
```

### Snowflake Objects Already Planned / Partially Created
- **Database**: `SYNTHEA`
- **Schemas**:
  - `RAW`
  - `STAGING`
  - `INTERMEDIATE`
  - `MARTS`
- **Warehouses**:
  - `SYNTHEA_INGEST_WH`
  - `SYNTHEA_TRANSFORM_WH`
  - `SYNTHEA_ANALYST_WH`
- **Roles** (RBAC already created by user):
  - `SYNTHEA_INGEST_ROLE`
  - `SYNTHEA_DBT_ROLE`
  - `SYNTHEA_ANALYST_ROLE`
  - `SYNTHEA_DEVELOPER_ROLE` (inherits the above two)
- **File Format**: `SYNTHEA_CSV_FORMAT` (CSV, skip header, etc.)
- **Storage Integration**: Planned name `synthea_s3_int`
- **External Stage**: Planned in `SYNTHEA.RAW` pointing at S3

---

## 4. Current Status

| Area                        | Status          | Notes |
|----------------------------|-----------------|-------|
| Snowflake roles & warehouses | Done           | User confirmed roles and personas created |
| Database & schemas         | Partially done | Database `SYNTHEA` and schemas planned/created |
| AWS CLI                    | Installed      | On Windows machine; credentials still need configuration |
| S3 bucket                  | Not created    | `aws s3 mb` failed with “Unable to locate credentials” |
| Data extraction            | Unknown        | User downloaded the 21GB archive; CSV extraction status unclear |
| dbt Core project           | Not started    | Will be built on Mac |
| Storage Integration + Stage| Not started    | Depends on S3 bucket + IAM role |

---

## 5. Immediate Next Steps (Dependencies)

### On the Windows machine (AWS CLI work)
1. Run `aws configure` and provide Access Key + Secret Key
2. Create S3 bucket (choose a real unique name)
3. Extract **only the CSV files** from the SyntheticMass archive
4. Upload CSVs to `s3://<bucket>/synthea-v2/csv/`
5. Verify with `aws s3 ls`

### In Snowflake (after S3 is ready)
1. Create IAM role + least-privilege policy for the bucket prefix
2. Create Storage Integration (`synthea_s3_int`)
3. Update IAM role trust policy with values from `DESC INTEGRATION`
4. Create external stage in `SYNTHEA.RAW`
5. `LIST @stage` to confirm access
6. Create RAW tables and `COPY INTO` the CSVs

### On the Mac (dbt Core)
1. Install dbt-core + dbt-snowflake
2. Initialize dbt project
3. Configure `profiles.yml` to use `SYNTHEA_DBT_ROLE` (prefer key-pair auth)
4. Build staging → intermediate → mart models
5. Add tests and documentation

---

## 6. Key Design Decisions Already Made

- Use **Storage Integration** (not hardcoded AWS keys) for S3 access
- Separate roles for ingestion vs transformation vs analysis
- Future grants for automatic privilege management
- Dedicated warehouses for cost control
- Only CSV data (ignore FHIR/C-CDA)
- Medallion architecture
- dbt Core (local development on Mac)

---

## 7. Dependencies & Prerequisites

| Dependency              | Owner / Location      | Status     | Notes |
|-------------------------|-----------------------|------------|-------|
| SyntheticMass v2 archive| User                  | Downloaded | 21GB |
| AWS Account + IAM user  | User                  | Exists     | Credentials not yet configured in CLI |
| AWS CLI                 | Windows machine       | Installed  | Needs `aws configure` |
| Snowflake Account       | User                  | Exists     | Roles already created |
| dbt Core                | Mac                   | Not installed | To be set up later |
| IAM Role for Snowflake  | AWS                   | Not created| Required for Storage Integration |
| Storage Integration     | Snowflake             | Not created| Depends on IAM Role ARN |

---

## 8. Suggested dbt Project Structure (for later)

```
synthea_analytics/
├── models/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
│       ├── core/          (patients, encounters, conditions)
│       └── finance/       (optional cost marts)
├── tests/
├── macros/
├── seeds/                 (if any small reference data)
├── dbt_project.yml
└── profiles.yml           (gitignored)
```

---

## 9. Useful References

- Synthea CSV Data Dictionary: https://github.com/synthetichealth/synthea/wiki/CSV-File-Data-Dictionary
- Snowflake S3 Storage Integration docs: https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration
- dbt Snowflake permissions: https://docs.getdbt.com/reference/database-permissions/snowflake-permissions

---

## 10. Implementation Notes

- Prefer **least privilege** and **Storage Integration** over access keys.
- The user is learning Analytics Engineering — favor clear, well-documented patterns over cleverness.
- Keep RAW as a pure landing zone; all transformation logic belongs in dbt.
- The 2017 SyntheticMass version may have a slightly older schema than current Synthea (claims tables may be limited or absent).
- User works primarily on Mac for development; Windows was only used for AWS CLI experimentation.
- Goal is a clean, shareable portfolio project.

---

*End of context document.*
