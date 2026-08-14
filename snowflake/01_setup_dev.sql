-- ============================================================================
-- Dev environment setup for the Snowflake-DBT-POC medallion project.
-- Run once, manually, as a role with account-admin privileges (ACCOUNTADMIN
-- or SECURITYADMIN+SYSADMIN). Idempotent: safe to re-run.
--
-- Isolation model: DEV and PROD share one Snowflake account but never share
-- a database, warehouse, or role. The CI_DEV_USER service user can only ever
-- reach DEV_DB / DEV_WH via DEV_ROLE.
-- ============================================================================

use role securityadmin;

-- ---------------------------------------------------------------------------
-- Role
-- ---------------------------------------------------------------------------
create role if not exists dev_role
    comment = 'Role for the Dev environment (dbt CI/CD). No access outside DEV_DB/DEV_WH.';

grant role dev_role to role sysadmin;

-- ---------------------------------------------------------------------------
-- Warehouse
-- ---------------------------------------------------------------------------
use role sysadmin;

create warehouse if not exists dev_wh
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Warehouse for the Dev environment.';

grant usage, operate on warehouse dev_wh to role dev_role;

-- ---------------------------------------------------------------------------
-- Database + medallion schemas
-- ---------------------------------------------------------------------------
create database if not exists dev_db
    comment = 'Dev environment database. Isolated from PROD_DB.';

create schema if not exists dev_db.bronze;
create schema if not exists dev_db.silver;
create schema if not exists dev_db.gold;

grant usage on database dev_db to role dev_role;
grant all on schema dev_db.bronze to role dev_role;
grant all on schema dev_db.silver to role dev_role;
grant all on schema dev_db.gold to role dev_role;

-- Future objects created by dbt (tables/views) inherit these grants too.
grant all on future tables in database dev_db to role dev_role;
grant all on future views in database dev_db to role dev_role;

-- ---------------------------------------------------------------------------
-- Service user for GitHub Actions CI/CD (key-pair auth only, no password)
-- ---------------------------------------------------------------------------
use role useradmin;

create user if not exists ci_dev_user
    type = service
    default_role = dev_role
    default_warehouse = dev_wh
    default_namespace = dev_db
    comment = 'Service user used by GitHub Actions to run dbt against DEV_DB.';

use role securityadmin;
grant role dev_role to user ci_dev_user;

-- After generating a key pair (see SETUP.md), attach the PUBLIC key here:
-- alter user ci_dev_user set rsa_public_key = 'MIIBIjANBgkqh...';
