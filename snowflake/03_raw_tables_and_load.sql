/* =============================================================================
   03_raw_tables_and_load.sql   (run as SYNTHEA_INGEST_ROLE)
   Author: Cortwright Grant

   Loads every S3 table folder into SYNTHEA.RAW.<TABLE>.

   Design choices (RAW = faithful landing zone; all logic lives in dbt):
     * Columns come from the CSV header (INFER_SCHEMA), not hand-typed DDL, so
       the 2017 schema is captured exactly - no guessing vs. today's dictionary.
     * Every source column is VARCHAR. A malformed date can never fail a load;
       typing/casting is dbt staging's job, where it is tested and documented.
     * Three audit columns per row: _SOURCE_FILE, _SOURCE_ROW, _LOADED_AT.
     * COPY keeps 64 days of per-file load metadata, so re-running a load only
       picks up NEW files - re-runs are safe and never duplicate rows.
   ============================================================================= */

USE ROLE      SYNTHEA_INGEST_ROLE;
USE WAREHOUSE SYNTHEA_INGEST_WH;     -- X-SMALL is plenty; bigger only if a load is slow
USE SCHEMA    SYNTHEA.RAW;

-- -----------------------------------------------------------------------------
-- 1. The pattern, written out once for PATIENTS (read this; the procedure below
--    runs exactly these three statements for each table)
-- -----------------------------------------------------------------------------

-- 1a. Create the table from the header, forcing every column to VARCHAR.
CREATE TABLE IF NOT EXISTS SYNTHEA.RAW.PATIENTS
USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
               'COLUMN_NAME', UPPER(column_name),
               'TYPE',        'VARCHAR',
               'NULLABLE',    TRUE))
           WITHIN GROUP (ORDER BY order_id)
    FROM TABLE(INFER_SCHEMA(
             LOCATION             => '@SYNTHEA.RAW.SYNTHEA_S3_STAGE/patients/',
             FILE_FORMAT          => 'SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT',
             MAX_FILE_COUNT       => 1,      -- header is all we need
             MAX_RECORDS_PER_FILE => 100))
);

-- 1b. Audit columns (populated by INCLUDE_METADATA in the COPY).
ALTER TABLE SYNTHEA.RAW.PATIENTS ADD COLUMN IF NOT EXISTS _SOURCE_FILE VARCHAR;
ALTER TABLE SYNTHEA.RAW.PATIENTS ADD COLUMN IF NOT EXISTS _SOURCE_ROW  NUMBER;
ALTER TABLE SYNTHEA.RAW.PATIENTS ADD COLUMN IF NOT EXISTS _LOADED_AT   TIMESTAMP_LTZ;

-- 1c. Load by column NAME, all files in the folder, fail loudly on bad rows.
COPY INTO SYNTHEA.RAW.PATIENTS
FROM @SYNTHEA.RAW.SYNTHEA_S3_STAGE/patients/
FILE_FORMAT          = (FORMAT_NAME = 'SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA     = (
    _SOURCE_FILE = METADATA$FILENAME,
    _SOURCE_ROW  = METADATA$FILE_ROW_NUMBER,
    _LOADED_AT   = METADATA$START_SCAN_TIME)
ON_ERROR             = ABORT_STATEMENT;   -- RAW should be complete or not loaded

SELECT COUNT(*) AS patients_rows FROM SYNTHEA.RAW.PATIENTS;


-- -----------------------------------------------------------------------------
-- 2. Reusable procedure: the same three steps for any table folder
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SYNTHEA.RAW.LOAD_RAW_TABLE(SOURCE_NAME VARCHAR)
RETURNS TABLE()
LANGUAGE SQL
COMMENT = 'Create RAW.<SOURCE_NAME> from its CSV header (all VARCHAR) and COPY new files from the stage folder'
EXECUTE AS OWNER
AS
$$
DECLARE
    tbl        VARCHAR;
    stage_path VARCHAR;
    stmt       VARCHAR;
    copy_result RESULTSET;
    bad_name   EXCEPTION (-20001, 'SOURCE_NAME must be lowercase letters/underscores, e.g. ''patients''');
