# One governed foundation, multiple approved definitions

## Presenter sequence — 24 minutes

Keep production on `main`. Use October 2026 with identical issue-date filters in Sheets, Claude, and Studio. Refresh connectors after deployment; connector rendering and editor underlines require presenter rehearsal.

1. **Semantic Layer (7 minutes):** show Revenue Official and Sales Approved Revenue side by side in Sheets, then ask Claude to discover their definitions and query the same month. Finance owns Official, Sales owns Sales Approved, and Engineering maintains both. Both sum tax-inclusive invoices with `status = 'paid'`, round each invoice to two decimals, report USD, and group by issue date. These are demo paid-invoice definitions, not GAAP recognition or net cash collections.
2. **v2 Stable (7 minutes):** switch to `demo/v2-errors` for three independent, always-active SQL diagnostics and a deliberate project-check violation. Use compile/check only on this branch. Return to `main` for healthy column lineage and test batching.
3. **Wizard (7 minutes):** create a clean development branch from updated `main` and add a new outstanding-invoices metric live. Do not pre-create this enhancement or deploy it during the demo.
4. **Wrap (3 minutes):** shared governed inputs, explicit business definitions, and earlier feedback on SQL and project rules.

## Revenue definitions

| Metric / label | Owner | Amount and FX policy |
| --- | --- | --- |
| `revenue_official` / Revenue Official | Finance | `invoice_amount_payment_fx_usd`; payment-date FX, latest rate on or before the date of `paid_at`. Leadership's official demo definition. |
| `sales_approved_revenue` / Sales Approved Revenue | Sales | `invoice_amount_usd`; governed issue-date FX, insulating Sales performance from later currency movements. |

Both live under `models[].metrics` in `models/marts/receivables/invoice_financials.yml`. Show the shared paid-status filter, `expr`, and structured `config.meta` fields. Finance's `fx_policy` is `payment_date`; Sales' is `invoice_issue_date`. Invoice issuance is the demo's sales event, not contract signing. Keep issue-date grouping for both so FX policy is the only difference. The Semantic Layer preserves both approved perspectives and identifies Finance's as official.

`payment_fx_rate_to_usd` is the selected rate. `payment_fx_rate_date` records the actual FX observation date, including prior observations carried forward by Core. USD uses identity rate 1 and the payment date. Payment valuation is null for unpaid invoices, with paid-only not-null tests. Later rates never enter an earlier payment's valuation.

Claude prompt:

```text
Discover revenue_official and sales_approved_revenue in the dbt Semantic Layer.
Explain their owners, tax treatment, shared paid-invoice population, issue-date
time basis, Finance's payment-date FX policy, and Sales' issue-date FX policy.
Query both for October 2026 using identical filters. Explain the difference
without calling it sales growth. State which environment you queried.
```

Studio query:

```text
dbt sl query --metrics revenue_official,sales_approved_revenue --group-by metric_time__month --where "{{ TimeDimension('metric_time', 'day') }} >= '2026-10-01' and {{ TimeDimension('metric_time', 'day') }} < '2026-11-01'"
```

Re-run this query in DEV after the FX-policy swap, then reconfirm against production after deployment. The scope is October 1 inclusive through November 1 exclusive. Do not reuse figures from the previous metric assignments. The installed CLI does not accept `--start-time` / `--end-time`.


## Column-level lineage

On `main`, open `invoice_financials.sql` and inspect the column-level lineage UI:

- `demo_core.invoices.total_cents` and `demo_core.fx_rates.rate` joined on `issue_date` and currency → `fx_rate_to_usd` → `invoice_amount_usd` → `sales_approved_revenue`.
- `demo_core.invoices.total_cents`, `paid_at`, currency and paid status plus `demo_core.fx_rates.rate` selected by latest `rate_date <= date(paid_at)` → `payment_fx_rate_to_usd` → `invoice_amount_payment_fx_usd` → `revenue_official`.
- `demo_core.fx_rates.source_rate_date` → `payment_fx_rate_date`; USD uses `date(paid_at)`.


Both amounts use `round(total_cents / 100.0 * rate, 2)`. Model-level DAGs are not column-level lineage. Local cross-project lineage may stop at Core's published interface; do not promise its internals are loaded.

