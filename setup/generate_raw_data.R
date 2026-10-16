#!/usr/bin/env Rscript
# =============================================================================
# generate_raw_data.R
#
# Deterministic fake-data generator for a fictional B2B SaaS company.
# Emits one CSV per raw table for loading into Snowflake database CORE_RAW.
#
# Implements raw_data_spec.md. Dependencies: readr, jsonlite. Everything else
# is base R.
#
#   Rscript setup/generate_raw_data.R
#   Rscript setup/generate_raw_data.R --scenario broken
#   Rscript setup/generate_raw_data.R --seed 42 --scale 2
# =============================================================================

suppressPackageStartupMessages({
  library(readr)
  library(jsonlite)
})

options(stringsAsFactors = FALSE, scipen = 999)

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

parse_args <- function(argv) {
  cfg <- list(
    scenario     = "standard",
    seed         = 20250301,
    as_of_date   = "2026-01-01",
    history_days = 730,
    scale        = 1,
    output_dir   = "setup/generated",
    manifest_dir = "setup"
  )
  i <- 1
  while (i <= length(argv)) {
    key <- sub("^--", "", argv[i])
    if (!key %in% names(cfg)) stop("Unknown argument: ", argv[i])
    if (i + 1 > length(argv)) stop("Missing value for ", argv[i])
    cfg[[key]] <- argv[i + 1]
    i <- i + 2
  }
  cfg$seed         <- as.numeric(cfg$seed)
  cfg$history_days <- as.integer(cfg$history_days)
  cfg$scale        <- as.numeric(cfg$scale)
  if (!cfg$scenario %in% c("clean", "standard", "broken")) {
    stop("scenario must be clean, standard, or broken")
  }
  if (cfg$scale <= 0) stop("scale must be positive")
  cfg
}

cfg <- parse_args(commandArgs(trailingOnly = TRUE))

set.seed(cfg$seed)

SCENARIO    <- cfg$scenario
SCALE       <- cfg$scale
AS_OF       <- as.Date(cfg$as_of_date)
START_DATE  <- AS_OF - cfg$history_days
# Reference instant: as-of date at 23:59 UTC. All _loaded_at values hang off this.
REF_TIME    <- as.POSIXct(paste0(cfg$as_of_date, " 23:59:00"), tz = "UTC")
GENERATED_AT <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

INJECT_STD    <- SCENARIO %in% c("standard", "broken")
INJECT_BROKEN <- SCENARIO == "broken"

# -----------------------------------------------------------------------------
# Small helpers
# -----------------------------------------------------------------------------

n_scaled <- function(n) max(1L, as.integer(round(n * SCALE)))

