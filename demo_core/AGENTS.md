# demo_core guidance

## Scope

`demo_core` is the upstream dbt Mesh project. It reads `CORE_RAW`, cleans source-system data, and publishes governed core models for `demo_finance` and other consumers.

## Approved architecture

- dbt project name: `demo_core`.
- Logical output databases: `CORE_SLV` and `CORE_CONFIG`.
- Physical databases are selected by target: `DEV_*` for `DEV` and `TST`; `PRD_*` for `PRD`.

- Development uses shared DEV schemas by default. Developers should normally pass `--vars '{sandbox: <name>}'` to build into `SANDBOX_<NAME>_<SCHEMA>`.
- TST must preserve dbt Platform's temporary PR schema and must never write to PRD databases.

- Sources live under `models/sources/<source>/`.
- Staging models are source-oriented under `models/staging/<source>/` for `crm`, `billing`, `product`, `erp`, and `market`.
- Intermediate models are ownership-oriented under `models/intermediate/<domain>/` for `sales`, `billing`, `product`, `finance_operations`, and `core`.
- Public silver interfaces live under `models/marts/` and materialize in the explicitly configured `CORE_SLV.CORE` schema.
- Staging models are views and private where group boundaries allow it. Shared internal boundaries are protected.
- Public interfaces are `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`, owned by `core`.
- `customers` is versioned: deprecated v1 and current v2.
- Every public model has an enforced contract and is materialized as a table or incremental model.
- Revenue recognition, USD reporting measures, and other finance/gold logic belong in `demo_finance`, which consumes the public core interfaces through Mesh.
- Dirty source data is generated as CSV by the R generator, loaded to `CORE_RAW`, and corrected by dbt transformations.
- Expected anomalies use warning-level tests with stored failures. Error-level invariants pass in the standard dataset.
- Microbatch incremental modeling is deferred and excluded from the current scope. Product events may initially use a table or conventional incremental model.

## Planned features

- Described sources with freshness.
- Seeds in `CORE_CONFIG.REFERENCE` with explicit column types.
- Private staging views and one protected ephemeral helper.
- Business-unit tables.
- Merge incremental invoices model with a `unique_key`.
- Timestamp-strategy SCD Type 2 account snapshot in `CORE_CONFIG.SNAPSHOTS`.
- Currency conversion, account cleaning/matching, database naming, and schema naming macros.
- Run logging hooks in `CORE_CONFIG.AUDIT` and limited illustrative model hooks.
- Generic, singular, and unit tests; dbt Checks; stored test failures.
- Groups, access controls, contracts, model versions, shared docs blocks, and selected dbt State configs.

## Progress log

- Phase 1 — Architecture: approved. Microbatch deferred; raw-data defects originate in the R-generated CSVs; project-specific TST automation will use GitHub Actions path filtering and the dbt Administrative API.
- Phase 2 — Snowflake setup: completed; `setup/snowflake_setup.sql` ran successfully and created the required Snowflake objects.
- Phase 3 — Raw data specification and load: completed; the standard dataset is loaded in `CORE_RAW`, warehouse invariants passed, and source timestamps were rebaselined.
- Phase 4 — Foundation: completed; `demo_core` is the configured project subdirectory, DEV/TST/PRD naming macros are enforced, all 14 raw sources have freshness rules, and three typed reference seeds are loaded in DEV.
- Phase 5 — Staging: completed; 14 private staging views preserve source grains, reusable cleaning macros standardize strings/emails/domains/countries, a protected ephemeral country helper prevents normalized-key fanout, product JSON is safely parsed, ownership groups and access controls are active, and expected anomaly tests store failures in `CORE_CONFIG.AUDIT`.
- Phase 6 — Business models: completed; CRM duplicates collapse to canonical customers, billing-to-CRM matching is deterministic and unit tested, CRM account history uses a timestamp snapshot, invoices use merge incremental materialization with cross-table watermarks, FX gaps use prior-rate fallback, and domain models are protected.
- Phase 7 — Quality: completed; reusable expression tests enforce billing, sales, contact, and lifecycle invariants; singular tests cover journals, refunds, snapshots, contacts, and product events; focused unit tests protect account normalization, invoice reconciliation, customer matching, and FX fallback; dbt Checks enforce public contracts, staging materializations, and public ownership. The full DEV build passes with seven intentional stored-warning classes and no errors.
- Phase 8 — Governance: completed; public interfaces are contracted, tagged, and classified as the core data product; `customers` publishes deprecated v1 and current v2 contracts with a v2 Stable latest-version pointer preserving the unversioned relation; shared docs blocks standardize cross-interface identifiers, currency, and ingestion semantics; group ownership and access controls remain enforced.
- Pre-Phase 9 architecture refactor: completed; models use source-oriented staging, ownership-oriented intermediate, and `models/marts/` public interfaces while explicit project config preserves physical schemas. Core publishes `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`; core-owned `revenue` was removed so finance/gold logic can be implemented in `demo_finance`.
- Phase 9 — Documentation: not started.
- Phase 10 — dbt State: not started.
