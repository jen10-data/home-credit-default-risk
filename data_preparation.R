#!/usr/bin/env Rscript

# Home Credit application data preparation -----------------------------------
# Implements the decisions in home_credit_eda.qmd as reusable base-R functions.
# All fitted values come from application_train and are reused unchanged on test.

UNKNOWN_LEVEL <- "__UNKNOWN__"
MISSING_LEVEL <- "__MISSING__"
RARE_LEVEL <- "__RARE__"

REQUIRED_COLUMNS <- c(
  "SK_ID_CURR", "NAME_CONTRACT_TYPE", "CODE_GENDER", "NAME_FAMILY_STATUS",
  "DAYS_BIRTH", "DAYS_EMPLOYED", "DAYS_REGISTRATION", "DAYS_ID_PUBLISH",
  "DAYS_LAST_PHONE_CHANGE", "AMT_INCOME_TOTAL", "AMT_CREDIT", "AMT_ANNUITY",
  "AMT_GOODS_PRICE", "CNT_CHILDREN", "CNT_FAM_MEMBERS",
  "REGION_RATING_CLIENT", "REGION_RATING_CLIENT_W_CITY", "EXT_SOURCE_1",
  "EXT_SOURCE_2", "EXT_SOURCE_3", "AMT_REQ_CREDIT_BUREAU_YEAR"
)
INQUIRY_COLUMNS <- paste0(
  "AMT_REQ_CREDIT_BUREAU_", c("HOUR", "DAY", "WEEK", "MON", "QRT", "YEAR")
)
CAP_COLUMNS <- c(
  "AMT_INCOME_TOTAL", "AMT_CREDIT", "AMT_ANNUITY", "AMT_GOODS_PRICE",
  "CNT_CHILDREN", "CNT_FAM_MEMBERS"
)
BIN_COLUMNS <- c(
  "AGE_YEARS", "EMPLOYMENT_YEARS", "LOG_INCOME", "AMT_CREDIT",
  "CREDIT_INCOME_RATIO", "ANNUITY_INCOME_RATIO"
)
# EDA decision: informative missingness requires flags for high-missingness and
# business-relevant fields before any imputation is performed.
BUSINESS_MISSING_COLUMNS <- c(
  "AMT_ANNUITY", "AMT_GOODS_PRICE", "DAYS_EMPLOYED", "OCCUPATION_TYPE",
  "ORGANIZATION_TYPE", "OWN_CAR_AGE", "EXT_SOURCE_1", "EXT_SOURCE_2",
  "EXT_SOURCE_3", "AMT_REQ_CREDIT_BUREAU_YEAR"
)


# Validate the source application schema before transformation.
validate_input_schema <- function(data, require_target) {
  missing_columns <- setdiff(REQUIRED_COLUMNS, names(data))
  if (length(missing_columns) > 0) {
    stop(
      "Input is missing required columns: ",
      paste(missing_columns, collapse = ", "), call. = FALSE
    )
  }
  if (require_target && !"TARGET" %in% names(data)) {
    stop("Training data must contain TARGET.", call. = FALSE)
  }
  if (!require_target && "TARGET" %in% names(data)) {
    stop("Test data must not contain TARGET.", call. = FALSE)
  }
  invisible(TRUE)
}


# Divide only when the denominator is finite and strictly positive.
safe_divide <- function(numerator, denominator) {
  numerator <- as.numeric(numerator)
  denominator <- as.numeric(denominator)
  valid <- !is.na(numerator) & is.finite(numerator) &
    !is.na(denominator) & is.finite(denominator) & denominator > 0
  result <- rep(NA_real_, length(numerator))
  result[valid] <- numerator[valid] / denominator[valid]
  result
}


