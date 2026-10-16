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
