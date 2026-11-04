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
| `revenue_official` / Revenue Official | Finance | `invoice_amount_usd`; governed issue-date FX. |
| `sales_approved_revenue` / Sales Approved Revenue | Sales | `invoice_amount_payment_fx_usd`; payment-date FX, latest rate on or before the date of `paid_at`. |

Both live under `models[].metrics` in `models/marts/receivables/invoice_financials.yml`. Show the shared paid-status filter, `expr`, and structured `config.meta` fields. Sales' `fx_policy` is exactly `payment-date FX`.

`payment_fx_rate_to_usd` is the selected rate. `payment_fx_rate_date` records the actual FX observation date, including prior observations carried forward by Core. USD uses identity rate 1 and the payment date. Payment valuation is null for unpaid invoices, with paid-only not-null tests. Later rates never enter an earlier payment's valuation.

Claude prompt:

```text
Discover revenue_official and sales_approved_revenue in the dbt Semantic Layer.
Explain their owners, tax treatment, shared paid-invoice population, issue-date
time basis, and issue-date versus payment-date FX policies. Query both for
October 2026 using identical filters. Explain the difference without calling
it sales growth. State which environment you queried.
```

Studio query:

```text
dbt sl query --metrics revenue_official,sales_approved_revenue --group-by metric_time__month --where "{{ TimeDimension('metric_time', 'day') }} >= '2026-10-01' and {{ TimeDimension('metric_time', 'day') }} < '2026-11-01'"
```

This command passed in DEV on v2 Stable 2.0.11: Revenue Official = $4,360,747.09 and Sales Approved Revenue = $4,360,272.67. The scope is October 1 inclusive through November 1 exclusive. Reconfirm against production after deployment; the installed CLI does not accept `--start-time` / `--end-time`.


## Column-level lineage

On `main`, open `invoice_financials.sql` and inspect the column-level lineage UI:

- `demo_core.invoices.total_cents` and `demo_core.fx_rates.rate` joined on `issue_date` and currency → `fx_rate_to_usd` → `invoice_amount_usd` → `revenue_official`.
- `demo_core.invoices.total_cents`, `paid_at`, currency and paid status plus `demo_core.fx_rates.rate` selected by latest `rate_date <= date(paid_at)` → `payment_fx_rate_to_usd` → `invoice_amount_payment_fx_usd` → `sales_approved_revenue`.
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


## Rehearsal record — 2026-11-04, v2 Stable 2.0.11

### Production-safe baseline

Payment-date FX was merged from `demo/payment-date-fx` to `main` and deployed by Finance Production run `70403232082308`, commit `2520a1d1f44edb95043709641e9f8a2ad22cc560`. The run explicitly selected `main`, successfully built all three local models, passed all data/unit tests and project checks, validated the Semantic Layer, generated the catalog, and ran the October `dbt sl query` above.

The deployed production Semantic Layer independently returned:

| Metric | Label | October 2026 USD |
| --- | --- | ---: |
| `revenue_official` | Revenue Official | 4,360,747.09 |
| `sales_approved_revenue` | Sales Approved Revenue | 4,360,272.67 |

Both use invoice issue month and paid invoices. DEV returned the same values. The existing outstanding-receivables metric remains; no new outstanding-invoices metric was created.

The payment-FX branch passed `dbt parse --no-partial-parse`, `dbt build --select +invoice_financials --defer`, `dbt compile --select +invoice_financials --static-analysis strict`, `dbt check`, and `dbt sl validate`. The slice build passed one model, 13 data tests (12 generic plus invoice-grain reconciliation), and two unit tests. A DEV data profile verified all 1,901 paid invoices have the three payment-FX values, all other statuses have null payment valuation, and no FX observation date is later than payment.

### Independent SQL errors — demo/v2-errors only

All paths below are relative to `demo_finance/`. Each analysis has inline strict-analysis config, contains one always-active error, and needs no var. Analyses keep the invalid SQL outside the warehouse model graph. Open all three in Studio before the demo and verify the editor underlines visually; CLI node diagnostics were verified, UI rendering cannot be certified by the command tools.

