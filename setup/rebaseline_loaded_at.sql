-- =============================================================================
-- rebaseline_loaded_at.sql
--
-- Shifts every _LOADED_AT in CORE_RAW by a single signed interval, so source
-- freshness behaves as designed on any demo date without regenerating the CSVs
-- or reloading.
--
-- The generator stamps _LOADED_AT relative to its as-of date (2026-01-01 by
-- default), with these ages behind the reference instant:
--
--     CRM      2 hours      fresh
--     BILLING  2 hours      fresh
--     PRODUCT  1 hour       fresh
--     ERP      8 hours      fresh
--     MARKET   30 hours     warns under warn_after 24h / error_after 48h
--
-- Every table shifts by the same amount, so those relative gaps are preserved
-- and MARKET stays exactly 29 hours behind CRM.
--
-- Run SECTION 1 to compute the shift, SECTION 2 to validate it, SECTION 3 to
-- apply it, SECTION 4 to confirm. Sections 2 and 3 use the same variable.
-- =============================================================================

USE ROLE DEV_DBT_ROLE2;
USE WAREHOUSE TRANSFORM_XS_WH;
USE DATABASE CORE_RAW;

-- -----------------------------------------------------------------------------
-- SECTION 1. Compute the shift.
--
-- Targets CRM at 2 hours old right now, which drags every other source to its
-- intended age. Positive = move timestamps forward.
-- -----------------------------------------------------------------------------

SET SHIFT_MINUTES = (
  SELECT DATEDIFF(minute, MAX(_LOADED_AT), DATEADD(hour, -2, CURRENT_TIMESTAMP()))
  FROM CRM.ACCOUNTS
);

SELECT $SHIFT_MINUTES                                   AS shift_minutes,
       ROUND($SHIFT_MINUTES / 60.0, 1)                  AS shift_hours,
       ROUND($SHIFT_MINUTES / 1440.0, 1)                AS shift_days,
       CASE WHEN $SHIFT_MINUTES < 0 THEN 'NEGATIVE - run section 2 before applying'
            ELSE 'forward shift, safe' END              AS note;

-- To set it by hand instead, overwrite the variable:
--   SET SHIFT_MINUTES = 20160;   -- two weeks forward
--   SET SHIFT_MINUTES = -1440;   -- one day back

-- -----------------------------------------------------------------------------
-- SECTION 2. Validate a negative shift.
--
-- Only needed when SHIFT_MINUTES < 0. A backward shift can push _LOADED_AT
-- behind the row's own business timestamp, which breaks the invariant that a
-- row cannot be loaded before it happened. This must return zero rows.
-- Forward shifts are always safe and this section can be skipped.
-- -----------------------------------------------------------------------------

WITH violations AS (
  SELECT 'CRM.ACCOUNTS' AS t, COUNT(*) AS n FROM CRM.ACCOUNTS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'CRM.CONTACTS', COUNT(*) FROM CRM.CONTACTS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'CRM.OPPORTUNITIES', COUNT(*) FROM CRM.OPPORTUNITIES
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.CUSTOMERS', COUNT(*) FROM BILLING.CUSTOMERS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.SUBSCRIPTIONS', COUNT(*) FROM BILLING.SUBSCRIPTIONS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.INVOICES', COUNT(*) FROM BILLING.INVOICES
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.INVOICE_LINES', COUNT(*) FROM BILLING.INVOICE_LINES
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.PAYMENTS', COUNT(*) FROM BILLING.PAYMENTS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'BILLING.REFUNDS', COUNT(*) FROM BILLING.REFUNDS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < UPDATED_AT
  UNION ALL SELECT 'PRODUCT.EVENTS', COUNT(*) FROM PRODUCT.EVENTS
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < RECEIVED_AT
  UNION ALL SELECT 'ERP.GL_ENTRIES', COUNT(*) FROM ERP.GL_ENTRIES
    WHERE DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT) < CREATED_AT
)
SELECT * FROM violations WHERE n > 0;

-- -----------------------------------------------------------------------------
-- SECTION 3. Apply.
-- -----------------------------------------------------------------------------

UPDATE CRM.SALES_REPS        SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE CRM.ACCOUNTS          SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE CRM.CONTACTS          SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE CRM.OPPORTUNITIES     SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.CUSTOMERS     SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.SUBSCRIPTIONS SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.INVOICES      SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.INVOICE_LINES SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.PAYMENTS      SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE BILLING.REFUNDS       SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE PRODUCT.EVENTS        SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE ERP.COST_CENTERS      SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE ERP.GL_ENTRIES        SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);
UPDATE MARKET.FX_RATES       SET _LOADED_AT = DATEADD(minute, $SHIFT_MINUTES, _LOADED_AT);

-- -----------------------------------------------------------------------------
-- SECTION 4. Confirm the freshness story.
--
-- Expect CRM/BILLING ~2h, PRODUCT ~1h, ERP ~8h, MARKET ~30h with status WARN.
-- -----------------------------------------------------------------------------

WITH src AS (
  SELECT 'CRM'     AS source, MAX(_LOADED_AT) AS max_loaded FROM CRM.ACCOUNTS
  UNION ALL SELECT 'BILLING', MAX(_LOADED_AT) FROM BILLING.INVOICES
  UNION ALL SELECT 'PRODUCT', MAX(_LOADED_AT) FROM PRODUCT.EVENTS
  UNION ALL SELECT 'ERP',     MAX(_LOADED_AT) FROM ERP.GL_ENTRIES
  UNION ALL SELECT 'MARKET',  MAX(_LOADED_AT) FROM MARKET.FX_RATES
)
SELECT source,
       max_loaded,
       ROUND(DATEDIFF(minute, max_loaded, CURRENT_TIMESTAMP()) / 60.0, 1) AS hours_old,
       CASE
         WHEN source = 'MARKET' AND DATEDIFF(hour, max_loaded, CURRENT_TIMESTAMP()) >= 48 THEN 'ERROR'
         WHEN source = 'MARKET' AND DATEDIFF(hour, max_loaded, CURRENT_TIMESTAMP()) >= 24 THEN 'WARN'
         WHEN source <> 'MARKET' AND DATEDIFF(hour, max_loaded, CURRENT_TIMESTAMP()) >= 24 THEN 'STALE'
         ELSE 'OK'
       END AS expected_freshness
FROM src
ORDER BY hours_old;