# Apply deterministic cleaning and row-level feature engineering.
# No population statistic is learned here, so this is safe for train or test.
clean_and_engineer_base <- function(data) {
  validate_input_schema(data, require_target = "TARGET" %in% names(data))
  result <- data

  # EDA decision — 365243 is an employment sentinel, not a duration. Recode it
  # to NA and retain a flag because the missing mechanism may be predictive.
  employment_sentinel <- !is.na(result$DAYS_EMPLOYED) &
    result$DAYS_EMPLOYED == 365243
  result$DAYS_EMPLOYED_SENTINEL_FLAG <- as.integer(employment_sentinel)
  result$DAYS_EMPLOYED[employment_sentinel] <- NA_real_

  # EDA decision — documented region-rating domains are 1, 2, and 3. Invalid
  # values become NA with an audit flag (the EDA found -1 in test).
  for (column in c("REGION_RATING_CLIENT", "REGION_RATING_CLIENT_W_CITY")) {
    invalid <- !is.na(result[[column]]) & !(result[[column]] %in% 1:3)
    result[[paste0(column, "_INVALID_FLAG")]] <- as.integer(invalid)
    result[[column]][invalid] <- NA_real_
  }

  # EDA decision — XNA and Unknown are placeholders, not substantive levels.
  character_columns <- names(result)[vapply(result, is.character, logical(1))]
  for (column in character_columns) {
    replace_value <- !is.na(result[[column]]) &
      result[[column]] %in% c("XNA", "Unknown")
    result[[column]][replace_value] <- UNKNOWN_LEVEL
  }

  # EDA decision — express negative day offsets as positive, interpretable years.
  result$AGE_YEARS <- -result$DAYS_BIRTH / 365.25
  result$EMPLOYMENT_YEARS <- -result$DAYS_EMPLOYED / 365.25
  result$REGISTRATION_YEARS <- -result$DAYS_REGISTRATION / 365.25
  result$ID_PUBLISH_YEARS <- -result$DAYS_ID_PUBLISH / 365.25
  result$PHONE_CHANGE_YEARS <- -result$DAYS_LAST_PHONE_CHANGE / 365.25

  # EDA decision — affordability relationships were curved, not linear. Retain
  # provisional ratios and fit their nonlinear bins from training later.
  result$ANNUITY_INCOME_RATIO <- safe_divide(
    result$AMT_ANNUITY, result$AMT_INCOME_TOTAL
  )
  result$CREDIT_INCOME_RATIO <- safe_divide(
    result$AMT_CREDIT, result$AMT_INCOME_TOTAL
  )
  result$ANNUITY_CREDIT_RATIO <- safe_divide(
    result$AMT_ANNUITY, result$AMT_CREDIT
  )
  result$CREDIT_GOODS_RATIO <- safe_divide(
    result$AMT_CREDIT, result$AMT_GOODS_PRICE
  )
  result$INCOME_PER_PERSON <- safe_divide(
    result$AMT_INCOME_TOTAL, result$CNT_FAM_MEMBERS
  )
  result$CHILDREN_FAMILY_RATIO <- safe_divide(
    result$CNT_CHILDREN, result$CNT_FAM_MEMBERS
  )
  result$EMPLOYMENT_AGE_RATIO <- safe_divide(
    result$EMPLOYMENT_YEARS, result$AGE_YEARS
  )

  # EDA decision — do not delete extreme monetary values. Add log1p features;
  # training-derived capped alternatives are created after fitting.
  log_pairs <- list(
    AMT_INCOME_TOTAL = "LOG_INCOME", AMT_CREDIT = "LOG_CREDIT",
    AMT_ANNUITY = "LOG_ANNUITY", AMT_GOODS_PRICE = "LOG_GOODS_PRICE"
  )
  for (source in names(log_pairs)) {
    values <- as.numeric(result[[source]])
    values[!is.na(values) & values < 0] <- NA_real_
    result[[log_pairs[[source]]]] <- log1p(values)
  }

  # EDA decision — external scores were strongest descriptively, but provenance
  # and missingness need governance review. Keep originals and add summaries.
  external <- as.matrix(result[c("EXT_SOURCE_1", "EXT_SOURCE_2", "EXT_SOURCE_3")])
  external_count <- rowSums(!is.na(external))
  external_sum <- rowSums(external, na.rm = TRUE)
  external_mean <- rep(NA_real_, nrow(result))
  has_external <- external_count > 0
  external_mean[has_external] <-
    external_sum[has_external] / external_count[has_external]
  external_min <- do.call(pmin, c(as.data.frame(external), list(na.rm = TRUE)))
  external_max <- do.call(pmax, c(as.data.frame(external), list(na.rm = TRUE)))
  external_min[!is.finite(external_min)] <- NA_real_
  external_max[!is.finite(external_max)] <- NA_real_
  external_sq_sum <- rowSums(external ^ 2, na.rm = TRUE)
  external_std <- rep(NA_real_, nrow(result))
  external_variance <- external_sq_sum[has_external] /
    external_count[has_external] - external_mean[has_external] ^ 2
  external_std[has_external] <- sqrt(pmax(external_variance, 0))
  result$EXT_SOURCE_COUNT <- as.integer(external_count)
  result$EXT_SOURCE_MEAN <- external_mean
  result$EXT_SOURCE_MIN <- external_min
  result$EXT_SOURCE_MAX <- external_max
  result$EXT_SOURCE_STD <- external_std

  # EDA decision — yearly inquiries were strongest while all windows shared
  # missingness. Retain YEAR and add a total plus one missingness indicator.
  available_inquiries <- intersect(INQUIRY_COLUMNS, names(result))
  inquiry_matrix <- as.matrix(result[available_inquiries])
  inquiry_total <- rowSums(inquiry_matrix, na.rm = TRUE)
  inquiry_total[rowSums(!is.na(inquiry_matrix)) == 0] <- NA_real_
  result$BUREAU_INQUIRY_TOTAL <- inquiry_total
  result$BUREAU_INQUIRY_MISSING_FLAG <- as.integer(
    rowSums(is.na(inquiry_matrix)) > 0
  )

  # EDA decision — summarize related document and contactability flags.
  document_columns <- grep("^FLAG_DOCUMENT_", names(result), value = TRUE)
  contact_columns <- intersect(
    c(
      "FLAG_MOBIL", "FLAG_EMP_PHONE", "FLAG_WORK_PHONE",
      "FLAG_CONT_MOBILE", "FLAG_PHONE", "FLAG_EMAIL"
    ), names(result)
  )
  result$DOCUMENT_COUNT <- rowSums(result[document_columns], na.rm = TRUE)
  result$CONTACT_COUNT <- rowSums(result[contact_columns], na.rm = TRUE)

  # EDA decision — contract type has a different observed baseline. Add an
  # interpretable product-by-burden interaction for validation.
  result$CASH_LOAN_FLAG <- as.integer(
    !is.na(result$NAME_CONTRACT_TYPE) &
      result$NAME_CONTRACT_TYPE == "Cash loans"
  )
  result$CASH_X_CREDIT_INCOME <-
    result$CASH_LOAN_FLAG * result$CREDIT_INCOME_RATIO
  result$EXT_MEAN_X_CREDIT_INCOME <-
    result$EXT_SOURCE_MEAN * result$CREDIT_INCOME_RATIO
  result
}


