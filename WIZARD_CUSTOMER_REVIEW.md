# Enterprise dbt Wizard review

## Purpose and presentation guidance

A concise briefing and slide outline for a 60-minute customer architecture review covering automated model development, documentation management, and data validation.

**Recommendation:** Start with supervised automation: versioned standards, trusted metadata, isolated development writes, deterministic CI, and human ownership of business definitions.

**Use this document:** Each numbered section can become one slide. Definitions explain what is being configured before setup and recommendations. Keep examples and caveats in speaker notes. The appendix is optional backup, not required presentation content.

**Suggested call allocation:** Customer walkthrough 10 minutes; configuration and context 15; one bounded demo 10; guardrails/privacy/cost 15; decisions and questions 10. Use slides selectively to support the discussion.

**Source scope:** Synthesized from the dbt documentation reviewed in this conversation. Preview/Beta labels, provider availability, pricing, and roadmap statements should be rechecked before presenting. Recommendations are not product commitments.

## 1. Choose the surface

**What it is:** The interface and execution environment where Wizard works. It determines configuration, available tools, and automation options.

| Surface | Best fit | Important distinction |
| --- | --- | --- |
| Platform: Studio IDE — Preview | Pairing with code, direct edits, investigation | Account/repo/session controls; local TOML settings do not automatically apply |
| Platform: home tab — Preview | Agent-led investigation, generation, diff review, validation | Platform configuration; verify account prerequisites |
| CLI — Beta | Local development, scripts, headless execution/review | Local configuration, custom agents, MCP, automation |
| Desktop — Beta | Visual local development, isolated chat environments, diffs/validation | Shares local configuration with CLI; UI capabilities can differ |

**Review question:** Which surfaces does the customer actually support, and has the framework been tested on each?

**Recommendation:** Standardize a primary workflow first. Shared concepts do not imply feature parity.

