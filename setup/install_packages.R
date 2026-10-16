#!/usr/bin/env Rscript
# Installs the two packages generate_raw_data.R needs.
# Safe to run repeatedly. Everything else in the generator is base R.

required <- c("readr", "jsonlite")

missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing) > 0) {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All required packages already installed.")
}

for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Failed to install package: ", pkg)
  }
  message(sprintf("  %-10s %s", pkg, as.character(utils::packageVersion(pkg))))
}

message("R version: ", R.version.string)
message("Ready. Run: Rscript setup/generate_raw_data.R")
