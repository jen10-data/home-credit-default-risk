# Home Credit Default Risk: modeling and model card

**Individual project by Jenny Ngo.** This folder contains my modeling analysis for the [Home Credit Default Risk competition](https://www.kaggle.com/competitions/home-credit-default-risk) and a model card written for a lending stakeholder. The outcome is the competition's **payment-difficulty indicator**; it is not a measured loan loss. The proposed use is to support further credit-policy research and manual review, pending validation.

## File index

| Source file | What it covers |
| --- | --- |
| [Modeling notebook](Home_Credit_Modeling_Assignment.qmd) | Applicant-level feature engineering, leakage-aware cross-validation, model and class-balance comparisons, hyperparameter tuning, Kaggle submission, and exports for the model card. |
| [Model card](model_card.qmd) | Business recommendation, cost and threshold assumptions, performance, approximate SHAP explanations, potential adverse-action reasons, group comparisons, and limitations. |
| [Model card stylesheet](model_card.css) | Formatting for the model card HTML. Keep it beside `model_card.qmd`. |

The modeling notebook is self-contained: its R functions are embedded in the QMD. This README does not depend on an additional `R/` directory, `notebooks/modeling.qmd`, or a score-recording script.

## Results at a glance

| Evidence | Reported result | What it means |
| --- | ---: | --- |
| Majority-class baseline AUC | 0.5000 | Accuracy of 0.9193 is misleading with an uncommon positive outcome. |
| Application-only candidate, three-fold CV AUC | 0.7515 | Candidate comparison on a stratified 50,000-applicant sample. |
| Application plus historical aggregates, three-fold CV AUC | **0.7670** | Selected **pre-tuning** feature configuration on the candidate sample. |
| Best tuning-sample CV AUC | 0.7497 | Used to choose hyperparameters on 5,000 applicants; not a final holdout score. |
| Final submission, Kaggle public leaderboard AUC | **0.761350** | Ranking performance on Kaggle's public evaluation subset. |
| Final tuned configuration, pooled out-of-fold AUC | 0.7559 | Reported in the existing model-card render for a 50,000-applicant sample; verify after rerendering the attached sources. |

The selected model is an upsampled gradient-boosted machine using application features and available historical aggregates. Its final fit uses all selected labeled training applications. The notebook fits imputation and encoding within each validation fold and applies class balancing to training folds only. The newly added out-of-fold export fits **fold models with the final selected feature set, class strategy, and tuned parameters**; each exported applicant is scored by a fold model that excluded that applicant. Earlier model selection and tuning used overlapping labeled applicants, so these scores do **not** create an untouched holdout.

The model card's exploratory **60.5% raw-score cutoff** gave **80.5% modeled approvals**, **20.6% flagged-case precision**, and **49.6% flagged-case recall** in its internal assessment sample. Its **$56,637 per 1,000 assessed applications** is a proxy-economics scenario, not measured profit or improvement over the current policy. Upsampling has left the scores poorly calibrated: the cutoff is **not** a 60.5% observed default probability. The model card recommends validation before a lending-policy pilot.

### Notebook-maintained results

The modeling notebook updates the following block when it runs. The “best candidate” AUC here refers to the **application-only model comparison**; the separate historical-feature comparison above reports 0.7670.

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

## Reproduce the analysis

Run commands **inside this folder** (`Home_Credit_Modeling_Assignment/`). The QMDs use relative paths such as `data/raw`, `outputs`, and `models`; putting data only in the repository root's `data/raw` will not satisfy these defaults.

1. Download the competition data from [Kaggle](https://www.kaggle.com/competitions/home-credit-default-risk/data) and place `application_train.csv` and `application_test.csv` in this folder's `data/raw/`. To reproduce the historical-aggregate result, include the supplementary CSVs you used (for example `bureau.csv`, `previous_application.csv`, `installments_payments.csv`, `POS_CASH_balance.csv`, and `credit_card_balance.csv`). The notebook discovers available sources; aggregation of the very large `bureau_balance.csv` is off by default. It may use prepared application files in `data/processed/` when present.
2. Install the R dependencies from the **R console**:

   ```r
   install.packages(c("data.table", "glmnet", "randomForest", "gbm", "knitr"))
   ```

3. From the **terminal**, change into the modeling folder and render the notebook:

   ```bash
   cd Home_Credit_Modeling_Assignment
   quarto render Home_Credit_Modeling_Assignment.qmd --to html
   ```

   Rendering can take considerable time. With the attached updated modeling QMD, it saves `models/final_home_credit_model.rds`, `outputs/submission.csv`, `outputs/model_card_oof.csv` (50,000 labeled applicants), and `outputs/model_card_features.csv` (up to 1,200 in-sample training rows for explanation), along with intermediate outputs. Check that it finishes successfully; the model card reads these files and cannot regenerate the fitted model itself.

4. Keep `model_card.qmd` and `model_card.css` in this folder. Then render:

   ```bash
   quarto render model_card.qmd --to html
   ```

   The resulting `model_card.html` displays narrative, tables, and figures with code hidden. Submit that compiled HTML through the course submission system if requested. The modeling HTML is a separate technical report.

To submit predictions to Kaggle, use the generated `outputs/submission.csv` from **this folder**. The modeling QMD contains an old illustrative command referencing `scripts/record_kaggle_score.R` and `notebooks/modeling.qmd`; those paths do not appear in the files supplied here. The public AUC above is the recorded result, and the notebook can read an optional `config/kaggle_score.yml` with `public_auc`, `submission_name`, and `submission_date` when it exists. Do not rerun that old script command unless you have actually added those files.

## Limits and responsible use

The Kaggle label records payment difficulty, not a loan's lifetime profitability or recoveries. The model-card economics use sourced portfolio and credit-card recovery figures as **illustrative proxies**. Random folds and a public leaderboard score do not measure performance on future applicants. The model uses `CODE_GENDER` and `NAME_EDUCATION_TYPE`, and its modeled approval rates differ across groups; policy use needs feature review, calibration, an independent later-period evaluation, and a full fair-lending assessment. Approximate grouped SHAP contributions explain model associations; any applicant-facing adverse-action reasons require separate validation against the actual decision factors.

**GitHub portfolio:** Commit this README and the individual `.qmd` sources (and `model_card.css`). Keep raw and prepared data, `outputs/`, `models/`, prediction and submission files, cached execution files, and compiled HTML out of Git with `.gitignore`. Local generated artifacts and the submitted HTML can be retained separately. From the repository root, link to this folder's README with `[Modeling and model card](Home_Credit_Modeling_Assignment/README.md)`.
