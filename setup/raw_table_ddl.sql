-- =============================================================================
-- raw_table_ddl.sql
--
-- Creates CORE_RAW and its 14 raw tables with explicit types.
--
-- Run this BEFORE loading any CSV. Do not let the Snowsight load wizard infer
-- the schema: it infers TIMESTAMP_NTZ for the timestamp columns, which silently
-- discards the UTC offsets that the product-event and freshness demos depend on.
-- Create the tables here, then load into existing tables.
-- =============================================================================

-- Role: SYSADMIN owns the raw layer. The dbt development role is read-only on
-- CORE_RAW by design, so it cannot run this script. Grants for it are at the
-- bottom of the file.
USE ROLE SYSADMIN;
USE WAREHOUSE TRANSFORM_XS_WH;

CREATE DATABASE IF NOT EXISTS CORE_RAW;
USE DATABASE CORE_RAW;

CREATE SCHEMA IF NOT EXISTS CRM;
CREATE SCHEMA IF NOT EXISTS BILLING;
CREATE SCHEMA IF NOT EXISTS PRODUCT;
CREATE SCHEMA IF NOT EXISTS ERP;
CREATE SCHEMA IF NOT EXISTS MARKET;

-- -----------------------------------------------------------------------------
-- File format
--
-- FIELD_OPTIONALLY_ENCLOSED_BY is the critical setting: the events.properties
-- column holds JSON containing commas and double quotes. Without it the row
-- splits on the commas inside the JSON and the load fails or corrupts.
-- Select this named format in the Snowsight wizard rather than relying on the
-- defaults.
-- -----------------------------------------------------------------------------

CREATE FILE FORMAT IF NOT EXISTS CORE_RAW.PUBLIC.CSV_RAW_FF
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  ESCAPE_UNENCLOSED_FIELD = NONE
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('')
  TRIM_SPACE = FALSE          -- deliberate: whitespace defects are part of the fixture
  ENCODING = 'UTF8'
  COMPRESSION = AUTO;

-- An internal stage, for the scripted load path. Not needed if you use the UI.
CREATE STAGE IF NOT EXISTS CORE_RAW.PUBLIC.RAW_CSV_STAGE
  FILE_FORMAT = CORE_RAW.PUBLIC.CSV_RAW_FF;

-- =============================================================================
-- CRM
-- =============================================================================

