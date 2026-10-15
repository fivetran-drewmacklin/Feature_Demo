# Raw data generator specification

## Instructions for Claude

Build a deterministic R-based fake-data generator for a fictional B2B SaaS company. The generated CSV files will be loaded outside dbt into Snowflake database `CORE_RAW`. dbt will then clean, test, snapshot, and model the data.

Implement this specification exactly. Do not rename tables or columns without asking. The standard scenario must contain realistic defects and warning-level test failures while still allowing a production dbt build to succeed. Also provide an optional broken scenario with error-level failures.

## Required deliverables

Create:

1. `setup/generate_raw_data.R` — the generator entry point.
2. Supporting R files under `setup/generator/` if useful.
3. `setup/generated/initial/<source>/<table>.csv` — historical baseline files.
4. `setup/generated/daily/YYYY-MM-DD/<source>/<table>.csv` — 14 sequential daily batches.
5. `setup/generated/manifest.csv` — one row per generated file with source, table, batch date, row count, load strategy, and file path.
6. `setup/generated/anomaly_manifest.csv` — every deliberately injected anomaly with scenario, table, technical key, anomaly type, expected dbt handling, and expected severity.
7. `setup/raw_table_ddl.sql` — Snowflake DDL for every raw table using the types below. Tables must be created in the existing `CORE_RAW` schemas and owned by `SYSADMIN`.
8. `setup/load_raw_data.md` — concise instructions for loading the initial files and then individual daily batches in order.
9. A validation summary printed by the R script showing row counts, key uniqueness, relationship counts, date ranges, and anomaly counts.

Do not include credentials or connect to Snowflake from R. Generated files should normally be excluded from Git; the generator, DDL, manifests, and documentation should be tracked.

## Generator interface

Support command-line arguments with these defaults:

- `--scenario standard` — valid values: `clean`, `standard`, `broken`.
- `--seed 20250301` — all output must be reproducible for the same seed and `as_of_date`.
- `--as_of_date <today in UTC>` — controls the end of the generated history.
- `--history_days 730` — approximately two years of history.
- `--daily_batches 14` — number of daily batch folders after the initial load.
- `--scale 1` — multiplier for volumes. Preserve anomaly rates and relationship integrity as scale changes.
- `--output_dir setup/generated`.

Scenario behavior:

- `clean`: no deliberate warning or error anomalies, but retain normal business variation, account changes, soft deletes, late events, and mixed time zones.
- `standard`: inject the deterministic warning/cleaning cases listed below. This is the default demo dataset and must not cause error-severity dbt tests to fail after intended cleaning.
- `broken`: include all standard anomalies plus the explicitly listed error-level failures.

## Time and batching requirements

- Historical period begins `as_of_date - history_days`.
- Initial files contain records through `as_of_date - daily_batches`.
- Daily folders contain one batch per UTC date through `as_of_date`.
- Use realistic seasonality: lower weekend product activity, modest month-end invoice volume, and gradual customer growth.
- Every table has `_loaded_at TIMESTAMP_TZ`.
- For normal records, `_loaded_at` is after the record's creation or event timestamp.
- Latest standard load ages, relative to generation time:
  - CRM: no more than 2 hours old.
  - BILLING: no more than 2 hours old.
  - PRODUCT: no more than 1 hour old.
  - ERP: no more than 8 hours old.
  - MARKET: 30 hours old, deliberately producing a freshness warning if configured with `warn_after: 24 hours` and `error_after: 48 hours`.
- The `broken` scenario makes MARKET more than 72 hours stale to demonstrate a freshness error.
- Timestamps in CSVs must be ISO-8601 with an explicit UTC offset. Preserve mixed offsets for product event timestamps.

## Load strategies

The manifest must identify one of these strategies for each table:

- `replace_initial_then_merge`: initial file replaces the table; daily files are merged by the listed primary key. Use for mutable source entities.
- `append`: initial and daily files append. Technical primary keys remain globally unique.
- `merge`: initial and daily files merge by a composite key.

