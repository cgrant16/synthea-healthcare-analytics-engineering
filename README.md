# Synthea Healthcare Analytics Engineering Project

**Author:** Cortwright Grant

Synthea CSV → **Amazon S3** → **Snowflake RAW** → dbt.
Full background: [docs/project-context.md](docs/project-context.md).

Two Synthea datasets land through the same pipeline:

| Dataset | Schema | Patients | Used for |
|---|---|---|---|
| SyntheticMass v2 (2017) | `SYNTHEA.RAW` | 1.59 M | Ingestion at scale. Clinical tables only. |
| Current-version Synthea (2026 build) | `SYNTHEA.RAW_2026` | 11,500 | The dbt and Tuva build. Adds organizations, providers, payers, claims and costs. See [Current-version dataset](#current-version-dataset-raw_2026). |

They are different populations with different columns and are never joined.

## Ingestion runbook

Run in this order. Each step is idempotent, so re-running one is safe.

| # | Where | File | Runs as | What it does |
|---|-------|------|---------|--------------|
| — | Snowflake | `snowflake/00_rbac_bootstrap.sql` | SYSADMIN / SECURITYADMIN | **Already run:** warehouses, roles, schemas, grants and service users |
| 0 | Windows | `aws/00_config.ps1` | — | **Edit once:** bucket name, region, archive path |
| 1 | Windows | `aws/01_setup_s3_and_upload.ps1` | your IAM user | Credentials, hardened bucket, extract CSVs only, upload one prefix per table |
| 2 | Windows | `aws/02_setup_iam_for_snowflake.ps1` (Phase A) | your IAM user | Read-only policy and role with a placeholder trust policy |
| 3 | Snowflake | `snowflake/01_storage_integration.sql` | ACCOUNTADMIN | Storage integration and grants; `DESC` returns Snowflake's ARN and external ID |
| 4 | Windows | `aws/02_setup_iam_for_snowflake.ps1 -SnowflakeIamUserArn … -SnowflakeExternalId …` (Phase B) | your IAM user | Restricts the role's trust policy to Snowflake |
| 5 | Snowflake | `snowflake/02_stage_and_file_format.sql` | SYNTHEA_INGEST_ROLE | File format, external stage, `LIST`, read test, header test |
| 5b | Mac | `aws/quarantine_patients.py` | — | Splits patients into clean rows and rejected lines, and keeps the original files in S3 |
| 6 | Snowflake | `snowflake/03_raw_tables_and_load.sql` | SYNTHEA_INGEST_ROLE | Builds each table from its CSV header and loads it with `COPY INTO` |
| 7 | Snowflake | `snowflake/04_load_verification.sql` | SYNTHEA_INGEST_ROLE | Row counts, compares staged files with loaded files, checks keys and audit columns |

Copy the whole `aws/` folder to the Windows machine. Run the scripts like this:

```powershell
cd C:\path\to\aws
powershell -ExecutionPolicy Bypass -File .\01_setup_s3_and_upload.ps1          # dry run: inventory and planned S3 keys
powershell -ExecutionPolicy Bypass -File .\01_setup_s3_and_upload.ps1 -Upload  # real upload
powershell -ExecutionPolicy Bypass -File .\02_setup_iam_for_snowflake.ps1      # Phase A
```

**On a Mac instead of Windows:** the bucket and IAM steps were run with the AWS CLI directly. For the upload, `aws/mac_extract_and_upload.sh` handles the nested archive. The 22 GB file contains 12 `output_N_*.tar.gz` batches, and each batch has `csv/` (9 tables), FHIR and C-CDA. The script extracts only the CSVs, gzips them and uploads one file per batch per table.

## S3 layout

```
s3://<bucket>/synthea-v2/csv/
    patients/      batch_01__patients.csv.gz ... batch_12__patients.csv.gz
    encounters/    ...
    observations/  ...
```

## Security model

- **No AWS keys in Snowflake.** The storage integration assumes `synthea-snowflake-s3-read-role`. The trust policy accepts only Snowflake's IAM user, and only when the request carries your account's external ID.
- **Least privilege in two places:**
  - The IAM policy allows `GetObject` and `ListBucket` only under `synthea-v2/csv/`. It grants no write or delete.
  - `STORAGE_ALLOWED_LOCATIONS` limits Snowflake to that prefix as well.
- **Roles are separated:**
  - Only `SYNTHEA_INGEST_ROLE` can use the integration, own the stage and write to RAW.
  - `SYNTHEA_DBT_ROLE` gets `SELECT` on RAW through future grants.
- **Bucket:** public access is blocked, ACLs are disabled (BucketOwnerEnforced) and SSE-S3 encryption is on.

## RAW design

- Every column is `VARCHAR`, and column names come from the CSV header (`INFER_SCHEMA`). Types are cast in dbt staging.
- Each row has three audit columns: `_SOURCE_FILE`, `_SOURCE_ROW` and `_LOADED_AT`.
- `COPY` skips files it has already loaded, so re-running a load never duplicates rows. Do not use `FORCE = TRUE`.

## dbt project (`synthea_analytics/`)

**Engine:** dbt v2 (2.0.12), the Rust-based engine and dbt's default for new installs. It runs as a single binary with no Python, and its stricter parsing catches errors earlier. The project also runs on dbt Core 1.12.7 as a fallback: it has no deprecations and gives identical source-test results on both engines.

**Install dbt v2:**
```bash
curl -fsSL https://public.cdn.getdbt.com/fs/install/install.sh | sh -s -- --update   # installs to ~/.local/bin/dbt
dbt system update                                                                    # later upgrades
```

**dbt Core 1.12 fallback (optional):**
```bash
python3.12 -m venv .venv && .venv/bin/pip install -r synthea_analytics/requirements.txt
```

**Profile:** copy `synthea_analytics/profiles.yml.example` to `~/.dbt/profiles.yml`, or append its `synthea:` block, then fill in the `<PLACEHOLDERS>`. Both engines read the same profile.

**Authentication:** dbt connects as `SYNTHEA_DBT_USER`, a `TYPE = SERVICE` user that can't use a password, with role `SYNTHEA_DBT_ROLE` and warehouse `SYNTHEA_TRANSFORM_WH`. It authenticates with an RSA key pair in PKCS#8 format. To set one up:
```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/keys/synthea_dbt_user.p8 -nocrypt
openssl rsa -in ~/.snowflake/keys/synthea_dbt_user.p8 -pubout -out ~/.snowflake/keys/synthea_dbt_user.pub
```
Then run this in Snowflake as SECURITYADMIN, pasting in the body of the `.pub` file without its BEGIN/END lines: `ALTER USER SYNTHEA_DBT_USER SET RSA_PUBLIC_KEY = '<key body>';`

**Daily use:**
```bash
cd synthea_analytics
dbt debug                 # dbt v2 (~/.local/bin/dbt)
dbt test -s "source:*"
```
To use dbt Core 1.12 instead, run `source ../.venv/bin/activate` first. While the virtual environment is active, its `dbt` takes precedence.

**Layers:**

| Layer | Schema | Materialized as |
|---|---|---|
| `staging/` | `STAGING` | views |
| `tuva_input_layer/` | `TUVA_INPUT_LAYER` | tables |
| Tuva Core (package) | `TUVA_NORMALIZED_LAYER`, `TUVA_CORE`, and others | tables |
| `intermediate/` | `INTERMEDIATE` | views |
| `marts/` | `MARTS` | tables |

`macros/generate_schema_name.sql` builds into those schemas exactly as named, because the dbt role can't create schemas.

### Tuva Core

[Tuva Core](https://github.com/tuva-health/tuva-core) 1.0.0 is the conformed layer between staging and the marts. It turns the source tables into a standard healthcare data model and attaches standard terminology (SNOMED CT, LOINC, CVX, RxNorm drug classes).

```
RAW_2026  →  stg_synthea_2026__*  →  tuva_input_layer/*  →  Tuva Core  →  marts
(landed)     (typed, renamed)        (Tuva's contract)      (package)     (to build)
```

- **Install:** `packages.yml` pins the `v1.0.0` GitHub tag, because Tuva 1.0 is not on dbt Hub yet. `package-lock.yml` records the exact commit. Run `dbt deps` after cloning.
- **Schemas:** Tuva builds into its own schemas, prefixed `TUVA_` by `tuva_schema_prefix`. `snowflake/07_tuva_schemas.sql` pre-creates them and grants the dbt role, since that role can't create schemas.
- **Input layer:** `models/tuva_input_layer/` holds one model per Tuva clinical input table, named as Tuva expects (`patient`, `encounter`, `condition`, and so on) with exactly the contract's columns, order and types. Each model's header comment explains its mapping decisions.
- **Scope:** only the clinical domain is mapped (`clinical_enabled: true`). The claims domain is not, so member months, cost and the claims-based marts are not built.
- **Seeds:** Tuva's 71 terminology, value-set and provider seeds load from Tuva's public S3 bucket with `COPY INTO`, run by the dbt role. This is the one place data enters Snowflake outside the ingest role and the storage integration.

```bash
cd synthea_analytics
dbt deps                                                    # install Tuva Core and dbt_utils
dbt seed  --select package:the_tuva_project                 # terminology, about 1 minute
dbt build --select path:models/staging/synthea_2026 path:models/tuva_input_layer
dbt build --select package:the_tuva_project --exclude resource_type:seed resource_type:unit_test
```

**How the source maps to Tuva:**

| Tuva input model | Source | Notes |
|---|---|---|
| `patient` | patients | Sex, race and ethnicity recoded to Tuva's values |
| `encounter` | encounters, organizations, providers | Encounter class mapped to Tuva encounter types; facility NPI and attending provider filled |
| `condition` | conditions | SNOMED CT, mapped as problem-list entries |
| `procedure` | procedures | SNOMED CT |
| `medication` | medications | RxNorm |
| `observation` | observations, all but laboratory | Vital signs, surveys, social history, exams |
| `lab_result` | observations, laboratory only | LOINC, mapped as the resulted component |
| `immunization` | immunizations | CVX |
| `location` | organizations | 1,116 of 1,144 NPIs exist in Tuva's NPI registry extract |
| `practitioner` | providers | Synthetic NPIs; one provider per organization |
| `appointment` | none | Empty by design; Synthea has no scheduling data |

Allergies, care plans, devices, supplies and imaging studies have no Tuva input table and are not mapped.

**Build results (2026-11-23), dbt 2.0.12 on a SMALL warehouse:**

- Staging and input layer: 20 models and 95 tests, all passing, in about 40 seconds.
- Tuva Core: 39 models and 58 data tests, all passing, in about 40 seconds. Tuva validated its Snowflake release on dbt Core 1.11, not on dbt 2.0, so this combination is this project's own result.
- Every Core table has exactly the row count of its input model, and the input models add up to the RAW_2026 tables they read.

| `TUVA_CORE` table | Rows | Standardized by Tuva |
|---|---|---|
| `patient` | 11,500 | Age and age group on every row |
| `encounter` | 1,894,556 | Encounter group and length of stay on every row |
| `condition` | 1,126,394 | SNOMED CT description on 100%; Tuva condition family on 63.4% |
| `procedure` | 5,797,021 | SNOMED CT description on 100%; procedure family on 0% |
| `medication` | 1,104,084 | RxNorm description on 97.8%; ATC drug class on 95.8% |
| `observation` | 14,936,192 | Standard code on 90.1% |
| `lab_result` | 7,924,196 | LOINC component on 100% |
| `immunization` | 618,211 | CVX on 100% |
| `location` | 1,144 | |
| `practitioner` | 1,144 | |
| `appointment` | 0 | Empty by design |

Three gaps in that table are expected. Tuva's procedure grouper covers ICD-10-PCS and HCPCS, so SNOMED CT procedures get no family. The conditions without a family are mostly social findings such as employment status. The observations without a standard code are Synthea's own quality-of-life scores.

**Tuva data quality:** the framework is off by default. To run it against the input layer:

```bash
dbt build --select tag:dq_structural tag:dq_logical --vars '{"data_quality_enabled": true}' --exclude resource_type:unit_test
```

Results land in `TUVA_DATA_QUALITY`. On 2026-11-23:

- **Structural:** all 11 input tables have every contract column and a correct primary key. `appointment` fails "table populated", by design.
- **Structural, false positive:** three integer columns (`patient.death_flag`, `condition.condition_rank`, `appointment.duration`) are reported as a type mismatch. They are `NUMBER(38,0)` in Snowflake, which is its integer type; the check sees only `NUMBER`.
- **Logical:** 143 checks ran and 11 reported failures, none of them a mapping defect:
  - Seven date checks flag anything before 2000-01-01, which is 30% to 43% of rows, because the data keeps full patient history back to 1915.
  - Three NPI checks flag the synthetic NPIs: all 1,144 practitioners, 28 locations, and the 6.5% of encounters at those locations.
  - One check flags the missing lab accession number, which Synthea does not have.
- **Package self-test:** one of Tuva's own tests, `check_logical_native_date_coverage`, fails in this clinical-only configuration. It tests Tuva's check catalog, not this project's data, and its cause was not investigated.

**Sources:** `synthea_raw` is the 2017 extract in `RAW`; `synthea_2026_raw` is the current-version dataset in `RAW_2026`, with 18 tables and 35 tests. Its relationship tests are hard failures, because the source files have no orphan keys. `dbt test -s "source:synthea_2026_raw"` passes all 35.

**Source tests:** `dbt test -s "source:synthea_raw"` passes, with one expected warning. The encounters → patients relationship test warns on the 38,391 encounters that belong to quarantined patients, and errors only above that count.

## RAW load results (2026-11-23)

| Table | Rows |
|---|---|
| OBSERVATIONS | 64,654,706 |
| ENCOUNTERS | 15,109,427 |
| IMMUNIZATIONS | 10,412,118 |
| CAREPLANS | 9,558,659 |
| PROCEDURES | 7,502,018 |
| CONDITIONS | 5,809,954 |
| MEDICATIONS | 4,781,956 |
| PATIENTS | 1,590,897 |
| ALLERGIES | 624,611 |
| PATIENTS_REJECTS | 4,153 |

Every table has 12 files. Each table's row count matches a profile of the source files taken before loading, row for row. Patient and encounter IDs have no nulls and no duplicates.

### Source defect in `patients.csv` (quarantined at ingest)

In the 2017 SyntheticMass patients files, some records were spliced together when the files were generated. Some lines hold two patients merged into one 33-field line. Others are fragments left over from those merges.

- **Scale:** 4,153 of 1.59 M lines are malformed (0.26%). The other 8 tables have no malformed rows.
- **Why Snowflake can't catch it:** matching columns by name needs `ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE`, and positional `COPY` ignores the column-count check. Either way, the bad rows load silently.
- **How it's handled:** `aws/quarantine_patients.py` keeps a line only if it has exactly the header's field count, copying it byte-for-byte. Every other line goes to `RAW.PATIENTS_REJECTS` with its file name, line number and field count. The original files are kept at `s3://…/synthea-v2/original/patients/`, outside the stage.
- **Effect downstream:** 3,694 patients (0.23%) exist only in rejected lines, so their encounters and other events have no patient row. Check 5 in `04` confirms that every orphan patient ID appears in a rejected line, with 0 unexplained. dbt relationship tests on `patient` should therefore use a documented warning threshold, not a hard failure.

## Current-version dataset (`RAW_2026`)

**Why it exists:** the 2017 archive has no usable provider, organization, payer, claims or cost data in any of its three formats. The CSV has 9 clinical tables. The FHIR bundles hold one placeholder organization per patient ("Synthetic Provider", no address or identifier) and no practitioners or claims. Current Synthea exports all of these, as 18 CSV tables.

### Runbook

Steps 8 and 9 default to a dry run. Each step is safe to re-run.

| # | Where | File | Runs as | What it does |
|---|-------|------|---------|--------------|
| 8 | Mac | `aws/mac_generate_and_upload_2026.sh` | your IAM user | Generates the population, gzips each CSV part, prints an inventory, uploads one prefix per table (`UPLOAD=1`) |
| 8b | Mac | `aws/profile_synthea_2026.py` | — | Proves every source row has the header's field count, prints row counts, checks keys |
| 9 | Mac | `aws/mac_add_prefix_to_iam_policy.sh` | your IAM user | Adds `synthea-2026/csv/` to the read-only IAM policy (`APPLY=1`) |
| 10 | Snowflake | `snowflake/05_raw_2026_landing.sql` | SYSADMIN, SECURITYADMIN, ACCOUNTADMIN, SYNTHEA_INGEST_ROLE | Schema, grants, widened storage integration, stage, load procedure, loads |
| 11 | Snowflake | `snowflake/06_raw_2026_verification.sql` | SYNTHEA_INGEST_ROLE | Row counts, staged files against loaded files, keys, relationships |

```bash
./aws/mac_generate_and_upload_2026.sh                             # generate, gzip, inventory
BUCKET=<bucket> ./aws/mac_generate_and_upload_2026.sh             # plus an upload dry run
BUCKET=<bucket> UPLOAD=1 ./aws/mac_generate_and_upload_2026.sh    # real upload
python3 aws/profile_synthea_2026.py                               # pre-load profile
BUCKET=<bucket> ./aws/mac_add_prefix_to_iam_policy.sh             # show the IAM change
BUCKET=<bucket> APPLY=1 ./aws/mac_add_prefix_to_iam_policy.sh     # publish it
```

### How the data was generated

- **Generator:** `synthea-with-dependencies.jar`, the `master-branch-latest` build published 2026-11-20 (commit `5441eef`, sha256 `1584dd9d4f8a393d64c6a5bcc8058bf075c38b2ae34676daf3b60977a092eddb`). The tagged v4.0.0 release was not used because it writes no NPI column on organizations or providers.
- **Java:** OpenJDK 17 (`brew install openjdk@17`). Synthea asks for an LTS release, 17 or 25.
- **Settings:** 10,000 living patients, Massachusetts, seed and reference date `20261123`, CSV only, parts of 1,000,000 lines. `exporter.years_of_history=0` keeps the full record; the default of 10 drops anything older than ten years.
- **Result:** 11,500 patients (10,000 living and 1,500 deceased), 22 GB of CSV in 83 parts, generated in under 4 minutes.

### S3 layout

```
s3://<bucket>/synthea-2026/csv/
    patients/             patients__part_001.csv.gz
    claims_transactions/  claims_transactions__part_001.csv.gz ... __part_034.csv.gz
    ...
```

The storage integration and the IAM policy each allow both prefixes, `synthea-v2/csv/` and `synthea-2026/csv/`, and nothing else. The integration is widened with `ALTER`, which keeps its external ID.

### RAW_2026 load results (2026-11-23)

| Table | Rows |
|---|---|
| CLAIMS_TRANSACTIONS | 33,015,078 |
| OBSERVATIONS | 22,860,388 |
| PROCEDURES | 5,797,021 |
| CLAIMS | 2,998,640 |
| ENCOUNTERS | 1,894,556 |
| IMAGING_STUDIES | 1,282,041 |
| CONDITIONS | 1,126,394 |
| MEDICATIONS | 1,104,084 |
| SUPPLIES | 829,208 |
| IMMUNIZATIONS | 618,211 |
| PAYER_TRANSITIONS | 492,824 |
| DEVICES | 184,522 |
| CAREPLANS | 101,948 |
| PATIENTS | 11,500 |
| ALLERGIES | 10,758 |
| ORGANIZATIONS | 1,144 |
| PROVIDERS | 1,144 |
| PAYERS | 10 |

72,329,471 rows in all, from 83 files, about 2 GB stored in Snowflake.

- **Before loading:** `aws/profile_synthea_2026.py` counted the same rows in the source files and found no row with a wrong field count, no duplicate or empty ID in the six entity tables, and no foreign key without a parent row.
- **After loading:** every table's row count matches that profile exactly, and all 83 staged files are present. Step 11 found no duplicate or null key and no orphan row in any of its nine relationship checks, including claims transactions → claims.

### What it adds, and its limits

- **Encounters** carry organization, provider, payer, one of 10 encounter classes, start and stop timestamps, and cost columns on every row.
- **Organizations (1,144)** have name, address and NPI. 1,116 NPIs start with 1 and 28 are in a synthetic 8888 range; none were checked against the national registry.
- **Providers (1,144)** are exactly one per organization, all with speciality GENERAL PRACTICE and a synthetic 9999 NPI. Provider-level analysis is in effect facility-level.
- **Payers (10)** and **payer transitions** give yearly coverage spans with member IDs.
- **Claims** link to every encounter, but their diagnosis and procedure codes are SNOMED CT or LOINC. There are no bill type, revenue, DRG or CMS place of service codes.

## Troubleshooting `LIST @stage`

| Error | Likely cause |
|-------|--------------|
| `Access Denied` / `not authorized to perform sts:AssumeRole` | Phase B has not run, or the external ID doesn't match. Running `CREATE OR REPLACE INTEGRATION` creates a new external ID, so after that you must re-run Phase B. IAM changes can take about 1 minute to take effect. |
| `location … is not allowed by integration` | The stage URL is outside `STORAGE_ALLOWED_LOCATIONS`. Check that it ends with `/`. |
| `LIST` returns nothing, but no error | The objects were uploaded under a different prefix. Check with `aws s3 ls s3://<bucket>/ --recursive \| Select -First 20`. |
| `INFER_SCHEMA` / `USING TEMPLATE` fails for a table | The S3 folder for that table is empty or has a different name. |
