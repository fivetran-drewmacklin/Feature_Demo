# dbt Enterprise Mesh demo

This repository contains a Snowflake-backed dbt Mesh implementation for a fictional B2B SaaS company.

- `demo_core/` is the upstream silver/core dbt project.
- `demo_finance/` will be the downstream finance/gold dbt project.
- `setup/` contains Snowflake setup, raw-data generation, loading, and demo-mutation utilities.

The only supported environment names are `DEV`, `TST`, and `PRD`. TST runs in temporary schemas in the DEV databases; PRD writes to the PRD databases.

Configure each dbt Platform project with its corresponding project subdirectory before running dbt commands.
