# One governed foundation, multiple approved definitions

## Audience and timing — 24 minutes

Technical dbt engineer, technical BI engineer, and VP of Engineering.

| Clock | Segment | Takeaway |
| --- | --- | --- |
| 00:00–01:00 | Frame the problem | Finance and Sales ask different legitimate questions about the same invoices. |
| 01:00–08:00 | Semantic Layer in Sheets and Claude | Govern definitions and ownership centrally; reuse them across tools. |
| 08:00–15:00 | v2 Stable | Catch SQL mistakes before executing model SQL, explain provenance, and batch compatible tests. |
| 15:00–22:00 | Wizard | Add a governed metric and semantic dimension with project context and validation. |
| 22:00–24:00 | Wrap and questions | Shared data, explicit choices, faster safe changes. |

## Numbered live-demo checklist — presenter view

Preparation status: the presenter reports that both Core and Finance PRD rebuilds are complete. Connector refresh, Sheets/Claude agreement, and visible column-level lineage remain presenter checks. Keep PRD on `main` throughout.

Use October 2026 only if confirmed during preflight; otherwise substitute the same populated period in Sheets and both Claude prompts. These connector queries use deployed data; the Wizard enhancement at the end uses DEV.

1. **Show the Google Sheet (about 2 minutes).** Start with **Revenue Official** (`revenue_official`) for October 2026. Keep **Sales Approved Revenue** (`sales_approved_revenue`) available beside it, using the same issue month and filters. Say: “These are approved definitions over the same invoices, with explicit ownership and FX policy.”

2. **Show Claude MCP agreeing with the official definition and Sheet (about 2 minutes).** Ask it to discover the governed definition before querying. Compare its monthly total with the same Sheet cell; a definition match and a number match are separate checks.

   ```text
   Discover revenue_official in the dbt Semantic Layer. Explain its owner,
   paid-invoice population, tax treatment, issue-date time basis, and FX policy.
   Query its total for October 2026 (2026-10-01 inclusive to 2026-11-01 exclusive),
   using the same filters as my Google Sheet. Use the governed metric rather
   than writing a new revenue calculation. State the environment queried.
   ```

3. **Ask Claude for the Sales team's approved definition (about 2 minutes).** Reveal/compare Sales Approved Revenue in Sheets for the identical scope.

   ```text
   Discover sales_approved_revenue and explain how Sales' approved definition
   differs from revenue_official. Query both governed metrics for the same
   October 2026 period and filters as before. Explain the FX valuation
   difference, who owns each metric, and when to use each. Do not describe the
   difference as sales growth or the rates as live. State the environment queried.
   ```

4. **Show where the definitions live (about 1 minute).** On `main`, open `demo_finance/models/marts/receivables/invoice_financials.yml` (project-relative: `models/marts/receivables/invoice_financials.yml`). Find `revenue_official` and `sales_approved_revenue` under `models[].metrics`. Show descriptions, the shared paid-status filter, `expr: invoice_amount_usd` versus `expr: invoice_amount_current_fx_usd`, and `config.meta` ownership/FX-policy fields. Finance owns Official; Sales owns Sales Approved; Engineering maintains both. Both include tax and group by issue date. This is demo paid-invoice reporting, not GAAP recognition or net collections.

5. **Switch to `demo/v2-errors` (about 30 seconds).** Use Studio Version control, then open `demo_finance/analyses/demo_v2_errors.sql` (project-relative: `analyses/demo_v2_errors.sql`). Explain that this branch isolates intentional errors from production. Leave the fixture unchanged; use compile only.

