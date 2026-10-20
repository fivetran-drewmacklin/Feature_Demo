# Feature_Demo project features

This repository is a Snowflake-backed dbt Enterprise demo for a fictional B2B SaaS company. It implements two dbt Mesh projects, a deterministic raw-data generator, governed public interfaces, a hosted Semantic Layer, and validated dbt Platform CI and Production workflows.

## Current status

Both dbt projects are deployed and operational on dbt v2 Stable.

- Core and Finance CI and Production jobs have been validated successfully.
- The Core freshness job has a successful baseline with one intentional FX warning.
- Finance's hosted Semantic Layer serves six governed metrics.
- Development and Production Semantic Layer time spines are deployed.
- Governance checks pass in both projects.
- Failure-email notifications are enabled for all five jobs.
- The repository is clean on `main`.

## Repository architecture

| Path | Purpose |
|---|---|
| `demo_core/` | Upstream silver/core data product. Cleans raw data, conforms entities, and publishes stable public contracts. |
| `demo_finance/` | Downstream finance/gold data product. Consumes deployed Core interfaces through dbt Mesh and owns finance reporting logic. |
| `setup/` | Snowflake setup, deterministic raw-data generation, loading guidance, demo mutations, freshness rebasing, and cleanup utilities. |

Raw CSV data is generated outside dbt and loaded into `CORE_RAW`. Core transforms that data through source, staging, intermediate, and public mart layers. Finance references only Core's deployed public models and adds finance-owned valuation, receivables, and semantic definitions.

Folders describe modeling role and ownership. Explicit dbt configuration controls physical Snowflake placement.

## dbt Mesh and data products

The repository demonstrates a real two-project dbt Mesh deployment:

- `demo_core` publishes public, contracted models.
- `demo_finance/dependencies.yml` declares `demo_core` as a project dependency.
- Finance uses project-qualified refs such as `ref('demo_core', 'invoices')`.
- Finance does not import or build Core source code.
- dbt resolves cross-project refs from deployed public-model metadata.
- Core Production must run successfully before Finance Production when Core or shared resources change.

Access boundaries reinforce the product contract:

- Staging models are private.
- Intermediate models are protected.
- Public marts are public.

## Core data product

### Source systems

Core models five source domains in `CORE_RAW`:

- CRM: accounts, contacts, opportunities, and sales representatives.
- Billing: customers, subscriptions, invoices, invoice lines, payments, and refunds.
- Product: behavioral events.
- ERP: cost centers and general-ledger entries.
- Market: daily foreign-exchange rates.

### Modeling layers

Core follows a source-oriented and domain-owned structure:

1. Source YAML declares raw relations, freshness behavior, and source metadata.
2. Staging views clean and normalize source-specific fields.
3. Intermediate tables implement business logic by domain.
4. Public marts expose contracted interfaces for downstream projects.

The intermediate domains are sales, billing, product, finance operations, and conformed core entities.

### Governed public interfaces

| Model | Grain | Purpose |
|---|---|---|
| `customers` | One conformed customer | Combines CRM and Billing identities, including CRM-only and billing-only customers. |
| `subscriptions` | One subscription | Publishes governed plan, lifecycle, quantity, price, and service-period attributes. |
| `invoices` | One invoice | Reconciles invoice lines, payments, refunds, net collections, and receivables in source currency. |
| `fx_rates` | One date and source currency | Publishes daily USD rates with exact or prior-date observation provenance. |
| `gl_entries` | One journal line | Enriches ledger lines with chart-of-accounts, cost-center, invoice, and customer context. |

All public interfaces are tables with:

- Enforced contracts.
- Typed columns and required constraints.
- Grain and data-product metadata.
- Relation and column documentation.
- Key uniqueness and nullability tests.
- Core group ownership.

### Model versioning

`customers` demonstrates safe public-interface evolution:

- Version 2 is current.
- A latest-version pointer resolves unversioned refs to version 2.
- Version 1 remains as a deprecated CRM-focused compatibility contract.
- Version 1 is scheduled for deprecation on 2027-06-30.

### Conformed identity resolution

Core demonstrates cross-system customer matching between CRM accounts and Billing customers. Matching logic uses explicit IDs plus normalized business attributes such as company names and domains. The public `customers` model publishes one stable conformed customer identifier and records whether the customer exists in CRM, Billing, or both.

### Reusable macros and reference data

Core includes reusable macros for:

- String cleaning.
- Email normalization.
- Domain normalization.
- Company-name normalization.
- Country join keys.
- Surrogate keys.
- Environment-aware database and schema naming.

