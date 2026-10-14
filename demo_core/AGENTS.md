# demo_core guidance

## Scope

`demo_core` is the upstream dbt Mesh project. It reads `CORE_RAW`, cleans source-system data, and publishes governed core models for `demo_finance` and other consumers.

## Approved architecture

- dbt project name: `demo_core`.
- Logical output databases: `CORE_SLV` and `CORE_CONFIG`.
- Physical databases are selected by target: `DEV_*` for `dev` and `ci`; `PRD_*` for `prod`.
- Development uses shared DEV schemas by default. Developers should normally pass `--vars '{sandbox: <name>}'` to build into `SANDBOX_<NAME>_<SCHEMA>`.
- CI must preserve dbt Platform's temporary PR schema and must never write to PRD databases.
- Sources live under `models/sources/<source>/`; output models mirror `models/core_slv/<business_schema>/`.
- Source groups: `crm`, `billing`, `product`, `erp`, and `market`.
- Ownership groups: `sales`, `billing`, `product`, `finance_operations`, and `core`.
- Staging models are views and private where group boundaries allow it. Shared internal boundaries are protected.
- Public interfaces are `customers`, `subscriptions`, and `revenue`, owned by `core`.
- `customers` is versioned: deprecated v1 and current v2.
- Every public model has an enforced contract and is materialized as a table or incremental model.
- Dirty source data is generated as CSV by the R generator, loaded to `CORE_RAW`, and corrected by dbt transformations.
- Expected anomalies use warning-level tests with stored failures. Error-level invariants pass in the standard dataset.
- Microbatch incremental modeling is deferred and excluded from the current scope. Product events may initially use a table or conventional incremental model.

## Planned features

- Described sources with freshness.
- Seeds in `CORE_CONFIG.REFERENCE` with explicit column types.
- Private staging views and one private ephemeral helper.
- Business-unit tables.
- Merge incremental invoices model with a `unique_key`.
- Timestamp-strategy SCD Type 2 account snapshot in `CORE_CONFIG.SNAPSHOTS`.
- Currency conversion, account cleaning/matching, database naming, and schema naming macros.
- Run logging hooks in `CORE_CONFIG.AUDIT` and limited illustrative model hooks.
- Generic, singular, and unit tests; dbt Checks; stored test failures.
- Groups, access controls, contracts, model versions, shared docs blocks, and selected dbt State configs.

## Progress log

- Phase 1 — Architecture: approved. Microbatch deferred; raw-data defects originate in the R-generated CSVs; project-specific CI will use GitHub Actions path filtering and the dbt Administrative API.
- Phase 2 — Snowflake setup: `setup/snowflake_setup.sql` authored and statically reviewed; awaiting administrator execution in Snowflake.
- Phase 3 — Raw data specification: not started.
- Phase 4 — Foundation: not started.
- Phase 5 — Staging: not started.
- Phase 6 — Business models: not started.
- Phase 7 — Quality: not started.
- Phase 8 — Governance: not started.
- Phase 9 — Documentation: not started.
- Phase 10 — dbt State: not started.