6. **Run the three strict-analysis cases, one at a time (about 3 minutes).** Show each analysis node's diagnostic, even if the Studio invocation is presented as successful with warnings.

   **Misspelled column:**

   ```text
   dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"typo"}' --static-analysis strict
   ```

   Expected: `UnresolvedIdentifier (dbt0227)` — no column `INVOICE_AMOUT_USD`; point out the missing “n” and available column suggestions.

   **Wrong side of the Mesh boundary:**

   ```text
   dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"upstream"}' --static-analysis strict
   ```

   Expected: `UnresolvedIdentifier (dbt0227)` — `INVOICE_AMOUNT_USD` is absent from core `invoices`; Finance owns USD valuation. Ignore the generic cache-refresh suggestion for this known fixture.

   **Incompatible types:**

   ```text
   dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"type"}' --static-analysis strict
   ```

   Expected: `InvalidComparison (dbt0407)` — `NUMBER(38,2) > ARRAY` is unsupported. Say: “v2 Stable catches these before executing the model SQL.” Metadata access may still require Snowflake.

7. **Return to `main` and show column-level lineage (about 2 minutes).** Open `models/marts/receivables/invoice_financials.sql` in the preflight-verified column-lineage UI. Trace `invoice_amount_usd` to invoice `total_cents` and issue-date FX; trace `invoice_amount_current_fx_usd` to the same amount and latest-rate selection. Say: “Same records, two explainable valuation paths.” If metadata needs regeneration, run:

   ```text
   dbt compile --select +invoice_financials --static-analysis strict --generate-info-schema
   ```

   Use the verified Studio, VS Code, or Catalog column-level experience. A model-level DAG is not a substitute; local cross-project lineage may stop at the published core interface.

8. **Demo batched testing on the healthy baseline (about 2 minutes).** Run both commands and show command details/logs:

   ```text
   dbt test --select invoice_financials,test_type:generic --force-node-selection
   dbt test --select invoice_financials,test_type:generic --force-node-selection --batch-tests
   ```

   The preparation runs each passed 13 generic tests; the batched run showed an `aggregated_not_null_...` runtime query. Show that grouped query as the evidence. `--force-node-selection` prevents State reuse from skipping the demonstration. The first command uses the current default; verify batching is not already enabled before calling it an unbatched baseline. Do not use the unsupported `--no-batch-tests` flag or promise a fixed speedup.

9. **Demo Wizard in DEV (about 7 minutes).** From updated `main`, create/switch to clean `demo/wizard-revenue-context`; do not branch from `demo/v2-errors`. Open the finance YAML and paste this short prompt:

   ```text
   Add revenue_fx_difference, reusing the two governed metrics.
   Expose the existing FX source date as a semantic dimension.
   Validate and query the change in DEV.
   ```

   Supply the following clarification with the short prompt, or use the full prompt in Segment 3 below, so the intended calculation, source date, and safety boundaries are explicit:

   ```text
   Work only in demo_finance using the latest nested Semantic Layer YAML spec.
   Define revenue_fx_difference as sales_approved_revenue minus revenue_official;
   Finance owns it and Engineering maintains it. Describe it as FX valuation
   difference, not sales growth. Expose current_fx_rate_source_date as a time
   dimension with day granularity. Preserve issue_date as the default time basis,
   all existing metrics, SQL, contracts, and tests. Read project guidance and the
   Semantic Layer skill. Cold-parse, strict-compile, run dbt sl validate, then use
   dbt sl query in DEV for all three metrics by metric_time__month and
   invoice__current_fx_rate_source_date__day. Show the diff. Do not commit,
   push, merge, or deploy. Do not query deployed connectors for this DEV-only change.
   ```

   Show the small YAML diff, validation, and DEV query. Close: “We reused governed metrics and added provenance context without inventing another revenue SQL calculation.” Keep the live enhancement off `main`; reset only its changes after the demo. Allow about two minutes for wrap/questions to keep the full demo within 20–25 minutes.


## Branch and deployment safety

- `main`: production-safe revenue definitions, model columns, tests, and this runbook. No intentional SQL errors. The live Wizard enhancement is intentionally absent.
- `demo/v2-errors`: same baseline plus `analyses/demo_v2_errors.sql`. Never merge this branch into `main`; never point PRD at it. Use compile only for its fixture.
- Create `demo/wizard-revenue-context` from updated `main` for the live Wizard segment. Do not create it from the errors branch.
- Switch between clean branches through Studio's Version control UI. If a branch has uncommitted work, stop and preserve it before switching. Do not discard unrelated work.