Governed seeds provide:

- Country-code mappings.
- Product plan catalog attributes.
- Chart-of-accounts classifications.

### Incremental model

The Core invoice intermediate model demonstrates merge-based incremental processing:

- Stable invoice unique key.
- Update timestamp watermark.
- Merge strategy for changed existing records.
- Dependency-aware CI cloning so existing incrementals exercise their incremental path.

### Type 2 snapshot

`snap_crm_accounts` tracks cleaned CRM account history using:

- YAML-defined snapshots.
- Timestamp strategy.
- `account_id` as the unique key.
- `updated_at` as the change timestamp.
- New history records for hard deletes.

### Product usage aggregation

Product events are cleaned and validated before being aggregated into daily account usage. Tests enforce valid identity, event timing, and daily grain.

### Finance operations

Core prepares finance-operational inputs without owning downstream presentation logic:

- Daily FX rates with prior-date fallback.
- General-ledger lines with account classifications.
- Journal balancing checks.
- Customer and invoice linkage.

Revenue recognition, profitability, USD reporting metrics, and other finance presentation logic belong in `demo_finance`.

## Finance data product

### Public receivables mart

`invoice_financials` is a contracted public mart at one row per invoice. It retains source-currency cents and reconciliation fields for auditability, then publishes major-unit and USD measures for:

- Invoice totals.
- Outstanding receivables.
- Successful payments.
- Refunds.
- Net collections.

USD invoices use an identity rate. Non-USD invoices use the governed issue-date FX rate and retain:

- FX observation date.
- FX provider.
- Prior-rate fallback indicator.

Tests enforce invoice grain, required fields, lifecycle values, and USD conversion behavior.

### Finance ownership and governance

All local Finance models belong to the Finance group. Project checks enforce that:

- Public Finance models are owned by Finance.
- Public Finance models enforce contracts.
- Protected and public Finance models use approved materializations.

The checks are scoped to local `demo_finance` resources so imported Core metadata is not incorrectly evaluated as Finance-owned code.

## Hosted dbt Semantic Layer

The Finance project uses the current dbt Semantic Layer specification directly on `invoice_financials`.

### Entities

- Invoice: primary entity.
- Customer: foreign entity.
- Subscription: foreign entity.

### Time dimensions

- Issue date, also used as the aggregation time dimension.
- Due date.
- Paid timestamp.

### Categorical dimensions

- Invoice lifecycle status.
- Source currency.
- Prior FX fallback indicator.
- FX provider.
- Reconciliation status.

### Governed metrics

1. `invoice_count`
2. `total_invoice_amount_usd`
3. `total_outstanding_receivable_amount_usd`
4. `total_successful_payment_amount_usd`
5. `total_refund_amount_usd`
6. `total_net_collections_amount_usd`

The hosted Semantic Layer is enabled against Finance Production and serves all six metrics.

### Time spine

`time_spine_daily` supplies the daily calendar required by MetricFlow:

- Daily grain.
- Coverage from 2020-01-01 through 2035-12-31.
- Unique and not-null tests.
- Protected access.
- Stored in the Finance configuration database under the `SEMANTIC` schema.

Permanent relations are deployed in both environments:

- `DEV_FINANCE_CONFIG.SEMANTIC.TIME_SPINE_DAILY`
- `PRD_FINANCE_CONFIG.SEMANTIC.TIME_SPINE_DAILY`

## Testing and data quality

The projects combine several testing patterns.

### Generic data tests

Tests cover:

- Uniqueness.
- Nullability.
- Accepted values.
- Relationships.
- Business expressions.
- Temporal and numeric boundaries.

### Singular tests

Custom SQL tests cover multi-row and cross-relation invariants, including:

- FX rate grain.
- Refund-to-payment integrity.
- One current snapshot record.
- Daily product usage grain.
- Balanced journals.
- One primary contact per account.
- Product-event identity and timing.
- Invoice-financial grain preservation.

### Unit tests

Unit tests isolate transformation behavior such as:

- Customer matching.
- Account mapping.
- Invoice normalization.
- FX exact-date and prior-date fallback.
- Finance source-currency-to-USD conversion.

### Contracts and constraints

Public interfaces use enforced contracts and typed columns. Required business keys also carry database-level not-null constraints where appropriate.

### Warning and error behavior

The standard generated data intentionally contains explainable anomalies. Warning-level tests surface these records without blocking Production:

- Unknown CRM countries.
- Rogue invoice statuses that staging normalizes.
- Unmatched payments.
- Customer-ID discrepancies.
- Invoice reconciliation differences.
- Prior-date FX fallback.
- One-cent journal imbalances.

