# Raw data generator specification

## Purpose

A deterministic R-based fake-data generator for a fictional B2B SaaS company. The generated CSV files are loaded into Snowflake database `CORE_RAW` outside dbt. dbt then cleans, tests, snapshots, and models the data.

The standard scenario contains realistic defects and warning-level test failures while still allowing a production dbt build to succeed. An optional broken scenario produces error-level failures.

## Snowflake context

- Database: `CORE_RAW`.
- Schemas: `CRM`, `BILLING`, `PRODUCT`, `ERP`, `MARKET`.
- Role: `DEV_DBT_ROLE2`.
- Warehouse: `TRANSFORM_XS_WH`.

## Deliverables

1. `setup/install_packages.R` — installs the required CRAN packages if absent. Safe to rerun.
2. `setup/generate_raw_data.R` — the generator. Single self-contained script.
3. `setup/generated/<source>/<table>.csv` — one file per table, 14 files total.
4. `setup/manifest.csv` — one row per generated file: source, table, row count, `intended_load_strategy`, declared primary key, file path, plus the run metadata `scenario`, `seed`, `scale`, `as_of_date`, `generated_at`, and `r_version`. Because `setup/generated/` is gitignored, this metadata is the only record of which run the tracked manifest describes.
5. `setup/anomaly_manifest.csv` — every deliberately injected anomaly: scenario, table, technical key, anomaly type, expected dbt handling, expected severity. Carries the same run metadata.
6. `setup/raw_table_ddl.sql` — Snowflake DDL for all 14 raw tables with explicit types, plus a named CSV file format for loading.
7. `setup/load_raw_data.md` — instructions for loading the CSVs through the Snowsight UI.
8. `setup/rebaseline_loaded_at.sql` — shifts every `_loaded_at` by a signed interval so source freshness behaves as designed on any demo date.
9. `setup/incremental_demo.sql` — reversible SQL that mutates loaded tables to exercise incremental models and snapshots.
10. A validation summary printed by the R script.

The generator never connects to Snowflake and never contains credentials. `setup/generated/` is gitignored; everything else is tracked.

## Generator interface

Command-line arguments and defaults:

- `--scenario standard` — `clean`, `standard`, or `broken`.
- `--seed 20250301` — output is reproducible for the same seed, scenario, scale, and as-of date.
- `--as_of_date 2026-01-01` — fixed historical default, interpreted as UTC. Deliberately in the past so `_loaded_at` is never in the future relative to a demo.
- `--history_days 730`.
- `--scale 1` — volume multiplier. Anomaly counts scale proportionally, with a floor of one of each.
- `--output_dir setup/generated`.
- `--manifest_dir setup`.

Scenario behavior:

- `clean`: no deliberate warning or error anomalies, but retain normal business variation, soft deletes, late events, and mixed time zones.
- `standard`: inject the anomaly ledger below. Must not cause error-severity dbt tests to fail after intended cleaning.
- `broken`: all standard anomalies plus the listed error-level failures.

## Time and freshness

- History runs from `as_of_date - history_days` through `as_of_date`.
- Each file contains current state as of `as_of_date`: one row per entity at its latest version, not a change log.
- Seasonality: lower weekend product activity, modest month-end invoice volume, gradual customer growth.
- Every table has `_loaded_at TIMESTAMP_TZ`, always at or after the row's creation, update, or event timestamp.
- Maximum `_loaded_at` per source, measured back from the reference time of `as_of_date` at 23:59 UTC:

| Source | Max age | Intent |
|---|---|---|
| CRM | 2 hours | Fresh |
| BILLING | 2 hours | Fresh |
| PRODUCT | 1 hour | Fresh |
| ERP | 8 hours | Fresh |
| MARKET | 30 hours | Freshness warning under `warn_after: 24 hours`, `error_after: 48 hours` |

- The broken scenario makes MARKET more than 72 hours stale.
- Freshness is evaluated at dbt run time, not generation time, so these offsets are only correct on the generation date. `rebaseline_loaded_at.sql` restores them on any later date and preserves the relative gaps above.
- Timestamps are ISO-8601 with an explicit UTC offset. Product event timestamps preserve mixed offsets.

## Load strategies

Recorded per table in the manifest as `intended_load_strategy`. Describes how the table would be loaded in a production pipeline and informs later dbt configuration; does not affect generator output.

