# Infra setup runbook

Everything in this repo (dbt project, GitHub Actions workflows, Snowflake SQL
scripts) is already in place. This document is the checklist of **manual**
steps required outside the repo — in your Snowflake trial account and in the
GitHub repo settings — since neither can be configured from the codebase
alone.

Do these in order.

## 1. Run the Snowflake setup scripts

In Snowsight (or SnowSQL), logged in as a user with `ACCOUNTADMIN` (or
`SECURITYADMIN` + `SYSADMIN` + `USERADMIN`) privileges, run:

1. [`snowflake/01_setup_dev.sql`](snowflake/01_setup_dev.sql)
2. [`snowflake/02_setup_prod.sql`](snowflake/02_setup_prod.sql)

This creates, per environment, a dedicated database (`DEV_DB` / `PROD_DB`)
with `BRONZE`/`SILVER`/`GOLD` schemas, a dedicated warehouse, a dedicated
role, and a dedicated service user (`CI_DEV_USER` / `CI_PROD_USER`). Each
role can only ever touch its own database and warehouse — that's the
isolation boundary between Dev and Prod inside the single account.

Both scripts are idempotent (`create ... if not exists`), so re-running them
is safe.

## 2. Generate a key pair per environment

Do this **twice** — once for `CI_DEV_USER`, once for `CI_PROD_USER`. Never
reuse a key pair across environments.

```bash
# Dev
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ci_dev_user_rsa_key.p8 -nocrypt
openssl rsa -in ci_dev_user_rsa_key.p8 -pubout -out ci_dev_user_rsa_key.pub

# Prod
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ci_prod_user_rsa_key.p8 -nocrypt
openssl rsa -in ci_prod_user_rsa_key.p8 -pubout -out ci_prod_user_rsa_key.pub
```

(Add `-v2 aes-256-cbc` to the first `openssl pkcs8` command if you'd rather
encrypt the private key with a passphrase — then set
`SNOWFLAKE_*_PRIVATE_KEY_PASSPHRASE` in step 4.)

These `.p8`/`.pub` files are gitignored — never commit them.

Attach each public key to its Snowflake user (strip the `BEGIN/END PUBLIC
KEY` header/footer lines, keep the base64 body as one line):

```sql
use role useradmin;
alter user ci_dev_user  set rsa_public_key = '<contents of ci_dev_user_rsa_key.pub>';
alter user ci_prod_user set rsa_public_key = '<contents of ci_prod_user_rsa_key.pub>';
```

## 3. Create GitHub Environments

In the GitHub repo: **Settings → Environments**.

1. Create environment `development`.
2. Create environment `production`.
   - Under **Deployment protection rules**, add yourself/your reviewers as
     **Required reviewers**. This is what forces a human approval before
     `dbt build` ever runs against `PROD_DB`, even after a PR to `main` is
     merged.
   - Under **Deployment branches and tags**, restrict to the `main` branch
     only.

## 4. Add secrets

Add these under each Environment's own secrets (Settings → Environments →
`development` / `production` → *Environment secrets*) — **not** as repo-wide
secrets, so a workflow run against `development` can never see prod
credentials and vice versa.

**Account-level** (add to both environments, same value):
| Secret | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Your account identifier, e.g. `xy12345.ap-south-1` |

**`development` environment:**
| Secret | Value |
|---|---|
| `SNOWFLAKE_DEV_USER` | `CI_DEV_USER` |
| `SNOWFLAKE_DEV_ROLE` | `DEV_ROLE` |
| `SNOWFLAKE_DEV_WAREHOUSE` | `DEV_WH` |
| `SNOWFLAKE_DEV_DATABASE` | `DEV_DB` |
| `SNOWFLAKE_DEV_PRIVATE_KEY` | full contents of `ci_dev_user_rsa_key.p8` |
| `SNOWFLAKE_DEV_PRIVATE_KEY_PASSPHRASE` | only if you encrypted the key |

**`production` environment:**
| Secret | Value |
|---|---|
| `SNOWFLAKE_PROD_USER` | `CI_PROD_USER` |
| `SNOWFLAKE_PROD_ROLE` | `PROD_ROLE` |
| `SNOWFLAKE_PROD_WAREHOUSE` | `PROD_WH` |
| `SNOWFLAKE_PROD_DATABASE` | `PROD_DB` |
| `SNOWFLAKE_PROD_PRIVATE_KEY` | full contents of `ci_prod_user_rsa_key.p8` |
| `SNOWFLAKE_PROD_PRIVATE_KEY_PASSPHRASE` | only if you encrypted the key |

## 5. Create the `development` branch and protect both branches

```bash
git checkout -b development
git push -u origin development
```

In **Settings → Branches**, add protection rules for both `main` and
`development`:

- Require a pull request before merging (require at least 1 approval).
- Require status checks to pass before merging — select the `dbt build
  (DEV_DB)` check (and, once one PR has run against `main`, the `Validate
  promotion candidate (DEV_DB)` check too).
- Do not allow bypassing the above settings.
- Disable force pushes and branch deletion.

Also set `development` as the repository's default branch for day-to-day
feature PRs, and confirm direct pushes are blocked on both `main` and
`development` (only merges via reviewed PR are allowed).

## 6. Verify end-to-end

1. Branch off `development`, open a PR back into `development` → confirm
   the **dbt CI/CD - Dev** workflow's `pr-build` job runs `dbt build
   --target dev` successfully against `DEV_DB`.
2. Merge that PR → confirm the same workflow's `merge-run` job runs `dbt
   run --target dev` on push to `development`.
3. Open a PR from `development` into `main` → confirm **dbt CI/CD -
   Prod**'s `validate-against-dev` job runs `dbt build --target dev`
   (still against `DEV_DB`, no prod credentials touched).
4. Merge into `main` → confirm the `deploy-to-prod` job pauses for the
   required reviewer approval on the `production` environment, then runs
   `dbt run --target prod` against `PROD_DB` once approved.

At that point Dev and Prod are both live, isolated, and the only path from
code to Prod is: feature branch → PR → `development` (build+test) → PR →
`main` (build+test against dev, then manual approval) → `dbt run` against
`PROD_DB`.

## Notes / things to revisit later

- **Workload Identity Federation (WIF):** Snowflake supports secretless
  OIDC auth from GitHub Actions, but as of the current `dbt-snowflake`
  release (1.10.2) the adapter doesn't yet expose it
  ([dbt-labs/dbt-adapters#1316](https://github.com/dbt-labs/dbt-adapters/pull/1316)
  is still open). Key-pair auth is the correct choice today; switch once
  that PR ships and rotate out the stored private keys.
- **Shared Dev database:** every PR into `development` builds directly against the
  same `DEV_DB`. Fine at this scale; if multiple people work in parallel and
  collide, look at ephemeral per-PR schemas (dbt's `+schema` override keyed
  off `github.head_ref`) later.
- **Key rotation:** Snowflake supports two RSA keys per user
  (`RSA_PUBLIC_KEY` / `RSA_PUBLIC_KEY_2`) specifically to allow zero-downtime
  rotation — use that when it's time to rotate.
