-- =============================================================================
-- rebaseline_loaded_at.sql
--
-- Shifts the complete CORE_RAW fixture timeline to the current demo date while
-- preserving relative intervals, timestamp ordering, and source freshness ages.
-- This keeps reusable deterministic CSV fixtures current without regenerating
-- or reloading them.
--
-- Business and ingestion shifts are calculated independently. This is important
-- when an older version of this script has already moved _LOADED_AT without
-- moving business dates such as issue_date, paid_at, or updated_at.
--
--   * DATE business fields use BUSINESS_SHIFT_DAYS.
--   * TIMESTAMP_TZ business fields use BUSINESS_SHIFT_MINUTES.
--   * _LOADED_AT uses INGEST_SHIFT_MINUTES.
--
-- Source freshness after the shift remains:
--
--     CRM      2 hours      fresh
--     BILLING  2 hours      fresh
--     PRODUCT  1 hour       fresh
--     ERP      8 hours      fresh
--     MARKET   30 hours     warns under warn_after 24h / error_after 48h
--
-- Run the sections in order. Re-running is safe: each independently calculated
-- shift will be near zero once both business and ingestion timelines are current.
-- =============================================================================

USE ROLE SYSADMIN;   -- UPDATE on CORE_RAW; the dbt dev role is read-only
USE WAREHOUSE TRANSFORM_XS_WH;
USE DATABASE CORE_RAW;

-- -----------------------------------------------------------------------------
-- SECTION 1. Compute and inspect the shifts.
--
-- Business dates are anchored on invoice activity. Ingestion timestamps are
-- anchored separately on CRM freshness, so this also repairs data where only
-- _LOADED_AT was previously rebaselined.
-- -----------------------------------------------------------------------------

SET BUSINESS_SHIFT_DAYS = (
  SELECT DATEDIFF(
    day,
    MAX(ISSUE_DATE),
    TO_DATE(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP()))
  )
  FROM BILLING.INVOICES
);

SET BUSINESS_SHIFT_MINUTES = (
  SELECT DATEDIFF(minute, MAX(UPDATED_AT), DATEADD(hour, -3, CURRENT_TIMESTAMP()))
  FROM BILLING.INVOICES
);

SET INGEST_SHIFT_MINUTES = (
  SELECT DATEDIFF(minute, MAX(_LOADED_AT), DATEADD(hour, -2, CURRENT_TIMESTAMP()))
  FROM CRM.ACCOUNTS
);

SELECT $BUSINESS_SHIFT_DAYS                              AS business_shift_days,
       $BUSINESS_SHIFT_MINUTES                           AS business_shift_minutes,
       ROUND($BUSINESS_SHIFT_MINUTES / 60.0, 1)          AS business_shift_hours,
       $INGEST_SHIFT_MINUTES                             AS ingest_shift_minutes,
       ROUND($INGEST_SHIFT_MINUTES / 60.0, 1)            AS ingest_shift_hours,
       CASE
         WHEN ABS($BUSINESS_SHIFT_MINUTES) < 5
          AND ABS($INGEST_SHIFT_MINUTES) < 5
          AND $BUSINESS_SHIFT_DAYS = 0 THEN 'already current'
         ELSE 'timeline shift required'
       END                                               AS note;

-- To set the shifts by hand, overwrite all three variables before SECTION 2:
--   SET BUSINESS_SHIFT_DAYS = 14;
--   SET BUSINESS_SHIFT_MINUTES = 20160;
--   SET INGEST_SHIFT_MINUTES = 20160;

-- -----------------------------------------------------------------------------
-- SECTION 2. Apply the timeline shifts.
--
-- Nullable timestamps remain null under DATEADD. Separate business and ingestion
-- anchors allow the script to repair an existing _LOADED_AT-only rebaseline.
-- For mutable/event tables, GREATEST also enforces _LOADED_AT at least one minute
-- after the shifted row-level update, creation, or receipt timestamp.
-- -----------------------------------------------------------------------------

BEGIN TRANSACTION;

UPDATE CRM.SALES_REPS
SET HIRE_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, HIRE_DATE),
    _LOADED_AT = DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT);

