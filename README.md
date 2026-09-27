# Home Credit Default Risk

This project studies whether application-time information can help rank the risk
of payment difficulty for Home Credit applicants, including applicants with
limited conventional credit histories. The analysis supports a documented
credit-review process; it does not establish causal effects or justify automated
adverse-action decisions.

The project uses the Kaggle
[Home Credit Default Risk](https://www.kaggle.com/competitions/home-credit-default-risk)
application data. Raw data, prepared data, fitted parameters, and model objects
are intentionally excluded from Git.

## Data-preparation script

[`data_preparation.R`](data_preparation.R) is a reusable base-R fit/transform
pipeline for `application_train.csv` and `application_test.csv`. It:

- validates the source schema and preserves one row per `SK_ID_CURR`;
- cleans sentinel values, invalid domains, and undocumented unknown categories;
- converts negative day offsets into interpretable positive-year features;
- creates affordability, household, tenure, external-score, inquiry, document,
  contact, log, interaction, capped, and binned features;
- creates missing-data indicators before median imputation;
- learns medians, cap bounds, quantile-bin edges, rare categories, and allowed
  category levels from training data only;
- stores the fitted recipe as an RDS file and reuses it unchanged on test; and
- checks that train and test have identical predictors in identical order, with
  `TARGET` present only in train.

`SK_ID_CURR` remains in each output so predictions can be joined back to an
application, but it must be excluded from model predictors. Sensitive or proxy
attributes such as age, gender, and family status are retained for subgroup
auditing and should not be used as underwriting predictors without legal and
policy approval.

## How the EDA decisions are implemented

| EDA decision | Implementation in `data_preparation.R` |
|---|---|
| Recode `DAYS_EMPLOYED=365243` and retain its missing mechanism | Replaces the sentinel with `NA`, creates `DAYS_EMPLOYED_SENTINEL_FLAG`, and creates positive `EMPLOYMENT_YEARS`. |
| Treat invalid region ratings as unknown | Maps values outside 1–3 to `NA` and adds an invalid-domain flag. |
| Treat `XNA` and `Unknown` as placeholders | Maps them to the shared `__UNKNOWN__` category before category pooling. |
| Make negative day offsets interpretable | Creates positive `AGE_YEARS`, `EMPLOYMENT_YEARS`, `REGISTRATION_YEARS`, `ID_PUBLISH_YEARS`, and `PHONE_CHANGE_YEARS`. |
| Retain informative missingness | Creates indicators for fields with at least 5% training missingness and named business-relevant fields; indicators are created before imputation. |
| Learn imputation only from training | Stores numeric training medians and applies exactly those values to test. Categories use explicit `__MISSING__`, `__RARE__`, and `__UNKNOWN__` levels. |
| Do not automatically delete extreme monetary observations | Keeps original values, adds log features, and creates sensitivity versions capped at the training 0.5th and 99.5th percentiles. |
| Model nonlinear amount and burden patterns | Learns training-decile edges for age, tenure, log income, credit, credit/income, and annuity/income; frozen edges are reused for test. |
| Retain provisional affordability proxies | Creates annuity/income, credit/income, annuity/credit, credit/goods, income/person, children/family, and employment/age ratios with safe denominators. |
| Test product interactions | Retains contract type and creates `CASH_X_CREDIT_INCOME`. |
| Retain income and employment stability candidates | Creates log income, clean tenure, capped household counts, and training-pooled rare occupation/employer categories. |
| Prioritize external scores with missingness and governance controls | Retains all three scores and their missing flags; creates count, mean, minimum, maximum, standard deviation, and an affordability interaction. |
| Prefer yearly inquiry information while recognizing shared missingness | Retains source fields, adds total inquiries and `BUREAU_INQUIRY_MISSING_FLAG`; later selection can remove redundant short windows. |
| Summarize application completeness/contactability | Creates `DOCUMENT_COUNT` and `CONTACT_COUNT`. |
| Preserve application grain and exclude the identifier from modeling | Asserts unique, non-null `SK_ID_CURR`; retains it only as a join key. |

### EDA decisions not implemented in preparation

- **Supplementary tables:** not processed because the EDA explicitly used only
  `application_train` and `application_test` and concluded that supplementary
  tables were optional and unnecessary for its conclusions.
- **Class imbalance:** stratified resampling, class-aware metrics, calibration,
  and decision thresholds belong in model training/evaluation, not in a
  deterministic preparation script. `TARGET` is not resampled here.
- **Production point-in-time approval:** the EDA could not verify source timing
  for 110 fields. This script cannot replace a field-level lineage review.
- **External-score governance and sensitive-feature authorization:** the script
  preserves the fields for research and auditing, but approval is a policy and
  legal decision rather than a data transformation.
- **Distribution-drift action:** the script freezes training parameters and
  handles unknown categories, but it does not alter test distributions. Contract
  type, `EXT_SOURCE_1`, and credit should be monitored during validation.

## Train/test consistency

`fit_preprocessor()` receives only the training table and stores:

- numeric medians;
- 0.5th/99.5th percentile cap bounds;
- decile bin edges;
- rare category lists and the allowed training category vocabulary;
- the source schema and exact prepared predictor order.

`transform_application()` reuses this frozen recipe for either partition. It
never recomputes a statistic from test data. Test-only categorical values map to
`__UNKNOWN__`; missing values map to the stored training median or the explicit
`__MISSING__` category.

The complete supplied files contain 307,511 training applications and 48,744
test applications. The preparation recipe produces 229 aligned predictor
columns, including `SK_ID_CURR`; train additionally contains `TARGET`.
`validate_prepared_data()` checks and reports:

| Check | Required result |
|---|---:|
| Prepared train dimensions | 307,511 rows × 230 columns, including `TARGET` |
| Prepared test dimensions | 48,744 rows × 229 predictor columns |
| Identical predictor names and order | `TRUE` |
| `TARGET` only in train | `TRUE` |
| Train: one row per non-null `SK_ID_CURR` | `TRUE` |
| Test: one row per non-null `SK_ID_CURR` | `TRUE` |
| Train/test ID overlap | 0 |
| Remaining numeric missing values | 0 in train; 0 in test |
| Remaining categorical missing values | 0 in train; 0 in test |
| Remaining `DAYS_EMPLOYED=365243` values | 0 in train; 0 in test |

The 229 prepared predictor columns include the identifier, leaving 228 candidate
model fields after excluding `SK_ID_CURR`. Final modeling may further exclude
audit-only, redundant, or governance-restricted fields.

## Inputs, outputs, and how to run

The script requires R 4.1 or newer and uses only base R. From the repository
root, place the Kaggle files under `data/raw/`:

```text
data/raw/application_train.csv   # 307,511 rows × 122 columns
data/raw/application_test.csv    # 48,744 rows × 121 columns
```

Run the complete pipeline:

```bash
Rscript data_preparation.R \
  --train data/raw/application_train.csv \
  --test data/raw/application_test.csv \
  --output-dir data/processed
```

The command creates:

| Output | Contents | Dimensions |
|---|---|---:|
| `data/processed/application_train_prepared.csv` | Prepared predictors plus `TARGET` | 307,511 × 230 |
| `data/processed/application_test_prepared.csv` | Prepared test predictors | 48,744 × 229 |
| `data/processed/preparation_parameters.rds` | Training medians, caps, bins, category rules, and schema | One fitted recipe |
| `data/processed/preparation_validation.csv` | Machine-readable integrity and consistency checks | One row per check |

To run every transformation and validation check without writing the two large
prepared CSV files, add `--validate-only`:

```bash
Rscript data_preparation.R \
  --train data/raw/application_train.csv \
  --test data/raw/application_test.csv \
  --output-dir data/processed \
  --validate-only
```

The functions can also be sourced and called from R or Quarto:

```r
source("data_preparation.R")

train <- read.csv(
  "data/raw/application_train.csv",
  check.names = FALSE,
  stringsAsFactors = FALSE,
  na.strings = c("", "NA")
)
test <- read.csv(
  "data/raw/application_test.csv",
  check.names = FALSE,
  stringsAsFactors = FALSE,
  na.strings = c("", "NA")
)

recipe <- fit_preprocessor(train)  # fit on training data only
train_ready <- transform_application(train, recipe, is_train = TRUE)
test_ready <- transform_application(test, recipe, is_train = FALSE)
checks <- validate_prepared_data(train_ready, test_ready)
```

To reuse the fitted recipe in another R session:

```r
save_preprocessor(recipe, "data/processed/preparation_parameters.rds")
recipe <- load_preprocessor("data/processed/preparation_parameters.rds")
```

## Version-control policy

The repository tracks source code, documentation, and notebooks. `.gitignore`
excludes raw data, prepared CSVs, fitted parameter artifacts, model objects, and
large serialized intermediates. Do not force-add generated files.
