# Snowflake Onboarding — Custom Roles Setup

This document describes the one-time onboarding steps required to provision the
custom Snowflake roles, the GitHub Actions service user, and the read-only
analyst role used by the **Cloud Champion Bootcamp – Snowflake Lakehouse**
project.

All SQL referenced here lives in [`snowflake-custom-roles.sql`](./snowflake-custom-roles.sql).
Run the script top-to-bottom in a Snowflake worksheet (or via SnowSQL) after
substituting the placeholders described below.

---

## 1. Prerequisites

| Requirement | Notes |
| --- | --- |
| Snowflake account | Enterprise edition or higher |
| `ACCOUNTADMIN` access | Required for the initial grant of `MANAGE GRANTS` to `SYSADMIN` and account-level privilege grants |
| `SECURITYADMIN` access | Used to create roles and the service user |
| RSA key pair | Generated with OpenSSL (see step 2) for the `GITHUB_ACTIONS_USER` |
| Existing warehouses | `UTIL_WH` and `COMPUTE_WH` should exist (or update the script to match your warehouse names) |

---

## 2. Generate the RSA Key Pair (GitHub Actions User)

On your local machine generate a 2048-bit PKCS8 RSA key pair. The unencrypted
form is recommended for CI/CD use.

```bash
# Private key (PKCS8, no passphrase)
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt

# Public key
openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub

# Extract the public key value (no headers, no newlines) for Snowflake
grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC" | tr -d '\n'
```

Keep `snowflake_key.p8` private — it will be uploaded to GitHub as the
`SNOWFLAKE_PRIVATE_KEY` secret. The extracted public key string replaces
`YOUR_PUBLIC_KEY_HERE` in the SQL script.

---

## 3. Custom Roles Created

The script provisions the following custom roles. Each role has a focused set
of responsibilities and is assigned to a Terraform provider alias.

| Role | Purpose | Account-Level Privileges |
| --- | --- | --- |
| `PLATFORM_DB_OWNER` | Owns databases and schemas | `CREATE DATABASE` |
| `DATA_OBJECT_ADMIN` | File formats, tables, dynamic tables, streams, tasks | none (granted later by Terraform) |
| `INGEST_ADMIN` | Storage integrations, stages, snowpipes | `CREATE INTEGRATION` |
| `WAREHOUSE_ADMIN` | Warehouse lifecycle | `CREATE WAREHOUSE`, `MONITOR USAGE`, `USAGE` on `UTIL_WH` |
| `ANALYST` | Read-only access for query / BI users | `USAGE` on `COMPUTE_WH`, schema-scoped `SELECT` |

All four automation roles (`PLATFORM_DB_OWNER`, `DATA_OBJECT_ADMIN`,
`INGEST_ADMIN`, `WAREHOUSE_ADMIN`) and `ANALYST` are granted to `SYSADMIN` so
the role hierarchy stays consistent with Snowflake best practices.

---

## 4. Onboarding Steps

### Step 1 — Allow `SYSADMIN` to Manage Grants

Run as `ACCOUNTADMIN`:

```sql
USE ROLE ACCOUNTADMIN;
GRANT MANAGE GRANTS ON ACCOUNT TO ROLE SYSADMIN;
```

### Step 2 — Create the Custom Roles

Run as `SECURITYADMIN`. This creates `PLATFORM_DB_OWNER`, `DATA_OBJECT_ADMIN`,
`INGEST_ADMIN`, `WAREHOUSE_ADMIN`, and `ANALYST`. See section 1 of the SQL
script.

### Step 3 — Grant Account-Level Privileges

Run as `ACCOUNTADMIN`. Grants `CREATE DATABASE`, `CREATE WAREHOUSE`, and
`CREATE INTEGRATION` to the appropriate roles. See section 2 of the SQL script.

### Step 4 — Wire the Role Hierarchy

Run as `SECURITYADMIN`. Each custom role is granted to `SYSADMIN`. See
section 3 of the SQL script.

### Step 5 — Create the GitHub Actions Service User

Replace `YOUR_PUBLIC_KEY_HERE` with the public key string from step 2 above and
run section 4 of the SQL script. The user is created with key-pair
authentication only — no password.

### Step 6 — Grant Custom Roles to the Service User

Run section 5 of the SQL script. The service user receives every automation
role but no default role (it must be selected explicitly per Terraform run).

### Step 7 — Configure the Analyst Role

Replace the `<DATABASE_NAME>`, `<SCHEMA_NAME>`, and `<ANALYST_USERNAME>`
placeholders, then run section 6 of the SQL script. This grants read-only
access to the analyst on existing and future tables and views in the target
schema.

### Step 8 — Post-Database Creation Grants

After Terraform (acting as `PLATFORM_DB_OWNER`) creates the lakehouse
databases and schemas, run section 7 of the SQL script as `ACCOUNTADMIN` to
grant the schema-scoped privileges that `DATA_OBJECT_ADMIN` and `INGEST_ADMIN`
need to create their objects.

### Step 9 — Verify

Run section 8 of the SQL script to confirm the user, custom roles, and grants
exist.

---

