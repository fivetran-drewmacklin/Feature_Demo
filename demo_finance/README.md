# demo_finance

`demo_finance` is the downstream gold project in this dbt Mesh demo. It consumes governed public interfaces from `demo_core` and owns finance business logic such as recurring revenue, revenue recognition, receivables, retention, USD reporting, and profitability.

## Mesh dependency

The project dependency is declared in `dependencies.yml`. Finance models must use project-qualified refs:

```text
{{ ref('demo_core', 'invoices') }}
```

Allowed upstream interfaces are `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`. `demo_finance` does not build or import the upstream project's source code; dbt resolves these refs from deployed public-model metadata.


## Finance marts

`invoice_financials` is the first public finance mart. It preserves one row per core invoice, retains source-currency cents and reconciliation fields for auditability, and publishes source-currency and issue-date USD amounts for invoice totals, outstanding receivables, successful payments, refunds, and net collections. USD invoices use an identity rate; non-USD invoices retain the governed FX observation date, provider, and prior-rate fallback flag from `demo_core.fx_rates`.

The mart is enabled as a latest-spec semantic model with invoice, customer, and subscription entities; issue, due, and paid time dimensions; lifecycle and FX dimensions; and governed metrics for invoice count, total invoiced, outstanding receivables, successful payments, refunds, and net collections in USD. `time_spine_daily` provides the protected daily calendar required by MetricFlow.

## Environment mapping

Logical databases are mapped by target:

| Target | `FINANCE_GLD` | `FINANCE_CONFIG` |
| --- | --- | --- |
| `DEV` | `DEV_FINANCE_GLD` | `DEV_FINANCE_CONFIG` |
| `TST` | `DEV_FINANCE_GLD` | `DEV_FINANCE_CONFIG` |
| `PRD` | `PRD_FINANCE_GLD` | `PRD_FINANCE_CONFIG` |

TST preserves dbt Platform's pull-request-specific schema. Production finance deployment must run after a successful `demo_core` production deployment.


## Physical layout

Active Finance relations are intentionally limited to:

- `FINANCE_GLD.RECEIVABLES.INVOICE_FINANCIALS` for the public receivables mart.
- `FINANCE_CONFIG.SEMANTIC.TIME_SPINE_DAILY` for shared Semantic Layer infrastructure.
- `FINANCE_CONFIG.AUDIT` for persisted dbt test results.

Environment-aware database naming maps these logical databases to `DEV_*` for `DEV` and `TST`, and `PRD_*` for `PRD`. Empty MRR, revenue, and retention schemas are not pre-created; add each domain config and schema with its first implemented model.

After deploying the time-spine move in both environments, run `setup/cleanup_finance_schemas.sql` with an authorized Snowflake operator. The script uses restricted drops so unexpected objects block cleanup instead of being deleted.

## Deployment controls

Finance CI must be attached to the General `Finance CI` environment, use target `TST`, use `DBT_DEV_ROLE2`, write to `DEV_FINANCE_GLD`, and defer to `Finance Production`. The CI job runs clone, state-modified build, Semantic Layer validation, and SQL linting with lint failures treated as errors.

Because both dbt projects share one repository, native pull-request CI triggers both projects for any pull request. This is an accepted demo tradeoff. Production jobs remain manual unless an explicit orchestration trigger is configured; Finance Production must follow a successful Core Production run for core or shared changes.