CREATE TABLE IF NOT EXISTS CRM.SALES_REPS (
  SALES_REP_ID          VARCHAR,
  FIRST_NAME            VARCHAR,
  LAST_NAME             VARCHAR,
  EMAIL                 VARCHAR,
  REGION                VARCHAR,
  MANAGER_SALES_REP_ID  VARCHAR,
  HIRE_DATE             DATE,
  IS_ACTIVE             BOOLEAN,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS CRM.ACCOUNTS (
  ACCOUNT_ID            VARCHAR,
  ACCOUNT_NAME          VARCHAR,
  WEBSITE_DOMAIN        VARCHAR,
  BILLING_COUNTRY       VARCHAR,
  INDUSTRY              VARCHAR,
  EMPLOYEE_COUNT        NUMBER(10,0),
  ANNUAL_REVENUE        NUMBER(18,2),
  ACCOUNT_CURRENCY      VARCHAR(3),
  ACCOUNT_TIER          VARCHAR,
  OWNER_SALES_REP_ID    VARCHAR,
  CREATED_AT            TIMESTAMP_TZ,
  UPDATED_AT            TIMESTAMP_TZ,
  IS_DELETED            BOOLEAN,
  DELETED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS CRM.CONTACTS (
  CONTACT_ID            VARCHAR,
  ACCOUNT_ID            VARCHAR,
  FIRST_NAME            VARCHAR,
  LAST_NAME             VARCHAR,
  EMAIL                 VARCHAR,
  JOB_TITLE             VARCHAR,
  IS_PRIMARY            BOOLEAN,
  CREATED_AT            TIMESTAMP_TZ,
  UPDATED_AT            TIMESTAMP_TZ,
  IS_DELETED            BOOLEAN,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS CRM.OPPORTUNITIES (
  OPPORTUNITY_ID        VARCHAR,
  ACCOUNT_ID            VARCHAR,
  OWNER_SALES_REP_ID    VARCHAR,
  OPPORTUNITY_NAME      VARCHAR,
  STAGE                 VARCHAR,
  AMOUNT_CENTS          NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  PROBABILITY           NUMBER(5,4),
  CLOSE_DATE            DATE,
  CREATED_AT            TIMESTAMP_TZ,
  UPDATED_AT            TIMESTAMP_TZ,
  IS_DELETED            BOOLEAN,
  _LOADED_AT            TIMESTAMP_TZ
);

-- =============================================================================
-- BILLING
-- =============================================================================

CREATE TABLE IF NOT EXISTS BILLING.CUSTOMERS (
  BILLING_CUSTOMER_ID   VARCHAR,
  CRM_ACCOUNT_ID        VARCHAR,
  CUSTOMER_NAME         VARCHAR,
  WEBSITE_DOMAIN        VARCHAR,
  BILLING_EMAIL         VARCHAR,
  BILLING_COUNTRY       VARCHAR,
  CURRENCY              VARCHAR(3),
  STATUS                VARCHAR,
  TAX_ID                VARCHAR,
  CREATED_AT            TIMESTAMP_TZ,
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS BILLING.SUBSCRIPTIONS (
  SUBSCRIPTION_ID       VARCHAR,
  BILLING_CUSTOMER_ID   VARCHAR,
  PLAN_CODE             VARCHAR,
  STATUS                VARCHAR,
  STARTED_AT            TIMESTAMP_TZ,
  CURRENT_PERIOD_START  DATE,
  CURRENT_PERIOD_END    DATE,
  CANCELED_AT           TIMESTAMP_TZ,
  QUANTITY              NUMBER(10,0),
  UNIT_PRICE_CENTS      NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS BILLING.INVOICES (
  INVOICE_ID            VARCHAR,
  INVOICE_NUMBER        VARCHAR,
  BILLING_CUSTOMER_ID   VARCHAR,
  SUBSCRIPTION_ID       VARCHAR,
  STATUS                VARCHAR,
  ISSUE_DATE            DATE,
  DUE_DATE              DATE,
  PAID_AT               TIMESTAMP_TZ,
  SUBTOTAL_CENTS        NUMBER(18,0),
  DISCOUNT_CENTS        NUMBER(18,0),
  TAX_CENTS             NUMBER(18,0),
  TOTAL_CENTS           NUMBER(18,0),
  AMOUNT_DUE_CENTS      NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS BILLING.INVOICE_LINES (
  INVOICE_LINE_ID       VARCHAR,
  INVOICE_ID            VARCHAR,
  PLAN_CODE             VARCHAR,
  LINE_TYPE             VARCHAR,
  DESCRIPTION           VARCHAR,
  QUANTITY              NUMBER(10,0),
  UNIT_AMOUNT_CENTS     NUMBER(18,0),
  LINE_AMOUNT_CENTS     NUMBER(18,0),
  SERVICE_PERIOD_START  DATE,
  SERVICE_PERIOD_END    DATE,
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS BILLING.PAYMENTS (
  PAYMENT_ID            VARCHAR,
  INVOICE_ID            VARCHAR,
  BILLING_CUSTOMER_ID   VARCHAR,
  STATUS                VARCHAR,
  AMOUNT_CENTS          NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  PAID_AT               TIMESTAMP_TZ,
  PAYMENT_METHOD        VARCHAR,
  PROCESSOR_REFERENCE   VARCHAR,
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS BILLING.REFUNDS (
  REFUND_ID             VARCHAR,
  PAYMENT_ID            VARCHAR,
  INVOICE_ID            VARCHAR,
  AMOUNT_CENTS          NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  REASON                VARCHAR,
  STATUS                VARCHAR,
  REFUNDED_AT           TIMESTAMP_TZ,
  UPDATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

-- =============================================================================
-- PRODUCT
--
-- PROPERTIES is VARCHAR, not VARIANT. COPY INTO cannot populate a VARIANT column
-- from a CSV field without a transforming select, and the load wizard cannot do
-- it at all. Staging applies TRY_PARSE_JSON.
-- =============================================================================

CREATE TABLE IF NOT EXISTS PRODUCT.EVENTS (
  EVENT_ID              VARCHAR,
  EVENT_NAME            VARCHAR,
  ACCOUNT_ID            VARCHAR,
  CONTACT_ID            VARCHAR,
  ANONYMOUS_ID          VARCHAR,
  SESSION_ID            VARCHAR,
  EVENT_TIMESTAMP       TIMESTAMP_TZ,
  RECEIVED_AT           TIMESTAMP_TZ,
  PROPERTIES            VARCHAR,
  _LOADED_AT            TIMESTAMP_TZ
);

-- =============================================================================
-- ERP
-- =============================================================================

CREATE TABLE IF NOT EXISTS ERP.COST_CENTERS (
  COST_CENTER_ID        VARCHAR,
  COST_CENTER_NAME      VARCHAR,
  BUSINESS_UNIT         VARCHAR,
  MANAGER_NAME          VARCHAR,
  EFFECTIVE_FROM        DATE,
  EFFECTIVE_TO          DATE,
  IS_ACTIVE             BOOLEAN,
  _LOADED_AT            TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS ERP.GL_ENTRIES (
  GL_ENTRY_ID           VARCHAR,
  JOURNAL_ID            VARCHAR,
  LINE_NUMBER           NUMBER(10,0),
  POSTED_DATE           DATE,
  ACCOUNT_CODE          VARCHAR,
  COST_CENTER_ID        VARCHAR,
  INVOICE_ID            VARCHAR,
  DESCRIPTION           VARCHAR,
  DEBIT_CENTS           NUMBER(18,0),
  CREDIT_CENTS          NUMBER(18,0),
  CURRENCY              VARCHAR(3),
  CREATED_AT            TIMESTAMP_TZ,
  _LOADED_AT            TIMESTAMP_TZ
);

-- =============================================================================
-- MARKET
-- =============================================================================

CREATE TABLE IF NOT EXISTS MARKET.FX_RATES (
  RATE_DATE             DATE,
  FROM_CURRENCY         VARCHAR(3),
  TO_CURRENCY           VARCHAR(3),
  RATE                  NUMBER(18,8),
  PROVIDER              VARCHAR,
  _LOADED_AT            TIMESTAMP_TZ
);

-- =============================================================================
-- Optional: scripted load path, as an alternative to the Snowsight wizard.
-- Run the PUT commands from SnowSQL or the Snowflake CLI (the web UI cannot
-- PUT local files), then the COPY INTO statements from anywhere.
--
--   PUT file://setup/generated/crm/*.csv            @CORE_RAW.PUBLIC.RAW_CSV_STAGE/crm/     OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://setup/generated/billing/*.csv        @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://setup/generated/product/*.csv        @CORE_RAW.PUBLIC.RAW_CSV_STAGE/product/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://setup/generated/erp/*.csv            @CORE_RAW.PUBLIC.RAW_CSV_STAGE/erp/     OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--   PUT file://setup/generated/market/*.csv         @CORE_RAW.PUBLIC.RAW_CSV_STAGE/market/  OVERWRITE=TRUE AUTO_COMPRESS=FALSE;
--
-- TRUNCATE before each COPY. Snowflake's load history would otherwise skip a
-- re-staged file with an unchanged name, and FORCE=TRUE without truncation
-- would duplicate every row.
-- =============================================================================

/*
TRUNCATE TABLE CRM.SALES_REPS;
COPY INTO CRM.SALES_REPS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/crm/sales_reps.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE CRM.ACCOUNTS;
COPY INTO CRM.ACCOUNTS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/crm/accounts.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE CRM.CONTACTS;
COPY INTO CRM.CONTACTS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/crm/contacts.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE CRM.OPPORTUNITIES;
COPY INTO CRM.OPPORTUNITIES FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/crm/opportunities.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.CUSTOMERS;
COPY INTO BILLING.CUSTOMERS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/customers.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.SUBSCRIPTIONS;
COPY INTO BILLING.SUBSCRIPTIONS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/subscriptions.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.INVOICES;
COPY INTO BILLING.INVOICES FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/invoices.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.INVOICE_LINES;
COPY INTO BILLING.INVOICE_LINES FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/invoice_lines.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.PAYMENTS;
COPY INTO BILLING.PAYMENTS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/payments.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE BILLING.REFUNDS;
COPY INTO BILLING.REFUNDS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/billing/refunds.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE PRODUCT.EVENTS;
COPY INTO PRODUCT.EVENTS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/product/events.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE ERP.COST_CENTERS;
COPY INTO ERP.COST_CENTERS FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/erp/cost_centers.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE ERP.GL_ENTRIES;
COPY INTO ERP.GL_ENTRIES FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/erp/gl_entries.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MARKET.FX_RATES;
COPY INTO MARKET.FX_RATES FROM @CORE_RAW.PUBLIC.RAW_CSV_STAGE/market/fx_rates.csv
  FILE_FORMAT = (FORMAT_NAME = CORE_RAW.PUBLIC.CSV_RAW_FF) ON_ERROR = ABORT_STATEMENT;
*/

-- =============================================================================
-- Rebuilding from scratch.
--
-- The CREATE statements above are IF NOT EXISTS, so this script is safe to
-- rerun against a loaded database: it will not touch existing data. That also
-- means a column change above will NOT be applied to an existing table. To
-- genuinely rebuild, uncomment and run this block first, then rerun the script
-- and reload every file.
-- =============================================================================

/*
DROP TABLE IF EXISTS CRM.SALES_REPS;
DROP TABLE IF EXISTS CRM.ACCOUNTS;
DROP TABLE IF EXISTS CRM.CONTACTS;
DROP TABLE IF EXISTS CRM.OPPORTUNITIES;
DROP TABLE IF EXISTS BILLING.CUSTOMERS;
DROP TABLE IF EXISTS BILLING.SUBSCRIPTIONS;
DROP TABLE IF EXISTS BILLING.INVOICES;
DROP TABLE IF EXISTS BILLING.INVOICE_LINES;
DROP TABLE IF EXISTS BILLING.PAYMENTS;
DROP TABLE IF EXISTS BILLING.REFUNDS;
DROP TABLE IF EXISTS PRODUCT.EVENTS;
DROP TABLE IF EXISTS ERP.COST_CENTERS;
DROP TABLE IF EXISTS ERP.GL_ENTRIES;
DROP TABLE IF EXISTS MARKET.FX_RATES;
*/

-- =============================================================================
-- Grants for the dbt development role.
--
-- Set this to your actual dbt role before running. Note the ordering of the
-- words: the connection in dbt was described as DEV_DBT_ROLE2 and the Snowflake
-- account as DBT_DEV_ROLE2. Confirm which exists with SHOW ROLES before running
-- this block, because GRANT on a nonexistent role fails loudly but GRANT to the
-- wrong existing role fails silently in the sense that dbt still cannot read.
-- =============================================================================

SET DBT_ROLE = 'DBT_DEV_ROLE2';

GRANT USAGE ON DATABASE CORE_RAW TO ROLE IDENTIFIER($DBT_ROLE);
GRANT USAGE ON ALL SCHEMAS IN DATABASE CORE_RAW TO ROLE IDENTIFIER($DBT_ROLE);
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE CORE_RAW TO ROLE IDENTIFIER($DBT_ROLE);
GRANT SELECT ON ALL TABLES IN DATABASE CORE_RAW TO ROLE IDENTIFIER($DBT_ROLE);
GRANT SELECT ON FUTURE TABLES IN DATABASE CORE_RAW TO ROLE IDENTIFIER($DBT_ROLE);
GRANT USAGE ON WAREHOUSE TRANSFORM_XS_WH TO ROLE IDENTIFIER($DBT_ROLE);

-- =============================================================================
-- Post-load verification. Compare against setup/manifest.csv.
-- =============================================================================

SELECT 'CRM.SALES_REPS'        AS table_name, COUNT(*) AS rows FROM CRM.SALES_REPS
UNION ALL SELECT 'CRM.ACCOUNTS',           COUNT(*) FROM CRM.ACCOUNTS
UNION ALL SELECT 'CRM.CONTACTS',           COUNT(*) FROM CRM.CONTACTS
UNION ALL SELECT 'CRM.OPPORTUNITIES',      COUNT(*) FROM CRM.OPPORTUNITIES
UNION ALL SELECT 'BILLING.CUSTOMERS',      COUNT(*) FROM BILLING.CUSTOMERS
UNION ALL SELECT 'BILLING.SUBSCRIPTIONS',  COUNT(*) FROM BILLING.SUBSCRIPTIONS
UNION ALL SELECT 'BILLING.INVOICES',       COUNT(*) FROM BILLING.INVOICES
UNION ALL SELECT 'BILLING.INVOICE_LINES',  COUNT(*) FROM BILLING.INVOICE_LINES
UNION ALL SELECT 'BILLING.PAYMENTS',       COUNT(*) FROM BILLING.PAYMENTS
UNION ALL SELECT 'BILLING.REFUNDS',        COUNT(*) FROM BILLING.REFUNDS
UNION ALL SELECT 'PRODUCT.EVENTS',         COUNT(*) FROM PRODUCT.EVENTS
UNION ALL SELECT 'ERP.COST_CENTERS',       COUNT(*) FROM ERP.COST_CENTERS
UNION ALL SELECT 'ERP.GL_ENTRIES',         COUNT(*) FROM ERP.GL_ENTRIES
UNION ALL SELECT 'MARKET.FX_RATES',        COUNT(*) FROM MARKET.FX_RATES
ORDER BY table_name;

-- Offsets survived the load if this returns more than one distinct offset.
SELECT DISTINCT EXTRACT(TIMEZONE_HOUR FROM EVENT_TIMESTAMP) AS tz_hour, COUNT(*) AS n
FROM PRODUCT.EVENTS GROUP BY 1 ORDER BY 1;

-- Should return zero rows. If it returns any, PROPERTIES was mangled on load.
SELECT COUNT(*) AS unparseable_properties
FROM PRODUCT.EVENTS WHERE TRY_PARSE_JSON(PROPERTIES) IS NULL;
