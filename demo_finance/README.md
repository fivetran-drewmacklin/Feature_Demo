# demo_finance

`demo_finance` is the downstream gold project in this dbt Mesh demo. It consumes governed public interfaces from `demo_core` and owns finance business logic such as recurring revenue, revenue recognition, receivables, retention, USD reporting, and profitability.

## Mesh dependency

The project dependency is declared in `dependencies.yml`. Finance models must use project-qualified refs:

```text
{{ ref('demo_core', 'invoices') }}
```

Allowed upstream interfaces are `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`. `demo_finance` does not build or import the upstream project's source code; dbt resolves these refs from deployed public-model metadata.

## Environment mapping

Logical databases are mapped by target:

| Target | `FINANCE_GLD` | `FINANCE_CONFIG` |
| --- | --- | --- |
| `DEV` | `DEV_FINANCE_GLD` | `DEV_FINANCE_CONFIG` |
| `TST` | `DEV_FINANCE_GLD` | `DEV_FINANCE_CONFIG` |
| `PRD` | `PRD_FINANCE_GLD` | `PRD_FINANCE_CONFIG` |

TST preserves dbt Platform's pull-request-specific schema. Production finance deployment must run after a successful `demo_core` production deployment.