## Pre-demo checklist (outside the 24 minutes)

1. Ensure the production-safe commit is on remote `main`.
2. Rebuild Core Production first if refreshing both projects, then Finance Production from `main`. Finance depends on Core's published Mesh metadata. Do not run PRD from `demo/v2-errors`.
3. Confirm the Finance deployment completes its build and Semantic Layer validation/publication. Refresh the Sheets metric picker and Claude's tool metadata/session as needed.
4. Verify `revenue_official` and `sales_approved_revenue` are available and `revenue` is absent. Existing Sheets selections of `revenue` must be changed explicitly; there is no compatibility alias.
5. In Sheets, prepare both metrics grouped by issue month with the same filters. For a focused live example, use October 2026 (2026-10-01 inclusive through 2026-11-01 exclusive). Verify that period still has data after the rebuild; change the period if the fixture is regenerated. Use the same period in Claude.
6. Open the metric YAML, invoice model SQL, v2 error fixture on its branch, and this runbook in advance. Have the Google Sheet and Claude connection ready.
7. Rehearse the editor's column-lineage UI in your account. Strict compilation and lineage metadata generation have been tested; the visible editor experience still requires a human UI check. If Studio does not expose column-level lineage, use the dbt VS Code extension's View Lineage → Show column lineage, or Catalog after the PRD refresh. Do not substitute a model-level DAG and call it column lineage.
8. Rehearse the Wizard prompt below on a clean branch, then reset only its changes. Production connectors will not see an undeployed DEV change. Use `dbt sl query` in Studio for the live enhancement.
9. Do not include a live v2 upgrade on this already-v2 project. If asked, explain that migration belongs in a separate legacy fixture.

## Segment 1 — Semantic Layer (7 minutes)

Opening: “One source of truth means shared, governed definitions—not forcing every team to answer a different question with the same metric.”

Both revenue metrics use the same one-invoice finance mart, `status = 'paid'`, tax-inclusive invoice total, USD reporting currency, per-invoice rounding, and issue-date grouping. The only intended difference is FX valuation policy.

| Metric ID / label | Business owner | Policy and appropriate use |
| --- | --- | --- |
| `revenue_official` / Revenue Official | Finance | Issue-date FX; official historical paid-invoice reporting. Preserves the former `revenue` calculation. |
| `sales_approved_revenue` / Sales Approved Revenue | Sales | Latest available FX per currency on or before the table build date; Sales current-FX comparisons. |

Engineering is the technical owner for both. Open `models/marts/receivables/invoice_financials.yml` and show descriptions plus `config.meta.owner`, `business_owner`, `technical_owner`, `intended_use`, `fx_policy`, and `related_metric`.

1. Show the two values side by side in Sheets, with the same month and filters.
2. Ask Claude to discover the definitions before querying. Prompt:

```text
Find revenue_official and sales_approved_revenue in the dbt Semantic Layer.
Explain who owns each, when to use it, and how the FX policies differ.
Then query both for October 2026 by source currency using identical filters.
Use the governed metrics, not a new revenue calculation. Explain the difference
without calling it sales growth, and state the environment you queried.
```

3. Compare the same scope in Sheets and Claude. Do not compare a Sheets monthly total with a differently filtered Claude total.
4. Close: “Sales has flexibility without copying Finance's logic into another spreadsheet.”

Caveats worth saying once: this is a demo paid-invoice revenue definition, not GAAP revenue recognition or net collections. Latest available FX does not mean a live quote. Current valuation is fixed until the table rebuilds; `current_fx_rate_source_date` and `fx_valuation_date` make that visible. USD always uses rate 1. The finite fixture can have stale rates.

## Segment 2 — v2 Stable (7 minutes)