The generated daily batches must be usable sequentially. Do not generate only the final state.

## CSV conventions

- UTF-8, comma-delimited, header row included.
- Double-quote fields when needed and escape embedded quotes correctly.
- Empty field represents SQL `NULL`; never emit the strings `NA`, `NULL`, or `NaN`.
- Boolean values are lowercase `true` and `false`.
- Dates use `YYYY-MM-DD`.
- Timestamps use ISO-8601 with offset.
- Monetary source fields ending in `_cents` are whole-number minor currency units.
- JSON for VARIANT columns is compact, valid JSON in one CSV field.
- IDs are stable strings with readable prefixes, for example `acct_000001` and `inv_000001`.

## Small starting volumes

Approximate final row counts at `scale = 1`. A variation of plus or minus 10% is acceptable except for deterministic anomaly counts.

| Source | Table | Approximate rows |
|---|---|---:|
| CRM | `accounts` | 250 current accounts plus change rows in daily batches |
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
| MARKET | `fx_rates` | About 3,650: five currencies over two years |

## Shared business domains

Use these values consistently:

- Currencies: `USD`, `EUR`, `GBP`, `CAD`, `AUD`.
- Canonical countries: United States/US, Canada/CA, United Kingdom/GB, Germany/DE, France/FR, Australia/AU, Netherlands/NL, Ireland/IE, Spain/ES, Japan/JP.
- Industries: Software, Financial Services, Healthcare, Retail, Manufacturing, Professional Services, Media, Education.
- Account tiers: `enterprise`, `mid_market`, `smb`.
- Plan codes, aligned with the future `plan_catalog` seed:
  - `STARTER_MONTHLY`
  - `STARTER_ANNUAL`
  - `GROWTH_MONTHLY`
  - `GROWTH_ANNUAL`
  - `ENTERPRISE_ANNUAL`
- ERP account codes, aligned with the future chart-of-accounts seed:
  - `1000` Cash
  - `1100` Accounts Receivable
  - `2000` Deferred Revenue
  - `4000` Subscription Revenue
  - `4010` Services Revenue
  - `5000` Hosting Cost
  - `6100` Sales and Marketing
  - `6200` Research and Development
  - `6300` General and Administrative

## CRM schema

### `CORE_RAW.CRM.SALES_REPS`

**Grain:** one current row per sales representative.  
**Primary key:** `sales_rep_id`.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `sales_rep_id` | `VARCHAR` | Required; stable ID. |
| `first_name` | `VARCHAR` | Required. |
| `last_name` | `VARCHAR` | Required. |
| `email` | `VARCHAR` | Required; unique after lowercase normalization. |
| `region` | `VARCHAR` | One of `NA`, `EMEA`, `APAC`. |
| `manager_sales_rep_id` | `VARCHAR` | Nullable self-reference to `sales_rep_id`; top-level managers are null. |
| `hire_date` | `DATE` | Required; not after `as_of_date`. |
| `is_active` | `BOOLEAN` | Required. About 10% inactive. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.CRM.ACCOUNTS`

**Grain:** one current source row per CRM account ID. Separate IDs may represent the same real business.  
**Primary key:** `account_id`.  
**Foreign key:** `owner_sales_rep_id -> CRM.SALES_REPS.sales_rep_id`.  
**Load strategy:** `replace_initial_then_merge`. Daily batches must update existing account rows so the dbt timestamp snapshot can capture history using `updated_at`.

| Column | Snowflake type | Rules |
|---|---|---|
| `account_id` | `VARCHAR` | Required; stable CRM ID. |
| `account_name` | `VARCHAR` | Required except in broken scenario. Preserve source casing and whitespace defects. |
| `website_domain` | `VARCHAR` | Nullable; mostly lowercase domains, with deliberate casing, protocol, `www.`, and trailing-slash variants. |
| `billing_country` | `VARCHAR` | Nullable free text; include canonical names, ISO codes, abbreviations, misspellings, and whitespace. |
| `industry` | `VARCHAR` | Nullable; use shared industry domain. |
| `employee_count` | `NUMBER(10,0)` | Nullable; nonnegative in standard scenario. |
| `annual_revenue` | `NUMBER(18,2)` | Nullable CRM estimate in account currency. |
| `account_currency` | `VARCHAR(3)` | Required; shared currency domain. |
| `account_tier` | `VARCHAR` | Required; `enterprise`, `mid_market`, or `smb`. |
| `owner_sales_rep_id` | `VARCHAR` | Required in standard scenario. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; greater than or equal to `created_at`; changes whenever tracked attributes change. |
| `is_deleted` | `BOOLEAN` | Required; soft-delete flag. |
| `deleted_at` | `TIMESTAMP_TZ` | Required only when `is_deleted = true`. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required; greater than or equal to `updated_at`. |

Account updates should change tier, owner, industry, employee count, name, or country over time. Update about 15% of accounts at least once across the daily batches and about 3% twice. Soft-delete about 3%.

### `CORE_RAW.CRM.CONTACTS`

**Grain:** one current row per CRM contact.  
**Primary key:** `contact_id`.  
**Foreign key:** `account_id -> CRM.ACCOUNTS.account_id`.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `contact_id` | `VARCHAR` | Required. |
| `account_id` | `VARCHAR` | Required in standard scenario. |
| `first_name` | `VARCHAR` | Required. |
| `last_name` | `VARCHAR` | Required. |
| `email` | `VARCHAR` | Nullable; mostly valid, with a small number of casing and whitespace defects. |
| `job_title` | `VARCHAR` | Nullable. |
| `is_primary` | `BOOLEAN` | Required; at most one active primary contact per account in standard scenario. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `is_deleted` | `BOOLEAN` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.CRM.OPPORTUNITIES`