# Learn unique quantile edges from training values only.
quantile_edges <- function(values, groups = 10L) {
  values <- as.numeric(values)
  values <- values[!is.na(values) & is.finite(values)]
  if (length(values) == 0L) return(c(-Inf, Inf))
  edges <- unique(as.numeric(quantile(
    values, probs = seq(0, 1, length.out = groups + 1L),
    na.rm = TRUE, type = 7, names = FALSE
  )))
  if (length(edges) < 2L) return(c(-Inf, Inf))
  edges[1] <- -Inf
  edges[length(edges)] <- Inf
  edges
}


# Add missing flags, capped alternatives, and bins from a fitted recipe.
add_training_derived_features <- function(base, parameters) {
  result <- base
  for (column in parameters$missing_indicator_columns) {
    result[[paste0(column, "_MISSING_FLAG")]] <- as.integer(
      is.na(result[[column]])
    )
  }
  for (column in names(parameters$cap_bounds)) {
    bounds <- parameters$cap_bounds[[column]]
    values <- as.numeric(result[[column]])
    result[[paste0(column, "_CAPPED")]] <- pmin(
      pmax(values, bounds[1]), bounds[2]
    )
  }
  for (column in names(parameters$bin_edges)) {
    edges <- parameters$bin_edges[[column]]
    labels <- sprintf("Q%02d", seq_len(length(edges) - 1L))
    result[[paste0(column, "_BIN")]] <- as.character(cut(
      as.numeric(result[[column]]), breaks = edges, labels = labels,
      include.lowest = TRUE, ordered_result = TRUE
    ))
  }
  result
}