- `replace_initial_then_merge` — mutable source entities, merged by primary key.
- `append` — immutable event-style tables with globally unique technical keys.
- `merge` — merged by composite key.

## CSV conventions

- UTF-8, comma-delimited, header row included.
- Fields double-quoted when needed; embedded quotes escaped by doubling. Loading must use `FIELD_OPTIONALLY_ENCLOSED_BY = '"'`.
- An empty field means SQL `NULL`. The literal strings `NA`, `NULL`, and `NaN` must never appear in any field.
- Booleans are lowercase `true` and `false`.
- Dates are `YYYY-MM-DD`. Timestamps are ISO-8601 with offset.
- Monetary fields ending in `_cents` are whole-number minor currency units.
- JSON columns hold compact, valid JSON in a single quoted field.
- IDs are stable strings with readable prefixes, for example `acct_000001`, `inv_000001`.

## Volumes

Approximate row counts at `scale = 1`, plus or minus 10% except for deterministic anomaly counts.

| Source | Table | Rows |
|---|---|---:|
| CRM | `accounts` | 250 |
| CRM | `contacts` | 700 |
| CRM | `opportunities` | 900 |
| CRM | `sales_reps` | 20 |
| BILLING | `customers` | 230 |
| BILLING | `subscriptions` | 350 |
| BILLING | `invoices` | 2,400 |
| BILLING | `invoice_lines` | 5,000 |
| BILLING | `payments` | 2,100 |
| BILLING | `refunds` | 120 |
| PRODUCT | `events` | 25,000 |
| ERP | `gl_entries` | 6,000 |
| ERP | `cost_centers` | 15 |
| MARKET | `fx_rates` | ~3,655: five currencies over two years |

## Shared domains

- Currencies: `USD`, `EUR`, `GBP`, `CAD`, `AUD`.
- Canonical countries: United States/US, Canada/CA, United Kingdom/GB, Germany/DE, France/FR, Australia/AU, Netherlands/NL, Ireland/IE, Spain/ES, Japan/JP.
- Industries: Software, Financial Services, Healthcare, Retail, Manufacturing, Professional Services, Media, Education.
- Account tiers: `enterprise`, `mid_market`, `smb`.
- Sales regions: `AMER`, `EMEA`, `APAC`. Never the literal string `NA`, which collides with R's missing-value sentinel and with the empty-field-means-NULL convention.
- Plan codes, aligned with the future `plan_catalog` seed: `STARTER_MONTHLY`, `STARTER_ANNUAL`, `GROWTH_MONTHLY`, `GROWTH_ANNUAL`, `ENTERPRISE_ANNUAL`.
- ERP account codes, aligned with the future chart-of-accounts seed: `1000` Cash, `1100` Accounts Receivable, `2000` Deferred Revenue, `4000` Subscription Revenue, `4010` Services Revenue, `5000` Hosting Cost, `6100` Sales and Marketing, `6200` Research and Development, `6300` General and Administrative.

## CRM schema

### `CORE_RAW.CRM.SALES_REPS`

**Grain:** one current row per sales representative.
**Primary key:** `sales_rep_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `sales_rep_id` | `VARCHAR` | Required; stable ID. |
| `first_name` | `VARCHAR` | Required. |
| `last_name` | `VARCHAR` | Required. |
| `email` | `VARCHAR` | Required; unique after lowercase normalization. |
| `region` | `VARCHAR` | One of `AMER`, `EMEA`, `APAC`. |
| `manager_sales_rep_id` | `VARCHAR` | Nullable self-reference; top-level managers are null. |
| `hire_date` | `DATE` | Required; not after `as_of_date`. |
| `is_active` | `BOOLEAN` | Required. About 10% inactive. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.CRM.ACCOUNTS`

**Grain:** one current source row per CRM account ID. Separate IDs may represent the same real business.
**Primary key:** `account_id`.
**Foreign key:** `owner_sales_rep_id -> CRM.SALES_REPS.sales_rep_id`.
**Intended load strategy:** `replace_initial_then_merge`.
**Composition:** 250 rows comprising 242 distinct real companies plus 8 rows duplicating another row's company under a different `account_id`.

