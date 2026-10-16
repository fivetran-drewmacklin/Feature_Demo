-- =============================================================================
-- incremental_demo.sql
--
-- The generator emits current state only. This script mutates the loaded tables
-- so incremental models, snapshots, and freshness have something to react to.
--
-- Run the sections in order. Each is independent and labelled.
--
--   SECTION 1  BACKUP   zero-copy clones, guarded against double-running
--   SECTION 2  INSERT   new rows, all keyed demo_*
--   SECTION 3  UPDATE   mutations to existing rows
--   SECTION 4  VERIFY   what changed, and what dbt should pick up
--   SECTION 5  RESET    undo everything, drop the clones
--
-- Inserted rows always use a demo_ prefix so reset can delete by pattern and
-- never touch generator data. Updated rows are restored from the clones, so no
-- original values need to be recorded anywhere.
--
-- Every mutation advances UPDATED_AT and _LOADED_AT together, keeping
-- _LOADED_AT >= UPDATED_AT.
-- =============================================================================

USE ROLE DEV_DBT_ROLE2;
USE WAREHOUSE TRANSFORM_XS_WH;
USE DATABASE CORE_RAW;

-- =============================================================================
-- SECTION 1. BACKUP
--
-- IF NOT EXISTS is the guard: if a backup already exists, it is from the
-- pre-mutation state and must not be overwritten by an already-mutated table.
-- To take a fresh backup, run SECTION 5 first.
-- =============================================================================

CREATE TABLE IF NOT EXISTS BILLING.INVOICES_DEMO_BACKUP      CLONE BILLING.INVOICES;
CREATE TABLE IF NOT EXISTS BILLING.INVOICE_LINES_DEMO_BACKUP CLONE BILLING.INVOICE_LINES;
CREATE TABLE IF NOT EXISTS BILLING.PAYMENTS_DEMO_BACKUP      CLONE BILLING.PAYMENTS;
CREATE TABLE IF NOT EXISTS BILLING.SUBSCRIPTIONS_DEMO_BACKUP CLONE BILLING.SUBSCRIPTIONS;
CREATE TABLE IF NOT EXISTS CRM.ACCOUNTS_DEMO_BACKUP          CLONE CRM.ACCOUNTS;
CREATE TABLE IF NOT EXISTS PRODUCT.EVENTS_DEMO_BACKUP        CLONE PRODUCT.EVENTS;

SELECT 'backup complete' AS status,
       (SELECT COUNT(*) FROM BILLING.INVOICES_DEMO_BACKUP) AS invoices_backed_up,
       (SELECT COUNT(*) FROM CRM.ACCOUNTS_DEMO_BACKUP)     AS accounts_backed_up;

-- =============================================================================
-- SECTION 2. INSERT
--
-- New rows arriving since the last dbt run. An incremental model filtered on
-- UPDATED_AT picks these up; a full refresh would too, which is the point of
-- the comparison.
-- =============================================================================

-- Five new invoices against existing customers and subscriptions.
INSERT INTO BILLING.INVOICES
SELECT
  'demo_inv_' || LPAD(seq4() + 1, 6, '0')                         AS invoice_id,
  'INV-DEMO-' || LPAD(seq4() + 1, 5, '0')                         AS invoice_number,
  c.billing_customer_id,
  c.subscription_id,
  'open'                                                          AS status,
  CURRENT_DATE()                                                  AS issue_date,
  DATEADD(day, 30, CURRENT_DATE())                                AS due_date,
  NULL                                                            AS paid_at,
  c.unit_price_cents * c.quantity                                 AS subtotal_cents,
  0                                                               AS discount_cents,
  ROUND(c.unit_price_cents * c.quantity * 0.20)                   AS tax_cents,
  c.unit_price_cents * c.quantity
    + ROUND(c.unit_price_cents * c.quantity * 0.20)               AS total_cents,
  c.unit_price_cents * c.quantity
    + ROUND(c.unit_price_cents * c.quantity * 0.20)               AS amount_due_cents,
  c.currency,
  CURRENT_TIMESTAMP()                                             AS updated_at,
  CURRENT_TIMESTAMP()                                             AS _loaded_at
FROM (
  SELECT s.billing_customer_id, s.subscription_id, s.unit_price_cents,
         s.quantity, s.currency,
         ROW_NUMBER() OVER (ORDER BY s.subscription_id) AS rn
  FROM BILLING.SUBSCRIPTIONS s
  WHERE s.status = 'active'
  QUALIFY rn <= 5
) c,
TABLE(GENERATOR(ROWCOUNT => 1));

