{% docs __demo_core__ %}
# demo_core

`demo_core` is the governed silver project for CRM, billing, product, ERP, and market data. It cleans source defects, conforms customer identity, reconciles billing facts, fills auditable FX gaps, and publishes stable public contracts for dbt Mesh consumers.

Use the five models tagged `public_interface` for cross-project dependencies: `customers`, `subscriptions`, `invoices`, `fx_rates`, and `gl_entries`. Internal staging and intermediate models are implementation details. Revenue recognition, USD reporting measures, and other finance presentation logic belong in the downstream `demo_finance` gold project.

The standard demo dataset intentionally produces warning-level quality findings. Those warnings are stored in `CORE_CONFIG.AUDIT`; error-level invariants must pass.
{% enddocs %}

{% docs conformed_customer_id %}
Stable identifier for a company conformed across CRM and billing. Duplicate CRM accounts that represent the same company share this identifier, while unmatched billing-only customers receive a deterministic billing-based identifier.
{% enddocs %}

{% docs billing_customer_id %}
Source identifier assigned by the billing platform. Multiple billing customer records may map to one conformed customer.
{% enddocs %}

{% docs subscription_id %}
Stable identifier for one billing subscription and its current lifecycle state.
{% enddocs %}

{% docs invoice_id %}
Stable billing invoice identifier. The public invoice interface contains one row per identifier after header, line, payment, and refund reconciliation.
{% enddocs %}

{% docs currency_code %}
Uppercase ISO 4217 currency code for monetary values on the record. Amount columns ending in `_cents` remain in this source currency unless their name explicitly identifies another currency.
{% enddocs %}

{% docs invoice_reconciliation_status %}
Indicates whether the stored invoice subtotal, discount, tax, and total agree with values recomputed from clean invoice lines. Known source discrepancies are retained for auditability and tested at warning severity.
{% enddocs %}

{% docs net_collections_cents %}
Successful payment amounts less successful refund amounts for the invoice, expressed in minor units of the invoice currency. This is a clean operational fact, not recognized revenue.
{% enddocs %}

{% docs record_updated_at %}
Latest update timestamp across every source record that can affect the modeled row. For invoices this includes the header, lines, payments, and refunds and acts as the incremental watermark.
{% enddocs %}

{% docs fx_rate %}
Exact or most-recent-prior conversion rate from `from_currency` to `to_currency` for `rate_date`. Consumers should retain the fallback provenance fields when applying the rate.
{% enddocs %}

{% docs source_rate_date %}
Date on which the applied exchange rate was originally observed. It differs from `rate_date` when a missing daily rate uses the most recent prior observation.
{% enddocs %}

{% docs used_prior_rate %}
Whether the exact daily FX observation was missing and the most recent prior rate was carried forward. These fallback rows are expected and tested at warning severity.
{% enddocs %}

{% docs gl_entry_id %}
Stable identifier for one general-ledger journal line. A journal contains multiple lines and is expected to balance by journal and currency.
{% enddocs %}

{% docs signed_amount_cents %}
Debit amount less credit amount in minor currency units. Positive values are debit balances and negative values are credit balances; account sign convention remains available separately.
{% enddocs %}

{% docs raw_loaded_at %}
Timestamp when the source record was loaded into the raw Snowflake layer. This is ingestion provenance rather than a business-event timestamp.
{% enddocs %}