| Column | Type | Rules |
|---|---|---|
| `account_id` | `VARCHAR` | Required. |
| `account_name` | `VARCHAR` | Required except in broken scenario. Preserves source casing and whitespace defects. |
| `website_domain` | `VARCHAR` | Nullable; mostly lowercase, with deliberate casing, protocol, `www.`, and trailing-slash variants. |
| `billing_country` | `VARCHAR` | Nullable free text; canonical names, ISO codes, abbreviations, misspellings, whitespace. |
| `industry` | `VARCHAR` | Nullable; shared industry domain. |
| `employee_count` | `NUMBER(10,0)` | Nullable; nonnegative in standard scenario. |
| `annual_revenue` | `NUMBER(18,2)` | Nullable CRM estimate in account currency. Deliberately decimal rather than cents, since it is an estimate rather than a transactional amount. |
| `account_currency` | `VARCHAR(3)` | Required. |
| `account_tier` | `VARCHAR` | Required; `enterprise`, `mid_market`, or `smb`. |
| `owner_sales_rep_id` | `VARCHAR` | Required in standard scenario. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; at or after `created_at`. |
| `is_deleted` | `BOOLEAN` | Required; soft-delete flag. |
| `deleted_at` | `TIMESTAMP_TZ` | Required only when `is_deleted = true`. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required; at or after `updated_at`. |

Distribution of `updated_at`, described by what a single row can evidence rather than by a revision count: about 82% never revised, with `updated_at` equal to `created_at`; about 15% carrying an older revision more than 14 days before `as_of_date`; about 3% carrying a recent revision within the final 14 days. Soft-delete about 3%, with `deleted_at` consistent with `updated_at`.

### `CORE_RAW.CRM.CONTACTS`

**Grain:** one current row per CRM contact.
**Primary key:** `contact_id`.
**Foreign key:** `account_id -> CRM.ACCOUNTS.account_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `contact_id` | `VARCHAR` | Required. |
| `account_id` | `VARCHAR` | Required in standard scenario. |
| `first_name` | `VARCHAR` | Required. |
| `last_name` | `VARCHAR` | Required. |
| `email` | `VARCHAR` | Nullable; mostly valid, with a small number of casing and whitespace defects. |
| `job_title` | `VARCHAR` | Nullable. |
| `is_primary` | `BOOLEAN` | Required; at most one active primary contact per account. Contacts with null email are never primary. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; at or after `created_at`. |
| `is_deleted` | `BOOLEAN` | Required. About 2% deleted. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.CRM.OPPORTUNITIES`

