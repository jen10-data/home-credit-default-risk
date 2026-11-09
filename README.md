Home Credit payment difficulty | Individual analytics portfolio
Business question: Can application and credit-history data help a lender identify payment difficulty while preserving access for applicants who can repay? I analyzed the Home Credit Default Risk Kaggle data from data audit through model selection and a credit-policy model card. The competition's TARGET measures payment difficulty, not an observed loan loss or a universal definition of default.

The proposed use is decision support for manual review. The current model is not approved for automated credit decisions.
File index
Individual work	What to open
[EDA notebook](home_credit_eda.qmd)	Application grain, missingness, sentinel values, drift, figures and preparation decisions.
[Data-preparation script](data_preparation.R)	A reusable training-fitted cleaning and feature-engineering demonstration.
[Modeling notebook](Home_Credit_Modeling_Assignment/Home_Credit_Modeling_Assignment.qmd)	Cross-validation, class imbalance, model comparison, tuning and Kaggle submission.
[Model card](model_card.qmd)	Business threshold, sourced cost scenario, SHAP, adverse-action mapping, group outcomes and deployment risks.


Project at a glance
Evidence	Result	Interpretation
Labeled applications	307,511	Historical applicants; 8.07% have TARGET = 1.
Application-only candidate, three-fold CV ROC AUC	0.7515	Uses application features on a 50,000-applicant comparison sample.
Application plus history candidate, three-fold CV ROC AUC	0.7670	Better ranking from historical aggregates; pre-tuning candidate.
Tuned model, public Kaggle ROC AUC	0.761350	Separate competition test set; does not measure calibration or profit.
Internal threshold assessment	60.5% raw score	Selected on half of a supplied 50,000-row out-of-fold file; see verification caveat below.


The model comparison included logistic regression, elastic net, random forest, and gradient boosting under several class-balancing strategies. The selected model was a tuned, upsampled gradient-boosted machine with application and historical credit aggregates. I fitted preprocessing within training folds so assessment rows did not determine imputation or encodings.
What changed my modeling choices
- Data audit: DAYS_EMPLOYED = 365243 occurs in 55,374 training applications and is a sentinel rather than plausible employment tenure. Heavy missingness, train/test differences, and application-time availability also require explicit checks.
- Feature evidence: External scores show strong descriptive separation across deciles, but their origin and timing need verification. Historical payment behavior improves ranking and needs careful applicant-level joins.
- Decision tradeoff: In a provisional internal assessment, the 60.5% raw-score cutoff yielded 80.5% modeled approvals, 20.6% precision and 49.6% recall among flagged applicants. These estimates depend on confirming that each out-of-fold prediction came from the final tuned configuration and excluded that applicant during training.
- Deployment gate: Scores are substantially miscalibrated, so the raw cutoff is not a 60.5% probability of default. The model also uses CODE_GENDER and education fields, and modeled approval rates differ by group. It needs feature review, an untouched validation set, calibration, and a fair-lending assessment before a pilot.

Exploratory association in the training data; the chart is not an individual denial reason or evidence of causality.

The data-preparation script is a separate fit/transform exercise. The modeling notebook builds its own application and historical features; this README does not claim the selected GBM was trained on the script's 229-column prepared export.
Business value and limitations
A useful ranking could help credit staff prioritize applications for review and investigate the cost of payment problems alongside the cost of declining applicants who would repay. The model card's $56,637 contribution per 1,000 assessed applications is an illustrative scenario based on proxy loan economics and normalized balances. It is not observed profit, cost savings, or improvement over the existing lending policy.

The source data are historical, earlier model tuning overlapped the out-of-fold assessment population, and there is no independent untouched holdout. External-score definitions and application-time availability remain unverified. I would validate on later applications, calibrate the model, revisit sensitive predictors and explanations, and compare any supervised pilot with the existing policy before claiming business benefit.
Reproduce
Download the competition data from Kaggle to data/raw/ for the root-level EDA notebook. The modeling notebook is inside Home_Credit_Modeling_Assignment/, and its current relative data_dir, outputs_dir, and models_dir settings need to be aligned with the repository paths before rendering. The repository excludes raw data, prepared exports, model objects, prediction files and HTML submissions. Use R and Quarto from the repository root after aligning those paths:
quarto render home_credit_eda.qmd --to html
quarto render Home_Credit_Modeling_Assignment/Home_Credit_Modeling_Assignment.qmd --to html
The EDA notebook uses notebook.css and the checked-in figures/ assets. Modeling additionally uses R packages data.table, glmnet, randomForest, gbm and knitr. The model card requires the saved final model and locally generated outputs/model_card_oof.csv and outputs/model_card_features.csv; the modeling notebook does not automatically export those two files. See the model card's reproduction section before rendering it.

Interview talking points: leakage-controlled folds, the difference between ranking and calibrated probability, what historical joins contributed, and why fair-lending and financial checks matter before using a risk score.
<!-- MODEL_RESULTS_START -->
- Majority-class ROC AUC: 0.5000; accuracy: 0.9193.
- Pre-tuning candidate three-fold CV ROC AUC: 0.7670 on 50,000 applicants.
- Tuning-sample CV ROC AUC: 0.7497 on 5,000 applicants.
<!-- MODEL_RESULTS_END -->