-- One subscription line per new invoice, so reconciliation still holds.
INSERT INTO BILLING.INVOICE_LINES
SELECT
  'demo_iline_' || LPAD(ROW_NUMBER() OVER (ORDER BY i.invoice_id), 6, '0') AS invoice_line_id,
  i.invoice_id,
  s.plan_code,
  'subscription'                                 AS line_type,
  s.plan_code || ' subscription'                 AS description,
  s.quantity,
  s.unit_price_cents,
  i.subtotal_cents                               AS line_amount_cents,
  CURRENT_DATE()                                 AS service_period_start,
  DATEADD(month, 1, CURRENT_DATE())              AS service_period_end,
  CURRENT_TIMESTAMP()                            AS updated_at,
  CURRENT_TIMESTAMP()                            AS _loaded_at
FROM BILLING.INVOICES i
JOIN BILLING.SUBSCRIPTIONS s ON s.subscription_id = i.subscription_id
WHERE i.invoice_id LIKE 'demo_inv_%';

-- Matching tax lines.
INSERT INTO BILLING.INVOICE_LINES
SELECT
  'demo_iline_tax_' || LPAD(ROW_NUMBER() OVER (ORDER BY i.invoice_id), 6, '0'),
  i.invoice_id,
  NULL, 'tax', 'Sales tax', 1,
  i.tax_cents, i.tax_cents,
  NULL, NULL,
  CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
FROM BILLING.INVOICES i
WHERE i.invoice_id LIKE 'demo_inv_%' AND i.tax_cents > 0;

-- 500 new product events, landing in the last hour.
INSERT INTO PRODUCT.EVENTS
SELECT
  'demo_evt_' || LPAD(seq4() + 1, 6, '0')                     AS event_id,
  ARRAY_CONSTRUCT('login','page_view','feature_used','api_call')[UNIFORM(0, 3, RANDOM())]::VARCHAR
                                                              AS event_name,
  a.account_id,
  NULL                                                        AS contact_id,
  NULL                                                        AS anonymous_id,
  'demo_sess_' || LPAD(seq4() + 1, 9, '0')                    AS session_id,
  DATEADD(minute, -UNIFORM(5, 55, RANDOM()), CURRENT_TIMESTAMP()) AS event_timestamp,
  DATEADD(minute, -UNIFORM(1, 4, RANDOM()), CURRENT_TIMESTAMP())  AS received_at,
  '{"source":"demo","feature_name":"dashboard"}'              AS properties,
  CURRENT_TIMESTAMP()                                         AS _loaded_at
FROM (
  SELECT account_id FROM CRM.ACCOUNTS WHERE is_deleted = FALSE LIMIT 50
) a,
TABLE(GENERATOR(ROWCOUNT => 10));

-- =============================================================================
-- SECTION 3. UPDATE
--
-- Changes to rows that already exist. These are what separate a merge-based
-- incremental model from an append-only one: a model keyed on INVOICE_ID with
-- an UPDATED_AT filter updates these in place, while append would duplicate.
-- =============================================================================

-- 3a. Twenty open invoices get paid.
UPDATE BILLING.INVOICES
SET status           = 'paid',
    paid_at          = CURRENT_TIMESTAMP(),
    amount_due_cents = 0,
    updated_at       = CURRENT_TIMESTAMP(),
    _loaded_at       = CURRENT_TIMESTAMP()
WHERE invoice_id IN (
  SELECT invoice_id FROM BILLING.INVOICES
  WHERE status = 'open' AND invoice_id NOT LIKE 'demo_%'
  ORDER BY issue_date DESC LIMIT 20
);

-- 3b. A succeeded payment for each, so the settlement rule still holds.
INSERT INTO BILLING.PAYMENTS
SELECT
  'demo_pay_' || LPAD(ROW_NUMBER() OVER (ORDER BY i.invoice_id), 6, '0'),
  i.invoice_id,
  i.billing_customer_id,
  'succeeded',
  i.total_cents,
  i.currency,
  i.paid_at,
  'card',
  'PR-DEMO-' || LPAD(ROW_NUMBER() OVER (ORDER BY i.invoice_id), 8, '0'),
  CURRENT_TIMESTAMP(),
  CURRENT_TIMESTAMP()
