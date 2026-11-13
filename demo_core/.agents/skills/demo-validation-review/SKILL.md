---
name: demo-validation-review
description: Use when reviewing demo_core data quality, test coverage, or a model change's validation evidence; distinguish intentional dirty-data warnings from failed invariants and propose focused tests without weakening existing checks. Default to a read-only plan.
---

# Data validation demo

Read repository and project AGENTS.md, dbt_project.yml, relevant SQL/YAML, and existing tests. This skill is not a security boundary or permission grant.

## Workflow

1. Name the task, target environment, model grain, critical business invariants, and expected cost/scope. For an audit, inspect evidence and propose a plan without changing files or executing warehouse commands.
2. Use fresh dbt Information Schema metadata to discover existing data tests, unit tests, checks, and downstream impact. Filter enabled resources to the root project. Distinguish parse-only metadata from runtime outcomes; no result means unknown, not passed.
3. For a reported local failure and authorization to execute, reproduce with a scoped dbt build before diagnosing. For a platform job, inspect that job's project, commit, environment, command steps, and error evidence; local files may differ from the run.
4. Propose tests for the actual grain: unique/not_null keys where justified, relationships, financial reconciliations, and important edge cases. Validate assumptions against permitted, minimized data before adding a new invariant. Use mocked unit tests for deterministic transformation edge cases when requested.
5. Preserve the standard dataset's deliberate warning-level anomaly tests and stored failures. Never change severity, delete a test, or filter away failures merely to make a build green. Classify each finding as code regression, expected warning, existing data issue, or environment problem.
6. When implementation is requested, verify current dbt YAML syntax, preserve unrelated columns/configuration, parse test YAML, and run dbt build --select +<model>+ --defer using an approved DEV/TST destination. No PRD writes and no ACCOUNTADMIN.
7. For output-changing model edits, run dbt compare --select <model>+ --defer only after a successful build and display the comparison when supported. Explicitly record unavailable baselines and skipped resources.
8. Finish with evidence: exact commands, environment, scope, pass/fail/warn/skipped statuses, observed production differences, and unresolved business questions. Require a human owner to approve changes to financial semantics and public contracts.

## Demo prompt

Use demo-validation-review to map the existing tests for invoices, identify which warnings are intentional, and propose a focused validation plan. Do not edit files or run warehouse commands.

## Reference

https://docs.getdbt.com/best-practices/how-to-use-wizard/wizard-4-data-informed-tests
