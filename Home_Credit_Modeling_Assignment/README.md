# Home Credit Default Risk

This project builds and compares classification models for the Kaggle Home Credit Default Risk competition. The modeling workflow is written in lightweight R, organized as reusable functions, and explained in a literate Quarto notebook.

The competition evaluates the ranking of predicted default probabilities using ROC AUC. The notebook therefore uses stratified three-fold cross-validation and selects models using out-of-sample AUC rather than accuracy.

## Modeling notebook

For a Mac that cannot read a separate `R/` folder, use the self-contained
[`Home_Credit_Modeling_Assignment.qmd`](Home_Credit_Modeling_Assignment.qmd).
All reusable modeling functions are embedded in that notebook, so it does not
call `source()` or require a separate R script.

The modular version remains available as [`notebooks/modeling.qmd`](notebooks/modeling.qmd).
It uses the supporting script in `R/modeling_functions.R`. Both notebook versions perform the same analysis. They:

1. calculates the majority-class accuracy, ROC AUC, and precision-recall AUC;
2. compares a focused logistic regression, elastic-net logistic regression, random forest, and gradient boosting;
3. compares gradient boosting with no sampling, downsampling, and upsampling;
4. uses a stratified 5,000-row sample, three-fold CV, and 20 random hyperparameter combinations to tune the best model family;
5. compares application-only features with available applicant-level historical aggregates;
6. fits the selected workflow on all training rows; and
7. writes `outputs/submission.csv` with default probabilities for Kaggle.

Reusable data, preprocessing, resampling, AUC, model, tuning, importance, and submission functions are in [`R/modeling_functions.R`](R/modeling_functions.R).

The notebook deliberately avoids the packages that are unavailable on the target Mac. It relies only on base R plus:

- `data.table` for efficient CSV input and historical aggregation;
- `glmnet` for elastic-net logistic regression;
- `randomForest` for random forests;
- `gbm` for gradient boosting; and
- `knitr` for notebook tables.

Categorical predictors use training-only frequency encoding, and numeric predictors use training-only median imputation and scaling. The script itself creates stratified folds, calculates AUC, performs class resampling, runs randomized search, and extracts model-native importance.

## Data

