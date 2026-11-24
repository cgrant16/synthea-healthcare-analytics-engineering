# Synthea Healthcare Analytics Engineering Project

**Author:** Cortwright Grant

SyntheticMass v2 (2017) CSV → **Amazon S3** → **Snowflake RAW** → dbt Core (later).
Full background: [docs/project-context.md](docs/project-context.md).

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

## dbt Core project (`synthea_analytics/`)

**Stack:** dbt Core 1.12.7 with dbt-snowflake 1.12.5, on Python 3.12, in a project virtual environment at `.venv/`.

dbt's "v2" is the Rust-based Fusion engine, a standalone binary. It is not the Python `dbt-core` package, whose 2.0 exists only as release candidates. This project targets dbt Core 1.12 and is kept free of deprecations so it can move to v2 without changes.

**One-time setup:**
```bash
python3.12 -m venv .venv && .venv/bin/pip install -r synthea_analytics/requirements.txt
cp synthea_analytics/profiles.yml.example ~/.dbt/profiles.yml   # or append its `synthea:` block, then fill in <PLACEHOLDERS>
```

**Authentication:** dbt connects as `SYNTHEA_DBT_USER`, a `TYPE = SERVICE` user that can't use a password, with role `SYNTHEA_DBT_ROLE` and warehouse `SYNTHEA_TRANSFORM_WH`. It authenticates with an RSA key pair. To set one up:
```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/keys/synthea_dbt_user.p8 -nocrypt
openssl rsa -in ~/.snowflake/keys/synthea_dbt_user.p8 -pubout -out ~/.snowflake/keys/synthea_dbt_user.pub
```
Then run this in Snowflake as SECURITYADMIN, pasting in the body of the `.pub` file without its BEGIN/END lines: `ALTER USER SYNTHEA_DBT_USER SET RSA_PUBLIC_KEY = '<key body>';`

**Daily use:** activate the virtual environment first. If another `dbt` is installed (for example dbt Fusion in `~/.local/bin`), it would otherwise be the one that runs.
```bash
source .venv/bin/activate && cd synthea_analytics
dbt debug            # connection check
dbt test -s "source:*"
```

**Layers:**

| Layer | Schema | Materialized as |
|---|---|---|
| `staging/` | `STAGING` | views |
| `intermediate/` | `INTERMEDIATE` | views |
| `marts/` | `MARTS` | tables |

`macros/generate_schema_name.sql` builds into those schemas exactly as named, because the dbt role can't create schemas.

**Source tests:** `dbt test -s "source:*"` passes, with one expected warning. The encounters → patients relationship test warns on the 38,391 encounters that belong to quarantined patients, and errors only above that count.

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

## Troubleshooting `LIST @stage`

| Error | Likely cause |
|-------|--------------|
| `Access Denied` / `not authorized to perform sts:AssumeRole` | Phase B has not run, or the external ID doesn't match. Running `CREATE OR REPLACE INTEGRATION` creates a new external ID, so after that you must re-run Phase B. IAM changes can take about 1 minute to take effect. |
| `location … is not allowed by integration` | The stage URL is outside `STORAGE_ALLOWED_LOCATIONS`. Check that it ends with `/`. |
| `LIST` returns nothing, but no error | The objects were uploaded under a different prefix. Check with `aws s3 ls s3://<bucket>/ --recursive \| Select -First 20`. |
| `INFER_SCHEMA` / `USING TEMPLATE` fails for a table | The S3 folder for that table is empty or has a different name. |