Selected warning failures are persisted in configuration-database audit schemas for inspection. Error-level invariants remain deployment blockers.

## Project governance checks

Core includes SQL-based project checks that enforce:

- Every public Core model has an enforced contract.
- Every public Core model is owned by the Core group.
- Every staging model remains a view.

Finance includes checks that enforce:

- Every public Finance model has an enforced contract.
- Every public Finance model is owned by the Finance group.
- Finance protected and public models use approved materializations.

These checks make architecture rules executable instead of relying only on documentation.

## Deterministic demo data

The R generator creates 14 typed CSV datasets and does not connect to Snowflake or contain credentials. Generation is reproducible by:

- Scenario.
- Random seed.
- Scale factor.
- History window.
- As-of date.

Each run produces:

- One CSV per raw table.
- A file manifest with load strategy, keys, row counts, and run metadata.
- An anomaly manifest describing every deliberate defect and its expected dbt handling.
- A validation summary.

### Generator scenarios

| Scenario | Behavior |
|---|---|
| `clean` | Normal business variation without deliberate test anomalies. |
| `standard` | Realistic warning-level defects while preserving a successful Production build. |
| `broken` | Standard anomalies plus error-level defects for failure and troubleshooting demos. |

The generated data includes seasonality, soft deletes, late events, multiple currencies, mixed time zones, customer identity mismatches, subscription lifecycle variation, invoice edge cases, payments and refunds, ERP journals, and incomplete daily FX observations.

## Incremental and snapshot demonstration utility

`setup/incremental_demo.sql` provides a reversible warehouse mutation workflow.

It can:

- Create guarded zero-copy backup clones.
- Insert new invoices and product events.
- Mark existing invoices as paid and insert balancing payments.
- Upgrade and downgrade subscriptions.
- Soft-delete CRM accounts.
- Change CRM account attributes for snapshot history.
- Verify settlement and timestamp invariants.
- Restore raw tables from their clones.
- Remove all temporary backup objects.

The mutation steps are idempotent and use `demo_` keys so they do not collide with generated records.

## Source freshness

Every raw table carries `_loaded_at`. The standard baseline is designed to produce:

| Source | Approximate age | Expected result |
|---|---:|---|
| CRM | 2 hours | Fresh |
| Billing | 2 hours | Fresh |
| Product | 1 hour | Fresh |
| ERP | 8 hours | Fresh |
| Market FX | 30 hours | Warning |

Market FX warns after 24 hours and errors after 48 hours. A healthy demo freshness run therefore returns one intentional warning and no error-level failures.

`setup/rebaseline_loaded_at.sql` shifts timestamps to preserve these relative ages on the day of a demonstration. Because the repository uses static demo data, the freshness schedule remains off unless raw data is reloaded or rebaselined regularly.

## Snowflake architecture

| Database | Purpose |
|---|---|
| `CORE_RAW` | Source data loaded outside dbt; read-only to dbt roles. |
| `DEV_CORE_SLV` / `PRD_CORE_SLV` | Core staging, intermediate, and public models. |
| `DEV_CORE_CONFIG` / `PRD_CORE_CONFIG` | Core seeds, snapshots, and persisted test failures. |
| `DEV_FINANCE_GLD` / `PRD_FINANCE_GLD` | Finance public marts. |
| `DEV_FINANCE_CONFIG` / `PRD_FINANCE_CONFIG` | Finance Semantic Layer infrastructure and audit failures. |

Supported dbt targets are exactly `DEV`, `TST`, and `PRD`.

Custom naming macros map logical databases to:

- `DEV_*` for DEV and TST.
- `PRD_*` for PRD.

TST uses pull-request-specific temporary schemas in DEV databases and defers unchanged resources to Production. dbt must not run as `ACCOUNTADMIN`.

### Finance physical footprint

Active Finance relations are intentionally limited to:

- `FINANCE_GLD.RECEIVABLES.INVOICE_FINANCIALS`
- `FINANCE_CONFIG.SEMANTIC.TIME_SPINE_DAILY`
- `FINANCE_CONFIG.AUDIT` for persisted test failures

Retired empty MRR, Revenue, and Retention schemas have been removed from DEV and PRD. The cleanup script uses restricted drops so unexpected objects block cleanup instead of being deleted.

## dbt Platform environments

Six environments are configured:

| Project | Environment | Type |
|---|---|---|
| Core | Demo Core Development | Development |
| Core | Core CI | General |
| Core | Core Production | Production |
| Finance | Finance Development | Development |
| Finance | Finance CI | General |
| Finance | Finance Production | Production |