# Fit every data-dependent preparation value using application_train only.
fit_preprocessor <- function(
  train,
  missing_indicator_threshold = 0.05,
  rare_category_threshold = 0.005,
  lower_cap_quantile = 0.005,
  upper_cap_quantile = 0.995,
  bin_count = 10L
) {
  validate_input_schema(train, require_target = TRUE)
  if (anyNA(train$SK_ID_CURR) || anyDuplicated(train$SK_ID_CURR) > 0L) {
    stop("Training SK_ID_CURR must be non-null and unique.", call. = FALSE)
  }
  source_predictors <- setdiff(names(train), "TARGET")
  base <- clean_and_engineer_base(train)

  # EDA decision — create flags using training missingness before imputation.
  predictor_names <- setdiff(names(base), "TARGET")
  missing_rates <- vapply(
    base[predictor_names], function(values) mean(is.na(values)), numeric(1)
  )
  missing_indicator_columns <- sort(unique(c(
    names(missing_rates)[missing_rates >= missing_indicator_threshold],
    intersect(BUSINESS_MISSING_COLUMNS, names(base))
  )))
  missing_indicator_columns <- setdiff(missing_indicator_columns, "SK_ID_CURR")

  # EDA decision — retain extremes but create alternatives capped at training
  # quantiles for sensitivity analysis.
  cap_bounds <- setNames(vector("list", length(CAP_COLUMNS)), CAP_COLUMNS)
  for (column in CAP_COLUMNS) {
    cap_bounds[[column]] <- as.numeric(quantile(
      base[[column]], probs = c(lower_cap_quantile, upper_cap_quantile),
      na.rm = TRUE, type = 7, names = FALSE
    ))
  }

  # EDA decision — create nonlinear bins with training-only decile thresholds.
  bin_edges <- setNames(vector("list", length(BIN_COLUMNS)), BIN_COLUMNS)
  for (column in BIN_COLUMNS) {
    bin_edges[[column]] <- quantile_edges(base[[column]], groups = bin_count)
  }
  staged <- add_training_derived_features(base, list(
    missing_indicator_columns = missing_indicator_columns,
    cap_bounds = cap_bounds, bin_edges = bin_edges
  ))
  predictors <- staged[setdiff(names(staged), "TARGET")]
  categorical_columns <- names(predictors)[vapply(
    predictors,
    function(values) is.character(values) || is.factor(values), logical(1)
  )]
  numeric_columns <- setdiff(
    names(predictors)[vapply(predictors, is.numeric, logical(1))], "SK_ID_CURR"
  )

  # EDA decision — numeric imputation uses robust training medians only.
  medians <- setNames(numeric(length(numeric_columns)), numeric_columns)
  for (column in numeric_columns) {
    median_value <- median(predictors[[column]], na.rm = TRUE)
    if (!is.finite(median_value)) median_value <- 0
    medians[[column]] <- as.numeric(median_value)
  }

  # EDA decision — pool rare employment/household categories from training.
  # Test-only levels later map to the shared UNKNOWN level.
  rare_levels <- setNames(vector("list", length(categorical_columns)),
                          categorical_columns)
  category_levels <- setNames(vector("list", length(categorical_columns)),
                              categorical_columns)
  for (column in categorical_columns) {
    values <- as.character(predictors[[column]])
    values[is.na(values)] <- MISSING_LEVEL
    shares <- prop.table(table(values))
    rare <- names(shares)[as.numeric(shares) < rare_category_threshold]
    rare_levels[[column]] <- sort(rare)
    values[values %in% rare] <- RARE_LEVEL
    category_levels[[column]] <- sort(unique(c(
      values, MISSING_LEVEL, UNKNOWN_LEVEL, RARE_LEVEL
    )))
  }

  list(
    version = "1.0.0", source_predictors = source_predictors,
    missing_indicator_columns = missing_indicator_columns, medians = medians,
    cap_bounds = cap_bounds, bin_edges = bin_edges, rare_levels = rare_levels,
    category_levels = category_levels, output_predictors = names(predictors),
    settings = list(
      missing_indicator_threshold = missing_indicator_threshold,
      rare_category_threshold = rare_category_threshold,
      lower_cap_quantile = lower_cap_quantile,
      upper_cap_quantile = upper_cap_quantile, bin_count = bin_count
    )
  )
}