BEGIN
    -- Guard against SQL injection: the name is concatenated into DDL below.
    IF (NOT REGEXP_LIKE(source_name, '^[a-z_]+$')) THEN
        RAISE bad_name;
    END IF;

    tbl        := 'SYNTHEA.RAW.' || UPPER(source_name);
    stage_path := '@SYNTHEA.RAW.SYNTHEA_S3_STAGE/' || source_name || '/';

    -- 1a. Table from header (fails here if the S3 folder is empty / misnamed)
    stmt := 'CREATE TABLE IF NOT EXISTS ' || tbl || ' USING TEMPLATE (
                SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                           ''COLUMN_NAME'', UPPER(column_name),
                           ''TYPE'',        ''VARCHAR'',
                           ''NULLABLE'',    TRUE))
                       WITHIN GROUP (ORDER BY order_id)
                FROM TABLE(INFER_SCHEMA(
                         LOCATION             => ''' || stage_path || ''',
                         FILE_FORMAT          => ''SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT'',
                         MAX_FILE_COUNT       => 1,
                         MAX_RECORDS_PER_FILE => 100)))';
    EXECUTE IMMEDIATE :stmt;

    -- 1b. Audit columns
    stmt := 'ALTER TABLE ' || tbl || ' ADD COLUMN IF NOT EXISTS _SOURCE_FILE VARCHAR';
    EXECUTE IMMEDIATE :stmt;
    stmt := 'ALTER TABLE ' || tbl || ' ADD COLUMN IF NOT EXISTS _SOURCE_ROW NUMBER';
    EXECUTE IMMEDIATE :stmt;
    stmt := 'ALTER TABLE ' || tbl || ' ADD COLUMN IF NOT EXISTS _LOADED_AT TIMESTAMP_LTZ';
    EXECUTE IMMEDIATE :stmt;

    -- 1c. Load
    stmt := 'COPY INTO ' || tbl || '
             FROM ' || stage_path || '
             FILE_FORMAT          = (FORMAT_NAME = ''SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT'')
             MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
             INCLUDE_METADATA     = (
                 _SOURCE_FILE = METADATA$FILENAME,
                 _SOURCE_ROW  = METADATA$FILE_ROW_NUMBER,
                 _LOADED_AT   = METADATA$START_SCAN_TIME)
             ON_ERROR             = ABORT_STATEMENT';
    copy_result := (EXECUTE IMMEDIATE :stmt);

    -- One row per file: status, rows_parsed, rows_loaded, first_error...
    RETURN TABLE(copy_result);
END;
$$;


-- -----------------------------------------------------------------------------
-- 3. Load the remaining tables
--    Match this list to the folders from 02 step 3b (drop or add as needed:
--    organizations/providers may not exist in the 2017 extract).
--    Load the small tables first so any file-format surprise shows up fast.
--    PATIENTS is safe to call again: already-loaded files are skipped.
-- -----------------------------------------------------------------------------
-- PATIENTS: the source has 4,153 spliced/fragment lines. Run
-- aws/quarantine_patients.py first; it replaces patients/ in S3 with clean
-- rows (originals kept at s3://<bucket>/synthea-v2/original/patients/) and
-- writes the bad lines to patients_rejects/. Then:
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('patients');           -- 1,590,897 rows
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('patients_rejects');   --     4,153 rows (audit)
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('allergies');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('careplans');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('immunizations');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('conditions');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('medications');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('procedures');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('encounters');
CALL SYNTHEA.RAW.LOAD_RAW_TABLE('observations');     -- by far the largest
-- organizations / providers do not exist in the 2017 extract.

/* If a COPY aborts: the error message names the file and line. Right after the
   failure, list every rejected row from that attempt with:
       SELECT * FROM TABLE(VALIDATE(SYNTHEA.RAW.<TABLE>, JOB_ID => '_last'));
   Fix the cause (usually a file-format option), then simply CALL again.
   Never add FORCE = TRUE to "retry": it reloads files and duplicates rows. */