**Grain:** one current row per sales opportunity.  
**Primary key:** `opportunity_id`.  
**Foreign keys:** `account_id -> CRM.ACCOUNTS.account_id`; `owner_sales_rep_id -> CRM.SALES_REPS.sales_rep_id`.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `opportunity_id` | `VARCHAR` | Required. |
| `account_id` | `VARCHAR` | Required. |
| `owner_sales_rep_id` | `VARCHAR` | Required. |
| `opportunity_name` | `VARCHAR` | Required. |
| `stage` | `VARCHAR` | One of `prospecting`, `qualification`, `proposal`, `negotiation`, `closed_won`, `closed_lost`. |
| `amount_cents` | `NUMBER(18,0)` | Required; nonnegative. |
| `currency` | `VARCHAR(3)` | Required. |
| `probability` | `NUMBER(5,2)` | Between 0 and 1 inclusive. |
| `close_date` | `DATE` | Required. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `is_deleted` | `BOOLEAN` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

Stages should move forward over daily batches, with a small number of realistic regressions such as negotiation back to proposal.

## BILLING schema

### `CORE_RAW.BILLING.CUSTOMERS`

**Grain:** one current billing customer.  
**Primary key:** `billing_customer_id`.  
**Soft cross-source relationship:** `crm_account_id -> CRM.ACCOUNTS.account_id`; this is nullable and occasionally wrong because account matching is part of the dbt demo.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `billing_customer_id` | `VARCHAR` | Required. |
| `crm_account_id` | `VARCHAR` | Nullable; usually exact, sometimes missing or incorrect in standard scenario. |
| `customer_name` | `VARCHAR` | Required; may vary from CRM name in punctuation, suffix, case, and whitespace. |
| `website_domain` | `VARCHAR` | Nullable; used as a secondary matching key. |
| `billing_email` | `VARCHAR` | Nullable. |
| `billing_country` | `VARCHAR` | Nullable free text. |
| `currency` | `VARCHAR(3)` | Required. |
| `status` | `VARCHAR` | One of `active`, `delinquent`, `closed`. |
| `tax_id` | `VARCHAR` | Nullable. |
| `created_at` | `TIMESTAMP_TZ` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.SUBSCRIPTIONS`

**Grain:** one current subscription. A customer may have multiple subscriptions over time or concurrently.  
**Primary key:** `subscription_id`.  
**Foreign key:** `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`.  
**Reference:** `plan_code` must normally exist in the future `plan_catalog` seed.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `subscription_id` | `VARCHAR` | Required. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `plan_code` | `VARCHAR` | Required. |
| `status` | `VARCHAR` | One of `trialing`, `active`, `past_due`, `paused`, `canceled`. |
| `started_at` | `TIMESTAMP_TZ` | Required. |
| `current_period_start` | `DATE` | Required. |
| `current_period_end` | `DATE` | Required and after start. |
| `canceled_at` | `TIMESTAMP_TZ` | Required only for canceled subscriptions. |
| `quantity` | `NUMBER(10,0)` | Required; at least 1. |
| `unit_price_cents` | `NUMBER(18,0)` | Required; nonnegative. |
| `currency` | `VARCHAR(3)` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.INVOICES`