# Apply one fitted training recipe to an application train or test table.
transform_application <- function(data, parameters, is_train) {
  validate_input_schema(data, require_target = is_train)
  actual_predictors <- setdiff(names(data), "TARGET")
  if (!identical(actual_predictors, parameters$source_predictors)) {
    stop(
      "Source predictor schema or order differs from training. Missing: ",
      paste(setdiff(parameters$source_predictors, actual_predictors), collapse = ", "),
      "; extra: ",
      paste(setdiff(actual_predictors, parameters$source_predictors), collapse = ", "),
      call. = FALSE
    )
  }
  target <- if (is_train) data$TARGET else NULL
  result <- add_training_derived_features(
    clean_and_engineer_base(data), parameters
  )

  # Apply only stored training medians; flags retain original absence.
  for (column in names(parameters$medians)) {
    missing_value <- is.na(result[[column]])
    result[[column]][missing_value] <- parameters$medians[[column]]
  }
  # Apply training-derived pooling and vocabulary to every category.
  for (column in names(parameters$category_levels)) {
    values <- as.character(result[[column]])
    values[is.na(values)] <- MISSING_LEVEL
    values[values %in% parameters$rare_levels[[column]]] <- RARE_LEVEL
    values[!(values %in% parameters$category_levels[[column]])] <- UNKNOWN_LEVEL
    result[[column]] <- values
  }
  result <- result[parameters$output_predictors]
  if (is_train) result$TARGET <- target
  result
}


# Verify rubric-critical grain, schema, and missing-value conditions.
validate_prepared_data <- function(train_prepared, test_prepared) {
  numeric_missing <- function(data) {
    columns <- names(data)[vapply(data, is.numeric, logical(1))]
    sum(vapply(data[columns], function(x) sum(is.na(x)), numeric(1)))
  }
  categorical_missing <- function(data) {
    columns <- names(data)[vapply(
      data, function(x) is.character(x) || is.factor(x), logical(1)
    )]
    sum(vapply(data[columns], function(x) sum(is.na(x)), numeric(1)))
  }
  checks <- list(
    train_rows = nrow(train_prepared), test_rows = nrow(test_prepared),
    train_columns_including_target = ncol(train_prepared),
    test_predictor_columns = ncol(test_prepared),
    identical_predictors_and_order = identical(
      setdiff(names(train_prepared), "TARGET"), names(test_prepared)
    ),
    target_only_in_train = "TARGET" %in% names(train_prepared) &&
      !("TARGET" %in% names(test_prepared)),
    train_one_row_per_SK_ID_CURR = !anyNA(train_prepared$SK_ID_CURR) &&
      anyDuplicated(train_prepared$SK_ID_CURR) == 0L,
    test_one_row_per_SK_ID_CURR = !anyNA(test_prepared$SK_ID_CURR) &&
      anyDuplicated(test_prepared$SK_ID_CURR) == 0L,
    train_test_id_overlap = length(intersect(
      train_prepared$SK_ID_CURR, test_prepared$SK_ID_CURR
    )),
    remaining_numeric_missing_train = numeric_missing(train_prepared),
    remaining_numeric_missing_test = numeric_missing(test_prepared),
    remaining_categorical_missing_train = categorical_missing(train_prepared),
    remaining_categorical_missing_test = categorical_missing(test_prepared),
    employment_sentinel_remaining_train = sum(
      train_prepared$DAYS_EMPLOYED == 365243, na.rm = TRUE
    ),
    employment_sentinel_remaining_test = sum(
      test_prepared$DAYS_EMPLOYED == 365243, na.rm = TRUE
    )
  )
  required_true <- c(
    "identical_predictors_and_order", "target_only_in_train",
    "train_one_row_per_SK_ID_CURR", "test_one_row_per_SK_ID_CURR"
  )
  required_zero <- c(
    "train_test_id_overlap", "remaining_numeric_missing_train",
    "remaining_numeric_missing_test", "remaining_categorical_missing_train",
    "remaining_categorical_missing_test",
    "employment_sentinel_remaining_train",
    "employment_sentinel_remaining_test"
  )
  checks$all_checks_passed <- all(unlist(checks[required_true])) &&
    all(unlist(checks[required_zero]) == 0)
  if (!checks$all_checks_passed) {
    stop("Prepared-data validation failed.", call. = FALSE)
  }
  checks
}