UPDATE CRM.ACCOUNTS
SET CREATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    DELETED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, DELETED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE CRM.CONTACTS
SET CREATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE CRM.OPPORTUNITIES
SET CLOSE_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, CLOSE_DATE),
    CREATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.CUSTOMERS
SET CREATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.SUBSCRIPTIONS
SET STARTED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, STARTED_AT),
    CURRENT_PERIOD_START = DATEADD(day, $BUSINESS_SHIFT_DAYS, CURRENT_PERIOD_START),
    CURRENT_PERIOD_END = DATEADD(day, $BUSINESS_SHIFT_DAYS, CURRENT_PERIOD_END),
    CANCELED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CANCELED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.INVOICES
SET ISSUE_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, ISSUE_DATE),
    DUE_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, DUE_DATE),
    PAID_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, PAID_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.INVOICE_LINES
SET SERVICE_PERIOD_START = DATEADD(day, $BUSINESS_SHIFT_DAYS, SERVICE_PERIOD_START),
    SERVICE_PERIOD_END = DATEADD(day, $BUSINESS_SHIFT_DAYS, SERVICE_PERIOD_END),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.PAYMENTS
SET PAID_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, PAID_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE BILLING.REFUNDS
SET REFUNDED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, REFUNDED_AT),
    UPDATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, UPDATED_AT))
    );

UPDATE PRODUCT.EVENTS
SET EVENT_TIMESTAMP = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, EVENT_TIMESTAMP),
    RECEIVED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, RECEIVED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, RECEIVED_AT))
    );

UPDATE ERP.COST_CENTERS
SET EFFECTIVE_FROM = DATEADD(day, $BUSINESS_SHIFT_DAYS, EFFECTIVE_FROM),
    EFFECTIVE_TO = DATEADD(day, $BUSINESS_SHIFT_DAYS, EFFECTIVE_TO),
    _LOADED_AT = DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT);

UPDATE ERP.GL_ENTRIES
SET POSTED_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, POSTED_DATE),
    CREATED_AT = DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT),
    _LOADED_AT = GREATEST(
      DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT),
      DATEADD(minute, 1, DATEADD(minute, $BUSINESS_SHIFT_MINUTES, CREATED_AT))
    );

UPDATE MARKET.FX_RATES
SET RATE_DATE = DATEADD(day, $BUSINESS_SHIFT_DAYS, RATE_DATE),
    _LOADED_AT = DATEADD(minute, $INGEST_SHIFT_MINUTES, _LOADED_AT);

COMMIT;


-- -----------------------------------------------------------------------------
-- SECTION 3. Confirm source freshness.
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

-- -----------------------------------------------------------------------------
-- SECTION 4. Confirm business-date recency and critical ordering invariants.
-- -----------------------------------------------------------------------------

SELECT MAX(ISSUE_DATE) AS max_issue_date,
       MAX(PAID_AT) AS max_paid_at,
       MAX(UPDATED_AT) AS max_updated_at,
       MAX(_LOADED_AT) AS max_loaded_at,
       TO_DATE(CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())) AS current_utc_date
FROM BILLING.INVOICES;

WITH violations AS (
  SELECT 'invoice due before issue' AS check_name, COUNT(*) AS failures
  FROM BILLING.INVOICES
  WHERE DUE_DATE < ISSUE_DATE

  UNION ALL

  SELECT 'invoice paid before issue', COUNT(*)
  FROM BILLING.INVOICES
  WHERE PAID_AT < ISSUE_DATE::TIMESTAMP_TZ

  UNION ALL

  SELECT 'invoice loaded before update', COUNT(*)
  FROM BILLING.INVOICES
  WHERE _LOADED_AT < UPDATED_AT

  UNION ALL

  SELECT 'payment loaded before update', COUNT(*)
  FROM BILLING.PAYMENTS
  WHERE _LOADED_AT < UPDATED_AT

  UNION ALL

  SELECT 'event loaded before received', COUNT(*)
  FROM PRODUCT.EVENTS
  WHERE _LOADED_AT < RECEIVED_AT
)
SELECT *
FROM violations
WHERE failures > 0;
