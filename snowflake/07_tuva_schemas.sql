/* =============================================================================
   07_tuva_schemas.sql   (SYSADMIN, then SECURITYADMIN)
   Author: Cortwright Grant

   Pre-creates the schemas Tuva Core builds into, and lets dbt build in them.

   Why this file exists: dbt normally creates any schema it needs, but
   SYNTHEA_DBT_ROLE has no CREATE SCHEMA right on the database (by design - see
   00_rbac_bootstrap.sql). Tuva writes to several schemas of its own, so each
   one is created here first, exactly as STAGING / INTERMEDIATE / MARTS were.

   The names come from `tuva_schema_prefix: tuva` in dbt_project.yml. To see
   which schemas the current configuration needs:
       dbt ls --resource-type model seed --output json --output-keys schema

   Clinical-only build (clinical_enabled: true, claims not enabled) needs the
   first seven. TUVA_DATA_QUALITY is only used when data_quality_enabled: true.
   Enabling claims later adds TUVA_CLAIMS_PREPROCESSING and TUVA_INTERMEDIATE.
   ============================================================================= */

-- =============================================================================
-- A. Schemas                                                       (SYSADMIN)
-- =============================================================================
USE ROLE SYSADMIN;

CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_INPUT_LAYER      COMMENT = 'Tuva Input Layer: this project''s mapping of RAW_2026 to Tuva''s contract, plus Tuva''s wrapper views';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_NORMALIZED_LAYER COMMENT = 'Tuva: type casting and terminology normalization';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_CORE             COMMENT = 'Tuva Core Data Model';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_TERMINOLOGY      COMMENT = 'Tuva terminology seeds (SNOMED CT, LOINC, ICD-10, CVX, ...)';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_VALUE_SETS       COMMENT = 'Tuva value-set seeds (condition and procedure groupers, ...)';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_PROVIDER_DATA    COMMENT = 'Tuva provider reference seeds (NPI registry extract, taxonomy)';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_METADATA         COMMENT = 'Tuva run metadata';
CREATE SCHEMA IF NOT EXISTS SYNTHEA.TUVA_DATA_QUALITY     COMMENT = 'Tuva data-quality results (only when data_quality_enabled: true)';

-- =============================================================================
-- B. Grants                                                   (SECURITYADMIN)
--    dbt needs to use each schema and create tables and views in it. It owns
--    what it creates, so no table-level grants are needed for dbt itself.
--    Analysts are deliberately NOT granted these schemas: they keep reading
--    MARTS only, and the marts are built on top of TUVA_CORE.
-- =============================================================================
USE ROLE SECURITYADMIN;

GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_INPUT_LAYER      TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_NORMALIZED_LAYER TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_CORE             TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_TERMINOLOGY      TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_VALUE_SETS       TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_PROVIDER_DATA    TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_METADATA         TO ROLE SYNTHEA_DBT_ROLE;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA SYNTHEA.TUVA_DATA_QUALITY     TO ROLE SYNTHEA_DBT_ROLE;

-- Check
SHOW SCHEMAS LIKE 'TUVA_%' IN DATABASE SYNTHEA;
