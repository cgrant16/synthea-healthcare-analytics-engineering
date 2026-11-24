/* =============================================================================
   02_stage_and_file_format.sql   (run as SYNTHEA_INGEST_ROLE)
   Author: Cortwright Grant

   Prereq: 01 has run AND the IAM trust policy was finalized (Phase B).
   Find/replace before running:  <BUCKET>
   ============================================================================= */

USE ROLE      SYNTHEA_INGEST_ROLE;
USE WAREHOUSE SYNTHEA_INGEST_WH;
USE SCHEMA    SYNTHEA.RAW;

-- -----------------------------------------------------------------------------
-- 0. Positional CSV format (planned in the context doc but not created by the
--    RBAC script). Used only for ad-hoc `SELECT $1, $2 FROM @stage` peeks.
-- -----------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS SYNTHEA.RAW.SYNTHEA_CSV_FORMAT
    TYPE                         = CSV
    SKIP_HEADER                  = 1
    FIELD_DELIMITER              = ','
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    EMPTY_FIELD_AS_NULL          = TRUE
    NULL_IF                      = ('')
    SKIP_BLANK_LINES             = TRUE
    ENCODING                     = 'UTF8'
    COMMENT                      = 'Synthea CSV, positional (skip header) - for stage peeks';

-- -----------------------------------------------------------------------------
-- 1. Header-aware CSV file format for loading
--
--    SYNTHEA_CSV_FORMAT above uses SKIP_HEADER = 1, which reads by
--    column POSITION. This one uses PARSE_HEADER = TRUE so that:
--      * INFER_SCHEMA can read column names straight from the CSV header, and
--      * COPY ... MATCH_BY_COLUMN_NAME loads by NAME (robust if the 2017 files
--        differ in column order from the current Synthea data dictionary).
--    PARSE_HEADER and SKIP_HEADER are mutually exclusive, hence a 2nd format.
--    Keep SYNTHEA_CSV_FORMAT for ad-hoc `SELECT $1, $2 FROM @stage` peeks.
-- -----------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT
    TYPE                         = CSV
    PARSE_HEADER                 = TRUE      -- first line = column names
    FIELD_DELIMITER              = ','
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'       -- descriptions contain commas
    EMPTY_FIELD_AS_NULL          = TRUE
    NULL_IF                      = ('')
    TRIM_SPACE                   = FALSE     -- RAW keeps values exactly as delivered
    SKIP_BLANK_LINES             = TRUE
    ENCODING                     = 'UTF8'
    -- Must be FALSE: with MATCH_BY_COLUMN_NAME, Snowflake counts the 3 audit
    -- columns (_SOURCE_FILE/_SOURCE_ROW/_LOADED_AT) against the file's fields.
    -- Field-count integrity is instead proven by row-count reconciliation in 04.
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    COMMENT                      = 'Synthea CSV, header parsed for INFER_SCHEMA + MATCH_BY_COLUMN_NAME';

-- -----------------------------------------------------------------------------
-- 2. External stage over the landing prefix
--    Owned by the ingest role; dbt never touches the stage, only RAW tables.
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS SYNTHEA.RAW.SYNTHEA_S3_STAGE
    STORAGE_INTEGRATION = SYNTHEA_S3_INT
    URL                 = 's3://<BUCKET>/synthea-v2/csv/'
    FILE_FORMAT         = SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT
    COMMENT             = 'SyntheticMass v2 (2017) CSV landing zone; one sub-folder per table';

-- -----------------------------------------------------------------------------
-- 3. Verification
-- -----------------------------------------------------------------------------

-- 3a. Can Snowflake see the files at all?  (Access Denied -> see README troubleshooting)
LIST @SYNTHEA.RAW.SYNTHEA_S3_STAGE;

-- 3b. Per-table summary of what LIST just returned
--     "name" looks like s3://<bucket>/synthea-v2/csv/patients/<file>.csv
SELECT SPLIT_PART("name", '/', -2)                       AS table_folder,
       COUNT(*)                                          AS files,
       ROUND(SUM("size") / POWER(1024, 3), 2)            AS size_gb
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP  BY 1
ORDER  BY 1;

-- 3c. Can Snowflake READ a file (not just list)? Peek at patients by position.
SELECT $1, $2, $3, $4, $5
FROM   @SYNTHEA.RAW.SYNTHEA_S3_STAGE/patients/
       (FILE_FORMAT => 'SYNTHEA.RAW.SYNTHEA_CSV_FORMAT')
LIMIT  10;

-- 3d. Does header parsing work? Shows the column names Snowflake will create.
SELECT column_name, type, order_id
FROM   TABLE(INFER_SCHEMA(
           LOCATION             => '@SYNTHEA.RAW.SYNTHEA_S3_STAGE/patients/',
           FILE_FORMAT          => 'SYNTHEA.RAW.SYNTHEA_CSV_HEADER_FORMAT',
           MAX_FILE_COUNT       => 1,
           MAX_RECORDS_PER_FILE => 1000))
ORDER  BY order_id;
