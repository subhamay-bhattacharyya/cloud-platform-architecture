-- ============================================================================
-- Snowflake: GitHub Actions Service User + Custom Automation Roles
--
-- Creates:
--   * User: GITHUB_ACTIONS_USER (key-pair auth; default role PUBLIC; no default WH)
--   * Custom Roles:
--       - PLATFORM_DB_OWNER   (CREATE DATABASE)
--       - DATA_OBJECT_ADMIN   (schema-scoped privileges granted later by Terraform)
--       - INGEST_ADMIN        (integration/stage/pipe scoped privileges)
--       - WAREHOUSE_ADMIN     (CREATE WAREHOUSE)
--       - ANALYST             (read-only access for query/analysis)
--   * Grants all automation roles to the GitHub Actions user
--
-- Run as: SECURITYADMIN / ACCOUNTADMIN (as indicated in each section)
-- Replace:
--   - YOUR_PUBLIC_KEY_HERE  with the contents of snowflake_key.pub
--   - <DATABASE_NAME> / <SCHEMA_NAME> / <ANALYST_USERNAME> as applicable
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Pre-requisite: Allow SYSADMIN to manage grants
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT MANAGE GRANTS ON ACCOUNT TO ROLE SYSADMIN;

-- ----------------------------------------------------------------------------
-- 1) Create Custom Roles
-- ----------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS PLATFORM_DB_OWNER
  COMMENT = '[CUSTOM ROLE] Owns databases and schemas for the lakehouse platform';

CREATE ROLE IF NOT EXISTS DATA_OBJECT_ADMIN
  COMMENT = '[CUSTOM ROLE] Manages file formats, tables, dynamic tables, streams, tasks';

CREATE ROLE IF NOT EXISTS INGEST_ADMIN
  COMMENT = '[CUSTOM ROLE] Manages storage integrations, stages, and snowpipes';

CREATE ROLE IF NOT EXISTS WAREHOUSE_ADMIN
  COMMENT = '[CUSTOM ROLE] Manages warehouse lifecycle';

CREATE ROLE IF NOT EXISTS ANALYST
  COMMENT = '[CUSTOM ROLE] Read-only access to query tables and views';

-- ----------------------------------------------------------------------------
-- 2) Grant Account-Level Privileges
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

-- PLATFORM_DB_OWNER: create databases (account-level)
GRANT CREATE DATABASE ON ACCOUNT TO ROLE PLATFORM_DB_OWNER;

-- WAREHOUSE_ADMIN: create warehouses (account-level)
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE WAREHOUSE_ADMIN;
GRANT MONITOR USAGE ON ACCOUNT TO ROLE WAREHOUSE_ADMIN;
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE WAREHOUSE_ADMIN;

-- INGEST_ADMIN: create storage integrations (account-level)
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE INGEST_ADMIN;

-- NOTE:
-- DATA_OBJECT_ADMIN and INGEST_ADMIN are intentionally left without
-- schema-level privileges here. They are granted later by Terraform once the
-- target database/schema/integrations exist (JSON-driven).

-- ----------------------------------------------------------------------------
-- 3) Role Hierarchy (report custom roles up to SYSADMIN)
-- ----------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT ROLE PLATFORM_DB_OWNER TO ROLE SYSADMIN;
GRANT ROLE DATA_OBJECT_ADMIN TO ROLE SYSADMIN;
GRANT ROLE INGEST_ADMIN      TO ROLE SYSADMIN;
GRANT ROLE WAREHOUSE_ADMIN   TO ROLE SYSADMIN;
GRANT ROLE ANALYST           TO ROLE SYSADMIN;

-- ----------------------------------------------------------------------------
-- 4) Create GitHub Actions Service User (Key-Pair Auth Only)
-- ----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS GITHUB_ACTIONS_USER
  LOGIN_NAME           = 'GITHUB_ACTIONS_USER'
  DISPLAY_NAME         = 'GitHub Actions Service User'
  DEFAULT_ROLE         = PUBLIC
  DEFAULT_WAREHOUSE    = NULL
  MUST_CHANGE_PASSWORD = FALSE
  DISABLED             = FALSE
  RSA_PUBLIC_KEY       = 'YOUR_PUBLIC_KEY_HERE';

-- ----------------------------------------------------------------------------
-- 5) Grant Custom Roles to GitHub Actions User
-- ----------------------------------------------------------------------------
GRANT ROLE PLATFORM_DB_OWNER TO USER GITHUB_ACTIONS_USER;
GRANT ROLE DATA_OBJECT_ADMIN TO USER GITHUB_ACTIONS_USER;
GRANT ROLE INGEST_ADMIN      TO USER GITHUB_ACTIONS_USER;
GRANT ROLE WAREHOUSE_ADMIN   TO USER GITHUB_ACTIONS_USER;

-- ----------------------------------------------------------------------------
-- 6) Analyst Role: Read-Only Privileges
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ANALYST;

GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE ANALYST;
GRANT USAGE ON SCHEMA   <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

GRANT SELECT ON ALL TABLES IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS  IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

GRANT SELECT ON FUTURE TABLES IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

GRANT ROLE ANALYST TO USER <ANALYST_USERNAME>;

-- ----------------------------------------------------------------------------
-- 7) Post-Database Creation Grants
--    Run after PLATFORM_DB_OWNER has created the target databases/schemas.
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

-- DATA_OBJECT_ADMIN
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT USAGE ON SCHEMA   <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE FILE FORMAT    ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE TABLE          ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE DYNAMIC TABLE  ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE STREAM         ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE TASK           ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;

-- INGEST_ADMIN
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE INGEST_ADMIN;
GRANT USAGE ON SCHEMA   <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;
GRANT CREATE STAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;
GRANT CREATE PIPE  ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;

-- ----------------------------------------------------------------------------
-- 8) Verification
-- ----------------------------------------------------------------------------
SHOW USERS LIKE 'GITHUB_ACTIONS_USER';
SHOW GRANTS TO USER GITHUB_ACTIONS_USER;
SHOW GRANTS TO ROLE PLATFORM_DB_OWNER;
SHOW GRANTS TO ROLE DATA_OBJECT_ADMIN;
SHOW GRANTS TO ROLE INGEST_ADMIN;
SHOW GRANTS TO ROLE WAREHOUSE_ADMIN;
SHOW GRANTS TO ROLE ANALYST;