Sources: [Platform](https://docs.getdbt.com/docs/platform/wizard-platform), [Home tab](https://docs.getdbt.com/docs/platform/wizard-home), [CLI](https://docs.getdbt.com/docs/dbt-ai/wizard-cli), [Desktop](https://docs.getdbt.com/docs/dbt-ai/wizard-desktop-use).

## 2. Configure providers and account controls

**Applies to:** All surfaces; configuration and provider coverage differ.

**What it is:** The provider/model runs inference. Managed inference uses dbt-provided access and billing; BYOK uses customer-supplied provider credentials and provider billing. Account controls govern platform AI access and managed spend.

**How:** Platform: Account settings → AI features → AI providers. CLI: `wizard providers configure <provider>`. Desktop: Settings → AI providers.

| Access | Platform | CLI / Desktop |
| --- | --- | --- |
| dbt-managed | OpenAI, Anthropic, selected open-weight models | Same provider categories |
| BYOK | OpenAI, Anthropic, Azure AI Foundry/Azure OpenAI | Also documented: Bedrock, Gemini, Cortex, Databricks; provider-specific constraints apply |

**Recommendation:** Use managed inference when approved for simpler operations. Use BYOK for approved provider agreements, endpoints, or provider-side attribution. Benchmark quality and total cost on representative work.

**Essential caveats:**
- Claude Enterprise subscriptions are not Wizard credentials; use an approved API/provider route.
- Platform BYOK is account-level. Open-weight does not mean locally hosted or zero egress.
- Cortex is marked Preview; the Databricks integration is marked Beta. Verify exact model availability.
- Review residency for the exact endpoint and failover path; provider choice alone is not a guarantee. Platform OpenAI custom-endpoint/residency limitations need explicit confirmation.

Sources: [Manage AI](https://docs.getdbt.com/docs/platform/manage-dbt-ai), [Platform BYOK](https://docs.getdbt.com/docs/platform/wizard-byok-platform), [Local BYOK](https://docs.getdbt.com/docs/dbt-ai/wizard-byok).

## 3. Configure instructions and skills

**Applies to:** Project skills in platform and CLI; Desktop reuses local skills. Skills documentation is marked Beta.

**What they are:** `AGENTS.md` supplies persistent project context. A skill is a reusable, task-specific workflow that Wizard can load when its description matches the request. Skills guide behavior; they do not enforce permissions.

**How:** Create `.agents/skills/<name>/SKILL.md` at the dbt project root, with `name`, `description`, and workflow instructions. Start a new chat after adding or changing skills. Studio docs explicitly describe creating this directory in the file explorer.

```text
<dbt-project-root>/
├── AGENTS.md
└── .agents/skills/
    ├── safe-model-development/SKILL.md
    ├── documentation-review/SKILL.md
    └── validation-review/SKILL.md
```

**Recommendation:** One skill per concern. A useful description states when to activate, the scope, and the outcome. Example: “Use when auditing finance model descriptions; verify grain, currency, and reconciliation semantics, and flag unsupported definitions for the owner.” Test activation with real prompts.

**Sharing:** Platform docs currently say native cross-project sharing is unsupported; synchronize reviewed files into each project. Local dbt v2 documents package-distributed skills and `dbt deps --ai-provider wizard`. Pin and review the package. Local user-level skills can live in `~/.agents/skills/`.

**Speaker-note caveat:** Package docs show a `flags:` YAML example that conflicts with this Studio runtime's configuration rules. Verify version/surface compatibility; do not copy that example blindly. `ai_provider: wizard` identifies the coding agent, not the inference provider.

Sources: [Platform skills](https://docs.getdbt.com/docs/dbt-ai/wizard-platform-skills), [Local skills](https://docs.getdbt.com/docs/dbt-ai/wizard-skills), [Package skills](https://docs.getdbt.com/docs/dbt-ai/package-skills).

## 4. Configure subagents

**Applies to:** Built-ins documented in platform and CLI; Desktop reuses local subagents. Custom TOML role loading is documented locally, not established for platform.

**What they are:** A subagent is a separate running agent assigned part of a larger task. Built-in roles provide common behavior; custom roles add specialized instructions and optional configuration.

**How:** Ask for a built-in role or create a local `.dbt/wizard/agents/<name>.toml` containing matching `name`, `description`, and `developer_instructions`. User-global roles use `~/.dbt/wizard/agents/`. Create directories as needed; project-local roles require trust.

| Built-in | Purpose |
| --- | --- |
| `explorer` | Focused, read-only investigation |
| `worker` | Implementation and execution |
| `validation` | Structured validation |
| `test_writer` | Data-informed test coverage |

**Customer examples:** A bounded model builder, a read-only docs auditor, and a validation planner.

**Recommendation:** Use subagents for independent investigations, not trivial tasks. Bound nesting/runtime and avoid concurrent edits to the same file. They add token overhead.

Sources: [Local subagents](https://docs.getdbt.com/docs/dbt-ai/wizard-subagents), [Platform subagents](https://docs.getdbt.com/docs/dbt-ai/wizard-platform-subagents), [Desktop](https://docs.getdbt.com/docs/dbt-ai/wizard-desktop-use).

## 5. Configure execution and connected tools

**What is being configured:** Approvals decide when actions require confirmation. A sandbox constrains local shell access. MCP servers expose external tools/context. Deferral reuses relations from another environment. These are separate controls.

| Surface / control | How and recommendation |
| --- | --- |
| Platform approvals | Start with Ask for approval. Platform does not expose the CLI-style bash sandbox. |
| CLI/Desktop runtime | `~/.dbt/wizard/config.toml`: model, approvals, sandbox, MCP, agent limits. Start read-only; grant workspace writes for implementation. |
| CLI/Desktop project setup | `~/.dbt/wizard/wizard_config.toml`: executable, profiles, deferral, state-refresh settings. Verify the intended project and baseline. |
| MCP in CLI/Desktop | Allowlist approved tools, protect secrets, and approve sensitive operations. Desktop reuses local MCP configuration. |
| Plugins/hooks | Documented for interactive CLI, not platform installation. Review executable sources and hook trust; not essential to an initial rollout. |

**Recommendation:** Let the correct runtime own deferral. Explicitly identify development write destinations and production comparison baselines. A local sandbox does not restrict remote warehouse privileges; enforce those through RBAC.

**Speaker note:** Memories are described as cross-session context, but a full management/storage contract was not verified. Keep mandatory team policy in versioned files. `approval_policy = never` means no human prompts, not deny-all.

Sources: [Config](https://docs.getdbt.com/docs/dbt-ai/wizard-config), [MCP](https://docs.getdbt.com/docs/dbt-ai/wizard-mcp), [Plugins/hooks](https://docs.getdbt.com/best-practices/how-to-use-wizard/wizard-8-plugins-hooks).

## 6. Verify metadata before automating

**Applies to:** All surfaces; platform uses connected development state, while CLI/Desktop use local metadata plus connected tools.

**What it is:** The dbt Information Schema is a structured metadata interface queried with embedded DuckDB, not Snowflake's `INFORMATION_SCHEMA`. It includes resources, docs, tests, configuration, dependencies, and available catalog/runtime evidence. Exported snapshots live under `target/info_schema/v1/`.

**How:** Inspect sources/columns and the latest invocation. Parsing supplies declared metadata; strict analysis adds model types/column lineage; catalog collection adds warehouse column metadata; builds add execution evidence.

**Recommendation:** Verify project, branch, target/role, metadata freshness, and source-column completeness. Missing runtime evidence means unknown, not passing.

**For the customer's previous source issue:** Check source YAML, role access, catalog collection, and the actual invocation/checkout. Parse alone does not discover every warehouse source column.

Sources: [Information Schema](https://docs.getdbt.com/docs/build/dbt-information-schema), [View reference](https://docs.getdbt.com/reference/info-schema).

## 7. Where Wizard fits and how to work with it

**Applies to:** All surfaces; tools vary.

| Good fit | Human or deterministic tooling should lead |
| --- | --- |
| Explain SQL/lineage; investigate failures | Approve undocumented business or accounting definitions |
| Implement bounded, schema-grounded changes | Approve breaking contracts or production repair |
| Draft documentation from verified evidence | Certify regulatory or financial correctness |
| Suggest tests and plan validation | Execute a fixed recurring validation suite |

**General practice:** One chat per coherent outcome. State the goal, grain, preserved behavior, scope, and environment. Separate review from implementation, and ask for evidence and remaining assumptions.

**Common mistakes to challenge:** Assuming surface parity; generating from stale metadata; treating skills as security; inventing definitions; treating compile as proof; weakening tests to get green; overusing subagents.

Sources: [Wizard architecture and sessions](https://docs.getdbt.com/docs/dbt-ai/wizard-how-it-works), [Validation limits](https://docs.getdbt.com/best-practices/how-to-use-wizard/wizard-3-validate-changes).

## 8. Guardrails and validation

**Applies to:** All surfaces; headless `wizard exec` / `wizard review` are CLI workflows.

**What it is:** Validation is the evidence that a change executes and meets defined expectations. Agent review, dbt execution, data comparison, and business approval answer different questions.

**How:** Use isolated development schemas and least-privilege roles. Keep builds/tests/checks independent of agent judgment. Require human review before merge/deployment.

| Risk | Validation approach |
| --- | --- |
| Low | Light / Desktop Small: syntax/lint where supported, focused tests, review; no changed-model materialization |
| Model logic | Medium: development materialization and relevant downstream validation |
| Grain, finance, contracts, incremental behavior | Heavy / Desktop Large: explicit expectations and production/development comparison where available |

**Recommendation:** For output-affecting changes, build the dependency slice and then compare development with production. Preserve existing assertions and intentional warnings. Record pass/fail/warn/skipped/unknown separately. Platform validation controls can differ from local levels.

**CI:** Start advisory, retain findings/patches, and run deterministic gates independently. A successful agent exit is not a data-quality gate. External consumers are only visible if represented in metadata or connected tools.

Sources: [Validation](https://docs.getdbt.com/best-practices/how-to-use-wizard/wizard-3-validate-changes), [Desktop validation](https://docs.getdbt.com/docs/dbt-ai/wizard-desktop-use), [CLI automation](https://docs.getdbt.com/docs/dbt-ai/wizard-cli-reference).

## 9. Data privacy and security

**Applies to:** All; platform documentation and local/BYOK paths require distinct review.

**What to review:** The complete path of prompts, project metadata, query results, credentials, and connected-tool data.

- Prompts, metadata, and approved query results may reach the provider; results can include row-level data. Platform docs say warehouse credentials are not shared with the AI provider.
- Managed-provider protections differ from BYOK terms. Review training, retention, residency, endpoint/failover behavior, and deletion requirements.
- Minimize sensitive samples and review MCP/hook trust boundaries. “No training” does not mean no transmission or retention anywhere.

**Speaker note:** Reviewed platform docs state 90-day conversation and 400-day submitted-feedback retention. Do not generalize those periods to local/provider stores.

Sources: [Privacy](https://docs.getdbt.com/docs/dbt-ai/dbt-ai-faqs#privacy-and-data), [Provider controls](https://docs.getdbt.com/docs/platform/manage-dbt-ai), [CLI telemetry](https://docs.getdbt.com/docs/dbt-ai/wizard-telemetry).

## 10. Usage and cost

**Applies to:** Managed usage spans platform, CLI, Desktop; BYOK reporting is provider-side.

**What it is:** Managed inference is token-based usage billed against an account-level balance. Model/token type, context, retries, and subagents affect cost. Warehouse validation compute is additional.

**How:** Account settings → Billing & Usage → Usage-based features → Wizard shows balance, reset date, spend limit, and usage by model. Included credits are per account: Enterprise $100/month; Enterprise+ $200/month. Verify current commercial terms with the account team.

**Recommendation:** Pilot representative work and measure cost per accepted task. Forecast active developers × active days × tasks/day × observed cost/task, plus scheduled automation. Verify which account supplies local AI access.

**Limits:** Reviewed docs did not establish customer-facing per-user/project/surface/session billing breakdowns or a public Wizard billing export/API. BYOK requires provider reporting; internal telemetry is not a customer analytics feed.

Sources: [Billing](https://docs.getdbt.com/docs/dbt-ai/pricing-billing/trial-and-billing), [Metering](https://docs.getdbt.com/docs/platform/billing/dbt-ai-usage), [Telemetry](https://docs.getdbt.com/docs/dbt-ai/wizard-telemetry).

## 11. Limitations and public roadmap

**Applies to:** Surface-specific. No inferred commitments are included.

| Status | Item |
| --- | --- |
| Available, Preview/Beta | Platform experiences, skills/subagents, CLI/Desktop as described above |
| Documented platform limitation | Native cross-project skill sharing unsupported; project-level platform BYOK not an available documented control |
| Not established | Platform custom TOML agent parity; granular customer billing API/export |
| Publicly marked coming soon | Additional Desktop connector browsing/enabling in Settings; no verified delivery date |
| Already described in newer docs | Desktop remote dbt MCP integration; older general docs lag this capability |
| Unverified | Summit 2026-specific promises; do not attribute commitments without a public source |

**Recommendation:** Do not make the November rollout dependent on unshipped features. Verify the actual account/build when docs differ.

Sources: [Release notes](https://docs.getdbt.com/docs/dbt-versions/release-notes), [Desktop settings](https://docs.getdbt.com/docs/dbt-ai/wizard-desktop-settings), [Platform skills](https://docs.getdbt.com/docs/dbt-ai/wizard-platform-skills), [BYOK FAQ](https://docs.getdbt.com/docs/dbt-ai/dbt-ai-faqs).

## 12. Close: readiness, ownership, and next decisions

**Applies to:** All. This is a recommended operating model.

**Rollout:** Baseline → representative pilot → harden controls and recovery → expand by domain.

**Evidence to request:** Accepted-task quality, reviewer corrections, escaped regressions, validation completeness, and time/cost per accepted task. Include ambiguous tasks and failure recovery in the pilot.

**Decisions:** Approved surfaces/providers, autonomy boundaries, human approvers, standards distribution, metadata freshness policy, spend owner, and stop/rollback criteria.

Source: [Validation and review evidence](https://docs.getdbt.com/best-practices/how-to-use-wizard/wizard-3-validate-changes).

## Appendix — Optional demo and quick reference

### Demo already prepared

Three skills are saved in `demo_core/.agents/skills/`. Start a new Wizard chat to discover them. File review and dbt parsing do not establish skill activation; exercise a prompt in the new session before the call.

```text
Use demo-safe-model-development to review invoices for a safe future refactor.
Explain its grain, incremental key, public contract, and validation plan.
Do not edit files or run warehouse commands.
```

```text
Use demo-documentation-review to audit invoices and its payment/reconciliation
semantics. Separate verified facts from finance-owner questions.
Do not edit files or query warehouse rows.
```

```text
Use demo-validation-review to map tests for invoices, identify intentional
warnings, and propose a focused validation plan.
Do not edit files or run warehouse commands.
```

### Metadata inspection

These inspect dbt metadata, not warehouse rows:

```bash
dbt show --info sources --limit 10
dbt show --info node_columns --limit 10
dbt show --inline "select command, generated_at from {{ info_schema('invocations') }} order by generated_at desc" --limit 5
```

Source: [Information Schema](https://docs.getdbt.com/docs/build/dbt-information-schema).

### One-page readiness checklist

- [ ] Record surfaces, versions, and Preview/Beta dependencies.
- [ ] Confirm provider, endpoint/model, AI billing account, and privacy approval.
- [ ] Assign owners for skills, credentials, evaluation, and spend.
- [ ] Inspect instructions/skills and verify discovery in a new session.
- [ ] Confirm standards distribution/versioning and rollback.
- [ ] Bound agents, tools, approvals, and external extensions.
- [ ] Verify source columns, metadata freshness, target/role, and deferral baseline.
- [ ] Isolate development writes and restrict production access.
- [ ] Require deterministic CI, explicit evidence, and human approval.
- [ ] Establish pilot success measures, budgets, and stop criteria.

### Five customer questions

1. Show one task from request to merged change. What can execute autonomously, and where are restrictions enforced outside the prompt?
2. How do you prove the branch, environment, source columns, metadata freshness, and baseline are correct?
3. Who owns business meaning, and what stops generated docs/tests from promoting assumptions into approved definitions?
4. How are skills, agents, MCP tools, and hooks reviewed, distributed, updated, and rolled back?
5. What pilot evidence gates company-wide rollout, including quality, cost, and tested failure recovery?