**Grain:** one current row per sales opportunity.
**Primary key:** `opportunity_id`.
**Foreign keys:** `account_id -> CRM.ACCOUNTS.account_id`; `owner_sales_rep_id -> CRM.SALES_REPS.sales_rep_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `opportunity_id` | `VARCHAR` | Required. |
| `account_id` | `VARCHAR` | Required. |
| `owner_sales_rep_id` | `VARCHAR` | Required. |
| `opportunity_name` | `VARCHAR` | Required. |
| `stage` | `VARCHAR` | One of `prospecting`, `qualification`, `proposal`, `negotiation`, `closed_won`, `closed_lost`. |
| `amount_cents` | `NUMBER(18,0)` | Required; nonnegative. |
| `currency` | `VARCHAR(3)` | Required. |
| `probability` | `NUMBER(5,4)` | Between 0 and 1 inclusive. Closed-won is 1, closed-lost is 0, open stages carry stage-appropriate values. |
| `close_date` | `DATE` | Required; past for closed stages, future for open stages. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; at or after `created_at`. |
| `is_deleted` | `BOOLEAN` | Required. About 2% deleted. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

Stage distribution reflects a realistic funnel, with older opportunities more likely to be closed.

## BILLING schema

### `CORE_RAW.BILLING.CUSTOMERS`

**Grain:** one current billing customer.
**Primary key:** `billing_customer_id`.
**Soft cross-source relationship:** `crm_account_id -> CRM.ACCOUNTS.account_id`, nullable and occasionally wrong, because account matching is part of the dbt demo.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `billing_customer_id` | `VARCHAR` | Required. |
| `crm_account_id` | `VARCHAR` | Nullable; usually exact, sometimes missing or incorrect. |
| `customer_name` | `VARCHAR` | Required; may vary from the CRM name in punctuation, suffix, case, and whitespace. |
| `website_domain` | `VARCHAR` | Nullable; secondary matching key. |
| `billing_email` | `VARCHAR` | Nullable. |
| `billing_country` | `VARCHAR` | Nullable free text. |
| `currency` | `VARCHAR(3)` | Required. |
| `status` | `VARCHAR` | One of `active`, `delinquent`, `closed`. |
| `tax_id` | `VARCHAR` | Nullable. |
| `created_at` | `TIMESTAMP_TZ` | Required; at or after the matched CRM account's `created_at`. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

Composition: about 70% of CRM accounts have a billing customer. A small number of accounts have a second billing entity, and roughly 25 billing customers have no CRM counterpart at all, reflecting self-serve signups.

### `CORE_RAW.BILLING.SUBSCRIPTIONS`

**Grain:** one current subscription. A customer may hold several over time or concurrently.
**Primary key:** `subscription_id`.
**Foreign key:** `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`.
**Reference:** `plan_code` normally exists in the future `plan_catalog` seed.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `subscription_id` | `VARCHAR` | Required. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `plan_code` | `VARCHAR` | Required. |
| `status` | `VARCHAR` | One of `trialing`, `active`, `past_due`, `paused`, `canceled`. |
| `started_at` | `TIMESTAMP_TZ` | Required; at or after the customer's `created_at`. |
| `current_period_start` | `DATE` | Required. |
| `current_period_end` | `DATE` | Required and after `current_period_start`; length matches the plan's billing interval. |
| `canceled_at` | `TIMESTAMP_TZ` | Required only for canceled subscriptions. |
| `quantity` | `NUMBER(10,0)` | Required; at least 1. |
| `unit_price_cents` | `NUMBER(18,0)` | Required; nonnegative. |
| `currency` | `VARCHAR(3)` | Required; equal to the customer's currency. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

A single current-state row cannot evidence a transition, so this table is not specified as containing upgrades, downgrades, or reactivations as such. It carries their residue: a realistic mix of statuses including `canceled` with a populated `canceled_at`, `paused`, and `past_due`; plan codes spread across the catalog; and `started_at` values distributed across the history. Plan changes remain implicitly observable through the sequence of `plan_code` values on a customer's invoice lines. Explicit, observable transitions are the job of `incremental_demo.sql`.

### `CORE_RAW.BILLING.INVOICES`

**Grain:** one current invoice.
**Primary key and future dbt incremental `unique_key`:** `invoice_id`.
**Foreign keys:** `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`; nullable `subscription_id -> BILLING.SUBSCRIPTIONS.subscription_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `invoice_id` | `VARCHAR` | Required. |
| `invoice_number` | `VARCHAR` | Required; unique human-readable number. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `subscription_id` | `VARCHAR` | Nullable for one-off charges. |
| `status` | `VARCHAR` | Normally `draft`, `open`, `paid`, `void`, or `uncollectible`; the standard scenario includes rogue values. |
| `issue_date` | `DATE` | Required; at or after the subscription's start date where applicable. |
| `due_date` | `DATE` | Required; on or after `issue_date`. |
| `paid_at` | `TIMESTAMP_TZ` | Required only for settled statuses; at or after `issue_date`. |
| `subtotal_cents` | `NUMBER(18,0)` | Required. |
| `discount_cents` | `NUMBER(18,0)` | Required; positive magnitude; default zero. |
| `tax_cents` | `NUMBER(18,0)` | Required; default zero. |
| `total_cents` | `NUMBER(18,0)` | Required. |
| `amount_due_cents` | `NUMBER(18,0)` | Required; between zero and `total_cents`. |
| `currency` | `VARCHAR(3)` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; drives future incremental filtering. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

**Reconciliation formula.** These identities hold exactly, except for the three deliberate discrepancies in the anomaly ledger:

- `subtotal_cents` = sum of `line_amount_cents` where `line_type` is `subscription` or `services`.
- `discount_cents` = absolute value of the sum of `line_amount_cents` where `line_type` is `credit`. Credit lines carry positive `quantity` and negative `unit_amount_cents`, so their `line_amount_cents` is negative.
- `tax_cents` = sum of `line_amount_cents` where `line_type` is `tax`.
- `total_cents` = `subtotal_cents` - `discount_cents` + `tax_cents`.

**Amount due formula.** Let `settled` be the sum of `amount_cents` over `succeeded` payments for the invoice. Refunds are deliberately excluded: a refund reduces net cash but does not reopen accounts receivable, and including it would make a refunded paid invoice violate the settlement rule below.