FROM BILLING.INVOICES i
WHERE i.paid_at >= DATEADD(minute, -5, CURRENT_TIMESTAMP())
  AND i.invoice_id NOT LIKE 'demo_%';

-- 3c. Three observable subscription upgrades. STARTER to GROWTH, with the
--     price change that goes with it. This is the transition the current-state
--     files cannot show on their own.
UPDATE BILLING.SUBSCRIPTIONS
SET plan_code        = REPLACE(plan_code, 'STARTER', 'GROWTH'),
    unit_price_cents = CASE
                         WHEN plan_code = 'STARTER_MONTHLY' THEN 19900
                         WHEN plan_code = 'STARTER_ANNUAL'  THEN 199000
                         ELSE unit_price_cents
                       END,
    updated_at       = CURRENT_TIMESTAMP(),
    _loaded_at       = CURRENT_TIMESTAMP()
WHERE subscription_id IN (
  SELECT subscription_id FROM BILLING.SUBSCRIPTIONS
  WHERE plan_code LIKE 'STARTER%' AND status = 'active'
  ORDER BY subscription_id LIMIT 3
);

-- 3d. Two downgrades, for the opposite direction.
UPDATE BILLING.SUBSCRIPTIONS
SET plan_code        = 'STARTER_MONTHLY',
    unit_price_cents = 4900,
    updated_at       = CURRENT_TIMESTAMP(),
    _loaded_at       = CURRENT_TIMESTAMP()
WHERE subscription_id IN (
  SELECT subscription_id FROM BILLING.SUBSCRIPTIONS
  WHERE plan_code = 'GROWTH_MONTHLY' AND status = 'active'
  ORDER BY subscription_id DESC LIMIT 2
);

-- 3e. Five account soft-deletes. Snapshot should retain the pre-delete version.
UPDATE CRM.ACCOUNTS
SET is_deleted = TRUE,
    deleted_at = CURRENT_TIMESTAMP(),
    updated_at = CURRENT_TIMESTAMP(),
    _loaded_at = CURRENT_TIMESTAMP()
WHERE account_id IN (
  SELECT account_id FROM CRM.ACCOUNTS
  WHERE is_deleted = FALSE ORDER BY account_id DESC LIMIT 5
);

-- 3f. Ten account attribute changes, for snapshot column tracking.
UPDATE CRM.ACCOUNTS
SET account_tier = CASE account_tier
                     WHEN 'smb'        THEN 'mid_market'
                     WHEN 'mid_market' THEN 'enterprise'
                     ELSE 'enterprise'
                   END,
    employee_count = COALESCE(employee_count, 100) * 2,
    updated_at     = CURRENT_TIMESTAMP(),
    _loaded_at     = CURRENT_TIMESTAMP()
WHERE account_id IN (
  SELECT account_id FROM CRM.ACCOUNTS
  WHERE is_deleted = FALSE ORDER BY account_id LIMIT 10
);

-- =============================================================================
-- SECTION 4. VERIFY
-- =============================================================================

SELECT 'inserted invoices'     AS change, COUNT(*) AS n FROM BILLING.INVOICES      WHERE invoice_id      LIKE 'demo_%'
UNION ALL SELECT 'inserted invoice_lines', COUNT(*) FROM BILLING.INVOICE_LINES WHERE invoice_line_id LIKE 'demo_%'
UNION ALL SELECT 'inserted payments',      COUNT(*) FROM BILLING.PAYMENTS      WHERE payment_id      LIKE 'demo_%'
UNION ALL SELECT 'inserted events',        COUNT(*) FROM PRODUCT.EVENTS        WHERE event_id        LIKE 'demo_%'
UNION ALL SELECT 'rows updated in last hour (invoices)',      COUNT(*) FROM BILLING.INVOICES
  WHERE updated_at >= DATEADD(hour, -1, CURRENT_TIMESTAMP()) AND invoice_id NOT LIKE 'demo_%'
UNION ALL SELECT 'rows updated in last hour (subscriptions)', COUNT(*) FROM BILLING.SUBSCRIPTIONS
  WHERE updated_at >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
UNION ALL SELECT 'rows updated in last hour (accounts)',      COUNT(*) FROM CRM.ACCOUNTS
  WHERE updated_at >= DATEADD(hour, -1, CURRENT_TIMESTAMP());