# ISO-8601 in UTC, "Z" offset.
ts_z <- function(x) {
  ifelse(is.na(x), NA_character_,
         format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
}

# ISO-8601 rendered in a non-UTC offset. offset_h is hours ahead of UTC.
# The instant is unchanged; only its presentation moves.
ts_offset <- function(x, offset_h) {
  x <- as.POSIXct(x, tz = "UTC")
  local <- x + offset_h * 3600
  sign <- ifelse(offset_h < 0, "-", "+")
  hh <- sprintf("%02d", floor(abs(offset_h)))
  mm <- sprintf("%02d", round((abs(offset_h) %% 1) * 60))
  paste0(format(local, "%Y-%m-%dT%H:%M:%S", tz = "UTC"), sign, hh, ":", mm)
}

d_str <- function(x) ifelse(is.na(x), NA_character_, format(as.Date(x), "%Y-%m-%d"))

b_str <- function(x) ifelse(is.na(x), NA_character_, ifelse(x, "true", "false"))

cents <- function(x) as.integer(round(x))

money2 <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.2f", x))
prob4  <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.4f", x))
rate8  <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.8f", x))

rint <- function(n, lo, hi) {
  if (n == 0) return(integer(0))
  as.integer(floor(runif(n, lo, hi + 1)))
}

rpick <- function(n, values, prob = NULL) {
  if (n == 0) return(values[0])
  sample(values, n, replace = TRUE, prob = prob)
}

# Random instant between two dates, as POSIXct UTC.
rtime <- function(n, from, to) {
  from_s <- as.numeric(as.POSIXct(paste0(format(as.Date(from)), " 00:00:00"), tz = "UTC"))
  to_s   <- as.numeric(as.POSIXct(paste0(format(as.Date(to)),   " 23:59:59"), tz = "UTC"))
  to_s   <- pmax(to_s, from_s + 60)
  as.POSIXct(runif(n, from_s, to_s), origin = "1970-01-01", tz = "UTC")
}

id_str <- function(prefix, i) sprintf("%s_%06d", prefix, i)

add_months <- function(d, n) {
  d <- as.Date(d)
  lt <- as.POSIXlt(d)
  target_month <- lt$mon + n
  lt$year <- lt$year + target_month %/% 12
  lt$mon  <- target_month %% 12
  out <- as.Date(lt)
  # Guard month-end rollover (e.g. Jan 31 + 1 month).
  bad <- is.na(out)
  if (any(bad)) out[bad] <- as.Date(lt[bad]) - 3
  out
}

# _loaded_at for a source: uniformly between the row's business time and the
# source's freshness ceiling, never before the business time.
loaded_at_for <- function(business_time, source) {
  max_age_h <- switch(source,
                      CRM = 2, BILLING = 2, PRODUCT = 1, ERP = 8,
                      MARKET = if (INJECT_BROKEN) 80 else 30)
  ceiling_t <- REF_TIME - max_age_h * 3600
  bt <- as.POSIXct(business_time, tz = "UTC")
  # Most rows load shortly after they happen; a slice loads at the ceiling so
  # every table actually touches its stated max age.
  lag_h <- runif(length(bt), 0.2, 6)
  out <- bt + lag_h * 3600
  out <- pmin(out, ceiling_t)
  out <- pmax(out, bt + 60)
  out <- pmin(out, ceiling_t)
  out
}

# Force the newest rows of a source to sit exactly at the freshness ceiling.
pin_max_loaded_at <- function(loaded, source) {
  max_age_h <- switch(source,
                      CRM = 2, BILLING = 2, PRODUCT = 1, ERP = 8,
                      MARKET = if (INJECT_BROKEN) 80 else 30)
  ceiling_t <- REF_TIME - max_age_h * 3600
  if (length(loaded) == 0) return(loaded)
  idx <- which.max(as.numeric(loaded))
  loaded[idx] <- ceiling_t
  loaded
}

# -----------------------------------------------------------------------------
# Anomaly manifest accumulator
# -----------------------------------------------------------------------------

ANOMALIES <- list()

record_anomaly <- function(table, key, type, handling, severity) {
  if (length(key) == 0) return(invisible(NULL))
  ANOMALIES[[length(ANOMALIES) + 1]] <<- data.frame(
    table_name        = table,
    technical_key     = as.character(key),
    anomaly_type      = type,
    expected_handling = handling,
    expected_severity = severity
  )
  invisible(NULL)
}

# -----------------------------------------------------------------------------
# Shared domains
# -----------------------------------------------------------------------------

CURRENCIES <- c("USD", "EUR", "GBP", "CAD", "AUD")
CURRENCY_W <- c(0.55, 0.15, 0.12, 0.10, 0.08)

COUNTRY_CANON <- c("United States", "Canada", "United Kingdom", "Germany",
                   "France", "Australia", "Netherlands", "Ireland",
                   "Spain", "Japan")

# Messy but recognizable variants, for the country-cleaning macro.
COUNTRY_VARIANTS <- c("usa", "U.S.A.", "US ", " united states", "UNITED STATES",
                      "Untied States", "CA", "canada ", "Canadaa",
                      "UK", "U.K.", "Great Britain", "united kingdom",
                      "DE", "deutschland", "Germny", "FR", "france",
                      "AUS", "australia", "NL", "netherlands", "Holland",
                      "IE", "eire", "ES", "espana", "JP", "japan ")

COUNTRY_UNKNOWN <- c("Atlantis", "ZZ-Nowhere")

INDUSTRIES <- c("Software", "Financial Services", "Healthcare", "Retail",
                "Manufacturing", "Professional Services", "Media", "Education")

TIERS <- c("enterprise", "mid_market", "smb")

REGIONS <- c("AMER", "EMEA", "APAC")

PLAN_CODES <- c("STARTER_MONTHLY", "STARTER_ANNUAL", "GROWTH_MONTHLY",
                "GROWTH_ANNUAL", "ENTERPRISE_ANNUAL")

PLAN_INTERVAL <- c(STARTER_MONTHLY = "month", STARTER_ANNUAL = "year",
                   GROWTH_MONTHLY = "month", GROWTH_ANNUAL = "year",
                   ENTERPRISE_ANNUAL = "year")

PLAN_PRICE <- c(STARTER_MONTHLY = 4900L, STARTER_ANNUAL = 49000L,
                GROWTH_MONTHLY = 19900L, GROWTH_ANNUAL = 199000L,
                ENTERPRISE_ANNUAL = 960000L)

ACCOUNT_CODES <- c("1000", "1100", "2000", "4000", "4010",
                   "5000", "6100", "6200", "6300")

EVENT_NAMES <- c("login", "page_view", "feature_used", "report_created",
                 "export_completed", "api_call", "invite_sent")

TZ_OFFSETS <- c(0, -5, -8, 1, 9, 5.5, 10)

FIRST_NAMES <- c("Avery", "Jordan", "Priya", "Marcus", "Lena", "Diego", "Nina",
                 "Omar", "Freya", "Tomas", "Ingrid", "Rashid", "Clara", "Noah",
                 "Yuki", "Mateo", "Saoirse", "Henrik", "Amara", "Pablo",
                 "Greta", "Idris", "Mira", "Caleb", "Zara", "Lukas", "Elena",
                 "Theo", "Ayana", "Felix")

LAST_NAMES <- c("Okafor", "Lindqvist", "Varga", "Moreau", "Castellanos",
                "Brennan", "Haddad", "Nakamura", "Delgado", "Novak",
                "Ferreira", "Kowalski", "Bergstrom", "Rahimi", "Whitfield",
                "Dubois", "Marchetti", "Osei", "Halvorsen", "Quintero",
                "Ashworth", "Petrova", "Sandoval", "Linde", "Ferrante")

COMPANY_PREFIX <- c("Northwind", "Cobalt", "Verdant", "Lumenaire", "Ironvale",
                    "Pinewright", "Halcyon", "Starling", "Granitepost",
                    "Blueharbor", "Ashford", "Meridian", "Quillstone",
                    "Brightfall", "Oakmere", "Silverkeep", "Tideline",
                    "Fernwood", "Copperline", "Marbleton", "Rookwood",
                    "Everdeen", "Sableridge", "Thornbury", "Larkfield",
                    "Highmoor", "Stonebrook", "Westvale", "Kingsmere",
                    "Alderpoint", "Foxglove", "Amberline", "Redcliff",
                    "Windermere", "Clearwater", "Hollowbrook", "Juniper",
                    "Nightingale", "Stormhaven", "Wrenfield")

COMPANY_SUFFIX <- c("Systems", "Analytics", "Labs", "Group", "Holdings",
                    "Partners", "Technologies", "Digital", "Industries",
                    "Solutions", "Networks", "Collective")

LEGAL_SUFFIX <- c("", " Inc.", " LLC", " Ltd.", " GmbH", " B.V.", " Pty Ltd")

cat("Generating:", SCENARIO, "| seed", cfg$seed, "| scale", SCALE,
    "| as of", format(AS_OF), "\n")

# -----------------------------------------------------------------------------
# 1. CRM.SALES_REPS
# -----------------------------------------------------------------------------

build_sales_reps <- function() {
  n <- n_scaled(20)
  ids <- id_str("rep", seq_len(n))
  fn <- rpick(n, FIRST_NAMES)
  ln <- rpick(n, LAST_NAMES)

  # Emails must be unique after lowercasing; the index guarantees it.
  email <- tolower(sprintf("%s.%s%d@demosaas.example", fn, ln, seq_len(n)))

  n_mgr <- max(2L, as.integer(round(n * 0.15)))
  manager <- rep(NA_character_, n)
  manager[(n_mgr + 1):n] <- rpick(n - n_mgr, ids[1:n_mgr])

  hire <- AS_OF - rint(n, 120, 2200)

  is_active <- runif(n) > 0.10

  lat <- loaded_at_for(as.POSIXct(paste0(format(AS_OF - rint(n, 1, 20)),
                                         " 09:00:00"), tz = "UTC"), "CRM")
  lat <- pin_max_loaded_at(lat, "CRM")

  data.frame(
    sales_rep_id         = ids,
    first_name           = fn,
    last_name            = ln,
    email                = email,
    region               = rpick(n, REGIONS, c(0.5, 0.3, 0.2)),
    manager_sales_rep_id = manager,
    hire_date            = d_str(hire),
    is_active            = b_str(is_active),
    `_loaded_at`         = ts_z(lat),
    check.names          = FALSE
  )
}

sales_reps <- build_sales_reps()

# -----------------------------------------------------------------------------
# 2. CRM.ACCOUNTS
# -----------------------------------------------------------------------------

build_accounts <- function(reps) {
  n_total <- n_scaled(250)
  n_dupes <- n_scaled(8)
  n_real  <- n_total - n_dupes

  # Unique fictional company names.
  grid <- expand.grid(p = COMPANY_PREFIX, s = COMPANY_SUFFIX,
                      stringsAsFactors = FALSE)
  grid <- grid[sample(nrow(grid)), ]
  if (nrow(grid) < n_real) stop("Not enough company name combinations")
  base_name <- paste(grid$p[1:n_real], grid$s[1:n_real])
  legal <- rpick(n_real, LEGAL_SUFFIX, c(0.45, 0.2, 0.12, 0.1, 0.05, 0.04, 0.04))
  real_name <- paste0(base_name, legal)

  base_domain <- paste0(tolower(gsub("[^A-Za-z]", "", grid$p[1:n_real])),
                        tolower(substr(gsub("[^A-Za-z]", "", grid$s[1:n_real]), 1, 3)),
                        ".com")

  ids <- id_str("acct", seq_len(n_total))

  name   <- c(real_name, rep(NA_character_, n_dupes))
  domain <- c(base_domain, rep(NA_character_, n_dupes))
  # Which real company each row represents. Duplicates point back at an earlier row.
  company_idx <- c(seq_len(n_real), rep(NA_integer_, n_dupes))

  # --- Anomaly: duplicate companies under separate account IDs --------------
  if (INJECT_STD && n_dupes > 0) {
    dup_src <- sample(seq_len(n_real), n_dupes)
    for (k in seq_len(n_dupes)) {
      src <- dup_src[k]
      row <- n_real + k
      v <- real_name[src]
      v <- switch(((k - 1) %% 4) + 1,
                  toupper(v),
                  paste0("  ", gsub("[.,]", "", v), " "),
                  gsub(" ", "  ", tolower(v)),
                  paste0(gsub("\\.", "", v), ","))
      name[row]        <- v
      domain[row]      <- base_domain[src]
      company_idx[row] <- src
    }
    record_anomaly("CRM.ACCOUNTS", ids[(n_real + 1):n_total],
                   "duplicate_company_separate_account_id",
                   "account matching macro consolidates to conformed customer",
                   "warn")
  } else if (n_dupes > 0) {
    # clean scenario: make them genuinely distinct companies
    extra <- paste(grid$p[(n_real + 1):(n_real + n_dupes)],
                   grid$s[(n_real + 1):(n_real + n_dupes)])
    name[(n_real + 1):n_total] <- extra
    domain[(n_real + 1):n_total] <- paste0(tolower(gsub("[^A-Za-z]", "", extra)), ".com")
    company_idx[(n_real + 1):n_total] <- (n_real + 1):n_total
  }

  # --- Anomaly: dirty website domains ---------------------------------------
  if (INJECT_STD) {
    k <- n_scaled(15)
    idx <- sample(seq_len(n_total), k)
    for (j in seq_along(idx)) {
      i <- idx[j]
      domain[i] <- switch(((j - 1) %% 5) + 1,
                          paste0("https://", domain[i]),
                          paste0("www.", domain[i]),
                          toupper(domain[i]),
                          paste0(domain[i], "/"),
                          paste0("http://www.", domain[i], "/"))
    }
    record_anomaly("CRM.ACCOUNTS", ids[idx], "dirty_website_domain",
                   "staging normalizes domain", "pass_after_cleaning")
  }

  # A few genuinely missing domains.
  domain[sample(seq_len(n_total), n_scaled(12))] <- NA_character_

  # --- Countries -------------------------------------------------------------
  country <- rpick(n_total, COUNTRY_CANON,
                   c(0.40, 0.10, 0.12, 0.08, 0.06, 0.06, 0.05, 0.05, 0.04, 0.04))
  n_var_crm <- n_scaled(15)   # remainder of the 25 variants land in BILLING
  if (INJECT_STD) {
    idx <- sample(seq_len(n_total), n_var_crm)
    country[idx] <- rpick(n_var_crm, COUNTRY_VARIANTS)
    record_anomaly("CRM.ACCOUNTS", ids[idx], "country_free_text_variant",
                   "country macro maps to ISO code", "pass_after_cleaning")

    k <- n_scaled(2)
    idx2 <- sample(setdiff(seq_len(n_total), idx), k)
    country[idx2] <- rpick(k, COUNTRY_UNKNOWN)
    record_anomaly("CRM.ACCOUNTS", ids[idx2], "country_unrecognized",
                   "map to UNKNOWN and store failing records", "warn")
  }
  country[sample(seq_len(n_total), n_scaled(10))] <- NA_character_

  # --- Attributes ------------------------------------------------------------
  tier <- rpick(n_total, TIERS, c(0.18, 0.37, 0.45))
  emp <- ifelse(tier == "enterprise", rint(n_total, 1200, 25000),
                ifelse(tier == "mid_market", rint(n_total, 120, 1200),
                       rint(n_total, 3, 120)))
  rev <- round(emp * runif(n_total, 80000, 240000) / 1000) * 1000
  rev[sample(seq_len(n_total), n_scaled(30))] <- NA_real_
  emp[sample(seq_len(n_total), n_scaled(18))] <- NA_integer_

  industry <- rpick(n_total, INDUSTRIES)
  industry[sample(seq_len(n_total), n_scaled(15))] <- NA_character_

  ccy <- rpick(n_total, CURRENCIES, CURRENCY_W)

  # Growth curve: more accounts created recently than two years ago.
  created <- rtime(n_total, START_DATE, AS_OF - 20)
  skew <- runif(n_total)^0.6
  created <- as.POSIXct(as.numeric(as.POSIXct(paste0(format(START_DATE), " 00:00:00"), tz = "UTC")) +
                          skew * (as.numeric(created) -
                                    as.numeric(as.POSIXct(paste0(format(START_DATE), " 00:00:00"), tz = "UTC"))),
                        origin = "1970-01-01", tz = "UTC")

  # updated_at: 82% never revised, 15% older revision, 3% recent revision.
  u <- runif(n_total)
  updated <- created
  old_rev <- which(u >= 0.82 & u < 0.97)
  new_rev <- which(u >= 0.97)
  if (length(old_rev) > 0) {
    updated[old_rev] <- rtime(length(old_rev), AS_OF - 300, AS_OF - 15)
    updated[old_rev] <- pmax(updated[old_rev], created[old_rev] + 86400)
  }
  if (length(new_rev) > 0) {
    updated[new_rev] <- rtime(length(new_rev), AS_OF - 13, AS_OF)
    updated[new_rev] <- pmax(updated[new_rev], created[new_rev] + 86400)
  }
  updated <- pmin(updated, REF_TIME - 3 * 3600)

  # --- Soft deletes ----------------------------------------------------------
  is_del <- runif(n_total) < 0.03
  deleted_at <- rep(as.POSIXct(NA, tz = "UTC"), n_total)
  if (any(is_del)) {
    deleted_at[is_del] <- updated[is_del]
    record_anomaly("CRM.ACCOUNTS", ids[is_del], "soft_deleted_account",
                   "excluded from conformed output, retained by snapshot", "pass")
  }

  owner <- rpick(n_total, reps$sales_rep_id)

  # --- Broken: one null account_id and one null name -------------------------
  if (INJECT_BROKEN) {
    bi <- sample(seq_len(n_total), 1)
    name[bi] <- NA_character_
    record_anomaly("CRM.ACCOUNTS", ids[bi], "null_account_name",
                   "not-null test fails", "error")
    bi2 <- sample(setdiff(seq_len(n_total), bi), 1)
    ids[bi2] <- NA_character_
    record_anomaly("CRM.ACCOUNTS", "(null)", "null_account_id",
                   "not-null test fails", "error")
  }

  lat <- loaded_at_for(updated, "CRM")
  lat <- pin_max_loaded_at(lat, "CRM")

  df <- data.frame(
    account_id         = ids,
    account_name       = name,
    website_domain     = domain,
    billing_country    = country,
    industry           = industry,
    employee_count     = emp,
    annual_revenue     = money2(rev),
    account_currency   = ccy,
    account_tier       = tier,
    owner_sales_rep_id = owner,
    created_at         = ts_z(created),
    updated_at         = ts_z(updated),
    is_deleted         = b_str(is_del),
    deleted_at         = ts_z(deleted_at),
    `_loaded_at`       = ts_z(lat),
    check.names        = FALSE
  )

  # Internal helper columns for downstream builders; dropped before writing.
  attr(df, "helper") <- data.frame(
    account_id  = ids,
    company_idx = company_idx,
    clean_name  = ifelse(is.na(company_idx), name, real_name[pmin(company_idx, n_real)]),
    clean_domain = ifelse(is.na(company_idx), NA_character_,
                          base_domain[pmin(company_idx, n_real)]),
    created     = created,
    currency    = ccy,
    tier        = tier,
    is_deleted  = is_del,
    stringsAsFactors = FALSE
  )
  df
}

accounts <- build_accounts(sales_reps)
acct_h <- attr(accounts, "helper")

# -----------------------------------------------------------------------------
# 3. CRM.CONTACTS
# -----------------------------------------------------------------------------

build_contacts <- function(acct_h) {
  n <- n_scaled(700)
  ids <- id_str("cont", seq_len(n))

  # Every account gets at least one contact, then the rest are spread around.
  n_acct <- nrow(acct_h)
  acct_ids <- c(acct_h$account_id,
                rpick(max(0, n - n_acct), acct_h$account_id))[1:n]

  fn <- rpick(n, FIRST_NAMES)
  ln <- rpick(n, LAST_NAMES)

  dom <- acct_h$clean_domain[match(acct_ids, acct_h$account_id)]
  dom[is.na(dom)] <- "demosaas.example"
  email <- tolower(sprintf("%s.%s%d@%s", fn, ln, seq_len(n), dom))

  # --- Anomaly: email casing and whitespace ---------------------------------
  if (INJECT_STD) {
    k <- n_scaled(20)
    idx <- sample(seq_len(n), k)
    for (j in seq_along(idx)) {
      i <- idx[j]
      email[i] <- switch(((j - 1) %% 3) + 1,
                         toupper(email[i]),
                         paste0(" ", email[i]),
                         paste0(email[i], "  "))
    }
    record_anomaly("CRM.CONTACTS", ids[idx], "email_case_or_whitespace",
                   "staging normalizes email", "pass_after_cleaning")
  }

  # --- Anomaly: null emails (never primary) ---------------------------------
  null_email_idx <- integer(0)
  if (INJECT_STD) {
    k <- n_scaled(5)
    null_email_idx <- sample(setdiff(seq_len(n), if (exists("idx")) idx else integer(0)), k)
    email[null_email_idx] <- NA_character_
    record_anomaly("CRM.CONTACTS", ids[null_email_idx], "null_email",
                   "allowed because contact is not primary", "pass")
  }

  created <- rtime(n, START_DATE, AS_OF - 10)
  parent_created <- acct_h$created[match(acct_ids, acct_h$account_id)]
  created <- pmax(created, parent_created + 3600)
  created <- pmin(created, REF_TIME - 6 * 3600)

  updated <- created
  bump <- runif(n) < 0.2
  if (any(bump)) {
    updated[bump] <- pmin(rtime(sum(bump), AS_OF - 200, AS_OF), REF_TIME - 4 * 3600)
    updated[bump] <- pmax(updated[bump], created[bump] + 3600)
  }

  is_del <- runif(n) < 0.02

  # Exactly one primary per account, chosen among non-deleted rows with an email.
  is_primary <- rep(FALSE, n)
  eligible <- !is_del & !is.na(email)
  for (a in unique(acct_ids)) {
    cand <- which(acct_ids == a & eligible)
    if (length(cand) > 0) is_primary[cand[1]] <- TRUE
  }

  lat <- loaded_at_for(updated, "CRM")
  lat <- pin_max_loaded_at(lat, "CRM")

  data.frame(
    contact_id   = ids,
    account_id   = acct_ids,
    first_name   = fn,
    last_name    = ln,
    email        = email,
    job_title    = rpick(n, c("Analyst", "Manager", "Director", "VP Finance",
                              "Head of Data", "CTO", "Controller", "Operations Lead",
                              NA_character_)),
    is_primary   = b_str(is_primary),
    created_at   = ts_z(created),
    updated_at   = ts_z(updated),
    is_deleted   = b_str(is_del),
    `_loaded_at` = ts_z(lat),
    check.names  = FALSE
  )
}

contacts <- build_contacts(acct_h)

# -----------------------------------------------------------------------------
# 4. CRM.OPPORTUNITIES
# -----------------------------------------------------------------------------

build_opportunities <- function(acct_h, reps) {
  n <- n_scaled(900)
  ids <- id_str("opp", seq_len(n))
  acct_ids <- rpick(n, acct_h$account_id)

  created <- rtime(n, START_DATE, AS_OF - 5)
  age_days <- as.numeric(difftime(as.POSIXct(paste0(format(AS_OF), " 23:59:59"), tz = "UTC"),
                                  created, units = "days"))

  # Older opportunities are much more likely to be closed.
  p_closed <- pmin(0.95, age_days / 240)
  closed <- runif(n) < p_closed
  won <- closed & (runif(n) < 0.38)

  stage <- ifelse(won, "closed_won",
                  ifelse(closed, "closed_lost",
                         rpick(n, c("prospecting", "qualification",
                                    "proposal", "negotiation"),
                               c(0.35, 0.3, 0.2, 0.15))))

  probability <- ifelse(stage == "closed_won", 1,
                        ifelse(stage == "closed_lost", 0,
                               ifelse(stage == "prospecting", 0.1,
                                      ifelse(stage == "qualification", 0.25,
                                             ifelse(stage == "proposal", 0.5, 0.75)))))

  tier <- acct_h$tier[match(acct_ids, acct_h$account_id)]
  amount <- ifelse(tier == "enterprise", rint(n, 4000000, 30000000),
                   ifelse(tier == "mid_market", rint(n, 500000, 4000000),
                          rint(n, 50000, 500000)))

  close_date <- as.Date(created) + rint(n, 20, 200)
  close_date[closed] <- pmin(close_date[closed], AS_OF)
  close_date[!closed] <- pmax(close_date[!closed], AS_OF + 5)

  updated <- created + rint(n, 1, 60) * 86400
  updated <- pmin(updated, REF_TIME - 4 * 3600)
  updated <- pmax(updated, created + 3600)

  lat <- loaded_at_for(updated, "CRM")
  lat <- pin_max_loaded_at(lat, "CRM")

  data.frame(
    opportunity_id     = ids,
    account_id         = acct_ids,
    owner_sales_rep_id = rpick(n, reps$sales_rep_id),
    opportunity_name   = paste0(rpick(n, c("New Business", "Expansion", "Renewal",
                                           "Upgrade", "Pilot")), " - ",
                                substr(acct_ids, 6, 11)),
    stage              = stage,
    amount_cents       = cents(amount),
    currency           = acct_h$currency[match(acct_ids, acct_h$account_id)],
    probability        = prob4(probability),
    close_date         = d_str(close_date),
    created_at         = ts_z(created),
    updated_at         = ts_z(updated),
    is_deleted         = b_str(runif(n) < 0.02),
    `_loaded_at`       = ts_z(lat),
    check.names        = FALSE
  )
}

opportunities <- build_opportunities(acct_h, sales_reps)

# -----------------------------------------------------------------------------
# 5. BILLING.CUSTOMERS
# -----------------------------------------------------------------------------

build_customers <- function(acct_h) {
  n_target <- n_scaled(230)

  # ~70% of accounts become customers.
  n_linked <- as.integer(round(nrow(acct_h) * 0.70))
  linked_accts <- sample(acct_h$account_id, n_linked)

  # A few accounts carry a second billing entity.
  n_second <- as.integer(round(n_target * 0.13))
  second_accts <- sample(linked_accts, min(n_second, length(linked_accts)))

  # The remainder are self-serve signups with no CRM counterpart.
  n_standalone <- max(0, n_target - n_linked - length(second_accts))

  src_acct <- c(linked_accts, second_accts, rep(NA_character_, n_standalone))
  n <- length(src_acct)
  ids <- id_str("bcust", seq_len(n))

  h <- acct_h[match(src_acct, acct_h$account_id), ]

  # Billing names drift from CRM names.
  cust_name <- h$clean_name
  drift <- runif(n) < 0.45
  cust_name[drift] <- gsub("[.,]", "", cust_name[drift])
  drift2 <- runif(n) < 0.2
  cust_name[drift2] <- toupper(cust_name[drift2])
  standalone <- is.na(src_acct)
  if (any(standalone)) {
    cust_name[standalone] <- paste0(rpick(sum(standalone), COMPANY_PREFIX), " ",
                                    rpick(sum(standalone), COMPANY_SUFFIX),
                                    " (Self Serve)")
  }

  domain <- h$clean_domain
  domain[standalone] <- paste0(tolower(gsub("[^A-Za-z]", "",
                                            substr(cust_name[standalone], 1, 10))),
                               ".io")

  crm_id <- src_acct

  # --- Anomaly: missing but matchable crm_account_id ------------------------
  if (INJECT_STD) {
    cand <- which(!is.na(crm_id) & !is.na(domain))
    k <- min(n_scaled(10), length(cand))
    idx <- sample(cand, k)
    crm_id[idx] <- NA_character_
    record_anomaly("BILLING.CUSTOMERS", ids[idx], "missing_matchable_crm_account_id",
                   "account matching fills conformed relationship",
                   "pass_after_cleaning")

    # --- Anomaly: wrong crm_account_id, domain still matches ----------------
    cand2 <- setdiff(which(!is.na(crm_id) & !is.na(domain)), idx)
    k2 <- min(n_scaled(3), length(cand2))
    idx2 <- sample(cand2, k2)
    for (i in idx2) {
      wrong <- sample(setdiff(acct_h$account_id, crm_id[i]), 1)
      crm_id[i] <- wrong
    }
    record_anomaly("BILLING.CUSTOMERS", ids[idx2], "incorrect_crm_account_id",
                   "matching logic picks correct account and flags discrepancy",
                   "warn")
  }

  country <- rpick(n, COUNTRY_CANON,
                   c(0.40, 0.10, 0.12, 0.08, 0.06, 0.06, 0.05, 0.05, 0.04, 0.04))
  if (INJECT_STD) {
    k <- n_scaled(10)   # completes the 25 country variants across CRM + BILLING
    idx <- sample(seq_len(n), k)
    country[idx] <- rpick(k, COUNTRY_VARIANTS)
    record_anomaly("BILLING.CUSTOMERS", ids[idx], "country_free_text_variant",
                   "country macro maps to ISO code", "pass_after_cleaning")
  }

  ccy <- h$currency
  ccy[standalone] <- rpick(sum(standalone), CURRENCIES, CURRENCY_W)

  if (INJECT_BROKEN) {
    bi <- sample(seq_len(n), 1)
    ccy[bi] <- "XYZ"
    record_anomaly("BILLING.CUSTOMERS", ids[bi], "unsupported_currency_xyz",
                   "accepted-values test fails; no FX rate exists", "error")
  }

  created <- h$created + rint(n, 1, 90) * 86400
  created[standalone] <- rtime(sum(standalone), START_DATE + 60, AS_OF - 30)
  created <- pmin(created, REF_TIME - 10 * 86400)

  status <- rpick(n, c("active", "delinquent", "closed"), c(0.78, 0.09, 0.13))

  updated <- pmax(created + rint(n, 1, 200) * 86400, created + 3600)
  updated <- pmin(updated, REF_TIME - 3 * 3600)

  lat <- loaded_at_for(updated, "BILLING")
  lat <- pin_max_loaded_at(lat, "BILLING")

  df <- data.frame(
    billing_customer_id = ids,
    crm_account_id      = crm_id,
    customer_name       = cust_name,
    website_domain      = domain,
    billing_email       = tolower(paste0("billing@", ifelse(is.na(domain),
                                                            "demosaas.example", domain))),
    billing_country     = country,
    currency            = ccy,
    status              = status,
    tax_id              = ifelse(runif(n) < 0.6,
                                 sprintf("TAX-%06d", rint(n, 100000, 999999)),
                                 NA_character_),
    created_at          = ts_z(created),
    updated_at          = ts_z(updated),
    `_loaded_at`        = ts_z(lat),
    check.names         = FALSE
  )

  attr(df, "helper") <- data.frame(
    billing_customer_id = ids,
    currency            = ccy,
    created             = created,
    status              = status,
    stringsAsFactors    = FALSE
  )
  df
}

customers <- build_customers(acct_h)
cust_h <- attr(customers, "helper")

# -----------------------------------------------------------------------------
# 6. BILLING.SUBSCRIPTIONS
# -----------------------------------------------------------------------------

build_subscriptions <- function(cust_h) {
  n <- n_scaled(350)

  # Active customers are likelier to hold a subscription, and some hold several.
  w <- ifelse(cust_h$status == "active", 3, 1)
  cust_ids <- sample(cust_h$billing_customer_id, n, replace = TRUE,
                     prob = w / sum(w))

  ids <- id_str("sub", seq_len(n))
  plan <- rpick(n, PLAN_CODES, c(0.26, 0.14, 0.28, 0.17, 0.15))
  interval <- unname(PLAN_INTERVAL[plan])

  cust_created <- cust_h$created[match(cust_ids, cust_h$billing_customer_id)]
  started <- cust_created + rint(n, 0, 120) * 86400
  started <- pmin(started, REF_TIME - 20 * 86400)

  cust_status <- cust_h$status[match(cust_ids, cust_h$billing_customer_id)]
  status <- ifelse(cust_status == "closed",
                   rpick(n, c("canceled", "paused"), c(0.85, 0.15)),
                   ifelse(cust_status == "delinquent",
                          rpick(n, c("past_due", "active", "canceled"), c(0.6, 0.25, 0.15)),
                          rpick(n, c("active", "trialing", "paused", "canceled", "past_due"),
                                c(0.75, 0.05, 0.05, 0.12, 0.03))))

  canceled_at <- rep(as.POSIXct(NA, tz = "UTC"), n)
  is_canc <- status == "canceled"
  if (any(is_canc)) {
    canceled_at[is_canc] <- started[is_canc] +
      rint(sum(is_canc), 40, 500) * 86400
    canceled_at[is_canc] <- pmin(canceled_at[is_canc], REF_TIME - 4 * 3600)
    canceled_at[is_canc] <- pmax(canceled_at[is_canc], started[is_canc] + 86400)
  }

  # Current period: the one containing as_of, or the final period for cancellations.
  anchor <- ifelse(is_canc, as.Date(canceled_at), AS_OF)
  anchor <- as.Date(anchor, origin = "1970-01-01")
  cps <- as.Date(rep(NA, n), origin = "1970-01-01")
  cpe <- as.Date(rep(NA, n), origin = "1970-01-01")
  for (i in seq_len(n)) {
    s <- as.Date(started[i])
    if (interval[i] == "month") {
      k <- max(0, as.integer(floor(as.numeric(anchor[i] - s) / 30.44)))
      cps[i] <- add_months(s, k)
      cpe[i] <- add_months(s, k + 1)
    } else {
      k <- max(0, as.integer(floor(as.numeric(anchor[i] - s) / 365.25)))
      cps[i] <- add_months(s, 12 * k)
      cpe[i] <- add_months(s, 12 * (k + 1))
    }
  }
  cpe <- pmax(cpe, cps + 1)

  qty <- ifelse(plan == "ENTERPRISE_ANNUAL", rint(n, 25, 400),
                ifelse(grepl("^GROWTH", plan), rint(n, 5, 60), rint(n, 1, 12)))
  price <- unname(PLAN_PRICE[plan])
  # Small negotiated variance off list price.
  price <- cents(price * runif(n, 0.9, 1.0))

  updated <- pmax(started + rint(n, 1, 120) * 86400, started + 3600)
  updated <- pmin(updated, REF_TIME - 3 * 3600)
  updated[is_canc] <- pmax(updated[is_canc], canceled_at[is_canc])
  updated <- pmin(updated, REF_TIME - 3 * 3600)

  if (INJECT_BROKEN) {
    bi <- sample(seq_len(n), 1)
    cpe[bi] <- cps[bi] - 5
    record_anomaly("BILLING.SUBSCRIPTIONS", ids[bi], "period_end_before_start",
                   "date ordering test fails", "error")
  }

  lat <- loaded_at_for(updated, "BILLING")
  lat <- pin_max_loaded_at(lat, "BILLING")

  df <- data.frame(
    subscription_id      = ids,
    billing_customer_id  = cust_ids,
    plan_code            = plan,
    status               = status,
    started_at           = ts_z(started),
    current_period_start = d_str(cps),
    current_period_end   = d_str(cpe),
    canceled_at          = ts_z(canceled_at),
    quantity             = cents(qty),
    unit_price_cents     = cents(price),
    currency             = cust_h$currency[match(cust_ids, cust_h$billing_customer_id)],
    updated_at           = ts_z(updated),
    `_loaded_at`         = ts_z(lat),
    check.names          = FALSE
  )

  attr(df, "helper") <- data.frame(
    subscription_id     = ids,
    billing_customer_id = cust_ids,
    plan_code           = plan,
    interval            = interval,
    started             = started,
    canceled_at         = canceled_at,
    quantity            = qty,
    unit_price          = price,
    currency            = df$currency,
    stringsAsFactors    = FALSE
  )
  df
}

subscriptions <- build_subscriptions(cust_h)
sub_h <- attr(subscriptions, "helper")

# -----------------------------------------------------------------------------
# 7. BILLING.INVOICES and INVOICE_LINES
#
# Built together: lines are generated first so the invoice header can be derived
# from them, which is what makes the reconciliation formula hold by construction.
# -----------------------------------------------------------------------------

build_invoices_and_lines <- function(sub_h, cust_h) {
  target_inv <- n_scaled(2400)

  # Candidate invoice periods for every subscription.
  periods <- list()
  for (i in seq_len(nrow(sub_h))) {
    s <- as.Date(sub_h$started[i])
    end <- if (!is.na(sub_h$canceled_at[i])) as.Date(sub_h$canceled_at[i]) else AS_OF
    end <- min(end, AS_OF)
    if (end <= s) next
    k <- 0
    repeat {
      issue <- if (sub_h$interval[i] == "month") add_months(s, k) else add_months(s, 12 * k)
      if (issue > end) break
      periods[[length(periods) + 1]] <- data.frame(
        subscription_id = sub_h$subscription_id[i],
        sub_row = i, issue_date = issue, stringsAsFactors = FALSE
      )
      k <- k + 1
      if (k > 30) break
    }
  }
  per <- do.call(rbind, periods)

  # Trim to target before generating anything downstream, keeping newer periods.
  n_oneoff <- as.integer(round(target_inv * 0.05))
  n_sub_inv <- target_inv - n_oneoff
  if (nrow(per) > n_sub_inv) {
    w <- as.numeric(per$issue_date - START_DATE)
    w <- (w / max(w))^1.5 + 0.05
    keep <- sample(seq_len(nrow(per)), n_sub_inv, prob = w)
    per <- per[sort(keep), ]
  }
  rownames(per) <- NULL

  n_sub_inv <- nrow(per)
  n_total <- n_sub_inv + n_oneoff

  inv_ids <- id_str("inv", seq_len(n_total))
  inv_no <- sprintf("INV-%s-%05d",
                    format(c(per$issue_date,
                             sample(seq(START_DATE, AS_OF, by = "day"), n_oneoff,
                                    replace = TRUE)), "%Y"),
                    seq_len(n_total))

  issue_date <- c(per$issue_date,
                  sample(seq(START_DATE + 30, AS_OF, by = "day"), n_oneoff,
                         replace = TRUE))
  issue_date <- as.Date(issue_date, origin = "1970-01-01")

  sub_id <- c(per$subscription_id, rep(NA_character_, n_oneoff))
  sub_row <- c(per$sub_row, rep(NA_integer_, n_oneoff))

  cust_id <- rep(NA_character_, n_total)
  cust_id[seq_len(n_sub_inv)] <- sub_h$billing_customer_id[per$sub_row]
  cust_id[(n_sub_inv + 1):n_total] <- rpick(n_oneoff, cust_h$billing_customer_id)

  ccy <- cust_h$currency[match(cust_id, cust_h$billing_customer_id)]

  # ---- Lines ---------------------------------------------------------------
  line_list <- list()
  subtotal <- integer(n_total)
  discount <- integer(n_total)
  tax <- integer(n_total)
  line_counter <- 0L

  for (i in seq_len(n_total)) {
    lines <- list()

    if (!is.na(sub_row[i])) {
      q <- sub_h$quantity[sub_row[i]]
      u <- sub_h$unit_price[sub_row[i]]
      plan <- sub_h$plan_code[sub_row[i]]
      ps <- issue_date[i]
      pe <- if (sub_h$interval[sub_row[i]] == "month") add_months(ps, 1) else add_months(ps, 12)
      lines[[1]] <- list(plan = plan, type = "subscription",
                         desc = paste0(plan, " subscription"),
                         q = q, u = u, ps = ps, pe = pe)
    } else {
      q <- rint(1, 1, 10)
      u <- cents(rint(1, 50000, 400000))
      lines[[1]] <- list(plan = NA_character_, type = "services",
                         desc = "Professional services engagement",
                         q = q, u = u, ps = NA, pe = NA)
    }

    if (runif(1) < 0.32) {
      q2 <- rint(1, 1, 5)
      u2 <- cents(rint(1, 20000, 150000))
      lines[[length(lines) + 1]] <- list(plan = NA_character_, type = "services",
                                         desc = "Onboarding and training",
                                         q = q2, u = u2, ps = NA, pe = NA)
    }

    if (runif(1) < 0.12) {
      base <- lines[[1]]$q * lines[[1]]$u
      u3 <- -cents(base * runif(1, 0.05, 0.20))
      lines[[length(lines) + 1]] <- list(plan = NA_character_, type = "credit",
                                         desc = "Promotional credit",
                                         q = 1, u = u3, ps = NA, pe = NA)
    }

    gross <- sum(vapply(lines, function(l) l$q * l$u, numeric(1)))
    if (runif(1) < 0.64) {
      rate <- sample(c(0.05, 0.075, 0.19, 0.20, 0.21), 1)
      u4 <- cents(max(0, gross) * rate)
      if (u4 > 0) {
        lines[[length(lines) + 1]] <- list(plan = NA_character_, type = "tax",
                                           desc = "Sales tax", q = 1, u = u4,
                                           ps = NA, pe = NA)
      }
    }

    for (l in lines) {
      line_counter <- line_counter + 1L
      line_list[[line_counter]] <- data.frame(
        invoice_line_id      = id_str("iline", line_counter),
        invoice_id           = inv_ids[i],
        plan_code            = l$plan,
        line_type            = l$type,
        description          = l$desc,
        quantity             = cents(l$q),
        unit_amount_cents    = cents(l$u),
        line_amount_cents    = cents(l$q * l$u),
        service_period_start = d_str(l$ps),
        service_period_end   = d_str(l$pe),
        stringsAsFactors     = FALSE
      )
    }

    amts <- vapply(lines, function(l) l$q * l$u, numeric(1))
    types <- vapply(lines, function(l) l$type, character(1))
    subtotal[i] <- cents(sum(amts[types %in% c("subscription", "services")]))
    discount[i] <- cents(abs(sum(amts[types == "credit"])))
    tax[i]      <- cents(sum(amts[types == "tax"]))
  }

  invoice_lines <- do.call(rbind, line_list)
  total <- cents(subtotal - discount + tax)

  # ---- Status, payments-driven settlement ----------------------------------
  age <- as.numeric(AS_OF - issue_date)
  p_paid <- pmin(0.85, 0.18 + age / 120)
  status <- ifelse(issue_date > AS_OF - 4, "draft",
                   ifelse(runif(n_total) < p_paid, "paid",
                          rpick(n_total, c("open", "void", "uncollectible"),
                                c(0.80, 0.12, 0.08))))

  paid_at <- rep(as.POSIXct(NA, tz = "UTC"), n_total)
  is_paid <- status == "paid"
  if (any(is_paid)) {
    paid_at[is_paid] <- as.POSIXct(paste0(format(issue_date[is_paid]), " 12:00:00"),
                                   tz = "UTC") + rint(sum(is_paid), 1, 45) * 86400
    paid_at[is_paid] <- pmin(paid_at[is_paid], REF_TIME - 5 * 3600)
  }

  due_date <- issue_date + rpick(n_total, c(0, 14, 30, 45), c(0.1, 0.25, 0.5, 0.15))

  # --- Anomaly: rogue statuses, generated as fully settled paid invoices ----
  if (INJECT_STD) {
    cand <- which(is_paid)
    k <- min(n_scaled(4), length(cand))
    idx <- sample(cand, k)
    status[idx] <- rep(c("PAID_LATE", "complete"), length.out = k)
    record_anomaly("BILLING.INVOICES", inv_ids[idx], "rogue_invoice_status",
                   "normalize to approved status or unknown",
                   "warn_then_pass_after_cleaning")
  }

  settled_status <- status %in% c("paid", "PAID_LATE", "complete")

  updated <- as.POSIXct(paste0(format(issue_date), " 09:00:00"), tz = "UTC")
  updated[settled_status] <- pmax(updated[settled_status], paid_at[settled_status])
  bump <- runif(n_total) < 0.08
  updated[bump] <- pmin(updated[bump] + rint(sum(bump), 5, 60) * 86400,
                        REF_TIME - 4 * 3600)
  updated <- pmin(updated, REF_TIME - 3 * 3600)
  updated <- pmax(updated, as.POSIXct(paste0(format(issue_date), " 09:00:00"), tz = "UTC"))

  # --- Anomaly: 1-3 cent arithmetic discrepancy -----------------------------
  if (INJECT_STD) {
    cand <- which(!settled_status & total > 10000)
    k <- min(n_scaled(3), length(cand))
    idx <- sample(cand, k)
    total[idx] <- total[idx] + sample(1:3, k, replace = TRUE)
    record_anomaly("BILLING.INVOICES", inv_ids[idx], "invoice_arithmetic_discrepancy",
                   "recompute or flag without changing raw record", "warn")
  }

  if (INJECT_BROKEN) {
    bi <- sample(which(!settled_status), 1)
    total[bi] <- -abs(total[bi])
    record_anomaly("BILLING.INVOICES", inv_ids[bi], "negative_total_cents",
                   "nonnegative test fails", "error")
  }

  list(
    inv_ids = inv_ids, inv_no = inv_no, cust_id = cust_id, sub_id = sub_id,
    status = status, issue_date = issue_date, due_date = due_date,
    paid_at = paid_at, subtotal = subtotal, discount = discount, tax = tax,
    total = total, ccy = ccy, updated = updated,
    settled_status = settled_status, lines = invoice_lines
  )
}

inv <- build_invoices_and_lines(sub_h, cust_h)

# -----------------------------------------------------------------------------
# 8. BILLING.PAYMENTS
# -----------------------------------------------------------------------------

build_payments <- function(inv) {
  rows <- list()
  k <- 0L
  n_inv <- length(inv$inv_ids)

  settled_sum <- numeric(n_inv)

  for (i in seq_len(n_inv)) {
    st <- inv$status[i]
    tot <- inv$total[i]

    if (inv$settled_status[i] && tot > 0) {
      # One or two succeeded payments that sum exactly to the total.
      n_pay <- if (runif(1) < 0.90) 1 else 2
      if (n_pay == 1) {
        amts <- tot
      } else {
        first <- cents(tot * runif(1, 0.3, 0.7))
        amts <- c(first, tot - first)
      }
      for (a in amts) {
        if (a <= 0) next
        k <- k + 1L
        pt <- inv$paid_at[i] - rint(1, 0, 3) * 86400
        pt <- max(pt, as.POSIXct(paste0(format(inv$issue_date[i]), " 08:00:00"), tz = "UTC"))
        rows[[k]] <- list(invoice_id = inv$inv_ids[i], cust = inv$cust_id[i],
                          status = "succeeded", amount = a, ccy = inv$ccy[i],
                          paid_at = pt)
        settled_sum[i] <- settled_sum[i] + a
      }
    } else if (st == "open" && tot > 0 && runif(1) < 0.18) {
      # Partial payment against an open invoice.
      a <- cents(tot * runif(1, 0.2, 0.7))
      if (a > 0) {
        k <- k + 1L
        pt <- as.POSIXct(paste0(format(inv$issue_date[i]), " 10:00:00"), tz = "UTC") +
          rint(1, 2, 40) * 86400
        pt <- min(pt, REF_TIME - 6 * 3600)
        rows[[k]] <- list(invoice_id = inv$inv_ids[i], cust = inv$cust_id[i],
                          status = "succeeded", amount = a, ccy = inv$ccy[i],
                          paid_at = pt)
        settled_sum[i] <- settled_sum[i] + a
      }
    }

    # Failed and pending attempts.
    if (tot > 0 && runif(1) < 0.05) {
      k <- k + 1L
      rows[[k]] <- list(invoice_id = inv$inv_ids[i], cust = inv$cust_id[i],
                        status = rpick(1, c("failed", "pending"), c(0.75, 0.25)),
                        amount = tot, ccy = inv$ccy[i],
                        paid_at = as.POSIXct(NA, tz = "UTC"))
    }
  }

  # --- Anomaly: payments against nonexistent invoices -----------------------
  orphan_ids <- character(0)
  n_orphan <- if (INJECT_STD) n_scaled(3) else 0
  if (INJECT_BROKEN) n_orphan <- n_orphan + 20
  if (n_orphan > 0) {
    for (j in seq_len(n_orphan)) {
      k <- k + 1L
      rows[[k]] <- list(invoice_id = sprintf("inv_9%05d", 90000 + j),
                        cust = sample(inv$cust_id, 1),
                        status = "succeeded",
                        amount = cents(rint(1, 10000, 500000)),
                        ccy = sample(CURRENCIES, 1),
                        paid_at = rtime(1, AS_OF - 300, AS_OF - 2))
    }
  }

  ids <- id_str("pay", seq_len(k))
  if (n_orphan > 0) {
    orphan_ids <- ids[(k - n_orphan + 1):k]
    record_anomaly("BILLING.PAYMENTS", orphan_ids, "payment_orphan_invoice_id",
                   "retain as unmatched payment, store relationship failures",
                   if (INJECT_BROKEN) "error" else "warn")
  }

  pay_status <- vapply(rows, function(r) r$status, character(1))
  paid_at <- as.POSIXct(vapply(rows, function(r) as.numeric(r$paid_at), numeric(1)),
                        origin = "1970-01-01", tz = "UTC")
  amount <- vapply(rows, function(r) r$amount, numeric(1))

  updated <- paid_at
  na_upd <- is.na(updated)
  if (any(na_upd)) updated[na_upd] <- rtime(sum(na_upd), AS_OF - 120, AS_OF)
  updated <- pmin(updated, REF_TIME - 3 * 3600)

  lat <- loaded_at_for(updated, "BILLING")
  lat <- pin_max_loaded_at(lat, "BILLING")

  df <- data.frame(
    payment_id          = ids,
    invoice_id          = vapply(rows, function(r) r$invoice_id, character(1)),
    billing_customer_id = vapply(rows, function(r) r$cust, character(1)),
    status              = pay_status,
    amount_cents        = cents(amount),
    currency            = vapply(rows, function(r) r$ccy, character(1)),
    paid_at             = ts_z(paid_at),
    payment_method      = rpick(k, c("card", "bank_transfer", "ach", "wire"),
                                c(0.55, 0.2, 0.15, 0.10)),
    processor_reference = sprintf("PR-%08d", 10000000 + seq_len(k)),
    updated_at          = ts_z(updated),
    `_loaded_at`        = ts_z(lat),
    check.names         = FALSE
  )

  attr(df, "settled") <- settled_sum
  attr(df, "helper") <- data.frame(
    payment_id = ids,
    invoice_id = df$invoice_id,
    status     = pay_status,
    amount     = cents(amount),
    currency   = df$currency,
    paid_at    = paid_at,
    stringsAsFactors = FALSE
  )
  df
}

payments <- build_payments(inv)
settled <- attr(payments, "settled")
pay_h <- attr(payments, "helper")

# Amount due follows from succeeded payments only; refunds are excluded by design.
amount_due <- ifelse(inv$settled_status | inv$status == "void", 0L,
                     pmax(0L, pmin(inv$total, cents(inv$total - settled))))
amount_due[inv$total < 0] <- 0L

# -----------------------------------------------------------------------------
# 9. BILLING.REFUNDS
# -----------------------------------------------------------------------------

build_refunds <- function(pay_h, inv) {
  n <- n_scaled(120)
  cand <- which(pay_h$status == "succeeded" &
                  pay_h$invoice_id %in% inv$inv_ids &
                  pay_h$amount > 1000)
  if (length(cand) == 0) stop("No candidate payments for refunds")
  idx <- sample(cand, min(n, length(cand)))
  m <- length(idx)

  ids <- id_str("ref", seq_len(m))
  amt <- cents(pay_h$amount[idx] * runif(m, 0.15, 1.0))
  amt <- pmin(amt, pay_h$amount[idx])
  amt <- pmax(amt, 1L)

  status <- rpick(m, c("succeeded", "pending", "failed"), c(0.86, 0.09, 0.05))
  refunded_at <- rep(as.POSIXct(NA, tz = "UTC"), m)
  ok <- status == "succeeded"
  if (any(ok)) {
    refunded_at[ok] <- pay_h$paid_at[idx][ok] + rint(sum(ok), 1, 60) * 86400
    refunded_at[ok] <- pmin(refunded_at[ok], REF_TIME - 5 * 3600)
    refunded_at[ok] <- pmax(refunded_at[ok], pay_h$paid_at[idx][ok] + 3600)
  }

  if (INJECT_BROKEN) {
    bi <- 1
    amt[bi] <- pay_h$amount[idx][bi] + 50000L
    record_anomaly("BILLING.REFUNDS", ids[bi], "refund_exceeds_payment",
                   "refund amount test fails", "error")
  }

  updated <- refunded_at
  na_upd <- is.na(updated)
  if (any(na_upd)) {
    updated[na_upd] <- pay_h$paid_at[idx][na_upd] + rint(sum(na_upd), 1, 30) * 86400
  }
  updated <- pmin(updated, REF_TIME - 3 * 3600)

  lat <- loaded_at_for(updated, "BILLING")
  lat <- pin_max_loaded_at(lat, "BILLING")

  df <- data.frame(
    refund_id    = ids,
    payment_id   = pay_h$payment_id[idx],
    invoice_id   = pay_h$invoice_id[idx],
    amount_cents = cents(amt),
    currency     = pay_h$currency[idx],
    reason       = rpick(m, c("customer_request", "duplicate", "fraud",
                              "service_issue", "other"),
                         c(0.45, 0.15, 0.08, 0.25, 0.07)),
    status       = status,
    refunded_at  = ts_z(refunded_at),
    updated_at   = ts_z(updated),
    `_loaded_at` = ts_z(lat),
    check.names  = FALSE
  )
  df
}

refunds <- build_refunds(pay_h, inv)

# -----------------------------------------------------------------------------
# 10. PRODUCT.EVENTS
# -----------------------------------------------------------------------------

build_events <- function(acct_h, contacts, cust_h) {
  n <- n_scaled(25000)
  ids <- id_str("evt", seq_len(n))

  ev <- rpick(n, EVENT_NAMES, c(0.22, 0.30, 0.18, 0.08, 0.05, 0.12, 0.05))

  # Activity concentrates on accounts that became customers.
  active_accts <- acct_h$account_id[!acct_h$is_deleted]
  w <- runif(length(active_accts))^2 + 0.05
  acct <- sample(active_accts, n, replace = TRUE, prob = w / sum(w))

  anon <- runif(n) < 0.15
  acct[anon] <- NA_character_

  cont <- rep(NA_character_, n)
  has_contact <- !anon & runif(n) < 0.8
  if (any(has_contact)) {
    pool <- contacts[, c("contact_id", "account_id")]
    m <- match(acct[has_contact], pool$account_id)
    cont[has_contact] <- pool$contact_id[m]
  }
  anonymous_id <- ifelse(is.na(acct) & is.na(cont),
                         sprintf("anon_%08d", rint(n, 1, 9999999)), NA_character_)

  session <- sprintf("sess_%09d", rint(n, 1, 999999999))
  session[ev == "api_call"] <- NA_character_

  # Weekday-weighted event times.
  day_offsets <- rint(n, 0, cfg$history_days)
  dates <- AS_OF - day_offsets
  dow <- as.POSIXlt(dates)$wday
  drop_weekend <- (dow %in% c(0, 6)) & (runif(n) < 0.6)
  dates[drop_weekend] <- dates[drop_weekend] - 2

  evt_time <- as.POSIXct(paste0(format(dates), " 00:00:00"), tz = "UTC") +
    rint(n, 0, 86399)
  evt_time <- pmin(evt_time, REF_TIME - 2 * 3600)

  # Late arrival.
  lag_s <- rint(n, 1, 600)
  late1 <- runif(n) < 0.05
  lag_s[late1] <- rint(sum(late1), 86400, 172800)
  late2 <- runif(n) < 0.01
  lag_s[late2] <- rint(sum(late2), 2 * 86400, 4 * 86400)
  received <- evt_time + lag_s
  received <- pmin(received, REF_TIME - 1.5 * 3600)
  received <- pmax(received, evt_time + 1)

  if (INJECT_STD) {
    record_anomaly("PRODUCT.EVENTS", ids[late2], "late_arriving_event_2_to_4_days",
                   "included when batch lands; late-arrival metric detects",
                   "expected")
  }

  # Mixed offsets on ~20% of rows. The instant is identical; only the rendering
  # differs, which is exactly what staging has to normalize.
  offs <- rep(0, n)
  mixed <- runif(n) < 0.20
  offs[mixed] <- rpick(sum(mixed), TZ_OFFSETS[TZ_OFFSETS != 0])
  evt_str <- ifelse(offs == 0, ts_z(evt_time), ts_offset(evt_time, offs))
  if (INJECT_STD) {
    record_anomaly("PRODUCT.EVENTS", ids[mixed], "mixed_timestamp_offset",
                   "normalize to UTC in staging", "pass_after_cleaning")
  }

  # Properties JSON, shaped by event name.
  features <- c("dashboard", "query_builder", "alerts", "sharing", "scheduler")
  pages <- c("/home", "/reports", "/settings", "/billing", "/explore")
  endpoints <- c("/v1/query", "/v1/users", "/v1/exports", "/v1/events")
  agents <- c("Chrome/121", "Safari/17", "Firefox/122", "Edge/120")
  sources <- c("web", "mobile", "api")

  props <- character(n)
  for (i in seq_len(n)) {
    p <- switch(ev[i],
      login            = list(source = sample(sources, 1), user_agent = sample(agents, 1)),
      page_view        = list(page_path = sample(pages, 1), user_agent = sample(agents, 1)),
      feature_used     = list(feature_name = sample(features, 1), source = sample(sources, 1)),
      report_created   = list(report_type = sample(c("table", "chart", "pivot"), 1)),
      export_completed = list(export_format = sample(c("csv", "xlsx", "pdf"), 1),
                              row_count = rint(1, 10, 50000)),
      api_call         = list(api_endpoint = sample(endpoints, 1),
                              response_time_ms = rint(1, 20, 2500)),
      invite_sent      = list(source = sample(sources, 1))
    )
    props[i] <- as.character(jsonlite::toJSON(p, auto_unbox = TRUE))
  }

  if (INJECT_BROKEN) {
    bi <- sample(seq_len(n), 1)
    props[bi] <- '{"feature_name": "dashboard", "source":}'
    record_anomaly("PRODUCT.EVENTS", ids[bi], "malformed_json_properties",
                   "TRY_PARSE_JSON returns null; staging flags", "error")

    bi2 <- sample(setdiff(seq_len(n), bi), 1)
    evt_time[bi2] <- REF_TIME + 7 * 86400
    evt_str[bi2] <- ts_z(evt_time[bi2])
    received[bi2] <- evt_time[bi2] + 3600
    record_anomaly("PRODUCT.EVENTS", ids[bi2], "future_event_timestamp",
                   "date sanity test fails", "error")
  }

  lat <- loaded_at_for(received, "PRODUCT")
  lat <- pin_max_loaded_at(lat, "PRODUCT")
  lat <- pmax(lat, received + 1)
  ceiling_t <- REF_TIME - (if (TRUE) 1 else 1) * 3600
  lat <- pmin(lat, pmax(ceiling_t, received + 1))

  data.frame(
    event_id        = ids,
    event_name      = ev,
    account_id      = acct,
    contact_id      = cont,
    anonymous_id    = anonymous_id,
    session_id      = session,
    event_timestamp = evt_str,
    received_at     = ts_z(received),
    properties      = props,
    `_loaded_at`    = ts_z(lat),
    check.names     = FALSE
  )
}

events <- build_events(acct_h, contacts, cust_h)

# -----------------------------------------------------------------------------
# 11. ERP.COST_CENTERS
# -----------------------------------------------------------------------------

build_cost_centers <- function() {
  bu <- c("Sales", "Marketing", "Product", "Engineering", "Finance",
          "Operations", "G&A")
  n <- n_scaled(15)
  ids <- id_str("cc", seq_len(n))
  unit <- rpick(n, bu)
  eff_from <- AS_OF - rint(n, 400, 2000)
  is_active <- runif(n) > 0.13
  eff_to <- as.Date(rep(NA, n), origin = "1970-01-01")
  eff_to[!is_active] <- eff_from[!is_active] + rint(sum(!is_active), 200, 900)
  eff_to[!is_active] <- pmin(eff_to[!is_active], AS_OF)

  lat <- loaded_at_for(as.POSIXct(paste0(format(AS_OF - rint(n, 1, 30)),
                                         " 06:00:00"), tz = "UTC"), "ERP")
  lat <- pin_max_loaded_at(lat, "ERP")

  data.frame(
    cost_center_id   = ids,
    cost_center_name = paste(unit, "-", sprintf("CC%03d", seq_len(n))),
    business_unit    = unit,
    manager_name     = paste(rpick(n, FIRST_NAMES), rpick(n, LAST_NAMES)),
    effective_from   = d_str(eff_from),
    effective_to     = d_str(eff_to),
    is_active        = b_str(is_active),
    `_loaded_at`     = ts_z(lat),
    check.names      = FALSE
  )
}

cost_centers <- build_cost_centers()

# -----------------------------------------------------------------------------
# 12. ERP.GL_ENTRIES
# -----------------------------------------------------------------------------

build_gl_entries <- function(cost_centers, inv) {
  target <- n_scaled(6000)
  n_inv_journals <- as.integer(round(target * 0.6 / 2))
  n_exp_journals <- as.integer(round(target * 0.4 / 2))

  rows <- list()
  k <- 0L
  j <- 0L
  imbalanced <- character(0)

  inv_pool <- sample(seq_along(inv$inv_ids),
                     min(n_inv_journals, length(inv$inv_ids)))

  for (ii in inv_pool) {
    j <- j + 1L
    jid <- id_str("jrnl", j)
    amt <- abs(inv$total[ii])
    if (amt <= 0) amt <- 10000L
    pdate <- inv$issue_date[ii]
    cc <- sample(cost_centers$cost_center_id, 1)
    ctime <- as.POSIXct(paste0(format(pdate), " 02:00:00"), tz = "UTC")

    k <- k + 1L
    rows[[k]] <- list(jid = jid, ln = 1L, pdate = pdate, code = "1100", cc = cc,
                      inv = inv$inv_ids[ii], desc = "Accounts receivable",
                      dr = amt, cr = 0L, ccy = inv$ccy[ii], ctime = ctime)
    k <- k + 1L
    rows[[k]] <- list(jid = jid, ln = 2L, pdate = pdate,
                      code = sample(c("4000", "2000", "4010"), 1, prob = c(0.6, 0.3, 0.1)),
                      cc = cc, inv = inv$inv_ids[ii], desc = "Revenue recognition",
                      dr = 0L, cr = amt, ccy = inv$ccy[ii], ctime = ctime)
  }

  for (e in seq_len(n_exp_journals)) {
    j <- j + 1L
    jid <- id_str("jrnl", j)
    amt <- cents(rint(1, 50000, 4000000))
    pdate <- START_DATE + rint(1, 1, cfg$history_days)
    cc <- sample(cost_centers$cost_center_id, 1)
    ctime <- as.POSIXct(paste0(format(pdate), " 03:00:00"), tz = "UTC")
    code <- sample(c("5000", "6100", "6200", "6300"), 1)

    k <- k + 1L
    rows[[k]] <- list(jid = jid, ln = 1L, pdate = pdate, code = code, cc = cc,
                      inv = NA_character_, desc = "Operating expense",
                      dr = amt, cr = 0L, ccy = "USD", ctime = ctime)
    k <- k + 1L
    rows[[k]] <- list(jid = jid, ln = 2L, pdate = pdate, code = "1000", cc = cc,
                      inv = NA_character_, desc = "Cash settlement",
                      dr = 0L, cr = amt, ccy = "USD", ctime = ctime)
  }

  ids <- id_str("gl", seq_len(k))
  jid <- vapply(rows, function(r) r$jid, character(1))
  dr <- vapply(rows, function(r) as.numeric(r$dr), numeric(1))
  cr <- vapply(rows, function(r) as.numeric(r$cr), numeric(1))

  # --- Anomaly: journals out of balance by exactly 1 cent -------------------
  if (INJECT_STD) {
    pick <- sample(unique(jid), n_scaled(2))
    for (p in pick) {
      row_i <- which(jid == p)[2]
      cr[row_i] <- cr[row_i] + 1
    }
    imbalanced <- pick
    record_anomaly("ERP.GL_ENTRIES", pick, "journal_imbalance_one_cent",
                   "singular balance test stores failures", "warn")
  }

  if (INJECT_BROKEN) {
    p <- sample(setdiff(unique(jid), imbalanced), 1)
    row_i <- which(jid == p)[2]
    cr[row_i] <- cr[row_i] + 10000
    imbalanced <- c(imbalanced, p)
    record_anomaly("ERP.GL_ENTRIES", p, "journal_imbalance_material",
                   "balance test fails at error severity", "error")
  }

  ctime <- as.POSIXct(vapply(rows, function(r) as.numeric(r$ctime), numeric(1)),
                      origin = "1970-01-01", tz = "UTC")
  ctime <- pmin(ctime, REF_TIME - 9 * 3600)

  lat <- loaded_at_for(ctime, "ERP")
  lat <- pin_max_loaded_at(lat, "ERP")

  df <- data.frame(
    gl_entry_id    = ids,
    journal_id     = jid,
    line_number    = vapply(rows, function(r) as.integer(r$ln), integer(1)),
    posted_date    = d_str(vapply(rows, function(r) as.numeric(r$pdate), numeric(1))),
    account_code   = vapply(rows, function(r) r$code, character(1)),
    cost_center_id = vapply(rows, function(r) r$cc, character(1)),
    invoice_id     = vapply(rows, function(r) r$inv, character(1)),
    description    = vapply(rows, function(r) r$desc, character(1)),
    debit_cents    = cents(dr),
    credit_cents   = cents(cr),
    currency       = vapply(rows, function(r) r$ccy, character(1)),
    created_at     = ts_z(ctime),
    `_loaded_at`   = ts_z(lat),
    check.names    = FALSE
  )
  attr(df, "imbalanced") <- imbalanced
  df
}

gl_entries <- build_gl_entries(cost_centers, inv)
gl_imbalanced <- attr(gl_entries, "imbalanced")

# -----------------------------------------------------------------------------
# 13. MARKET.FX_RATES
# -----------------------------------------------------------------------------

build_fx_rates <- function() {
  dates <- seq(START_DATE, AS_OF, by = "day")
  base <- c(USD = 1, EUR = 0.92, GBP = 0.79, CAD = 1.35, AUD = 1.52)

  out <- list()
  k <- 0L
  for (ccy in CURRENCIES) {
    if (ccy == "USD") {
      k <- k + 1L
      out[[k]] <- data.frame(rate_date = dates, from_currency = "USD",
                             to_currency = "USD", rate = 1,
                             stringsAsFactors = FALSE)
      next
    }
    # Mean-reverting random walk around the base rate.
    r <- numeric(length(dates))
    r[1] <- base[[ccy]]
    for (i in 2:length(dates)) {
      drift <- 0.004 * (base[[ccy]] - r[i - 1])
      r[i] <- r[i - 1] + drift + rnorm(1, 0, base[[ccy]] * 0.003)
    }
    # Weekends carry Friday forward.
    dow <- as.POSIXlt(dates)$wday
    for (i in seq_along(dates)) {
      if (dow[i] == 6 && i > 1) r[i] <- r[i - 1]
      if (dow[i] == 0 && i > 1) r[i] <- r[i - 1]
    }
    k <- k + 1L
    out[[k]] <- data.frame(rate_date = dates, from_currency = ccy,
                           to_currency = "USD", rate = r,
                           stringsAsFactors = FALSE)
  }
  fx <- do.call(rbind, out)

  # --- Anomaly: missing daily rates -----------------------------------------
  if (INJECT_STD) {
    cand <- which(fx$from_currency != "USD" &
                    fx$rate_date > AS_OF - 200 & fx$rate_date < AS_OF - 10)
    drop <- sample(cand, n_scaled(2))
    record_anomaly("MARKET.FX_RATES",
                   paste0(format(fx$rate_date[drop]), "|",
                          fx$from_currency[drop], "|USD"),
                   "missing_daily_fx_rate",
                   "conversion falls back to most recent prior rate", "warn")
    fx <- fx[-drop, ]
  }

  biz_time <- as.POSIXct(paste0(format(fx$rate_date), " 22:00:00"), tz = "UTC")
  lat <- loaded_at_for(biz_time, "MARKET")
  lat <- pin_max_loaded_at(lat, "MARKET")

  if (INJECT_BROKEN) {
    record_anomaly("MARKET.FX_RATES", "(max _loaded_at)", "market_freshness_error",
                   "source freshness exceeds error_after", "error")
  }

  data.frame(
    rate_date     = d_str(fx$rate_date),
    from_currency = fx$from_currency,
    to_currency   = fx$to_currency,
    rate          = rate8(fx$rate),
    provider      = "DEMO_MARKET_DATA",
    `_loaded_at`  = ts_z(lat),
    check.names   = FALSE
  )
}

fx_rates <- build_fx_rates()

# -----------------------------------------------------------------------------
# Assemble invoices and invoice_lines data frames
# -----------------------------------------------------------------------------

inv_lat <- loaded_at_for(inv$updated, "BILLING")
inv_lat <- pin_max_loaded_at(inv_lat, "BILLING")

invoices <- data.frame(
  invoice_id          = inv$inv_ids,
  invoice_number      = inv$inv_no,
  billing_customer_id = inv$cust_id,
  subscription_id     = inv$sub_id,
  status              = inv$status,
  issue_date          = d_str(inv$issue_date),
  due_date            = d_str(inv$due_date),
  paid_at             = ts_z(inv$paid_at),
  subtotal_cents      = cents(inv$subtotal),
  discount_cents      = cents(inv$discount),
  tax_cents           = cents(inv$tax),
  total_cents         = cents(inv$total),
  amount_due_cents    = cents(amount_due),
  currency            = inv$ccy,
  updated_at          = ts_z(inv$updated),
  `_loaded_at`        = ts_z(inv_lat),
  check.names         = FALSE
)

# --- Broken: duplicate invoice_id with conflicting values -------------------
if (INJECT_BROKEN) {
  src <- sample(seq_len(nrow(invoices)), 2)
  dupes <- invoices[src, ]
  dupes$total_cents <- dupes$total_cents + 777L
  dupes$status <- "open"
  invoices <- rbind(invoices, dupes)
  record_anomaly("BILLING.INVOICES", invoices$invoice_id[src],
                 "duplicate_invoice_id_conflicting_values",
                 "unique test fails", "error")
}

line_updated <- inv$updated[match(inv$lines$invoice_id, inv$inv_ids)]
line_lat <- loaded_at_for(line_updated, "BILLING")
line_lat <- pin_max_loaded_at(line_lat, "BILLING")

invoice_lines <- data.frame(
  inv$lines,
  updated_at   = ts_z(line_updated),
  `_loaded_at` = ts_z(line_lat),
  check.names  = FALSE
)

# -----------------------------------------------------------------------------
# Table registry
# -----------------------------------------------------------------------------

TABLES <- list(
  list(source = "crm",     table = "sales_reps",    df = sales_reps,
       pk = "sales_rep_id",      strategy = "replace_initial_then_merge"),
  list(source = "crm",     table = "accounts",      df = accounts,
       pk = "account_id",        strategy = "replace_initial_then_merge"),
  list(source = "crm",     table = "contacts",      df = contacts,
       pk = "contact_id",        strategy = "replace_initial_then_merge"),
  list(source = "crm",     table = "opportunities", df = opportunities,
       pk = "opportunity_id",    strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "customers",     df = customers,
       pk = "billing_customer_id", strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "subscriptions", df = subscriptions,
       pk = "subscription_id",   strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "invoices",      df = invoices,
       pk = "invoice_id",        strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "invoice_lines", df = invoice_lines,
       pk = "invoice_line_id",   strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "payments",      df = payments,
       pk = "payment_id",        strategy = "replace_initial_then_merge"),
  list(source = "billing", table = "refunds",       df = refunds,
       pk = "refund_id",         strategy = "replace_initial_then_merge"),
  list(source = "product", table = "events",        df = events,
       pk = "event_id",          strategy = "append"),
  list(source = "erp",     table = "cost_centers",  df = cost_centers,
       pk = "cost_center_id",    strategy = "replace_initial_then_merge"),
  list(source = "erp",     table = "gl_entries",    df = gl_entries,
       pk = "gl_entry_id",       strategy = "append"),
  list(source = "market",  table = "fx_rates",      df = fx_rates,
       pk = "rate_date,from_currency,to_currency", strategy = "merge")
)

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

FAILURES <- character(0)
fail <- function(msg) FAILURES <<- c(FAILURES, msg)

cat("\nValidating...\n")

# Primary keys
for (t in TABLES) {
  pk_cols <- strsplit(t$pk, ",")[[1]]
  key <- do.call(paste, c(lapply(pk_cols, function(c) t$df[[c]]), sep = "|"))
  dupes <- sum(duplicated(key))
  nulls <- sum(is.na(t$df[[pk_cols[1]]]))
  if (dupes > 0 && !INJECT_BROKEN) {
    fail(sprintf("%s.%s: %d duplicate primary keys", t$source, t$table, dupes))
  }
  if (nulls > 0 && !INJECT_BROKEN) {
    fail(sprintf("%s.%s: %d null primary keys", t$source, t$table, nulls))
  }
}

# Hard foreign keys
check_fk <- function(child_df, child_col, parent_vals, label, allow = 0) {
  v <- child_df[[child_col]]
  v <- v[!is.na(v)]
  orphans <- sum(!(v %in% parent_vals))
  if (orphans > allow) fail(sprintf("%s: %d orphans (allowed %d)", label, orphans, allow))
  orphans
}

fk_report <- list()
fk_report[["accounts.owner_sales_rep_id"]] <-
  check_fk(accounts, "owner_sales_rep_id", sales_reps$sales_rep_id, "accounts -> sales_reps")
fk_report[["contacts.account_id"]] <-
  check_fk(contacts, "account_id", accounts$account_id, "contacts -> accounts")
fk_report[["opportunities.account_id"]] <-
  check_fk(opportunities, "account_id", accounts$account_id, "opportunities -> accounts")
fk_report[["opportunities.owner_sales_rep_id"]] <-
  check_fk(opportunities, "owner_sales_rep_id", sales_reps$sales_rep_id, "opportunities -> sales_reps")
fk_report[["subscriptions.billing_customer_id"]] <-
  check_fk(subscriptions, "billing_customer_id", customers$billing_customer_id, "subscriptions -> customers")
fk_report[["invoices.billing_customer_id"]] <-
  check_fk(invoices, "billing_customer_id", customers$billing_customer_id, "invoices -> customers")
fk_report[["invoice_lines.invoice_id"]] <-
  check_fk(invoice_lines, "invoice_id", invoices$invoice_id, "invoice_lines -> invoices")
fk_report[["payments.billing_customer_id"]] <-
  check_fk(payments, "billing_customer_id", customers$billing_customer_id, "payments -> customers")
fk_report[["payments.invoice_id"]] <-
  check_fk(payments, "invoice_id", invoices$invoice_id, "payments -> invoices",
           allow = if (INJECT_BROKEN) 23 else if (INJECT_STD) n_scaled(3) else 0)
fk_report[["refunds.payment_id"]] <-
  check_fk(refunds, "payment_id", payments$payment_id, "refunds -> payments")
fk_report[["gl_entries.cost_center_id"]] <-
  check_fk(gl_entries, "cost_center_id", cost_centers$cost_center_id, "gl_entries -> cost_centers")

# Invoice reconciliation
line_sum <- function(type_filter) {
  sel <- invoice_lines[invoice_lines$line_type %in% type_filter, ]
  tapply(sel$line_amount_cents, sel$invoice_id, sum)
}
sub_sum <- line_sum(c("subscription", "services"))
cre_sum <- line_sum("credit")
tax_sum <- line_sum("tax")

recon_bad <- 0L
for (i in seq_len(nrow(invoices))) {
  iid <- invoices$invoice_id[i]
  s <- if (iid %in% names(sub_sum)) as.numeric(sub_sum[[iid]]) else 0
  d <- if (iid %in% names(cre_sum)) abs(as.numeric(cre_sum[[iid]])) else 0
  x <- if (iid %in% names(tax_sum)) as.numeric(tax_sum[[iid]]) else 0
  expected <- s - d + x
  if (abs(invoices$total_cents[i] - expected) > 0) recon_bad <- recon_bad + 1L
}
allow_recon <- if (INJECT_BROKEN) n_scaled(3) + 3 else if (INJECT_STD) n_scaled(3) else 0
if (recon_bad > allow_recon) {
  fail(sprintf("invoice reconciliation: %d mismatches (allowed %d)", recon_bad, allow_recon))
}

# Amount due: bounds, then an independent recomputation of the full formula.
# The bounds check alone would pass on a value that is in range but wrong, so
# the formula is re-derived here from the payments table rather than reusing the
# settled vector the generator built.
ad_bad <- sum(invoices$amount_due_cents < 0 |
                (invoices$amount_due_cents > invoices$total_cents &
                   invoices$total_cents >= 0))
if (ad_bad > 0 && !INJECT_BROKEN) fail(sprintf("amount_due out of bounds: %d rows", ad_bad))

succeeded <- payments[payments$status == "succeeded", ]
settled_by_inv <- tapply(succeeded$amount_cents, succeeded$invoice_id, sum)

settled_statuses <- c("paid", "PAID_LATE", "complete")
formula_bad <- 0L
settle_rule_bad <- 0L
for (i in seq_len(nrow(invoices))) {
  iid <- invoices$invoice_id[i]
  tot <- invoices$total_cents[i]
  st  <- invoices$status[i]
  s <- if (!is.na(iid) && iid %in% names(settled_by_inv)) {
    as.numeric(settled_by_inv[[iid]])
  } else 0

  expected <- if (st %in% settled_statuses || st == "void") {
    0
  } else {
    max(0, min(tot, tot - s))
  }
  if (tot < 0) expected <- 0

  if (invoices$amount_due_cents[i] != expected) formula_bad <- formula_bad + 1L

  # A settled status is only legitimate when payments cover the total exactly.
  if (st %in% settled_statuses && tot > 0 && s != tot) {
    settle_rule_bad <- settle_rule_bad + 1L
  }
}
allow_ad <- if (INJECT_BROKEN) 2 else 0   # broken mode appends conflicting dupes
if (formula_bad > allow_ad) {
  fail(sprintf("amount_due formula mismatch: %d rows (allowed %d)",
               formula_bad, allow_ad))
}
if (settle_rule_bad > allow_ad) {
  fail(sprintf("settled-status invoices not exactly covered by payments: %d rows",
               settle_rule_bad))
}

# Refunds vs payments
ref_bad <- 0L
pay_amt <- setNames(payments$amount_cents, payments$payment_id)
for (i in seq_len(nrow(refunds))) {
  p <- pay_amt[[refunds$payment_id[i]]]
  if (!is.null(p) && refunds$amount_cents[i] > p) ref_bad <- ref_bad + 1L
}
if (ref_bad > (if (INJECT_BROKEN) 1 else 0)) {
  fail(sprintf("refunds exceeding payment: %d", ref_bad))
}

# Journal balance
bal <- aggregate(cbind(debit_cents, credit_cents) ~ journal_id + currency,
                 data = gl_entries, FUN = sum)
unbalanced <- bal$journal_id[bal$debit_cents != bal$credit_cents]
allow_unbal <- length(gl_imbalanced)
if (length(unbalanced) > allow_unbal) {
  fail(sprintf("unbalanced journals: %d (allowed %d)", length(unbalanced), allow_unbal))
}

# JSON validity
json_bad <- sum(!vapply(events$properties, jsonlite::validate, logical(1), USE.NAMES = FALSE))
allow_json <- if (INJECT_BROKEN) 1 else 0
if (json_bad != allow_json) {
  fail(sprintf("invalid JSON in properties: %d (expected %d)", json_bad, allow_json))
}

# Currency domain
allowed_ccy <- c(CURRENCIES, if (INJECT_BROKEN) "XYZ" else character(0))
for (t in TABLES) {
  for (col in intersect(c("currency", "account_currency", "from_currency", "to_currency"),
                        names(t$df))) {
    v <- t$df[[col]][!is.na(t$df[[col]])]
    bad <- setdiff(unique(v), allowed_ccy)
    if (length(bad) > 0) {
      fail(sprintf("%s.%s: currency outside domain: %s",
                   t$table, col, paste(bad, collapse = ", ")))
    }
  }
}

# _loaded_at ordering
check_order <- function(df, later_col, earlier_col, label) {
  if (!all(c(later_col, earlier_col) %in% names(df))) return(invisible(NULL))
  a <- as.POSIXct(sub("Z$", "", df[[later_col]]), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  b <- as.POSIXct(sub("Z$", "", df[[earlier_col]]), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  ok <- is.na(a) | is.na(b) | a >= b
  n_bad <- sum(!ok)
  if (n_bad > 0) fail(sprintf("%s: %d rows where %s < %s", label, n_bad, later_col, earlier_col))
}
check_order(accounts, "_loaded_at", "updated_at", "accounts")
check_order(contacts, "_loaded_at", "updated_at", "contacts")
check_order(opportunities, "_loaded_at", "updated_at", "opportunities")
check_order(customers, "_loaded_at", "updated_at", "customers")
check_order(subscriptions, "_loaded_at", "updated_at", "subscriptions")
check_order(invoices, "_loaded_at", "updated_at", "invoices")
check_order(invoice_lines, "_loaded_at", "updated_at", "invoice_lines")
check_order(payments, "_loaded_at", "updated_at", "payments")
check_order(refunds, "_loaded_at", "updated_at", "refunds")
check_order(events, "_loaded_at", "received_at", "events")
check_order(gl_entries, "_loaded_at", "created_at", "gl_entries")

# Banned literal strings
for (t in TABLES) {
  for (col in names(t$df)) {
    v <- t$df[[col]]
    if (is.character(v)) {
      bad <- sum(!is.na(v) & v %in% c("NA", "NULL", "NaN"))
      if (bad > 0) {
        fail(sprintf("%s.%s column %s: %d literal NA/NULL/NaN strings",
                     t$source, t$table, col, bad))
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Write output
# -----------------------------------------------------------------------------

dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$manifest_dir, recursive = TRUE, showWarnings = FALSE)

manifest_rows <- list()
written <- character(0)

for (t in TABLES) {
  d <- file.path(cfg$output_dir, t$source)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  p <- file.path(d, paste0(t$table, ".csv"))
  readr::write_csv(t$df, p, na = "")
  written <- c(written, p)
  manifest_rows[[length(manifest_rows) + 1]] <- data.frame(
    source                 = toupper(t$source),
    table_name             = toupper(t$table),
    row_count              = nrow(t$df),
    intended_load_strategy = t$strategy,
    primary_key            = t$pk,
    file_path              = p,
    scenario               = SCENARIO,
    seed                   = cfg$seed,
    scale                  = SCALE,
    as_of_date             = format(AS_OF),
    generated_at           = GENERATED_AT,
    r_version              = R.version.string,
    stringsAsFactors       = FALSE
  )
}

manifest <- do.call(rbind, manifest_rows)
readr::write_csv(manifest, file.path(cfg$manifest_dir, "manifest.csv"), na = "")

if (length(ANOMALIES) > 0) {
  anom <- do.call(rbind, ANOMALIES)
  anom$scenario     <- SCENARIO
  anom$seed         <- cfg$seed
  anom$scale        <- SCALE
  anom$as_of_date   <- format(AS_OF)
  anom$generated_at <- GENERATED_AT
  anom$r_version    <- R.version.string
} else {
  anom <- data.frame(table_name = character(0), technical_key = character(0),
                     anomaly_type = character(0), expected_handling = character(0),
                     expected_severity = character(0), scenario = character(0),
                     seed = numeric(0), scale = numeric(0), as_of_date = character(0),
                     generated_at = character(0), r_version = character(0))
}
readr::write_csv(anom, file.path(cfg$manifest_dir, "anomaly_manifest.csv"), na = "")

# Verify what landed on disk matches the manifest.
for (i in seq_len(nrow(manifest))) {
  actual <- nrow(readr::read_csv(manifest$file_path[i], show_col_types = FALSE,
                                 progress = FALSE))
  if (actual != manifest$row_count[i]) {
    fail(sprintf("row count mismatch for %s: manifest %d, file %d",
                 manifest$file_path[i], manifest$row_count[i], actual))
  }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

cat("\n================ GENERATION SUMMARY ================\n")
cat(sprintf("scenario     : %s\n", SCENARIO))
cat(sprintf("seed         : %s\n", format(cfg$seed)))
cat(sprintf("scale        : %s\n", format(SCALE)))
cat(sprintf("as_of_date   : %s\n", format(AS_OF)))
cat(sprintf("history_days : %d\n", cfg$history_days))
cat(sprintf("generated_at : %s\n", GENERATED_AT))
cat(sprintf("r_version    : %s\n", R.version.string))

cat("\n-- Row counts --\n")
for (i in seq_len(nrow(manifest))) {
  cat(sprintf("  %-10s %-16s %7d\n", manifest$source[i], manifest$table_name[i],
              manifest$row_count[i]))
}

cat("\n-- Timestamp ranges --\n")
ts_range <- function(df, col) {
  v <- df[[col]]
  v <- v[!is.na(v)]
  if (length(v) == 0) return("none")
  paste(min(v), "..", max(v))
}
for (t in TABLES) {
  if ("_loaded_at" %in% names(t$df)) {
    cat(sprintf("  %-16s _loaded_at  %s\n", t$table, ts_range(t$df, "_loaded_at")))
  }
}

cat("\n-- Primary key duplicates --\n")
for (t in TABLES) {
  pk_cols <- strsplit(t$pk, ",")[[1]]
  key <- do.call(paste, c(lapply(pk_cols, function(c) t$df[[c]]), sep = "|"))
  cat(sprintf("  %-16s %d\n", t$table, sum(duplicated(key))))
}

cat("\n-- Foreign key orphans --\n")
for (nm in names(fk_report)) {
  cat(sprintf("  %-36s %d\n", nm, fk_report[[nm]]))
}

cat("\n-- Anomaly counts --\n")
if (nrow(anom) > 0) {
  tt <- table(anom$anomaly_type)
  for (nm in names(tt)) cat(sprintf("  %-42s %d\n", nm, tt[[nm]]))
} else {
  cat("  none (clean scenario)\n")
}

cat("\n-- Seed alignment inventory --\n")
cat("country_variants: ",
    paste(sort(unique(c(accounts$billing_country, customers$billing_country))),
          collapse = " | "), "\n", sep = "")
cat("plan_codes: ", paste(sort(unique(c(subscriptions$plan_code,
                                        invoice_lines$plan_code[!is.na(invoice_lines$plan_code)]))),
                          collapse = " | "), "\n", sep = "")
cat("account_codes: ", paste(sort(unique(gl_entries$account_code)), collapse = " | "),
    "\n", sep = "")

cat("\n-- Files written --\n")
for (p in written) cat("  ", p, "\n", sep = "")
cat("  ", file.path(cfg$manifest_dir, "manifest.csv"), "\n", sep = "")
cat("  ", file.path(cfg$manifest_dir, "anomaly_manifest.csv"), "\n", sep = "")

if (length(FAILURES) > 0) {
  cat("\n!! VALIDATION FAILURES !!\n")
  for (f in FAILURES) cat("  - ", f, "\n", sep = "")
  quit(status = 1)
}

cat("\nAll validations passed.\n")
