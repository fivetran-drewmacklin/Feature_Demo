# demo_finance guidance

## Scope

`demo_finance` is the downstream gold project in this dbt Mesh demo. It consumes only public, contracted `demo_core` models through cross-project refs and owns finance business logic, reporting marts, and governed finance metrics.

## Architecture

- dbt project name: `demo_finance`.
- Logical output databases: `FINANCE_GLD` and `FINANCE_CONFIG`.
- Physical databases use `DEV_*` for `DEV` and `TST`, and `PRD_*` for `PRD`.
- Targets are exactly `DEV`, `TST`, and `PRD`.
- Use `DBT_DEV_ROLE2` for development and CI and `DBT_PRD_ROLE` for production; never run dbt as `ACCOUNTADMIN`.
- Intermediate models are ownership-oriented under `models/intermediate/<domain>/` and are protected tables by default.
- Public finance marts live under `models/marts/<domain>/`, use plural business nouns, and must be contracted tables or incrementals.
- Supported finance domains are `mrr`, `revenue`, `receivables`, and `retention`.

## Mesh boundary

- Declare `demo_core` in `dependencies.yml` as a project dependency.
- Use two-argument refs such as `ref('demo_core', 'invoices')`.
- Consume only `demo_core` public interfaces: `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`.
- Do not duplicate core cleaning, identity matching, invoice reconciliation, FX fallback, or account-classification logic.
- Production finance runs must follow a successful core production run so current public-model metadata is available.

## Semantic layer and exposures

- Define the latest Semantic Layer spec only on local finance gold models after their grains and business definitions are stable.
- Do not attach latest-spec semantic models directly to cross-project resources.
- Add exposures only for real dashboards, notebooks, applications, or ML workflows with real owners and URLs.

## Progress

- Phase 1 — Mesh foundation: completed. `demo_core` resolves from its Production environment after the PR-only `Core CI` environment was classified as General instead of Staging; `dbt deps` and a cold parse succeed on dbt v2 Stable 2.0.8.
- Phase 2 — First finance mart: completed. Public contracted `invoice_financials` preserves one-invoice grain from `demo_core.invoices`, joins governed issue-date rates from `demo_core.fx_rates`, retains source audit fields and FX provenance, and publishes source-currency and USD amounts for invoicing, receivables, payments, refunds, and net collections. Dependency-aware DEV build, unit conversion scenarios, structural tests, status checks, and cross-project grain reconciliation pass.