-- Settlement rule still holds: this must return zero rows.
SELECT i.invoice_id, i.total_cents, SUM(p.amount_cents) AS settled
FROM BILLING.INVOICES i
LEFT JOIN BILLING.PAYMENTS p
  ON p.invoice_id = i.invoice_id AND p.status = 'succeeded'
WHERE i.status IN ('paid', 'PAID_LATE', 'complete')
GROUP BY i.invoice_id, i.total_cents
HAVING COALESCE(SUM(p.amount_cents), 0) <> i.total_cents
LIMIT 20;

-- Invariant: _LOADED_AT never precedes UPDATED_AT. Must return zero.
SELECT COUNT(*) AS loaded_before_updated
FROM BILLING.INVOICES WHERE _loaded_at < updated_at;

-- =============================================================================
-- SECTION 5. RESET
--
-- Deletes every demo_ row, restores mutated rows from the clones, verifies the
-- counts match, then drops the clones. After this the tables are byte-identical
-- to their post-load state.
-- =============================================================================

DELETE FROM BILLING.INVOICES      WHERE invoice_id      LIKE 'demo_%';
DELETE FROM BILLING.INVOICE_LINES WHERE invoice_line_id LIKE 'demo_%';
DELETE FROM BILLING.PAYMENTS      WHERE payment_id      LIKE 'demo_%';
DELETE FROM PRODUCT.EVENTS        WHERE event_id        LIKE 'demo_%';

-- Restore mutated rows. The clone is authoritative, so a straight replace of
-- every row that differs is simpler and safer than replaying inverse updates.
CREATE OR REPLACE TABLE BILLING.INVOICES      CLONE BILLING.INVOICES_DEMO_BACKUP;
CREATE OR REPLACE TABLE BILLING.INVOICE_LINES CLONE BILLING.INVOICE_LINES_DEMO_BACKUP;
CREATE OR REPLACE TABLE BILLING.PAYMENTS      CLONE BILLING.PAYMENTS_DEMO_BACKUP;
CREATE OR REPLACE TABLE BILLING.SUBSCRIPTIONS CLONE BILLING.SUBSCRIPTIONS_DEMO_BACKUP;
CREATE OR REPLACE TABLE CRM.ACCOUNTS          CLONE CRM.ACCOUNTS_DEMO_BACKUP;
CREATE OR REPLACE TABLE PRODUCT.EVENTS        CLONE PRODUCT.EVENTS_DEMO_BACKUP;

-- Confirm the restore before dropping the safety net. All diffs must be zero.
SELECT 'invoices'      AS t, (SELECT COUNT(*) FROM BILLING.INVOICES)      - (SELECT COUNT(*) FROM BILLING.INVOICES_DEMO_BACKUP)      AS diff
UNION ALL SELECT 'invoice_lines', (SELECT COUNT(*) FROM BILLING.INVOICE_LINES) - (SELECT COUNT(*) FROM BILLING.INVOICE_LINES_DEMO_BACKUP)
UNION ALL SELECT 'payments',      (SELECT COUNT(*) FROM BILLING.PAYMENTS)      - (SELECT COUNT(*) FROM BILLING.PAYMENTS_DEMO_BACKUP)
UNION ALL SELECT 'subscriptions', (SELECT COUNT(*) FROM BILLING.SUBSCRIPTIONS) - (SELECT COUNT(*) FROM BILLING.SUBSCRIPTIONS_DEMO_BACKUP)
UNION ALL SELECT 'accounts',      (SELECT COUNT(*) FROM CRM.ACCOUNTS)          - (SELECT COUNT(*) FROM CRM.ACCOUNTS_DEMO_BACKUP)
UNION ALL SELECT 'events',        (SELECT COUNT(*) FROM PRODUCT.EVENTS)        - (SELECT COUNT(*) FROM PRODUCT.EVENTS_DEMO_BACKUP);

-- Only once the diffs above are all zero:
DROP TABLE IF EXISTS BILLING.INVOICES_DEMO_BACKUP;
DROP TABLE IF EXISTS BILLING.INVOICE_LINES_DEMO_BACKUP;
DROP TABLE IF EXISTS BILLING.PAYMENTS_DEMO_BACKUP;
DROP TABLE IF EXISTS BILLING.SUBSCRIPTIONS_DEMO_BACKUP;
DROP TABLE IF EXISTS CRM.ACCOUNTS_DEMO_BACKUP;
DROP TABLE IF EXISTS PRODUCT.EVENTS_DEMO_BACKUP;