CI environments use target `TST`, DEV databases, pull-request-specific schemas, and Production deferral.

## dbt Platform jobs

Five jobs are configured and validated:

| Project | Job | Purpose |
|---|---|---|
| Core | Pull Request CI | Lint, clone existing incrementals, and build modified resources plus downstream dependents. |
| Core | Production | Build and publish the Core Production manifest and public Mesh interfaces. |
| Core | Source Freshness | Evaluate raw-source freshness independently of the main deployment. |
| Finance | Pull Request CI | Lint, clone/build modified resources, and validate the Semantic Layer. |
| Finance | Production | Deploy the Finance mart, Semantic Layer metadata, and time spine. |

Failure-email notifications are enabled for all jobs.

### State-aware CI

The validated CI flow uses state selection and Production deferral:

1. SQL linting runs first and stops the job on error.
2. `dbt clone` creates CI copies of modified existing incrementals so their incremental paths are tested.
3. `dbt build --select state:modified+` builds modified resources and downstream dependents.
4. Unselected parents defer to the latest successful Production state.
5. Finance CI also runs Semantic Layer validation.

Core CI is intentionally classified as General rather than Staging because pull-request relations are temporary and removed during cleanup.

## Monorepo behavior

Both dbt Platform projects attach to the same repository with different project subdirectories.

Native dbt Platform pull-request automation does not filter by changed subdirectory, so a repository pull request can trigger both projects. The repository guidance documents GitHub Actions path filters plus the dbt Administrative API as the selective orchestration pattern:

- Changes under `demo_core/**` trigger Core TST and any required downstream Finance validation.
- Changes under `demo_finance/**` trigger Finance TST only.
- Shared or setup changes trigger both when appropriate.

Production deployment remains ordered: Finance follows a successful Core Production run when Core or shared resources changed.

## Documentation and observability

Both projects persist relation and column descriptions to supported Snowflake objects. Query comments append the dbt project and node identifier to warehouse queries for traceability.

The repository follows these documentation conventions:

- One YAML file per model with the same basename as its SQL file.
- One YAML file per source system.
- Public interface terms are reused through dbt docs blocks where appropriate.
- Project-specific architecture and operating guidance lives in each project's `README.md` and `AGENTS.md`.

## Demonstration stories

This repository supports demonstrations of:

- A real two-project dbt Mesh.
- Cross-project refs and deployed public-model metadata.
- Public, protected, and private access boundaries.
- Domain groups and ownership.
- Contracts, constraints, and persisted documentation.
- Public-model versioning and deprecation.
- Cross-system identity resolution.
- Incremental merge processing.
- Type 2 snapshots and delete history.
- Generic, singular, and unit tests.
- Warning-level observability versus error-level gates.
- Source freshness warnings and failures.
- Slim CI, state selection, clone, and deferral.
- Environment-aware Snowflake naming.
- Deterministic clean, standard, and broken data scenarios.
- Reversible warehouse mutation demos.
- Finance FX conversion with provenance and auditability.
- A hosted Semantic Layer with entities, dimensions, metrics, and a time spine.
- Governance checks expressed as executable project rules.

## Validated operational state

The implementation has been validated through successful Development, CI, and Production executions:

- Core Production publishes the Mesh metadata required by Finance.
- Core CI passes with Production deferral.
- Finance CI passes after correctly scoping governance checks to local Finance models.
- Finance Production deploys the receivables mart and Semantic Layer.
- The dedicated freshness job passes with 13 fresh sources and one intentional Market FX warning.
- DEV and PRD Finance time-spine tables are present.
- Retired Finance schemas are absent.
- Hosted Semantic Layer serves all six Finance metrics.

## Useful setup and operations files

| File | Purpose |
|---|---|
| `setup/snowflake_setup.sql` | Creates Snowflake roles, grants, databases, schemas, and supporting objects. |
| `setup/raw_table_ddl.sql` | Defines the 14 raw tables and CSV file format. |
| `setup/generate_raw_data.R` | Generates deterministic raw CSV data and anomaly manifests. |
| `setup/load_raw_data.md` | Documents loading through Snowsight. |
| `setup/rebaseline_loaded_at.sql` | Repositions ingestion timestamps for freshness demos. |
| `setup/incremental_demo.sql` | Mutates and restores raw data for incremental and snapshot demos. |
| `setup/cleanup_finance_schemas.sql` | Safely removes retired empty Finance schemas. |
| `setup/raw_data_spec.md` | Defines source grains, keys, distributions, anomalies, and expected dbt handling. |
