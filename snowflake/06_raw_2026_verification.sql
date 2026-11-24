/* =============================================================================
   06_raw_2026_verification.sql   (SYNTHEA_INGEST_ROLE or SYNTHEA_DEVELOPER_ROLE)
   Author: Cortwright Grant

   "Did RAW_2026 load completely and sanely?" - the same checks as
   04_load_verification.sql, plus the keys this dataset adds (organizations,
   providers, payers, claims).

   Unlike the 2017 extract, every referential check here should return 0:
   the generator writes all tables in one run, so no patient is missing.
   ============================================================================= */

USE ROLE      SYNTHEA_INGEST_ROLE;
USE WAREHOUSE SYNTHEA_INGEST_WH;
USE SCHEMA    SYNTHEA.RAW_2026;          -- temp table below needs a current schema

-- 1. Every RAW_2026 table and its row count.
--    Compare with the "data lines" column printed by
--    aws/mac_generate_and_upload_2026.sh (or aws/profile_synthea_2026.py).
SELECT table_name, row_count, ROUND(bytes / POWER(1024, 3), 2) AS size_gb, created
FROM   SYNTHEA.INFORMATION_SCHEMA.TABLES
WHERE  table_schema = 'RAW_2026'
ORDER  BY table_name;

-- 2. Per-file load results for the largest table (repeat per table as needed).
--    Every file should be 'Loaded' with row_parsed = row_count.
SELECT file_name, status, row_parsed, row_count, first_error_message, last_load_time
FROM   TABLE(SYNTHEA.INFORMATION_SCHEMA.COPY_HISTORY(
           TABLE_NAME => 'SYNTHEA.RAW_2026.CLAIMS_TRANSACTIONS',
           START_TIME => DATEADD(day, -7, CURRENT_TIMESTAMP())))
ORDER  BY file_name;

-- 3. Completeness: files in S3 vs. distinct files present in each table.
LIST @SYNTHEA.RAW_2026.SYNTHEA_2026_S3_STAGE;
CREATE OR REPLACE TEMPORARY TABLE _staged_files AS
SELECT UPPER(SPLIT_PART("name", '/', -2)) AS table_name, COUNT(*) AS files_staged
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP  BY 1;

WITH loaded AS (
              SELECT 'ALLERGIES' AS table_name, COUNT(DISTINCT _source_file) AS files_loaded FROM SYNTHEA.RAW_2026.ALLERGIES
    UNION ALL SELECT 'CAREPLANS',           COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.CAREPLANS
    UNION ALL SELECT 'CLAIMS',              COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.CLAIMS
    UNION ALL SELECT 'CLAIMS_TRANSACTIONS', COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.CLAIMS_TRANSACTIONS
    UNION ALL SELECT 'CONDITIONS',          COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.CONDITIONS
    UNION ALL SELECT 'DEVICES',             COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.DEVICES
    UNION ALL SELECT 'ENCOUNTERS',          COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.ENCOUNTERS
    UNION ALL SELECT 'IMAGING_STUDIES',     COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.IMAGING_STUDIES
    UNION ALL SELECT 'IMMUNIZATIONS',       COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.IMMUNIZATIONS
    UNION ALL SELECT 'MEDICATIONS',         COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.MEDICATIONS
    UNION ALL SELECT 'OBSERVATIONS',        COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.OBSERVATIONS
    UNION ALL SELECT 'ORGANIZATIONS',       COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.ORGANIZATIONS
    UNION ALL SELECT 'PATIENTS',            COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.PATIENTS
    UNION ALL SELECT 'PAYER_TRANSITIONS',   COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.PAYER_TRANSITIONS
    UNION ALL SELECT 'PAYERS',              COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.PAYERS
    UNION ALL SELECT 'PROCEDURES',          COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.PROCEDURES
    UNION ALL SELECT 'PROVIDERS',           COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.PROVIDERS
    UNION ALL SELECT 'SUPPLIES',            COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW_2026.SUPPLIES
)
SELECT s.table_name, s.files_staged, l.files_loaded,
       IFF(s.files_staged = l.files_loaded, 'OK', 'MISMATCH') AS check_result
FROM   _staged_files s
LEFT   JOIN loaded l USING (table_name)
ORDER  BY 1;