- Status `paid`, `void`, `PAID_LATE`, or `complete`: `amount_due_cents` = 0.
- Status `draft`, `open`, or `uncollectible`: `amount_due_cents` = `total_cents` - `settled`, clamped to 0 through `total_cents`.
- An invoice may carry a settled status only when `settled` equals `total_cents`. The two rogue statuses are generated as fully settled paid invoices in every respect, including a populated `paid_at`; only the status string is defective, which is what staging normalizes.

**Net collections.** Not a stored column, defined here so downstream models compute it consistently: `settled` minus the sum of `amount_cents` over `succeeded` refunds for the invoice. May be less than `total_cents` on a fully paid invoice, and may be zero after a full refund.

About 8% of invoices carry an `updated_at` materially later than `issue_date`, reflecting a later status change, payment, or amount correction.

### `CORE_RAW.BILLING.INVOICE_LINES`

**Grain:** one invoice line.
**Primary key:** `invoice_line_id`.
**Foreign key:** `invoice_id -> BILLING.INVOICES.invoice_id`.
**Reference:** nullable `plan_code` normally exists in the plan catalog.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `invoice_line_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Required. |
| `plan_code` | `VARCHAR` | Nullable for tax, credit, and services lines. |
| `line_type` | `VARCHAR` | One of `subscription`, `services`, `credit`, `tax`. |
| `description` | `VARCHAR` | Required. |
| `quantity` | `NUMBER(10,0)` | Required; positive. Credit lines use positive quantity with negative `unit_amount_cents`. |
| `unit_amount_cents` | `NUMBER(18,0)` | Required. |
| `line_amount_cents` | `NUMBER(18,0)` | Required; equals `quantity` times `unit_amount_cents`. |
| `service_period_start` | `DATE` | Nullable. |
| `service_period_end` | `DATE` | Nullable; after `service_period_start`. |
| `updated_at` | `TIMESTAMP_TZ` | Required; consistent with the parent invoice's `updated_at` for revised invoices. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.PAYMENTS`

**Grain:** one payment attempt, including failed attempts.
**Primary key:** `payment_id`.
**Foreign keys:** `invoice_id -> BILLING.INVOICES.invoice_id`; `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `payment_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Always non-null; the deliberate orphans reference a well-formed ID that does not exist. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `status` | `VARCHAR` | One of `pending`, `succeeded`, `failed`. |
| `amount_cents` | `NUMBER(18,0)` | Required; positive. |
| `currency` | `VARCHAR(3)` | Required; equal to the invoice currency. |
| `paid_at` | `TIMESTAMP_TZ` | Required when `succeeded`, null otherwise; at or after the invoice `issue_date`. |
| `payment_method` | `VARCHAR` | One of `card`, `bank_transfer`, `ach`, `wire`. |
| `processor_reference` | `VARCHAR` | Required; unique. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

Most succeeded payments reconcile to invoice amount due; realistic partial payments and multiple payments against one invoice are included.

### `CORE_RAW.BILLING.REFUNDS`

