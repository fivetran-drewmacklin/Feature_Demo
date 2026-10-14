# Repository guidance

## Purpose

This repository contains a realistic dbt Enterprise demo implemented as two dbt Mesh projects:

- `demo_core/`: upstream silver/core project.
- `demo_finance/`: downstream finance/gold project, built later.
- `setup/`: Snowflake setup SQL, raw-data specification, and R-based CSV generator.

Both projects target Snowflake and dbt Platform's Latest release track (dbt v2).

## Repository architecture

- Raw data is generated as deliberately dirty CSV files by an R script and loaded outside dbt into `CORE_RAW`.
- dbt cleans and models the raw data; the standard generated dataset may produce intentional warning-level tests but must allow production builds to succeed.
- Optional generator scenarios may produce build-breaking data for failure demonstrations.
- `demo_finance` consumes only public, contracted `demo_core` models through cross-project `ref()` calls in dbt Mesh.
- Logical database names in dbt config omit environment prefixes. Custom database naming maps them to `DEV_*` for `dev` and `ci`, and `PRD_*` for `prod`.
- Model folders mirror logical Snowflake destinations, for example `models/core_slv/sales/`.

## Snowflake environments

- Raw: `CORE_RAW`, owned by `SYSADMIN` and read-only to dbt roles.
- Core outputs: `DEV_CORE_SLV`, `PRD_CORE_SLV`.
- Core config: `DEV_CORE_CONFIG`, `PRD_CORE_CONFIG`.
- Finance outputs: `DEV_FINANCE_GLD`, `PRD_FINANCE_GLD`.
- Finance config: `DEV_FINANCE_CONFIG`, `PRD_FINANCE_CONFIG`.
- Targets are exactly `dev`, `ci`, and `prod`.
- dbt must never run as `ACCOUNTADMIN`.

## CI and deployment

- CI builds temporary schemas in DEV databases using `DBT_DEV_ROLE` and defers to Production.
- Native dbt Platform monorepo CI triggers every attached project and has no project-subdirectory path filter.
- Use GitHub Actions path filters plus the dbt Administrative API so changes under `demo_core/**` trigger only core CI, changes under `demo_finance/**` trigger only finance CI, and shared/setup changes trigger both when appropriate.
- Production deployment of `demo_finance` must follow a successful `demo_core` production run so current public-model metadata is available.

## Shared conventions

- One YAML file per model, with the same basename as its SQL model; one YAML file per source system.
- Use `dependencies.yml`, not `packages.yml`.
- Staging model names: `stg_<source>__<entity>`.
- Intermediate model names: `int_<domain>__<purpose>`.
- Public models use plural business nouns.
- Use `ref()` and `source()`; do not hardcode dbt-managed relations.
- Public models are contracted tables or incrementals.
- Known raw-data anomalies are corrected in staging/business logic and tested at appropriate warn/error severity.
- Keep this file and each project's `AGENTS.md` current as architecture decisions and implementation phases progress.