**Grain:** one current invoice.  
**Primary key and dbt incremental `unique_key`:** `invoice_id`.  
**Foreign keys:** `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`; nullable `subscription_id -> BILLING.SUBSCRIPTIONS.subscription_id`.  
**Load strategy:** `replace_initial_then_merge`. At least 8% of invoices must be updated in later batches after initial creation, including status, paid timestamp, and amounts where appropriate.

| Column | Snowflake type | Rules |
|---|---|---|
| `invoice_id` | `VARCHAR` | Required. |
| `invoice_number` | `VARCHAR` | Required; unique human-readable number. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `subscription_id` | `VARCHAR` | Nullable for one-off charges. |
| `status` | `VARCHAR` | Normally `draft`, `open`, `paid`, `void`, or `uncollectible`; standard scenario includes rogue values. |
| `issue_date` | `DATE` | Required. |
| `due_date` | `DATE` | Required; on or after issue date. |
| `paid_at` | `TIMESTAMP_TZ` | Required only when paid. |
| `subtotal_cents` | `NUMBER(18,0)` | Required. |
| `discount_cents` | `NUMBER(18,0)` | Required; default zero. |
| `tax_cents` | `NUMBER(18,0)` | Required; default zero. |
| `total_cents` | `NUMBER(18,0)` | Required; normally subtotal minus discount plus tax. |
| `amount_due_cents` | `NUMBER(18,0)` | Required; between zero and total in standard scenario. |
| `currency` | `VARCHAR(3)` | Required. |
| `updated_at` | `TIMESTAMP_TZ` | Required; drives incremental filtering and updates. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.INVOICE_LINES`

**Grain:** one invoice line.  
**Primary key:** `invoice_line_id`.  
**Foreign key:** `invoice_id -> BILLING.INVOICES.invoice_id`.  
**Reference:** nullable `plan_code` normally exists in the plan catalog.  
**Load strategy:** `replace_initial_then_merge` because updated invoices may update their lines.

| Column | Snowflake type | Rules |
|---|---|---|
| `invoice_line_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Required. |
| `plan_code` | `VARCHAR` | Nullable for tax, credit, and services lines. |
| `line_type` | `VARCHAR` | One of `subscription`, `services`, `credit`, `tax`. |
| `description` | `VARCHAR` | Required. |
| `quantity` | `NUMBER(10,0)` | Required; positive except credit lines may use a positive quantity with negative unit amount. |
| `unit_amount_cents` | `NUMBER(18,0)` | Required. |
| `line_amount_cents` | `NUMBER(18,0)` | Required; normally quantity times unit amount. |
| `service_period_start` | `DATE` | Nullable. |
| `service_period_end` | `DATE` | Nullable; after period start. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.PAYMENTS`

**Grain:** one payment attempt, including failed attempts.  
**Primary key:** `payment_id`.  
**Foreign keys:** `invoice_id -> BILLING.INVOICES.invoice_id`; `billing_customer_id -> BILLING.CUSTOMERS.billing_customer_id`.  
**Load strategy:** `replace_initial_then_merge` because pending payments may later succeed or fail.

| Column | Snowflake type | Rules |
|---|---|---|
| `payment_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Required, except deliberate standard orphans. |
| `billing_customer_id` | `VARCHAR` | Required. |
| `status` | `VARCHAR` | One of `pending`, `succeeded`, `failed`. |
| `amount_cents` | `NUMBER(18,0)` | Required; positive. |
| `currency` | `VARCHAR(3)` | Required. |
| `paid_at` | `TIMESTAMP_TZ` | Nullable for pending/failed attempts. |
| `payment_method` | `VARCHAR` | One of `card`, `bank_transfer`, `ach`, `wire`. |
| `processor_reference` | `VARCHAR` | Required; unique. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.BILLING.REFUNDS`

**Grain:** one refund.  
**Primary key:** `refund_id`.  
**Foreign keys:** `payment_id -> BILLING.PAYMENTS.payment_id`; `invoice_id -> BILLING.INVOICES.invoice_id`.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `refund_id` | `VARCHAR` | Required. |
| `payment_id` | `VARCHAR` | Required. |
| `invoice_id` | `VARCHAR` | Required. |
| `amount_cents` | `NUMBER(18,0)` | Required; positive and no more than the successful payment total. |
| `currency` | `VARCHAR(3)` | Required and equal to payment currency. |
| `reason` | `VARCHAR` | One of `customer_request`, `duplicate`, `fraud`, `service_issue`, `other`. |
| `status` | `VARCHAR` | One of `pending`, `succeeded`, `failed`. |
| `refunded_at` | `TIMESTAMP_TZ` | Nullable until succeeded. |
| `updated_at` | `TIMESTAMP_TZ` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

## PRODUCT schema

### `CORE_RAW.PRODUCT.EVENTS`

**Grain:** one product event.  
**Primary key:** `event_id`.  
**Soft foreign keys:** nullable `account_id -> CRM.ACCOUNTS.account_id`; nullable `contact_id -> CRM.CONTACTS.contact_id`. Anonymous events may have both null.  
**Load strategy:** `append`.

| Column | Snowflake type | Rules |
|---|---|---|
| `event_id` | `VARCHAR` | Required and globally unique. |
| `event_name` | `VARCHAR` | One of `login`, `page_view`, `feature_used`, `report_created`, `export_completed`, `api_call`, `invite_sent`. |
| `account_id` | `VARCHAR` | Nullable. |
| `contact_id` | `VARCHAR` | Nullable. |
| `anonymous_id` | `VARCHAR` | Nullable; required when both account and contact are null. |
| `session_id` | `VARCHAR` | Nullable for API calls; otherwise required. |
| `event_timestamp` | `TIMESTAMP_TZ` | Required; actual occurrence time and future dbt `event_time`. Preserve offsets such as `Z`, `-05:00`, `+01:00`, and `+09:00`. |
| `received_at` | `TIMESTAMP_TZ` | Required; equal to or after event time. |
| `properties` | `VARIANT` | Valid JSON object. Shape varies by event name. Include keys such as feature name, page path, report type, export format, API endpoint, response time, user agent, and source. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required; equal to or after received time. |

Late-arriving behavior:

- About 5% arrive one day late.
- About 1% arrive two to four days late and appear in a later daily batch than their `event_timestamp` date.
- Standard scenario has no duplicate `event_id`.
- Keep this volume modest for now; the generator must support scaling later.

## ERP schema

### `CORE_RAW.ERP.COST_CENTERS`

**Grain:** one current cost center.  
**Primary key:** `cost_center_id`.  
**Load strategy:** `replace_initial_then_merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `cost_center_id` | `VARCHAR` | Required. |
| `cost_center_name` | `VARCHAR` | Required. |
| `business_unit` | `VARCHAR` | One of `Sales`, `Marketing`, `Product`, `Engineering`, `Finance`, `Operations`, `G&A`. |
| `manager_name` | `VARCHAR` | Required. |
| `effective_from` | `DATE` | Required. |
| `effective_to` | `DATE` | Nullable. |
| `is_active` | `BOOLEAN` | Required. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. |