**Grain:** one refund.
**Primary key:** `refund_id`.
**Foreign keys:** `payment_id -> BILLING.PAYMENTS.payment_id`; `invoice_id -> BILLING.INVOICES.invoice_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `refund_id` | `VARCHAR` | Required. |
| `payment_id` | `VARCHAR` | Required; references a `succeeded` payment. |
| `invoice_id` | `VARCHAR` | Required; equals the referenced payment's `invoice_id`. |
| `amount_cents` | `NUMBER(18,0)` | Required; positive and no more than the referenced payment's `amount_cents`. |
| `currency` | `VARCHAR(3)` | Required; equal to payment currency. |
| `reason` | `VARCHAR` | One of `customer_request`, `duplicate`, `fraud`, `service_issue`, `other`. |
| `status` | `VARCHAR` | One of `pending`, `succeeded`, `failed`. |
| `refunded_at` | `TIMESTAMP_TZ` | Null unless `succeeded`; at or after the payment's `paid_at`. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

## PRODUCT schema

### `CORE_RAW.PRODUCT.EVENTS`

**Grain:** one product event.
**Primary key:** `event_id`.
**Soft foreign keys:** nullable `account_id -> CRM.ACCOUNTS.account_id`; nullable `contact_id -> CRM.CONTACTS.contact_id`. Anonymous events may have both null.
**Intended load strategy:** `append`.

| Column | Type | Rules |
|---|---|---|
| `event_id` | `VARCHAR` | Required and globally unique. |
| `event_name` | `VARCHAR` | One of `login`, `page_view`, `feature_used`, `report_created`, `export_completed`, `api_call`, `invite_sent`. |
| `account_id` | `VARCHAR` | Nullable. |
| `contact_id` | `VARCHAR` | Nullable. |
| `anonymous_id` | `VARCHAR` | Nullable; required when both account and contact are null. |
| `session_id` | `VARCHAR` | Nullable for `api_call`; otherwise required. |
| `event_timestamp` | `TIMESTAMP_TZ` | Required; actual occurrence time and future dbt `event_time`. Preserves offsets such as `Z`, `-05:00`, `+01:00`, `+09:00`. |
| `received_at` | `TIMESTAMP_TZ` | Required; at or after `event_timestamp`. |
| `properties` | `VARCHAR` | Compact, valid JSON object as text. Shape varies by `event_name`. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required; at or after `received_at`. |

**On the `properties` type.** The raw column is `VARCHAR`, not `VARIANT`, because `COPY INTO` cannot populate a VARIANT column from a CSV field without a transforming select, and the Snowsight load wizard cannot do so at all. Landing JSON as text also matches how raw layers typically receive it. Staging applies `TRY_PARSE_JSON`, which gives the demo a natural place to show malformed-JSON handling. Every emitted string must parse, with exactly one exception: the single malformed value declared in the broken scenario, which must be the only parse failure in any scenario.

Late-arriving behavior, expressed as the gap between `event_timestamp` and `received_at`: about 5% arrive one day late, about 1% two to four days late. No duplicate `event_id` in the standard scenario.

## ERP schema

### `CORE_RAW.ERP.COST_CENTERS`

**Grain:** one current cost center.
**Primary key:** `cost_center_id`.
**Intended load strategy:** `replace_initial_then_merge`.

| Column | Type | Rules |
|---|---|---|
| `cost_center_id` | `VARCHAR` | Required. |
| `cost_center_name` | `VARCHAR` | Required. |
| `business_unit` | `VARCHAR` | One of `Sales`, `Marketing`, `Product`, `Engineering`, `Finance`, `Operations`, `G&A`. |
| `manager_name` | `VARCHAR` | Required. |
| `effective_from` | `DATE` | Required. |
| `effective_to` | `DATE` | Nullable; null when active. |
| `is_active` | `BOOLEAN` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.ERP.GL_ENTRIES`

**Grain:** one journal line. Multiple lines share a `journal_id`.
**Primary key:** `gl_entry_id`.
**Foreign key:** `cost_center_id -> ERP.COST_CENTERS.cost_center_id`.
**Soft relationship:** nullable `invoice_id -> BILLING.INVOICES.invoice_id`.
**Reference:** `account_code` normally exists in the chart-of-accounts seed.
**Intended load strategy:** `append`.

