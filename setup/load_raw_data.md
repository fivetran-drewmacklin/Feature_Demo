# Loading the generated CSVs into Snowflake

Fourteen files, loaded through the Snowsight UI. Budget about twenty minutes.

## Before you start

Generate the data:

```bash
Rscript setup/install_packages.R
Rscript setup/generate_raw_data.R
```

The script exits nonzero if any invariant fails, so a clean exit means the files
are internally consistent. It prints row counts that should match
`setup/manifest.csv`.

Then run `setup/raw_table_ddl.sql` in a Snowsight worksheet. This creates the
database, the five schemas, all 14 tables, and a named file format.

**Create the tables first. Do not let the load wizard infer the schema.** Schema
inference types the timestamp columns as `TIMESTAMP_NTZ`, which silently drops
the UTC offsets. Those offsets are the whole point of the mixed-timezone demo,
and `_LOADED_AT` without a zone breaks source freshness too. Inference also
tends to read `probability` and `rate` as floats, losing precision.

## Loading each file

In Snowsight: **Data → Databases → CORE_RAW → [schema] → [table] → Load Data**.

For every file:

1. Select the CSV from `setup/generated/<source>/<table>.csv`.
2. Choose the existing table — not "create new table".
3. Open **File format** and select the existing format `CORE_RAW.PUBLIC.CSV_RAW_FF`
   rather than configuring one inline.
4. Load.

If you configure the format by hand instead, the setting that matters is
**Field optionally enclosed by: double quote**. `PRODUCT.EVENTS.PROPERTIES`
holds JSON containing commas and quotes; without that setting the row splits on
the commas inside the JSON and the load either fails or scrambles the columns.
Also leave **Trim space** off — the whitespace defects in names and emails are
deliberate fixtures for the staging layer to clean.

Order doesn't matter, since there are no foreign keys in the DDL.

| Schema | Table | File |
|---|---|---|
| CRM | SALES_REPS | `crm/sales_reps.csv` |
| CRM | ACCOUNTS | `crm/accounts.csv` |
| CRM | CONTACTS | `crm/contacts.csv` |
| CRM | OPPORTUNITIES | `crm/opportunities.csv` |
| BILLING | CUSTOMERS | `billing/customers.csv` |
| BILLING | SUBSCRIPTIONS | `billing/subscriptions.csv` |
| BILLING | INVOICES | `billing/invoices.csv` |
| BILLING | INVOICE_LINES | `billing/invoice_lines.csv` |
| BILLING | PAYMENTS | `billing/payments.csv` |
| BILLING | REFUNDS | `billing/refunds.csv` |
| PRODUCT | EVENTS | `product/events.csv` |
| ERP | COST_CENTERS | `erp/cost_centers.csv` |
| ERP | GL_ENTRIES | `erp/gl_entries.csv` |
| MARKET | FX_RATES | `market/fx_rates.csv` |

`events.csv` is the largest at roughly 4 MB, well under the wizard's 250 MB cap.

## After loading

Run the three verification queries at the bottom of `raw_table_ddl.sql`:

- Row counts per table, which should match `setup/manifest.csv`.
- Distinct timezone offsets in `PRODUCT.EVENTS`. Expect seven: `Z` plus six
  others. One row means the offsets were lost and the tables were created by
  inference rather than by the DDL.
- Unparseable `PROPERTIES`, which must be zero in the standard scenario. Any
  nonzero result means the quote setting was wrong.

Then run `setup/rebaseline_loaded_at.sql`. The generator uses 2026-01-01 as a deterministic fixture anchor. The script independently moves business `DATE` fields, business `TIMESTAMP_TZ` fields—including invoice `paid_at`—and `_LOADED_AT`. Separate anchors let it repair data where an earlier run moved only `_LOADED_AT`, while preserving relative durations, ordering invariants, and intended source freshness gaps. The script prints freshness and business-date checks after applying the shifts.



## Re-loading

The wizard appends. To reload a file, truncate first:

```sql
TRUNCATE TABLE CORE_RAW.BILLING.INVOICES;
```

## Scripted alternative

If you'd rather not click through fourteen wizards, `raw_table_ddl.sql` ends
with a commented-out `PUT` plus `COPY INTO` block for the whole set. The `PUT`
commands need SnowSQL or the Snowflake CLI, since the web UI can't read local
files. That path is also the one to use if you start regenerating data often.

## Demo

Once loaded and rebaselined, `setup/incremental_demo.sql` mutates the tables to
exercise incremental models and snapshots. Run section 1 to back up, 2 and 3 to
mutate, 4 to verify, and 5 to undo. Everything it inserts is keyed `demo_*`, and
everything it changes is restored from zero-copy clones.