### A. Strict static analysis — about 3 minutes

Switch to `demo/v2-errors`. The analysis fixture selects one problem per invocation so diagnostics cannot mask each other. It is disabled unless `v2_error_case` is provided. Leave the SQL errors intact.

Run these in Studio's command bar, one at a time:

```text
dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"typo"}' --static-analysis strict
dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"upstream"}' --static-analysis strict
dbt compile --select path:analyses/demo_v2_errors.sql --vars '{"v2_error_case":"type"}' --static-analysis strict
```

| Case | Intentional mistake | Rehearsed diagnostic | Narration |
| --- | --- | --- | --- |
| `typo` | `invoice_amout_usd` instead of `invoice_amount_usd` | `UnresolvedIdentifier (dbt0227)` | SQL-aware analysis identifies a misspelled column and available alternatives. |
| `upstream` | Selecting `invoice_amount_usd` from `ref('demo_core', 'invoices')` | `UnresolvedIdentifier (dbt0227)` | Mesh boundaries matter: core exposes source currency; Finance owns USD valuation. |
| `type` | `invoice_amount_usd > array_construct(1, 2)` | `InvalidComparison (dbt0407)` | A NUMBER-to-ARRAY ordering is invalid even though the SQL parses. |

These were reproduced on v2 Stable 2.0.9. In this Studio wrapper, a compile invocation can appear successful with warnings while the analysis node is marked errored. Show the node diagnostic and summary, not just the invocation status. The upstream diagnostic includes a generic schema-cache suggestion; the schema was inspected and the column really is absent, so do not spend demo time cleaning caches.

Say “before executing the model SQL,” not “without any warehouse connection.” Strict analysis may hydrate schema metadata from Snowflake. Studio also injects two unsupported legacy compile options (`--skip-write-msgpack-if-exist`, `--populate-cache`), producing unrelated warnings; they are not configuration errors in this repo.

### B. Column-level lineage — about 2 minutes

Return to the clean production baseline before the healthy-model demonstration. Open `invoice_financials.sql` and inspect lineage for:

- `invoice_amount_usd`: invoice `total_cents` plus issue-date `fx_rates.rate`.
- `invoice_amount_current_fx_usd`: the same invoice amount plus the latest-rate selection.

Narration: “Same business records, two explicit transformation paths. We can explain why the numbers differ.”

Strict lineage metadata generation was rehearsed with:

```text
dbt compile --select +invoice_financials --static-analysis strict --generate-info-schema
```

Use the verified editor/Catalog UI from preflight. Cross-project local lineage may stop at the published core interface; show the finance transformation and do not promise core internals are locally loaded.

### C. Batched tests — about 2 minutes

On the healthy baseline, run the same generic tests twice:

```text
dbt test --select invoice_financials,test_type:generic --force-node-selection
dbt test --select invoice_financials,test_type:generic --force-node-selection --batch-tests
```

Both were rehearsed with 13 passing generic tests. The batched invocation produced an `aggregated_not_null_...` runtime query. Show that query in command details/logs. Use generated SQL as read-only evidence; never edit it.

`--force-node-selection` prevents dbt State from reusing prior test results and hiding the batching demonstration. The installed build has no `--no-batch-tests` switch: the first command uses the current default. If account configuration later enables batching by default, reset that outside the demo before claiming an unbatched baseline.

Batching applies to compatible default-config `not_null`/`unique` tests on the same model, with at least two of a type. Tests with `where`, custom severities, thresholds, or stored failures are excluded. The single unique and accepted-values tests are not evidence of batching. Do not promise a fixed runtime or dollar saving on this small fixture.

## Segment 3 — Wizard (7 minutes)

Switch to a clean `demo/wizard-revenue-context` branch created from updated `main`. Open the finance YAML. The new metric and semantic date dimension must not already exist.

Paste this prompt into Wizard:

```text
Work only in demo_finance. Add a derived Semantic Layer metric named
revenue_fx_difference, label Revenue FX Difference, defined as
sales_approved_revenue minus revenue_official. Finance is the business owner;
Engineering is the technical owner. Document that positive means current FX
increases valuation and that this is not sales growth. Add config.meta owner,
business_owner, technical_owner, and intended_use fields.

Expose the existing current_fx_rate_source_date column on invoice_financials
as a time dimension with day granularity. Preserve issue_date as the default
aggregation time dimension, existing metrics, SQL columns, contracts, and tests.
Use the latest nested semantic YAML spec. Do not modify model SQL or deploy.

Read project guidance and the Semantic Layer skill first. Validate with a cold
parse and dbt sl validate. Run strict compilation of +invoice_financials to show
the v2 validation step. Then query revenue_official, sales_approved_revenue, and
revenue_fx_difference by metric_time__month and
invoice__current_fx_rate_source_date__day using dbt sl query in DEV. Do not use
the deployed Semantic Layer tool for this undeployed change. Show the diff and
summarize what changed. Do not commit, push, or merge the live enhancement.
```

1. Show Wizard inspecting project context, making a small YAML diff, and validating it.
2. Inspect the ownership metadata and explicit input metric references.
3. Show the development query result. Explain: “We reused governed metrics rather than writing a third revenue SQL calculation.”
4. Use these commands as a fallback if the agent has completed the edit but the demo is short on time:

```text
dbt parse --no-partial-parse
dbt compile --select +invoice_financials --static-analysis strict
dbt sl validate
dbt sl query --metrics revenue_official,sales_approved_revenue,revenue_fx_difference --group-by metric_time__month,invoice__current_fx_rate_source_date__day
```

The derived metric and date dimension were temporarily added, cold-parsed, semantically validated, and queried successfully in DEV during preparation, then removed from the baseline. A live agent interaction can still vary in timing. Timebox to seven minutes; inspect the diff and validation rather than narrating every tool call.

This enhancement is metadata-only: it needs parse/semantic validation and strict compilation, not a new warehouse SQL build. The physical date column and not-null test already exist. It will not appear in Sheets/Claude until separately deployed, which is outside this segment.

### Reset after rehearsal/demo

On the dedicated Wizard branch, inspect Version control changes and discard only the live enhancement after preserving anything you want to keep. Never discard an entire working tree containing unrelated work. The reset is removal of `revenue_fx_difference` and the time-dimension/granularity annotation on `current_fx_rate_source_date`; keep its physical column, description, contract, and tests. Return to `main` or a fresh Wizard branch for the next run.

On the error branch, leave intentional errors unfixed. Returning to `main` removes the error fixture. Keep PRD on `main` throughout.

## Validation record and remaining manual gates

Rehearsed in Finance DEV on v2 Stable 2.0.9 with deployed Core Mesh inputs:

- Cold parse passed.
- Dependency-aware build passed: 1 model, 14 data tests, 2 unit tests.
- Revenue semantic validation and monthly metric query passed.
- Current FX provenance checked against the confirmed DEV table; no future rates selected.
- Forced generic-test runs passed with and without the batching flag; aggregated not-null runtime SQL observed.
- Strict compilation and information-schema generation passed.
- Three error diagnostics reproduced independently without executing the invalid query.
- Wizard enhancement parsed, validated, and queried successfully, then reset.

A production comparison was attempted with `dbt compare --select invoice_financials+ --defer` and was blocked because this session has no state manifest. No compare result is claimed. Production rebuild, connector refresh, cross-tool value agreement, and visible editor lineage are human pre-demo gates; these cannot be certified from local validation alone.

## Reference docs

- [Batch tests](https://docs.getdbt.com/reference/global-configs/batch-tests)
- [Static analysis](https://docs.getdbt.com/docs/build/about-static-analysis)
- [Column-level lineage](https://docs.getdbt.com/docs/explore/column-level-lineage)
- [Latest Semantic Layer spec](https://docs.getdbt.com/docs/build/latest-metrics-spec)