| Column | Type | Rules |
|---|---|---|
| `gl_entry_id` | `VARCHAR` | Required. |
| `journal_id` | `VARCHAR` | Required. |
| `line_number` | `NUMBER(10,0)` | Required; unique within journal. |
| `posted_date` | `DATE` | Required. |
| `account_code` | `VARCHAR` | Required. |
| `cost_center_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Nullable; populated for invoice-related entries. |
| `description` | `VARCHAR` | Required. |
| `debit_cents` | `NUMBER(18,0)` | Required; default zero and nonnegative. |
| `credit_cents` | `NUMBER(18,0)` | Required; default zero and nonnegative. |
| `currency` | `VARCHAR(3)` | Required. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

Each journal has at least two lines. Debits equal credits by `journal_id` and currency in clean data. Invoice journals debit Accounts Receivable and credit Deferred Revenue or Revenue as appropriate.

## MARKET schema

### `CORE_RAW.MARKET.FX_RATES`

**Grain:** one daily exchange rate from a currency to USD.
**Primary key:** (`rate_date`, `from_currency`, `to_currency`).
**Intended load strategy:** `merge`.

| Column | Type | Rules |
|---|---|---|
| `rate_date` | `DATE` | Required. |
| `from_currency` | `VARCHAR(3)` | Required; one of the shared currencies. |
| `to_currency` | `VARCHAR(3)` | Required; always `USD`. |
| `rate` | `NUMBER(18,8)` | Required and positive; USD-to-USD is exactly 1. |
| `provider` | `VARCHAR` | Required; `DEMO_MARKET_DATA`. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required; maximum value is 30 hours before the reference time. |

Rates follow a mean-reverting random walk rather than independent draws. Weekends carry forward Friday's rate under a new `rate_date`.

## Relationships

Hard relationships hold in clean and standard scenarios unless listed as an anomaly:

- CRM accounts to sales reps.
- CRM contacts and opportunities to accounts.
- Opportunities to sales reps.
- Billing subscriptions, invoices, payments, and refunds to billing customers.
- Invoice lines to invoices.
- Refunds to payments and invoices.
- ERP entries to cost centers.

Soft or intentionally imperfect:

- Billing customers to CRM accounts.
- Payments to invoices: three standard orphans.
- Product events to CRM accounts and contacts, because anonymous and delayed identity resolution are valid.
- ERP entries to billing invoices, because many journals are unrelated to invoices.

Dates are temporally consistent: children do not predate parents, refunds do not predate payments, paid timestamps do not predate invoice issue dates.

## Standard anomaly ledger

Exact counts at `scale = 1`, scaled proportionally above that with a floor of one each. Every affected key is recorded in `anomaly_manifest.csv`.

| Anomaly | Count | Expected dbt behavior | Expected severity |
|---|---:|---|---|
| Separate CRM account IDs representing the same real company, with case/whitespace/punctuation differences | 8 duplicate rows within the 250 | Account matching macro consolidates them to a conformed customer | Unit-tested cleaning case; source warning if tested |
| CRM domains containing protocol, `www.`, uppercase, or trailing slash | 15 | Staging normalizes domain | Pass after cleaning |
| Free-text country variants and misspellings | 25 rows across CRM/BILLING | Country macro maps to ISO code; unknowns become `UNKNOWN` | Pass after cleaning; optional raw warning |
| Truly unrecognized country value | 2 | Map to `UNKNOWN` and store failing raw records | Warning |
| Soft-deleted CRM accounts | About 3% | Excluded from current conformed output but retained by snapshot history | Pass |
| Billing customers with missing `crm_account_id` but matchable name/domain | 10 | Account matching fills conformed relationship | Pass after cleaning |
| Billing customers with incorrect `crm_account_id` but strong domain match | 3 | Matching logic chooses the correct account and flags discrepancy | Warning or audit output |
| Rogue invoice status `PAID_LATE` or `complete`, generated as fully settled paid invoices | 4 | Normalize to an approved status or `unknown` | Raw accepted-values warning; pass after cleaning |
| Invoice arithmetic discrepancy of 1–3 cents against the reconciliation formula | 3 | Recompute or flag without changing the raw record | Warning |
| Payments referencing nonexistent invoice IDs | 3 | Retain as unmatched payments and store relationship failures | Warning below error threshold |
| Missing daily FX rate | 2 non-USD currency/date rows | Conversion uses the most recent prior rate and flags fallback | Warning |
| Product events with `received_at` two to four days after `event_timestamp` | About 1% | Late-arrival metric detects them | Expected behavior |
| Product events with mixed timestamp offsets | About 20% | Normalize to UTC in staging | Pass after cleaning |
| Contacts with email casing or surrounding whitespace | 20 | Normalize in staging | Pass after cleaning |
| Contacts with null email | 5 | Allowed because none are primary | Pass |
| ERP journals imbalanced by exactly 1 cent | 2 journals | Singular test stores failures | Warning |

The standard scenario contains no duplicate technical primary keys, no null required technical keys, no negative payments, no impossible dates, and no unresolved hard foreign-key failures, except the three intentional payment-to-invoice orphans.

## Broken scenario additions

Opt-in; causes error-severity checks or tests to fail. Adds:

- Two duplicate `invoice_id` records with conflicting values.
- One null `account_id`.
- Twenty additional orphan payments, exceeding the error threshold.
- One invoice with negative `total_cents`.
- One refund larger than its successful payment.
- One subscription with `current_period_end` before `current_period_start`.
- One event whose `event_timestamp` is seven days after `as_of_date`.
- One event whose `properties` value is malformed JSON.
- One GL journal out of balance by at least 10,000 cents.
- MARKET `_loaded_at` older than 72 hours.
- One unsupported currency `XYZ` with no FX rate.

The anomaly manifest labels these as expected errors.

## Seed alignment

The generator does not create dbt seed CSVs, but generated values align with these future seeds:

- `country_codes`: accepted raw variants mapped to ISO alpha-2 codes and canonical names.
- `plan_catalog`: plan code, plan name, billing interval, list price in cents, currency, product family.
- `chart_of_accounts`: account code, account name, account type, financial statement, sign convention.

The validation output includes a machine-readable inventory of every country variant, plan code, and account code used, so the seeds can be authored without guessing.

## Realism requirements

- Lifecycle is coherent: CRM account precedes billing customer, which precedes subscription, which precedes invoices, which precede successful payment.
- Not every CRM account becomes a customer; about 70% do.
- About 75% of active billing customers have an active subscription.
- Late payments, partial payments, multiple payments against one invoice, and refunds are all visible in current state.
- Upgrades, downgrades, pauses, cancellations, and reactivations are visible only as current-state residue plus the plan-code sequence on invoice lines, and are not claimed as directly observable transitions.
- Annual plans produce annual invoice patterns; monthly plans produce monthly patterns.
- Invoice totals reconcile to invoice lines per the stated formula, except the three intentional discrepancies.
- Won opportunities are more likely to map to billing customers, but the systems do not align perfectly.
- Product activity concentrates among active customers and declines after cancellation.
- Names, emails, domains, and descriptions are fictional.

## R implementation

- Dependencies: `readr` and `jsonlite` only. The generator otherwise uses base R, keeping the dependency surface small and the output stable.
- Reproducibility comes from a single `set.seed(seed)` at the top of the run. Identical output is expected for the same seed, scenario, scale, and as-of date on a given R installation.
- Write CSVs with `readr::write_csv(na = "")`, then verify no field contains the literal strings `NA`, `NULL`, or `NaN`.
- Each table has its own build function; a single orchestrator handles ordering, referential integrity, anomaly injection, validation, and output.

## Demo script requirements

`incremental_demo.sql` exists because the generator emits current state only. It must be safe to run, rerun, and fully undo.

- **Backup.** Before any mutation, create zero-copy clones named `<TABLE>_DEMO_BACKUP`, guarded so an existing backup is never overwritten by an already-mutated table. The clone is the source of truth for reset.
- **Inserts.** Every inserted row uses a reserved `demo_` prefix on its technical key. No inserted row collides with a generator-produced ID. Reset deletes by this prefix.
- **Updates.** Invoice status and `paid_at` transitions, new succeeded payments against open invoices, subscription plan changes constituting an observable upgrade or downgrade, and account soft-deletes. Every update advances both `updated_at` and `_loaded_at`, and `_loaded_at` stays at or after `updated_at`. Soft-deletes set `is_deleted`, `deleted_at`, `updated_at`, and `_loaded_at` together.
- **Reset.** Deletes all `demo_`-prefixed rows, restores mutated rows from the backup clones, verifies row counts, then drops the clones.
- **Sections.** Organized so backup, insert, update, verify, and reset can each be run independently.

## Generator validation

The script exits nonzero if any unexpected condition is found:

- Duplicate technical primary keys outside the broken scenario.
- Missing required keys outside the broken scenario.
- Unexpected hard relationship failures.
- Invalid JSON in `properties`, other than the single declared broken-scenario value.
- Invalid timestamp ordering, including any `_loaded_at` earlier than its row's `updated_at`, `received_at`, or `created_at`.
- Currency outside the allowed domain, except `XYZ` in broken mode.
- Invoice-line reconciliation outside the listed anomalies.
- Amount-due values outside the stated formula.
- Refunds exceeding payments outside broken mode.
- Unbalanced journals outside the listed anomalies.
- Literal `NA`, `NULL`, or `NaN` strings in any output field.
- Missing manifest entries or row-count mismatches.

On completion it prints:

- Seed, scenario, scale, as-of date, generation timestamp, R version.
- Row count per table.
- Min and max business timestamps and `_loaded_at` per table.
- Primary-key duplicate count per table.
- Foreign-key orphan count per declared relationship.
- Count per anomaly type.
- The seed-alignment inventory.
- Paths of all generated files.