### `CORE_RAW.ERP.GL_ENTRIES`

**Grain:** one journal line. Multiple lines share a `journal_id`.  
**Primary key:** `gl_entry_id`.  
**Foreign key:** `cost_center_id -> ERP.COST_CENTERS.cost_center_id`.  
**Soft relationship:** nullable `invoice_id -> BILLING.INVOICES.invoice_id`.  
**Reference:** `account_code` must normally exist in the chart-of-accounts seed.  
**Load strategy:** `append`.

| Column | Snowflake type | Rules |
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

Each journal must have at least two lines. Debits must equal credits by `journal_id` and currency in clean data. Standard anomalies are listed below.

## MARKET schema

### `CORE_RAW.MARKET.FX_RATES`

**Grain:** one daily exchange rate from a currency to USD.  
**Primary key:** (`rate_date`, `from_currency`, `to_currency`).  
**Load strategy:** `merge`.

| Column | Snowflake type | Rules |
|---|---|---|
| `rate_date` | `DATE` | Required. |
| `from_currency` | `VARCHAR(3)` | Required; one of shared currencies. |
| `to_currency` | `VARCHAR(3)` | Required; always `USD` in this dataset. |
| `rate` | `NUMBER(18,8)` | Required and positive; USD-to-USD is exactly 1. |
| `provider` | `VARCHAR` | Required; use `DEMO_MARKET_DATA`. |
| `_loaded_at` | `TIMESTAMP_TZ` | Required. Latest standard value is deliberately 30 hours old. |