-- 4. Primary keys: expect row_count = distinct_ids and null_ids = 0 on every line.
SELECT 'patients' AS tbl, COUNT(*) AS row_count, COUNT(DISTINCT id) AS distinct_ids, COUNT_IF(id IS NULL) AS null_ids
FROM   SYNTHEA.RAW_2026.PATIENTS
UNION ALL SELECT 'organizations', COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL) FROM SYNTHEA.RAW_2026.ORGANIZATIONS
UNION ALL SELECT 'providers',     COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL) FROM SYNTHEA.RAW_2026.PROVIDERS
UNION ALL SELECT 'payers',        COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL) FROM SYNTHEA.RAW_2026.PAYERS
UNION ALL SELECT 'encounters',    COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL) FROM SYNTHEA.RAW_2026.ENCOUNTERS
UNION ALL SELECT 'claims',        COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL) FROM SYNTHEA.RAW_2026.CLAIMS;

-- 5. Referential checks: every count should be 0.
SELECT 'encounters -> patients' AS relationship, COUNT(*) AS orphan_rows
FROM   SYNTHEA.RAW_2026.ENCOUNTERS e LEFT JOIN SYNTHEA.RAW_2026.PATIENTS p ON p.id = e.patient
WHERE  p.id IS NULL
UNION ALL
SELECT 'encounters -> organizations', COUNT(*)
FROM   SYNTHEA.RAW_2026.ENCOUNTERS e LEFT JOIN SYNTHEA.RAW_2026.ORGANIZATIONS o ON o.id = e.organization
WHERE  o.id IS NULL
UNION ALL
SELECT 'encounters -> providers', COUNT(*)
FROM   SYNTHEA.RAW_2026.ENCOUNTERS e LEFT JOIN SYNTHEA.RAW_2026.PROVIDERS pr ON pr.id = e.provider
WHERE  pr.id IS NULL
UNION ALL
SELECT 'encounters -> payers', COUNT(*)
FROM   SYNTHEA.RAW_2026.ENCOUNTERS e LEFT JOIN SYNTHEA.RAW_2026.PAYERS py ON py.id = e.payer
WHERE  py.id IS NULL
UNION ALL
SELECT 'providers -> organizations', COUNT(*)
FROM   SYNTHEA.RAW_2026.PROVIDERS pr LEFT JOIN SYNTHEA.RAW_2026.ORGANIZATIONS o ON o.id = pr.organization
WHERE  o.id IS NULL
UNION ALL
SELECT 'payer_transitions -> patients', COUNT(*)
FROM   SYNTHEA.RAW_2026.PAYER_TRANSITIONS t LEFT JOIN SYNTHEA.RAW_2026.PATIENTS p ON p.id = t.patient
WHERE  p.id IS NULL
UNION ALL
SELECT 'payer_transitions -> payers', COUNT(*)
FROM   SYNTHEA.RAW_2026.PAYER_TRANSITIONS t LEFT JOIN SYNTHEA.RAW_2026.PAYERS py ON py.id = t.payer
WHERE  py.id IS NULL
UNION ALL
SELECT 'claims -> encounters', COUNT(*)
FROM   SYNTHEA.RAW_2026.CLAIMS c LEFT JOIN SYNTHEA.RAW_2026.ENCOUNTERS e ON e.id = c.appointmentid
WHERE  e.id IS NULL
UNION ALL
SELECT 'claims_transactions -> claims', COUNT(*)
FROM   SYNTHEA.RAW_2026.CLAIMS_TRANSACTIONS t LEFT JOIN SYNTHEA.RAW_2026.CLAIMS c ON c.id = t.claimid
WHERE  c.id IS NULL;

-- 6. Lineage columns populated on every row (expect 0)
SELECT COUNT_IF(_source_file IS NULL OR _loaded_at IS NULL) AS rows_missing_audit_cols
FROM   SYNTHEA.RAW_2026.ENCOUNTERS;

-- 7. Can dbt actually read RAW_2026? (dbt's role, read-only)
USE ROLE      SYNTHEA_DBT_ROLE;
USE WAREHOUSE SYNTHEA_TRANSFORM_WH;   -- dbt's role has no rights on the ingest WH
SELECT COUNT(*) FROM SYNTHEA.RAW_2026.PATIENTS;
