# demo_core

`demo_core` is the upstream silver project in this dbt Mesh demo. It reads deliberately dirty source data from `CORE_RAW`, standardizes and validates it, conforms identities across systems, and publishes stable contracts for downstream projects.

## Model organization

```text
models/
  sources/<source>/
  staging/<source>/
  intermediate/<business_domain>/
  marts/
```

Folders describe modeling role and ownership. Physical Snowflake placement is configured explicitly in `dbt_project.yml`:

| Layer | Logical database | Schemas |
| --- | --- | --- |
| Staging | `CORE_SLV` | `SALES`, `BILLING`, `PRODUCT`, `FINANCE_OPERATIONS` |
| Intermediate | `CORE_SLV` | `SALES`, `BILLING`, `PRODUCT`, `FINANCE_OPERATIONS`, `CORE` |
| Public marts | `CORE_SLV` | `CORE` |
| Seeds, snapshots, test failures | `CORE_CONFIG` | `REFERENCE`, `SNAPSHOTS`, `AUDIT` |

Custom naming macros map logical databases to `DEV_*` for DEV/TST and `PRD_*` for PRD. TST uses temporary schemas and defers to production.

## Public Mesh interfaces

Downstream projects should depend only on these contracted models:

| Model | Grain | Purpose |
| --- | --- | --- |
| `customers` | One conformed customer | CRM and billing identities combined into a stable customer interface. |
| `subscriptions` | One subscription | Current subscription lifecycle and governed plan attributes. |
| `invoices` | One invoice | Reconciled invoice, payment, refund, and net-collection facts in source currency. |
| `fx_rates` | One date and source currency | Daily currency-to-USD rates with prior-date fallback provenance. |
| `gl_entries` | One journal line | Clean general-ledger lines enriched with account classifications and customer linkage. |

`customers` is versioned. Version 2 is current; version 1 is a deprecated CRM-focused compatibility contract scheduled for deprecation on 2027-06-30. New consumers should use the latest version unless they intentionally require v1.

Revenue recognition, USD reporting measures, profitability, and other finance presentation logic belong in downstream `demo_finance`. `demo_core` publishes the atomic, governed inputs needed to calculate them.

## Data quality behavior

The standard generated dataset intentionally contains known anomalies. Warning-level tests preserve and surface those records in `CORE_CONFIG.AUDIT`; error-level invariants must pass. Expected warnings cover unknown CRM countries, rogue invoice statuses, unmatched payments, customer-ID discrepancies, invoice reconciliation differences, prior-date FX fallback, and one-cent journal imbalances.

## Development and validation

The project targets are exactly `DEV`, `TST`, and `PRD`. dbt must never run as `ACCOUNTADMIN`.

Typical validation for a model change is a dependency-aware build:

```text
dbt build --select +<model>+
```

Use a cold parse when checking project configuration or deprecations:

```text
dbt parse --no-partial-parse
```

On dbt Platform, Catalog is populated automatically by v2 Stable job runs. Model and column descriptions are also persisted to supported Snowflake relations as comments.


## Deployment, state, and CI

The `Core Production` dbt Platform environment builds `main` with target `PRD`. A successful production build publishes the manifest used as the deferred baseline for downstream Mesh metadata and Slim CI. Production jobs must complete successfully before dependent `demo_finance` production jobs run.

The `Core CI` staging environment uses target `TST`, `DBT_DEV_ROLE2`, and a pull-request-specific schema in the DEV databases. Its validated command sequence is:

```text
dbt clone --select state:modified+,config.materialized:incremental,state:old
dbt build --select state:modified+
```

The clone step exercises existing incremental models through their incremental path; the build selects modified resources and downstream dependents while deferring unselected parents to the latest successful production run. SQL linting runs first and stops the job on error. Production manifests and run artifacts must be retained long enough for open pull requests and downstream project resolution.

Native pull-request cleanup removes the temporary schema from the connection's default `DEV_CORE_SLV` database. Because this project also writes test failures and configuration resources to `DEV_CORE_CONFIG`, the matching temporary schema there requires explicit cleanup after a pull request closes.
