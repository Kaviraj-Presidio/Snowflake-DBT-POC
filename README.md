# Snowflake DBT POC

Medallion-architecture dbt project running against Snowflake, with isolated
Dev and Prod environments and a merge-request-only GitHub Actions CI/CD
pipeline.

## Architecture

- **One Snowflake account, two isolated databases:** `DEV_DB` and `PROD_DB`.
  Isolation is enforced by dedicated warehouses, roles, and service users per
  environment — `DEV_ROLE`/`CI_DEV_USER` cannot see `PROD_DB` or vice versa.
- **Medallion layers = schemas**, identical in both databases:
  - `BRONZE` — source-conformed, minimal transformation (rename/cast only).
  - `SILVER` — cleaned, conformed, business rules applied.
  - `GOLD` — aggregated marts for consumption/BI.
- **dbt** owns all transformation logic (`models/bronze`, `models/silver`,
  `models/gold`). Which database a run targets is controlled entirely by
  `--target dev` / `--target prod` (see [`profiles/profiles.yml`](profiles/profiles.yml)).

## Branching / promotion flow

```
feature/* --PR--> development --PR--> main
                        |                 |
                  DEV_CI builds     PROD_CI validates against dev,
                  against DEV_DB    then deploys to PROD_DB (after
                  (dbt build)       required-reviewer approval,
                                    dbt run)
```

- No direct pushes to `development` or `main` — both are protected branches,
  all changes land via reviewed pull request.
- A PR into `development` triggers `dbt build --target dev` (models + tests)
  against `DEV_DB`. Merging runs `dbt run --target dev` (models only).
- A PR into `main` triggers a validation build (`dbt build --target dev`,
  models + tests) against `DEV_DB` — no prod credentials touched pre-merge.
  Once merged, a second job runs `dbt run --target prod` against `PROD_DB`,
  gated behind GitHub's `production` environment approval.

See [`.github/workflows/dev.yml`](.github/workflows/dev.yml) and
[`.github/workflows/prod.yml`](.github/workflows/prod.yml).

## Repo layout

```
dbt_project.yml          dbt project config
profiles/profiles.yml    connection profile (env-var driven, no secrets committed)
models/bronze/           source-conformed models
models/silver/           cleaned/conformed models
models/gold/             marts
seeds/                   example seed data (raw_customers)
macros/                  generate_schema_name override (schema == medallion layer)
snowflake/               one-time manual Snowflake setup SQL (databases, warehouses, roles, users)
.github/workflows/       CI/CD pipelines
SETUP.md                 step-by-step manual infra setup runbook
```

## First-time setup

Nothing here works until the manual Snowflake + GitHub configuration in
[`SETUP.md`](SETUP.md) is done — start there.

## Local development

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export DBT_PROFILES_DIR=./profiles
export SNOWFLAKE_ACCOUNT=...
export SNOWFLAKE_DEV_USER=...
export SNOWFLAKE_DEV_ROLE=DEV_ROLE
export SNOWFLAKE_DEV_WAREHOUSE=DEV_WH
export SNOWFLAKE_DEV_DATABASE=DEV_DB
export SNOWFLAKE_DEV_PRIVATE_KEY="$(cat ~/.ssh/ci_dev_user_rsa_key.p8)"

dbt debug --target dev
dbt build --target dev
```

Never run `dbt` against `--target prod` locally — prod is deploy-only via
CI, after review approval.