Generate smoothly varying, plausible rates rather than independent random values. Include weekends by carrying forward Friday's rate with a new `rate_date`.

## Relationship summary

Hard relationships should hold in clean and standard scenarios unless explicitly listed as an anomaly:

- CRM accounts to sales reps.
- CRM contacts and opportunities to accounts.
- Opportunities to sales reps.
- Billing subscriptions, invoices, payments, and refunds to billing customers.
- Invoice lines to invoices.
- Refunds to payments and invoices.
- ERP entries to cost centers.

Soft or intentionally imperfect relationships:

- Billing customers to CRM accounts.
- Payments to invoices: a few standard orphans.
- Product events to CRM accounts/contacts because anonymous and delayed identity resolution are valid.
- ERP entries to billing invoices because many journals are unrelated to invoices.

Dates must be temporally consistent: children cannot normally predate parents, refunds cannot predate payments, and paid timestamps cannot predate invoice issue dates.

## Standard anomaly ledger

Inject these exact counts at `scale = 1`. Scale counts proportionally for larger scales while keeping at least one of each anomaly. Record every affected key in `anomaly_manifest.csv`.

| Anomaly | Count | Expected dbt behavior | Expected severity |
|---|---:|---|---|
| Separate CRM account IDs representing the same real company, with case/whitespace/punctuation differences | 8 duplicate pairs | Account matching macro consolidates them to a conformed customer | Unit-tested cleaning case; source warning if tested |
| CRM domains containing protocol, `www.`, uppercase, or trailing slash | 15 | Staging normalizes domain | Pass after cleaning |
| Free-text country variants and misspellings | 25 rows across CRM/BILLING | Country macro maps to ISO code; unknowns become `UNKNOWN` | Pass after cleaning; optional raw warning |
| Truly unrecognized country value | 2 | Map to `UNKNOWN` and store failing raw records | Warning |
| Soft-deleted CRM accounts | About 3% | Excluded from current conformed output but retained by snapshot history | Pass |
| Billing customers with missing `crm_account_id` but matchable name/domain | 10 | Account matching fills conformed relationship | Pass after cleaning |
| Billing customers with incorrect `crm_account_id` but strong domain match | 3 | Matching logic chooses the correct account and flags discrepancy | Warning or audit output |
| Rogue invoice status `PAID_LATE` or `complete` | 4 | Normalize to an approved status or `unknown` | Raw accepted-values warning; pass after cleaning |
| Invoice arithmetic discrepancy of 1–3 cents | 3 | Recompute or flag discrepancy without changing the raw record | Warning |
| Payments referencing nonexistent invoice IDs | 3 | Retain as unmatched payments and store relationship failures | Warning with threshold below error limit |
| Missing daily FX rate | 2 non-USD currency/date rows | Currency conversion uses the most recent prior rate and flags fallback | Warning |
| Product events arriving two to four days late | About 1% | Included when later batch is loaded; late-arrival metric can detect them | Expected behavior |
| Product events with mixed timestamp offsets | About 20% | Normalize to UTC in staging | Pass after cleaning |
| Contacts with email casing or surrounding whitespace | 20 | Normalize in staging | Pass after cleaning |
| Contacts with null email | 5 | Allowed unless the contact is marked primary | Pass |
| ERP journals imbalanced by exactly 1 cent | 2 journals | Singular test stores failures | Warning |

