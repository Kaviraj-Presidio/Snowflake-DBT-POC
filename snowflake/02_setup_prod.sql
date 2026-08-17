-- ============================================================================
-- Prod environment setup for the Snowflake-DBT-POC medallion project.
-- Run once, manually, as a role with account-admin privileges (ACCOUNTADMIN
-- or SECURITYADMIN+SYSADMIN). Idempotent: safe to re-run.
--
-- Isolation model: mirrors 01_setup_dev.sql exactly, but every object is
-- distinct (PROD_DB/PROD_WH/PROD_ROLE/CI_PROD_USER). Nothing here grants
-- access to anything in the Dev environment.
-- ============================================================================

use role securityadmin;

-- ---------------------------------------------------------------------------
-- Role
-- ---------------------------------------------------------------------------
create role if not exists prod_role
    comment = 'Role for the Prod environment (dbt CI/CD). No access outside PROD_DB/PROD_WH.';

grant role prod_role to role sysadmin;

-- ---------------------------------------------------------------------------
-- Warehouse
-- ---------------------------------------------------------------------------
use role sysadmin;

create warehouse if not exists prod_wh
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Warehouse for the Prod environment.';

grant usage, operate on warehouse prod_wh to role prod_role;

-- ---------------------------------------------------------------------------
-- Database + medallion schemas
-- ---------------------------------------------------------------------------
create database if not exists prod_db
    comment = 'Prod environment database. Isolated from DEV_DB.';

create schema if not exists prod_db.bronze;
create schema if not exists prod_db.silver;
create schema if not exists prod_db.gold;

grant usage on database prod_db to role prod_role;
grant all on schema prod_db.bronze to role prod_role;
grant all on schema prod_db.silver to role prod_role;
grant all on schema prod_db.gold to role prod_role;

-- Future objects created by dbt (tables/views) inherit these grants too.
grant all on future tables in database prod_db to role prod_role;
grant all on future views in database prod_db to role prod_role;

-- ---------------------------------------------------------------------------
-- Service user for GitHub Actions CI/CD (key-pair auth only, no password)
-- ---------------------------------------------------------------------------
use role useradmin;

create user if not exists ci_prod_user
    type = service
    default_role = prod_role
    default_warehouse = prod_wh
    default_namespace = prod_db
    comment = 'Service user used by GitHub Actions to run dbt against PROD_DB. Only the protected "production" GitHub Environment may use it.';

use role securityadmin;
grant role prod_role to user ci_prod_user;

-- After generating a key pair (see SETUP.md), attach the PUBLIC key here.
-- Use a DIFFERENT key pair from CI_DEV_USER's.
-- alter user ci_prod_user set rsa_public_key = 'MIIBIjANBgkqh...';
