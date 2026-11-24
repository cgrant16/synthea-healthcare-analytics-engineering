/* =============================================================================
   04_load_verification.sql   (SYNTHEA_INGEST_ROLE or SYNTHEA_DEVELOPER_ROLE)
   Author: Cortwright Grant

   Quick "did RAW load completely and sanely?" checks. These are deliberately
   light: the real data-quality contract will be dbt tests on staging models.
   ============================================================================= */

USE ROLE      SYNTHEA_INGEST_ROLE;
USE WAREHOUSE SYNTHEA_INGEST_WH;
USE SCHEMA    SYNTHEA.RAW;          -- temp table below needs a current schema

-- 1. Every RAW table and its row count
SELECT table_name, row_count, ROUND(bytes / POWER(1024, 3), 2) AS size_gb, created
FROM   SYNTHEA.INFORMATION_SCHEMA.TABLES
WHERE  table_schema = 'RAW'
ORDER  BY table_name;

-- 2. Per-file load results for one table (no latency; repeat per table).
--    Every file should be 'Loaded' with row_parsed = row_count.
SELECT file_name, status, row_parsed, row_count, first_error_message, last_load_time
FROM   TABLE(SYNTHEA.INFORMATION_SCHEMA.COPY_HISTORY(
           TABLE_NAME => 'SYNTHEA.RAW.PATIENTS',
           START_TIME => DATEADD(day, -7, CURRENT_TIMESTAMP())));

-- 3. Completeness: files in S3 vs. distinct files actually present in each table
--    (uses the _SOURCE_FILE audit column). files_staged should = files_loaded.
LIST @SYNTHEA.RAW.SYNTHEA_S3_STAGE;
CREATE OR REPLACE TEMPORARY TABLE _staged_files AS
SELECT UPPER(SPLIT_PART("name", '/', -2)) AS table_name, COUNT(*) AS files_staged
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP  BY 1;

WITH loaded AS (
              SELECT 'PATIENTS'      AS table_name, COUNT(DISTINCT _source_file) AS files_loaded FROM SYNTHEA.RAW.PATIENTS
    UNION ALL SELECT 'ALLERGIES',     COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.ALLERGIES
    UNION ALL SELECT 'CAREPLANS',     COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.CAREPLANS
    UNION ALL SELECT 'IMMUNIZATIONS', COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.IMMUNIZATIONS
    UNION ALL SELECT 'CONDITIONS',    COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.CONDITIONS
    UNION ALL SELECT 'MEDICATIONS',   COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.MEDICATIONS
    UNION ALL SELECT 'PROCEDURES',    COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.PROCEDURES
    UNION ALL SELECT 'ENCOUNTERS',    COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.ENCOUNTERS
    UNION ALL SELECT 'OBSERVATIONS',  COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.OBSERVATIONS
    UNION ALL SELECT 'PATIENTS_REJECTS', COUNT(DISTINCT _source_file) FROM SYNTHEA.RAW.PATIENTS_REJECTS
)
SELECT s.table_name, s.files_staged, l.files_loaded,
       IFF(s.files_staged = l.files_loaded, 'OK', 'MISMATCH') AS check_result
FROM   _staged_files s
LEFT   JOIN loaded l USING (table_name)
ORDER  BY 1;

-- 4. Shape checks on the core entities
--    Primary keys are UUIDs: expect 0 nulls and 0 duplicates.
SELECT 'patients'   AS tbl, COUNT(*) AS row_count, COUNT(DISTINCT id) AS distinct_ids,
       COUNT_IF(id IS NULL) AS null_ids
FROM   SYNTHEA.RAW.PATIENTS
UNION ALL
SELECT 'encounters', COUNT(*), COUNT(DISTINCT id), COUNT_IF(id IS NULL)
FROM   SYNTHEA.RAW.ENCOUNTERS;

-- 5. Referential check: encounters pointing at a patient missing from PATIENTS.
--    NOT 0 for this dataset: 3,694 patients exist only inside spliced lines that
--    were quarantined to PATIENTS_REJECTS (see aws/quarantine_patients.py).
--    PASS = every orphan patient ID is found somewhere in a rejected line
--    (orphans_not_explained_by_quarantine = 0). Verified 2026-11-23: 3,694 / 0.
WITH orphans AS (
    SELECT DISTINCT e.patient
    FROM   SYNTHEA.RAW.ENCOUNTERS e
    LEFT   JOIN SYNTHEA.RAW.PATIENTS p ON p.id = e.patient
    WHERE  p.id IS NULL
),
reject_ids AS (
    SELECT DISTINCT f.value::STRING AS id
    FROM   SYNTHEA.RAW.PATIENTS_REJECTS r,
           LATERAL FLATTEN(REGEXP_SUBSTR_ALL(r.raw_line,
               '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')) f
)
SELECT COUNT(*)               AS orphan_patients,
       COUNT_IF(r.id IS NULL) AS orphans_not_explained_by_quarantine
FROM   orphans o
LEFT   JOIN reject_ids r ON r.id = o.patient;

-- 6. Lineage columns populated on every row (expect 0)
SELECT COUNT_IF(_source_file IS NULL OR _loaded_at IS NULL) AS rows_missing_audit_cols
FROM   SYNTHEA.RAW.PATIENTS;

-- 7. Can dbt actually read RAW? (dbt's role, read-only)
USE ROLE      SYNTHEA_DBT_ROLE;
USE WAREHOUSE SYNTHEA_TRANSFORM_WH;   -- dbt's role has no rights on the ingest WH
SELECT COUNT(*) FROM SYNTHEA.RAW.PATIENTS;