```text
dbt compile --select +invoice_financials --static-analysis strict
```

## Error-demo isolation

Only `demo/v2-errors` may contain intentional SQL errors and the check violation. Production runs must explicitly use `main`. Do not merge the error branch.

The branch handoff records the actual paths, independent strict-compile commands, observed diagnostic codes, and check failure. Use one always-active analysis per error so each file contains only one visible problem; analyses avoid creating invalid warehouse models or expanding the mart build graph. Studio live underlines still need visual rehearsal.

The three cases are:

- Misspelled Finance column: `invoice_amout_usd`.
- Mesh boundary: `invoice_amount_usd` selected from `ref('demo_core', 'invoices')`, which publishes source amounts, not Finance USD valuation.
- Type mismatch: numeric `invoice_amount_usd > array_construct(1, 2)`.

Strict analysis may connect to Snowflake for schema metadata, but does not execute the invalid model query. Inspect node diagnostics as well as the command summary; wrapper success/warnings may differ from individual node status.

## Existing project checks

```text
dbt check
```

- `checks/public_models_owned_by_finance.sql`: every public local Finance model belongs to the finance group.
- `checks/public_models_enforce_contracts.sql`: every public local Finance model enforces a contract.
- `checks/finance_models_use_approved_materializations.sql`: Finance public models are tables/incrementals and protected models are tables.

The demo branch adds a small protected Finance view solely to violate the materialization rule. The handoff records the observed failure and whether the SQL errors interfere with check execution.

## Batched tests — run on main

```text
dbt test --select invoice_financials,test_type:generic --force-node-selection
dbt test --select invoice_financials,test_type:generic --force-node-selection --batch-tests
```

Count executed generic tests from the current output; do not reuse an older count. Look for `aggregated_not_null_...` runtime SQL as evidence of batching. The new paid-only tests have a `where` filter, so do not assume they join the default-config not-null batch. A single unique test and accepted-values test are not proof of batching. The first command uses the current default; do not promise it is unbatched if account defaults change. Do not promise fixed runtime savings on this small fixture.

## Live outstanding-invoices enhancement

The current-state mart has enough information for a current collectible open-invoice metric: one invoice per row, `status = 'open'`, and `amount_due_cents` / `outstanding_receivable_amount_usd`. The lifecycle values are `draft`, `open`, `paid`, `uncollectible`, and `void`. Do not filter merely `status <> 'paid'`, which would include drafts, voids, and write-offs. Decide explicitly whether the audience means invoice count, invoice face value, or remaining receivable balance.

An existing metric, `total_outstanding_receivable_amount_usd`, already sums current balances across the mart. Preserve it. The new open-invoice demo metric must remain absent until the live segment. Historical month-end outstanding balances need payment/status history; issue-month grouping of today's open invoices is not an as-of snapshot.

Suggested live prompt:

```text
Work only in demo_finance on a clean development branch from main. Add a
Semantic Layer metric named outstanding_invoice_count, label Outstanding
Invoice Count, counting invoices with status = 'open'. Finance owns it and
Engineering maintains it. Document that it measures current collectible open
invoices grouped by issue date, not historical month-end balances. Preserve
all existing columns, contracts, tests, and metrics. Read project guidance and
the Semantic Layer skill, validate with a cold parse and dbt sl validate, and
query it in DEV with dbt sl query. Do not commit, merge, or deploy.
```

## Validation and rehearsal gates

Payment-FX preparation must pass cold parse, dependency-aware build, strict compile, all project checks, and Semantic Layer validation. Compare the development mart to production when the state baseline is available; disclose any compare limitation. Verify October metric values again after production deployment.

Presenter-only gates: refresh Sheets/Claude metadata, compare identical filters, visually inspect Studio underlines and column-level lineage, and rehearse switching branches. Returning to `main` removes the intentional errors. Never run production from `demo/v2-errors`.

## Reference docs

- [Batch tests](https://docs.getdbt.com/reference/global-configs/batch-tests)
- [Static analysis](https://docs.getdbt.com/docs/build/about-static-analysis)
- [Column-level lineage](https://docs.getdbt.com/docs/explore/column-level-lineage)
- [Latest Semantic Layer spec](https://docs.getdbt.com/docs/build/latest-metrics-spec)