Download the data only after accepting the competition rules on the [Kaggle data page](https://www.kaggle.com/competitions/home-credit-default-risk/data). Put the CSV files in `data/raw/`. Raw data are intentionally ignored by Git.

Required files:

- `application_train.csv`
- `application_test.csv`

Optional supplementary files detected by the notebook:

- `bureau.csv`
- `bureau_balance.csv`
- `previous_application.csv`
- `installments_payments.csv`
- `POS_CASH_balance.csv`
- `credit_card_balance.csv`

The notebook also accepts browser duplicate names such as `bureau(1).csv`. If the earlier preparation workflow created prepared application files in `data/processed/`, the notebook uses those before the raw application files.

The three reviewed supplementary files have the following structure:

| Table | Rows | Columns | Grain |
|---|---:|---:|---|
| `bureau.csv` | 1,716,428 | 17 | One external bureau credit |
| `bureau_balance.csv` | 27,299,925 | 3 | One month per external bureau credit |
| `credit_card_balance.csv` | 3,840,312 | 23 | One month per previous Home Credit card |

`bureau.csv` contains 305,811 applicants and has a unique `SK_ID_BUREAU`. `bureau_balance.csv` covers 817,395 bureau credits over months -96 through 0. `credit_card_balance.csv` covers 104,307 previous card contracts and 103,558 applicants over months -96 through -1.

## Run the analysis

From the repository's top-level folder:

Run this once in the Positron R Console:

```r
install.packages(c("data.table", "glmnet", "randomForest", "gbm", "knitr"))
```

Then render from the Positron Terminal:

```bash
quarto render Home_Credit_Modeling_Assignment.qmd
```

The rendered assignment is created as `Home_Credit_Modeling_Assignment.html`. It is ignored by Git because the assignment instructions specify that only code should be committed. Submit the HTML separately through the course submission system.

The notebook defaults to a disclosed 50,000-row stratified sample for candidate cross-validation. Set `candidate_rows: 0` to compare candidates on the complete training set. Hyperparameter tuning defaults to the required 5,000 rows, three folds, and 20 random combinations. The final model is trained on the full selected training data.

`bureau_balance.csv` has more than 27 million rows, so its aggregation is disabled by default for memory-constrained computers. Change `include_bureau_balance: true` in the notebook only when enough memory is available. Other available supplementary tables are still incorporated.

## Model results and selection

The final README values must come from the executed notebook. They cannot be calculated until the required application train/test files are present.

<!-- MODEL_RESULTS_START -->
- Majority-class accuracy: **0.9193**
- Majority-class ROC AUC: **0.5000**
- Best candidate model: **Gradient boosting with upsampling**
- Best three-fold CV ROC AUC: **0.7515**
- Best gradient-boosting class strategy: **upsample**
- Supplementary-feature decision: **Application plus historical aggregate features**
- Final tuned model: **Gradient boosting with upsampling**
- Best tuning-sample ROC AUC: **0.7497**
<!-- MODEL_RESULTS_END -->

The selection rule is fixed in advance: choose the candidate with the largest mean cross-validation ROC AUC, compare that configuration with and without available supplementary features, tune the selected family, and fit the finalized workflow on the complete training set.

## Kaggle submission and score

After rendering, submit the locally generated file:

```bash
kaggle competitions submit \
  -c home-credit-default-risk \
  -f outputs/submission.csv \
  -m "Tuned Home Credit model"
```

Record the public leaderboard score in the notebook and README with:

```bash
Rscript scripts/record_kaggle_score.R 0.00000 "Tuned Home Credit model"
quarto render notebooks/modeling.qmd
```

<!-- KAGGLE_SCORE_START -->
- Public leaderboard AUC: **0.76135**
- Submission: `Home Credit gradient boosting model`
- Date submitted: 2026-10-11
<!-- KAGGLE_SCORE_END -->

## Files committed to GitHub

```text
R/modeling_functions.R
Home_Credit_Modeling_Assignment.qmd
notebooks/modeling.qmd
scripts/install_packages.R
scripts/record_kaggle_score.R
config/kaggle_score.yml
README.md
.gitignore
_quarto.yml
```

Data, prepared outputs, fitted models, resampling objects, submission files, rendered HTML, and Quarto cache files remain local through `.gitignore`.

## Limitations

Cross-validation and a Kaggle public score assess discrimination on historical competition data. They do not establish probability calibration on future applicants, lending-policy impact, fairness across applicant groups, or causal effects of applicant characteristics.

## Model card

[`model_card.qmd`](model_card.qmd) documents the selected Home Credit payment-difficulty model for a lending-policy audience. The rendered `model_card.html` is the assignment deliverable. The report includes an executive summary, the model and its intended use, cross-validation and Kaggle AUC, an exploratory decision threshold, sourced lending-cost assumptions, scenario sensitivity, approximate SHAP explanations for 1,000 sampled applicants, possible adverse-action reasons, group approval rates, and deployment limitations. The rendered report displays results with R code hidden.

The selected model is an upsampled gradient-boosted machine with historical credit aggregates. The modeling notebook reports **0.7670 AUC** for the pre-tuning candidate in three-fold cross-validation and **0.761350 public Kaggle AUC** for the submitted final model. An applicant-level, 50,000-row out-of-fold (OOF) file for the final tuned configuration reports **0.7559 pooled OOF AUC**. On 25,000 OOF applicants reserved for *internal assessment*, the AUC is **0.752**. The threshold chosen on the other 25,000 OOF applicants is a **60.5% raw model score**: on the assessment half, it yields **80.5% modeled approvals**, **20.6% precision** and **49.6% recall** among flagged applicants. Under explicit proxy economics and $1,000 normalized balances, the contribution is **$56,637 per 1,000 assessed applications**. This is an illustrative scenario, **not incremental profit** relative to the current policy.

The raw scores are substantially miscalibrated: in one assessment band, an average score of 64.9% corresponds to a 15.6% observed difficulty rate. The 60.5% score cutoff is therefore **not a 60.5% calibrated default probability** or an approved operating rule. Earlier model selection and tuning used overlapping labeled data, so the OOF assessment is **not an untouched holdout**. The trained model also uses `CODE_GENDER` and `NAME_EDUCATION_TYPE`; the model card recommends further validation, calibration, feature review, and a fair-lending assessment before any lending-policy pilot. The report's SHAP values are approximate grouped permutation contributions computed on an in-sample feature export.

To reproduce the report from the project root, retain the fitted model at `models/final_home_credit_model.rds` and the local input files at `outputs/model_card_oof.csv` and `outputs/model_card_features.csv`, then run:

```bash
quarto render model_card.qmd --to html
```

The Quarto source uses [`model_card.css`](model_card.css) and the already-used R package `gbm`. `fastshap` is optional: the report can compute approximate grouped SHAP contributions with base R. The raw feature sample must come from the modeling workflow. Verify that each OOF prediction was generated by a fold model that excluded that applicant.

Keep data, fitted models, local OOF/feature exports, and Kaggle submission files out of Git; commit the Quarto source, stylesheet and this README section. The generated HTML is for submission to the course unless the repository's policy calls for committing rendered reports.
