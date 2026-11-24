/* =============================================================================
   01_storage_integration.sql   (run as ACCOUNTADMIN)
   Author: Cortwright Grant

   Creates the Snowflake <-> AWS trust object and hands it to the ingest role.
   Prereq: aws\02_setup_iam_for_snowflake.ps1 Phase A has run.

   Find/replace before running:
     <AWS_ACCOUNT_ID>        12-digit AWS account id   (aws sts get-caller-identity)
     <BUCKET>                your bucket name          (aws/00_config.ps1)
     <YOUR_SNOWFLAKE_USER>   your login user           (SELECT CURRENT_USER();)
   ============================================================================= */

USE ROLE ACCOUNTADMIN;   -- CREATE INTEGRATION is an account-level privilege

-- -----------------------------------------------------------------------------
-- 1. Storage integration
--    * No AWS keys stored in Snowflake: Snowflake assumes the IAM role instead.
--    * STORAGE_ALLOWED_LOCATIONS caps every stage built on this integration to
--      the one prefix, even if someone later points a stage elsewhere.
--    * IF NOT EXISTS on purpose: CREATE OR REPLACE would mint a NEW external ID
--      and silently break the IAM trust policy.
-- -----------------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS SYNTHEA_S3_INT
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'S3'
    ENABLED                   = TRUE
    STORAGE_AWS_ROLE_ARN      = 'arn:aws:iam::<AWS_ACCOUNT_ID>:role/synthea-snowflake-s3-read-role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://<BUCKET>/synthea-v2/csv/')
    COMMENT                   = 'Read-only access to the Synthea CSV landing prefix';

-- -----------------------------------------------------------------------------
-- 2. Get the two values AWS needs for the trust policy
--    Copy them into Phase B of aws\02_setup_iam_for_snowflake.ps1.
-- -----------------------------------------------------------------------------
DESC INTEGRATION SYNTHEA_S3_INT;

SELECT "property", "property_value"
FROM   TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE  "property" IN ('STORAGE_AWS_IAM_USER_ARN', 'STORAGE_AWS_EXTERNAL_ID');

-- -----------------------------------------------------------------------------
-- 3. Hand the integration to the ingest persona (and only that persona)
-- -----------------------------------------------------------------------------
GRANT USAGE ON INTEGRATION SYNTHEA_S3_INT TO ROLE SYNTHEA_INGEST_ROLE;

-- -----------------------------------------------------------------------------
-- 4. The one gap in the RBAC bootstrap: 03 creates a load procedure in RAW.
--    (Warehouse/database/schema usage, CREATE TABLE/STAGE/FILE FORMAT, and
--    dbt's SELECT + future grants on RAW were already granted by the RBAC
--    script, so they are not repeated here.)
-- -----------------------------------------------------------------------------
GRANT CREATE PROCEDURE ON SCHEMA SYNTHEA.RAW TO ROLE SYNTHEA_INGEST_ROLE;

-- Your HUMAN user also needs the project roles. The RBAC script granted them to
-- the two service users and rolled them up to SYSADMIN, but not to you.
-- Granting the developer role gives you both INGEST and DBT via inheritance.
GRANT ROLE SYNTHEA_DEVELOPER_ROLE TO USER <YOUR_SNOWFLAKE_USER>;   -- SELECT CURRENT_USER();

-- Sanity checks
SHOW GRANTS TO ROLE SYNTHEA_INGEST_ROLE;
SHOW FUTURE GRANTS IN SCHEMA SYNTHEA.RAW;

/* NEXT: Phase B (lock IAM trust to the two values from step 2), wait ~1 min,
         then run 02_stage_and_file_format.sql.  */