```text
dbt compile --select path:analyses/demo_v2_misspelled_column.sql --static-analysis strict
dbt compile --select path:analyses/demo_v2_mesh_boundary.sql --static-analysis strict
dbt compile --select path:analyses/demo_v2_type_mismatch.sql --static-analysis strict
```

| Analysis | Observed diagnostic |
| --- | --- |
| `analyses/demo_v2_misspelled_column.sql` | `UnresolvedIdentifier (dbt0227)`: `No column INVOICE_AMOUT_USD found in the locally cached schema for the source in DEV_FINANCE_GLD.RECEIVABLES.INVOICE_FINANCIALS`. |
| `analyses/demo_v2_mesh_boundary.sql` | `UnresolvedIdentifier (dbt0227)`: `No column INVOICE_AMOUNT_USD found in the locally cached schema for the source in PRD_CORE_SLV.CORE.INVOICES`. Finance, not Core, owns USD valuation. |
| `analyses/demo_v2_type_mismatch.sql` | `InvalidComparison (dbt0407)`: `Comparison failed: Comparison between NUMBER(38,2) and ARRAY with > operator is not supported`. |

Each command reported `Summary 1 total | 1 error` and an errored analysis node. **Important wrapper behavior:** the overall invocation reports success-with-warnings, so do not promise a nonzero exit or a red invocation badge. Show the failed node and its diagnostic. The unresolved-column message suggests `dbt clean` generically; these columns really are absent, so cleaning is not the fix. Two additional `dbt1700` warnings come from Studio-injected legacy compile options, not these fixtures.

### Deliberate project-check failure

`models/intermediate/receivables/int_receivables__check_violation.sql` configures a protected Finance model as a view; the existing rule requires protected Finance models to be tables. Its matching YAML documents its branch-only purpose. This fixture was never materialized.

```text
dbt check
```

Observed key output:

```text
Failed check finance_models_use_approved_materializations
Error [CheckFailed (dbt1650)]: check 'finance_models_use_approved_materializations' failed with 1 violation(s)
model.demo_finance.int_receivables__check_violation
Passed check public_models_enforce_contracts
Passed check public_models_owned_by_finance
```

With all three SQL-error files present and before adding the view, `dbt check` passed all three checks. With the view present, check still executes and fails only the intended materialization rule. No exclusions or var toggles are needed. Cold parse also succeeds on the error branch.

All three checks pass on deployed `main`; production `run_results.json` records `pass` for each:

- `checks/finance_models_use_approved_materializations.sql`: Finance public models must be tables/incrementals and protected models must be tables.
- `checks/public_models_enforce_contracts.sql`: every public local Finance model must enforce its contract.
- `checks/public_models_owned_by_finance.sql`: every public local Finance model must belong to the finance group.

### Main-branch batching evidence

Both requested test commands were executed while checked out on `main`, against DEV, with 12/12 generic tests passing. The selection comprises ten not-null tests, one unique test, and one accepted-values test. The three paid-only not-null tests use `where` and are not part of the default-config batch.

The batched invocation logged:

```text
Writing runtime sql for node "test.demo_finance.aggregated_not_null_model_demo_ba447a739b26c366f73193c7f879bc2f"
Processed 12 data tests
Summary 12 total | 12 success
```

The unflagged invocation was `56e80450-2de1-4069-977e-cc6876d704ed`; the batched invocation was `cb432b2c-40f1-42bb-9fc5-4405175d7a0e`. Use command details/debug logs to show the aggregation; do not claim every test is batched or promise faster timing.

### Limitations to rehearse

- `dbt compare --select invoice_financials+ --defer` failed with `InvalidArgument (dbt1007): Compare command requires a state manifest (via --state, --defer-state, or dbt Cloud)`. No rendered production diff is claimed.
- Use the verified `--where` query, not unsupported `--start-time` / `--end-time` flags.
- Verify live editor underlines and column-level lineage manually, and refresh Sheets/Claude after deployment. Column lineage described above is grounded in the SQL; local Mesh lineage may stop at the published Core interface.
- Keep production on `main`. Never build, deploy, or merge `demo/v2-errors`. Return to `main` for healthy tests and the live metric enhancement.