# Save/load the complete training-fitted recipe for later scoring.
save_preprocessor <- function(parameters, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(parameters, path)
  invisible(path)
}
load_preprocessor <- function(path) readRDS(path)


# Write the validation results as a human-readable two-column CSV.
write_validation <- function(checks, path) {
  validation_table <- data.frame(
    check = names(checks),
    value = vapply(checks, as.character, character(1)),
    stringsAsFactors = FALSE
  )
  write.csv(validation_table, path, row.names = FALSE)
  invisible(path)
}


# Read, fit, transform, validate, and optionally write both datasets.
prepare_datasets <- function(
  train_path, test_path, output_dir = "data/processed", write_data = TRUE
) {
  train <- read.csv(
    train_path, check.names = FALSE, stringsAsFactors = FALSE,
    na.strings = c("", "NA")
  )
  test <- read.csv(
    test_path, check.names = FALSE, stringsAsFactors = FALSE,
    na.strings = c("", "NA")
  )
  parameters <- fit_preprocessor(train)
  train_prepared <- transform_application(train, parameters, is_train = TRUE)
  test_prepared <- transform_application(test, parameters, is_train = FALSE)
  validation <- validate_prepared_data(train_prepared, test_prepared)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  save_preprocessor(parameters, file.path(output_dir, "preparation_parameters.rds"))
  write_validation(validation, file.path(output_dir, "preparation_validation.csv"))
  if (write_data) {
    write.csv(
      train_prepared, file.path(output_dir, "application_train_prepared.csv"),
      row.names = FALSE
    )
    write.csv(
      test_prepared, file.path(output_dir, "application_test_prepared.csv"),
      row.names = FALSE
    )
  }
  list(
    train = train_prepared, test = test_prepared,
    parameters = parameters, validation = validation
  )
}


# Parse --name value arguments without adding an R package dependency.
parse_arguments <- function(arguments = commandArgs(trailingOnly = TRUE)) {
  options <- list(
    train = "data/raw/application_train.csv",
    test = "data/raw/application_test.csv",
    output_dir = "data/processed", validate_only = FALSE
  )
  index <- 1L
  while (index <= length(arguments)) {
    argument <- arguments[[index]]
    if (argument == "--validate-only") {
      options$validate_only <- TRUE
      index <- index + 1L
    } else if (argument %in% c("--train", "--test", "--output-dir")) {
      if (index == length(arguments)) stop("Missing value after ", argument)
      key <- gsub("-", "_", sub("^--", "", argument))
      options[[key]] <- arguments[[index + 1L]]
      index <- index + 2L
    } else {
      stop("Unknown command-line argument: ", argument, call. = FALSE)
    }
  }
  options
}


# Run the complete pipeline and print validation results.
main <- function(arguments = commandArgs(trailingOnly = TRUE)) {
  options <- parse_arguments(arguments)
  prepared <- prepare_datasets(
    train_path = options$train, test_path = options$test,
    output_dir = options$output_dir, write_data = !options$validate_only
  )
  print(unlist(prepared$validation))
  invisible(prepared)
}


# Sourcing exposes the functions; Rscript execution runs the pipeline.
if (sys.nframe() == 0L) main()
