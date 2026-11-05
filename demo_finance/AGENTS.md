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
- Phase 3 — Semantic Layer foundation: completed. `invoice_financials` uses the latest nested semantic-model spec with invoice, customer, and subscription entities; issue, due, and paid time dimensions; lifecycle and FX dimensions; and six governed simple metrics. `invoice_customers` provides the primary customer entity and readable `customer_name` dimension for analyzing invoice metrics without exposing hashed identifiers to consumers. Protected `time_spine_daily` covers 2020-01-01 through 2035-12-31. Cold parse, model builds/tests, `dbt sl validate`, and end-to-end metric queries pass.

- Demo preparation — Revenue governance: `revenue_official` preserves Finance's issue-date-FX paid-invoice reporting; Sales owns `sales_approved_revenue` using payment-date FX, the latest governed rate on or before the date of `paid_at`. Engineering is technical owner. Preserve the tax-inclusive paid population and issue-date grouping for both. Payment valuation exposes `payment_fx_rate_to_usd`, `payment_fx_rate_date` (actual observation date), and `invoice_amount_payment_fx_usd`, null for unpaid invoices and tested not-null for paid invoices. Do not imply live quotes or GAAP recognition.
- Demo isolation: production-safe metrics, tests, and `DEMO_RUNBOOK.md` belong on `main`. Intentionally broken v2 SQL and deliberate check violations belong only on `demo/v2-errors`; never merge them to `main` or run production from this branch. Keep the live outstanding-invoices enhancement absent from the production baseline; the existing total-outstanding-receivables metric is preserved.
- Error-demo rehearsal (branch-only): `analyses/demo_v2_misspelled_column.sql`, `analyses/demo_v2_mesh_boundary.sql`, and `analyses/demo_v2_type_mismatch.sql` are always-active strict analyses; keep the errors intact. `models/intermediate/receivables/int_receivables__check_violation.sql` is deliberately a protected view and must fail `finance_models_use_approved_materializations`. Run compile/check only, never build or deploy this branch. `dbt check` remains runnable with the broken analyses. See `DEMO_RUNBOOK.md` for verified commands and wrapper-status caveats.
- Studio underline probes (error branch only): `analyses/demo_v2_probe_cte_misspelled_column.sql` and `analyses/demo_v2_probe_cte_type_mismatch.sql` are self-contained strict error examples; `analyses/demo_v2_probe_mesh_type_mismatch.sql` tests Core's published numeric interface. Presenter reported underlines appearing after creation/individual compilation. Preserve the original fixtures; see the runbook's Studio underline rehearsal section for the recommended presentation sequence and unconfirmed editor-root-cause caveat. `invoice_financials` explicitly requests strict analysis; no Core-wide strict change is required by this rehearsal.






## Physical schema lifecycle

- Keep active public finance marts in domain schemas under `FINANCE_GLD`; currently only `RECEIVABLES` is active.
- Keep shared Semantic Layer infrastructure such as `time_spine_daily` under `FINANCE_CONFIG.SEMANTIC`.
- Do not pre-create MRR, revenue, or retention schemas before their first models are implemented.
- After a model moves schemas and the replacement is deployed successfully, remove its orphaned relation explicitly; dbt does not drop the old relation.
- Preserve Snowflake's automatic `PUBLIC` schemas and manage their privileges instead of dropping them.

## Deployment baseline

- Finance CI is a General environment with target `TST`, role `DBT_DEV_ROLE2`, default database `DEV_FINANCE_GLD`, and deferral to `Finance Production`.
- Finance Production uses target `PRD`, role `DBT_PRD_ROLE`, and the `main` branch.
- Native PR webhooks run both monorepo projects for this demo; do not classify a PR-only environment as Staging.
- Run Finance Production after successful Core Production when core public interfaces or shared setup change.
- Production and CI jobs should have owners, failure notifications, and bounded timeouts; 15 minutes is the current Finance baseline.