Do not create duplicate technical primary keys, null required technical keys, negative payments, impossible dates, or unresolved hard foreign-key failures in the standard scenario except the three intentional payment-to-invoice orphans.

## Broken scenario additions

The `broken` scenario is opt-in and should cause error-severity checks or tests. Add:

- Two duplicate `invoice_id` records with conflicting values.
- One null `account_id`.
- Twenty additional orphan payments, exceeding the intended error threshold.
- One invoice with negative `total_cents`.
- One refund larger than its successful payment.
- One subscription with `current_period_end < current_period_start`.
- One event whose `event_timestamp` is seven days in the future.
- One GL journal materially out of balance by at least 10,000 cents.
- MARKET freshness older than 72 hours.
- One unsupported currency `XYZ` with no FX rate.

The anomaly manifest must label these as expected errors.

## Seed alignment data

The R generator does not need to create dbt seed CSVs, but generated values must align with these future seeds:

- `country_codes`: accepted raw variants mapped to ISO alpha-2 country codes and canonical names.
- `plan_catalog`: plan code, plan name, billing interval, list price in cents, currency, and product family.
- `chart_of_accounts`: account code, account name, account type, financial statement, and sign convention.

Include a machine-readable section in the validation output listing every country variant, plan code, and account code used so the seeds can be authored without guessing.

## Data realism requirements

- Customer lifecycle should be coherent: CRM account precedes billing customer; billing customer precedes subscription; subscription precedes invoices; successful payment follows invoice.
- Not every CRM account becomes a customer. About 70% should have billing customers.
- About 75% of active billing customers have an active subscription.
- Include upgrades, downgrades, pauses, cancellations, reactivations, late payments, partial payments, and refunds.
- Annual plans produce annual invoice patterns; monthly plans produce monthly patterns.
- Invoice totals should reconcile to invoice lines except the three intentional standard discrepancies.
- Most successful payments should reconcile to invoice amount due; allow realistic partial and multiple payments.
- Won opportunities should be more likely to map to billing customers, but the systems should not align perfectly.
- Product activity should be concentrated among active customers and decline after cancellation.
- ERP invoice journals should debit Accounts Receivable and credit Deferred Revenue or Revenue as appropriate.
- Names, emails, domains, and descriptions must be fictional. Do not use real people, companies, or secrets.

## Generator validation requirements

Fail the R script with a nonzero exit status if any unexpected condition is found:

- Duplicate technical primary keys outside the broken scenario.
- Missing required keys outside the broken scenario.
- Unexpected hard relationship failures.
- Invalid JSON.
- Invalid timestamp ordering.
- Currency outside the allowed domain, except `XYZ` in broken mode.
- Invoice-line reconciliation outside listed anomalies.
- Refunds exceeding payments outside broken mode.
- Unbalanced journals outside listed anomalies.
- Missing manifest entries or row-count mismatches.

At completion, print:

- Seed, scenario, scale, and as-of date.
- Row count per table and batch.
- Min/max business timestamps and `_loaded_at` per table.
- Primary-key duplicate count per table.
- Foreign-key orphan count per declared relationship.
- Count per anomaly type.
- Paths of all generated files.