## 5. Placeholder Reference

Before running the SQL script, replace the following placeholders:

| Placeholder | Where | Replace With |
| --- | --- | --- |
| `YOUR_PUBLIC_KEY_HERE` | Section 4 — `CREATE USER` | The single-line public key from step 2 |
| `<DATABASE_NAME>` | Sections 6 and 7 | Target lakehouse database name (e.g., `LAKEHOUSE_DB`) |
| `<SCHEMA_NAME>` | Sections 6 and 7 | Target schema (e.g., `CURATED`) |
| `<ANALYST_USERNAME>` | Section 6 | Snowflake username for the analyst |

If your account uses different utility / compute warehouses, also update the
references to `UTIL_WH` and `COMPUTE_WH` in sections 2 and 6.

---

## 6. Security Notes

- Use key-pair authentication for service users; never store passwords in CI.
- Never commit `snowflake_key.p8` to the repository.
- Rotate the RSA key pair on a regular schedule and update the
  `SNOWFLAKE_PRIVATE_KEY` GitHub secret accordingly.
- `DATA_OBJECT_ADMIN` and `INGEST_ADMIN` are deliberately created with **no**
  schema privileges. Terraform grants them only what they need, when the
  target objects exist — preserving least privilege.
- `MANAGE GRANTS` on `SYSADMIN` is a powerful privilege. Limit who can assume
  `SYSADMIN` and audit grant changes.

---

## 7. Run the Script from a Snowflake Worksheet (via Git Integration)

Instead of copy-pasting SQL, you can connect Snowflake directly to this GitHub
repository using an **API integration** plus a **Git repository** object, then
open `snowflake-custom-roles.sql` straight from a worksheet.

### Step 1 — Create the API Integration

Run as `ACCOUNTADMIN`. The API integration whitelists the GitHub host and (if
the repo is private) references a secret holding a personal access token.

```sql
USE ROLE ACCOUNTADMIN;

-- Public repository: no secret needed
CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER         = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/subhamay-bhattacharyya/')
  ENABLED              = TRUE
  COMMENT              = 'API integration for cloning GitHub repos into Snowflake';
```

If the repository is private, create a secret first and reference it on the
integration:

```sql
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE SECRET GITHUB_PAT_SECRET
  TYPE     = PASSWORD
  USERNAME = '<github-username>'
  PASSWORD = '<github-personal-access-token>';

CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER         = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/subhamay-bhattacharyya/')
  ALLOWED_AUTHENTICATION_SECRETS = (GITHUB_PAT_SECRET)
  ENABLED              = TRUE;
```

### Step 2 — Create the Git Repository Object

Create a database/schema to hold the Git repository reference, then register
the repo. Snowflake will fetch its contents on demand.

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS ONBOARDING_DB;
CREATE SCHEMA   IF NOT EXISTS ONBOARDING_DB.GIT;

CREATE OR REPLACE GIT REPOSITORY ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO
  API_INTEGRATION = GITHUB_API_INTEGRATION
  -- GIT_CREDENTIALS = GITHUB_PAT_SECRET   -- uncomment for private repos
  ORIGIN = 'https://github.com/subhamay-bhattacharyya/cloud-platform-architecture.git';

-- Pull the latest commits/branches into Snowflake's metadata
ALTER GIT REPOSITORY ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO FETCH;

-- Confirm the file is visible
LS @ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO/branches/main/snowflake/;
```

### Step 3 — Open `snowflake-custom-roles.sql` in a Worksheet

In Snowsight:

1. Open **Projects → Worksheets** and click **+ Worksheet** to create a new SQL worksheet.
2. Click the worksheet title (top-left), choose **Open Worksheet From File** or
   the **Open from Git Repository** option, and browse to
   `ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO` → `branches/main` → `snowflake/snowflake-custom-roles.sql`.
3. Snowsight loads the script into the worksheet.

Alternatively, load the file inline from any worksheet:

```sql
EXECUTE IMMEDIATE FROM @ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO/branches/main/snowflake/snowflake-custom-roles.sql;
```

### Step 4 — Substitute Placeholders and Execute

Before running the script, replace the placeholders listed in section 5
(`YOUR_PUBLIC_KEY_HERE`, `<DATABASE_NAME>`, `<SCHEMA_NAME>`, `<ANALYST_USERNAME>`).
Then either:

- Highlight all statements in the worksheet and click **Run All**, or
- Step through each section (1 → 8) and run them individually so you can verify
  results between steps.

Section 8 of the script (`SHOW USERS` / `SHOW GRANTS`) will print the final
state — confirm every custom role and grant exists before moving on to the
Terraform deployment.

### Step 5 — Refreshing the Repo After Code Changes

If the SQL file is updated in GitHub, re-fetch before re-running:

```sql
ALTER GIT REPOSITORY ONBOARDING_DB.GIT.CLOUD_PLATFORM_ARCHITECTURE_REPO FETCH;
```

---

## 8. Related Files

- [`snowflake-custom-roles.sql`](./snowflake-custom-roles.sql) — the executable SQL script
- [`../README.md`](../README.md) — overall project documentation
