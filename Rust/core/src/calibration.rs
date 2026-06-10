use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::{
    GooseError, GooseResult,
    store::{CalibrationRunRecord, CalibrationRunTimes},
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationDataset {
    pub schema: String,
    pub records: Vec<CalibrationRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationRecord {
    pub record_id: String,
    pub captured_at: String,
    #[serde(default)]
    pub session_id: Option<String>,
    pub metric_family: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub prediction: f64,
    pub label: f64,
    pub label_source: String,
    pub label_provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationOptions {
    pub metric_family: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub split_at: String,
    #[serde(default = "default_min_train_rows")]
    pub min_train_rows: usize,
    #[serde(default = "default_min_holdout_rows")]
    pub min_holdout_rows: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    #[serde(default)]
    pub dataset_valid: bool,
    #[serde(default)]
    pub labels_valid: bool,
    #[serde(default)]
    pub split_valid: bool,
    #[serde(default)]
    pub model_fit_ready: bool,
    #[serde(default)]
    pub train_metrics_ready: bool,
    #[serde(default)]
    pub holdout_metrics_ready: bool,
    #[serde(default)]
    pub holdout_improvement_valid: bool,
    #[serde(default)]
    pub calibration_ready: bool,
    pub metric_family: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub split_policy: String,
    pub split_at: String,
    pub train_count: usize,
    pub holdout_count: usize,
    pub train_start: Option<String>,
    pub train_end: Option<String>,
    pub holdout_start: Option<String>,
    pub holdout_end: Option<String>,
    pub model: Option<LinearCalibrationModel>,
    pub uncalibrated_train: Option<CalibrationMetrics>,
    pub calibrated_train: Option<CalibrationMetrics>,
    pub uncalibrated_holdout: Option<CalibrationMetrics>,
    pub calibrated_holdout: Option<CalibrationMetrics>,
    pub holdout_improved: bool,
    pub leakage_checks: LeakageChecks,
    pub holdout_bias_by_label_band: Vec<ScoreBandBias>,
    pub issues: Vec<String>,
    #[serde(default)]
    pub next_actions: Vec<CalibrationNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LinearCalibrationModel {
    pub model_type: String,
    pub slope: f64,
    pub intercept: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationMetrics {
    pub mae: f64,
    pub correlation: Option<f64>,
    pub count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LeakageChecks {
    pub train_rows_before_split: bool,
    pub holdout_rows_at_or_after_split: bool,
    pub no_session_overlap: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ScoreBandBias {
    pub band: String,
    pub count: usize,
    pub mean_error: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationApplicationInput {
    pub metric_family: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub raw_score: f64,
    #[serde(default)]
    pub input_run_id: Option<String>,
    pub score_min: f64,
    pub score_max: f64,
    pub calibration_run: CalibrationRunRecord,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalibrationApplicationReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    #[serde(default)]
    pub input_valid: bool,
    #[serde(default)]
    pub score_range_valid: bool,
    #[serde(default)]
    pub calibration_run_valid: bool,
    #[serde(default)]
    pub model_ready: bool,
    #[serde(default)]
    pub model_applied: bool,
    #[serde(default)]
    pub application_ready: bool,
    pub metric_family: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub raw_score: f64,
    pub calibrated_score: Option<f64>,
    pub score_min: f64,
    pub score_max: f64,
    pub calibration_run_id: String,
    pub applied_model: Option<LinearCalibrationModel>,
    pub output_kind: String,
    pub official_labels_are_labels: bool,
    pub quality_flags: Vec<String>,
    pub provenance: serde_json::Value,
    pub issues: Vec<String>,
    #[serde(default)]
    pub next_actions: Vec<CalibrationNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct CalibrationNextAction {
    pub scope: String,
    pub reason: String,
    pub action: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CalibrationRunParams {
    model: Option<LinearCalibrationModel>,
    #[serde(default)]
    split_policy: Option<String>,
    #[serde(default)]
    split_at: Option<String>,
    #[serde(default)]
    pass: bool,
}

pub fn evaluate_linear_calibration(
    dataset: &CalibrationDataset,
    options: &CalibrationOptions,
) -> CalibrationReport {
    let mut issues = Vec::new();
    if dataset.schema != "goose.calibration-dataset.v1" {
        issues.push(format!("unsupported dataset schema {}", dataset.schema));
    }
    validate_required("metric_family", &options.metric_family, &mut issues);
    validate_required("algorithm_id", &options.algorithm_id, &mut issues);
    validate_required("algorithm_version", &options.algorithm_version, &mut issues);
    validate_required("split_at", &options.split_at, &mut issues);
    let split_at_unix_ms = parse_rfc3339_utc_unix_ms(&options.split_at);
    if !options.split_at.trim().is_empty() && split_at_unix_ms.is_none() {
        issues.push("split_at is not a UTC RFC3339 timestamp".to_string());
    }

    let mut scoped = Vec::new();
    for record in &dataset.records {
        validate_record(record, &mut issues);
        if record.metric_family == options.metric_family
            && record.algorithm_id == options.algorithm_id
            && record.algorithm_version == options.algorithm_version
        {
            scoped.push(record.clone());
        }
    }

    let (train, holdout): (Vec<_>, Vec<_>) = scoped.into_iter().partition(|record| {
        matches!(
            (record_captured_at_unix_ms(record), split_at_unix_ms),
            (Some(captured_ms), Some(split_ms)) if captured_ms < split_ms
        )
    });
    let train_count = train.len();
    let holdout_count = holdout.len();

    if train_count < options.min_train_rows {
        issues.push(format!(
            "train_count {train_count} is below min_train_rows {}",
            options.min_train_rows
        ));
    }
    if holdout_count < options.min_holdout_rows {
        issues.push(format!(
            "holdout_count {holdout_count} is below min_holdout_rows {}",
            options.min_holdout_rows
        ));
    }

    let leakage_checks = leakage_checks(&train, &holdout, split_at_unix_ms);
    if !leakage_checks.train_rows_before_split {
        issues.push("train rows must be before split_at".to_string());
    }
    if !leakage_checks.holdout_rows_at_or_after_split {
        issues.push("holdout rows must be at or after split_at".to_string());
    }
    if !leakage_checks.no_session_overlap {
        issues.push("session_id appears in both train and holdout".to_string());
    }

    let model = if issues.is_empty() {
        fit_linear_model(&train)
            .map_err(|error| issues.push(error.to_string()))
            .ok()
    } else {
        None
    };

    let uncalibrated_train = metrics_for(&train, |record| record.prediction);
    let uncalibrated_holdout = metrics_for(&holdout, |record| record.prediction);
    let calibrated_train = model
        .as_ref()
        .and_then(|model| metrics_for(&train, |record| model.predict(record.prediction)));
    let calibrated_holdout = model
        .as_ref()
        .and_then(|model| metrics_for(&holdout, |record| model.predict(record.prediction)));
    let holdout_improved = match (uncalibrated_holdout.as_ref(), calibrated_holdout.as_ref()) {
        (Some(raw), Some(calibrated)) => calibrated.mae < raw.mae,
        _ => false,
    };

    if model.is_some() && !holdout_improved {
        issues.push("calibrated holdout MAE did not improve".to_string());
    }
    let next_actions = calibration_next_actions(&issues);
    let dataset_valid = !issues.iter().any(|issue| calibration_dataset_issue(issue));
    let labels_valid = !issues.iter().any(|issue| calibration_label_issue(issue));
    let split_valid = train_count >= options.min_train_rows
        && holdout_count >= options.min_holdout_rows
        && leakage_checks.train_rows_before_split
        && leakage_checks.holdout_rows_at_or_after_split
        && leakage_checks.no_session_overlap;
    let model_fit_ready = model.is_some();
    let train_metrics_ready = uncalibrated_train.is_some() && calibrated_train.is_some();
    let holdout_metrics_ready = uncalibrated_holdout.is_some() && calibrated_holdout.is_some();
    let holdout_improvement_valid = holdout_metrics_ready && holdout_improved;
    let calibration_ready = dataset_valid
        && labels_valid
        && split_valid
        && model_fit_ready
        && train_metrics_ready
        && holdout_improvement_valid
        && issues.is_empty();

    CalibrationReport {
        schema: "goose.calibration-report.v1".to_string(),
        generated_by: "goose-calibration-evaluator".to_string(),
        pass: calibration_ready,
        dataset_valid,
        labels_valid,
        split_valid,
        model_fit_ready,
        train_metrics_ready,
        holdout_metrics_ready,
        holdout_improvement_valid,
        calibration_ready,
        metric_family: options.metric_family.clone(),
        algorithm_id: options.algorithm_id.clone(),
        algorithm_version: options.algorithm_version.clone(),
        split_policy: "date_cutoff_train_before_holdout_at_or_after".to_string(),
        split_at: options.split_at.clone(),
        train_count,
        holdout_count,
        train_start: min_time(&train),
        train_end: max_time(&train),
        holdout_start: min_time(&holdout),
        holdout_end: max_time(&holdout),
        model,
        uncalibrated_train,
        calibrated_train,
        uncalibrated_holdout,
        calibrated_holdout,
        holdout_improved,
        leakage_checks,
        holdout_bias_by_label_band: holdout_bias_by_label_band(&holdout),
        issues,
        next_actions,
    }
}

pub fn apply_calibration(input: &CalibrationApplicationInput) -> CalibrationApplicationReport {
    let mut issues = Vec::new();
    let mut quality_flags = Vec::new();

    validate_required("metric_family", &input.metric_family, &mut issues);
    validate_required("algorithm_id", &input.algorithm_id, &mut issues);
    validate_required("algorithm_version", &input.algorithm_version, &mut issues);
    if !input.raw_score.is_finite() {
        issues.push("raw_score must be finite".to_string());
    }
    if !input.score_min.is_finite()
        || !input.score_max.is_finite()
        || input.score_min >= input.score_max
    {
        issues.push("score_min must be finite and less than score_max".to_string());
    }
    if input.calibration_run.algorithm_id != input.algorithm_id
        || input.calibration_run.version != input.algorithm_version
    {
        issues.push(format!(
            "calibration run targets {}@{}, not {}@{}",
            input.calibration_run.algorithm_id,
            input.calibration_run.version,
            input.algorithm_id,
            input.algorithm_version
        ));
    }

    let params =
        match serde_json::from_str::<CalibrationRunParams>(&input.calibration_run.params_json) {
            Ok(params) => Some(params),
            Err(error) => {
                issues.push(format!("calibration params_json invalid: {error}"));
                None
            }
        };
    if let Some(params) = &params {
        if !params.pass {
            issues.push("calibration run did not pass holdout validation".to_string());
        }
        if params.model.is_none() {
            issues.push("calibration run has no model".to_string());
        }
    }

    let applied_model = params.as_ref().and_then(|params| params.model.clone());
    let calibrated_score = if issues.is_empty() {
        let model = applied_model.as_ref().expect("checked model exists");
        let raw_calibrated = model.predict(input.raw_score);
        let clamped = raw_calibrated.clamp(input.score_min, input.score_max);
        if (clamped - raw_calibrated).abs() > f64::EPSILON {
            quality_flags.push("calibrated_score_clamped_to_range".to_string());
        }
        Some(clamped)
    } else {
        None
    };
    let next_actions = calibration_application_next_actions(&issues);
    let input_valid = !issues.iter().any(|issue| {
        issue == "raw_score must be finite"
            || issue == "metric_family is required"
            || issue == "algorithm_id is required"
            || issue == "algorithm_version is required"
    });
    let score_range_valid = !issues
        .iter()
        .any(|issue| issue == "score_min must be finite and less than score_max");
    let calibration_run_valid = !issues.iter().any(|issue| {
        issue.starts_with("calibration run targets ")
            || issue.starts_with("calibration params_json invalid:")
            || issue == "calibration run did not pass holdout validation"
    });
    let model_ready = applied_model.is_some()
        && !issues
            .iter()
            .any(|issue| issue == "calibration run has no model");
    let model_applied = calibrated_score.is_some();
    let application_ready = input_valid
        && score_range_valid
        && calibration_run_valid
        && model_ready
        && model_applied
        && issues.is_empty();

    CalibrationApplicationReport {
        schema: "goose.calibrated-score.v1".to_string(),
        generated_by: "goose-calibration-apply".to_string(),
        pass: application_ready,
        input_valid,
        score_range_valid,
        calibration_run_valid,
        model_ready,
        model_applied,
        application_ready,
        metric_family: input.metric_family.clone(),
        algorithm_id: input.algorithm_id.clone(),
        algorithm_version: input.algorithm_version.clone(),
        raw_score: input.raw_score,
        calibrated_score,
        score_min: input.score_min,
        score_max: input.score_max,
        calibration_run_id: input.calibration_run.calibration_run_id.clone(),
        applied_model,
        output_kind: "goose_calibrated_local_score".to_string(),
        official_labels_are_labels: true,
        quality_flags,
        provenance: json!({
            "input_run_id": input.input_run_id,
            "calibration_run_id": input.calibration_run.calibration_run_id,
            "train_start": input.calibration_run.times.train_start,
            "train_end": input.calibration_run.times.train_end,
            "holdout_start": input.calibration_run.times.holdout_start,
            "holdout_end": input.calibration_run.times.holdout_end,
            "calibration_params": params,
            "label_policy": "user_owned_labels_only",
            "official_labels_are_labels": true
        }),
        issues,
        next_actions,
    }
}

fn calibration_next_actions(issues: &[String]) -> Vec<CalibrationNextAction> {
    dedupe_calibration_next_actions(
        issues
            .iter()
            .map(|issue| {
                let (reason, action) = calibration_issue_action(issue);
                CalibrationNextAction {
                    scope: calibration_issue_scope(issue),
                    reason: reason.to_string(),
                    action: action.to_string(),
                }
            })
            .collect(),
    )
}

fn calibration_application_next_actions(issues: &[String]) -> Vec<CalibrationNextAction> {
    dedupe_calibration_next_actions(
        issues
            .iter()
            .map(|issue| {
                let (reason, action) = calibration_application_issue_action(issue);
                CalibrationNextAction {
                    scope: calibration_application_issue_scope(issue),
                    reason: reason.to_string(),
                    action: action.to_string(),
                }
            })
            .collect(),
    )
}

fn calibration_issue_scope(issue: &str) -> String {
    if issue.starts_with("unsupported dataset schema ") {
        return "dataset.schema".to_string();
    }
    if let Some((field, _)) = issue.split_once(" is required") {
        return field.to_string();
    }
    if let Some((record_id, _)) = issue.split_once(" prediction is not finite") {
        return record_id.to_string();
    }
    if let Some((record_id, _)) = issue.split_once(" label is not finite") {
        return record_id.to_string();
    }
    if let Some((record_id, _)) = issue.split_once(" has unsupported label_source ") {
        return record_id.to_string();
    }
    if let Some((record_id, _)) = issue.split_once(" missing label_provenance") {
        return record_id.to_string();
    }
    if issue == "split_at is not a UTC RFC3339 timestamp" {
        return "split_at".to_string();
    }
    if let Some((record_id, _)) = issue.split_once(" captured_at is not a UTC RFC3339 timestamp") {
        return record_id.to_string();
    }
    if issue.starts_with("train_count ") || issue == "train rows must be before split_at" {
        return "train".to_string();
    }
    if issue.starts_with("holdout_count ") || issue == "holdout rows must be at or after split_at" {
        return "holdout".to_string();
    }
    if issue == "session_id appears in both train and holdout" {
        return "split.session_id".to_string();
    }
    if issue == "training predictions have zero variance" {
        return "train.prediction".to_string();
    }
    if issue == "calibrated holdout MAE did not improve" {
        return "holdout.mae".to_string();
    }
    "calibration".to_string()
}

fn calibration_application_issue_scope(issue: &str) -> String {
    if issue == "raw_score must be finite" {
        "raw_score".to_string()
    } else if issue == "score_min must be finite and less than score_max" {
        "score_range".to_string()
    } else if issue.starts_with("calibration run targets ") {
        "calibration_run".to_string()
    } else if issue.starts_with("calibration params_json invalid:") {
        "calibration_run.params_json".to_string()
    } else if issue == "calibration run did not pass holdout validation" {
        "calibration_run.pass".to_string()
    } else if issue == "calibration run has no model" {
        "calibration_run.model".to_string()
    } else {
        calibration_issue_scope(issue)
    }
}

fn calibration_issue_action(issue: &str) -> (&'static str, &'static str) {
    if issue.starts_with("unsupported dataset schema ") {
        (
            "unsupported_dataset_schema",
            "Convert the labels to goose.calibration-dataset.v1 before evaluating calibration.",
        )
    } else if issue.contains(" is required") {
        (
            "missing_required_field",
            "Fill the missing calibration option or record field before rerunning calibration.",
        )
    } else if issue.contains(" prediction is not finite") || issue.contains(" label is not finite")
    {
        (
            "non_finite_score_value",
            "Replace the non-finite prediction or label with a finite user-owned score value.",
        )
    } else if issue.contains(" has unsupported label_source ") {
        (
            "unsupported_label_source",
            "Use a supported user-owned label source such as manual, passive official capture, user export, or screenshot import.",
        )
    } else if issue.contains(" missing label_provenance") {
        (
            "missing_label_provenance",
            "Attach non-empty provenance JSON that explains how the user-owned label was captured.",
        )
    } else if issue.ends_with(" is not a UTC RFC3339 timestamp") {
        (
            "timestamp_not_utc_rfc3339",
            "Normalize split_at and every captured_at to UTC RFC3339 timestamps with a Z suffix before evaluating calibration.",
        )
    } else if issue.starts_with("train_count ") {
        (
            "insufficient_train_rows",
            "Add more pre-split calibration labels or move split_at only if that preserves a clean train/holdout boundary.",
        )
    } else if issue.starts_with("holdout_count ") {
        (
            "insufficient_holdout_rows",
            "Add post-split holdout labels so calibration can prove generalization before promotion.",
        )
    } else if issue == "train rows must be before split_at"
        || issue == "holdout rows must be at or after split_at"
    {
        (
            "split_boundary_invalid",
            "Move records or adjust split_at so all training rows are before the split and all holdout rows are at or after it.",
        )
    } else if issue == "session_id appears in both train and holdout" {
        (
            "session_leakage",
            "Split by whole sessions or dates so no session contributes to both training and holdout.",
        )
    } else if issue == "training predictions have zero variance" {
        (
            "zero_prediction_variance",
            "Add calibration rows with varied Goose predictions before fitting a linear calibration model.",
        )
    } else if issue == "calibrated holdout MAE did not improve" {
        (
            "holdout_not_improved",
            "Keep the uncalibrated algorithm as primary and gather more labels or adjust the model before applying this calibration.",
        )
    } else {
        (
            "calibration_issue",
            "Inspect the calibration issue, repair the dataset or options, and rerun the evaluator before trusting the model.",
        )
    }
}

fn calibration_application_issue_action(issue: &str) -> (&'static str, &'static str) {
    if issue == "raw_score must be finite" {
        (
            "raw_score_invalid",
            "Recompute the local Goose score and apply calibration only to a finite raw score.",
        )
    } else if issue == "score_min must be finite and less than score_max" {
        (
            "score_range_invalid",
            "Provide the metric family score range before applying calibration.",
        )
    } else if issue.starts_with("calibration run targets ") {
        (
            "calibration_run_mismatch",
            "Choose a passed calibration run for the same algorithm id and version as the score being calibrated.",
        )
    } else if issue.starts_with("calibration params_json invalid:") {
        (
            "calibration_params_invalid",
            "Repair or regenerate the persisted calibration run params JSON before applying it.",
        )
    } else if issue == "calibration run did not pass holdout validation" {
        (
            "calibration_run_failed",
            "Do not apply this calibration run; rerun calibration with enough clean train and holdout labels.",
        )
    } else if issue == "calibration run has no model" {
        (
            "calibration_model_missing",
            "Regenerate the calibration run so it includes a fitted model from a passing evaluator report.",
        )
    } else {
        calibration_issue_action(issue)
    }
}

fn calibration_dataset_issue(issue: &str) -> bool {
    issue.starts_with("unsupported dataset schema ")
        || issue.contains(" is required")
        || issue.contains(" prediction is not finite")
        || issue.ends_with(" is not a UTC RFC3339 timestamp")
}

fn calibration_label_issue(issue: &str) -> bool {
    issue.contains(" label is not finite")
        || issue.contains(" has unsupported label_source ")
        || issue.contains(" missing label_provenance")
}

fn dedupe_calibration_next_actions(
    actions: Vec<CalibrationNextAction>,
) -> Vec<CalibrationNextAction> {
    actions
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

pub fn calibration_run_record(
    calibration_run_id: &str,
    report: &CalibrationReport,
) -> GooseResult<CalibrationRunRecord> {
    let metrics_json = serde_json::to_string(&json!({
        "dataset_valid": report.dataset_valid,
        "labels_valid": report.labels_valid,
        "split_valid": report.split_valid,
        "model_fit_ready": report.model_fit_ready,
        "train_metrics_ready": report.train_metrics_ready,
        "holdout_metrics_ready": report.holdout_metrics_ready,
        "holdout_improvement_valid": report.holdout_improvement_valid,
        "calibration_ready": report.calibration_ready,
        "uncalibrated_train": report.uncalibrated_train,
        "calibrated_train": report.calibrated_train,
        "uncalibrated_holdout": report.uncalibrated_holdout,
        "calibrated_holdout": report.calibrated_holdout,
        "holdout_improved": report.holdout_improved,
        "holdout_bias_by_label_band": report.holdout_bias_by_label_band,
        "leakage_checks": report.leakage_checks,
        "issues": report.issues,
        "next_actions": report.next_actions
    }))
    .map_err(|error| {
        GooseError::message(format!("cannot serialize calibration metrics: {error}"))
    })?;
    let params_json = serde_json::to_string(&json!({
        "model": report.model,
        "split_policy": report.split_policy,
        "split_at": report.split_at,
        "dataset_valid": report.dataset_valid,
        "labels_valid": report.labels_valid,
        "split_valid": report.split_valid,
        "model_fit_ready": report.model_fit_ready,
        "holdout_improvement_valid": report.holdout_improvement_valid,
        "calibration_ready": report.calibration_ready,
        "pass": report.pass
    }))
    .map_err(|error| {
        GooseError::message(format!("cannot serialize calibration params: {error}"))
    })?;

    Ok(CalibrationRunRecord {
        calibration_run_id: calibration_run_id.to_string(),
        algorithm_id: report.algorithm_id.clone(),
        version: report.algorithm_version.clone(),
        times: CalibrationRunTimes {
            train_start: report.train_start.clone().unwrap_or_default(),
            train_end: report.train_end.clone().unwrap_or_default(),
            holdout_start: report.holdout_start.clone().unwrap_or_default(),
            holdout_end: report.holdout_end.clone().unwrap_or_default(),
        },
        metrics_json,
        params_json,
    })
}

impl LinearCalibrationModel {
    pub fn predict(&self, prediction: f64) -> f64 {
        self.slope * prediction + self.intercept
    }
}

fn fit_linear_model(records: &[CalibrationRecord]) -> GooseResult<LinearCalibrationModel> {
    let x_mean = records.iter().map(|record| record.prediction).sum::<f64>() / records.len() as f64;
    let y_mean = records.iter().map(|record| record.label).sum::<f64>() / records.len() as f64;
    let x_var = records
        .iter()
        .map(|record| {
            let diff = record.prediction - x_mean;
            diff * diff
        })
        .sum::<f64>();
    if x_var == 0.0 {
        return Err(GooseError::message(
            "training predictions have zero variance",
        ));
    }
    let covariance = records
        .iter()
        .map(|record| (record.prediction - x_mean) * (record.label - y_mean))
        .sum::<f64>();
    let slope = covariance / x_var;
    let intercept = y_mean - slope * x_mean;
    Ok(LinearCalibrationModel {
        model_type: "ordinary_least_squares_1d".to_string(),
        slope,
        intercept,
    })
}

fn metrics_for<F>(records: &[CalibrationRecord], prediction_fn: F) -> Option<CalibrationMetrics>
where
    F: Fn(&CalibrationRecord) -> f64,
{
    if records.is_empty() {
        return None;
    }
    let predictions: Vec<f64> = records.iter().map(&prediction_fn).collect();
    let labels: Vec<f64> = records.iter().map(|record| record.label).collect();
    let mae = records
        .iter()
        .map(|record| (prediction_fn(record) - record.label).abs())
        .sum::<f64>()
        / records.len() as f64;
    Some(CalibrationMetrics {
        mae,
        correlation: correlation(&predictions, &labels),
        count: records.len(),
    })
}

fn correlation(x: &[f64], y: &[f64]) -> Option<f64> {
    if x.len() < 2 || y.len() < 2 {
        return None;
    }
    let x_mean = x.iter().sum::<f64>() / x.len() as f64;
    let y_mean = y.iter().sum::<f64>() / y.len() as f64;
    let covariance = x
        .iter()
        .zip(y.iter())
        .map(|(x_value, y_value)| (x_value - x_mean) * (y_value - y_mean))
        .sum::<f64>();
    let x_var = x
        .iter()
        .map(|value| {
            let diff = value - x_mean;
            diff * diff
        })
        .sum::<f64>();
    let y_var = y
        .iter()
        .map(|value| {
            let diff = value - y_mean;
            diff * diff
        })
        .sum::<f64>();
    if x_var == 0.0 || y_var == 0.0 {
        None
    } else {
        Some(covariance / (x_var.sqrt() * y_var.sqrt()))
    }
}

fn leakage_checks(
    train: &[CalibrationRecord],
    holdout: &[CalibrationRecord],
    split_at_unix_ms: Option<i64>,
) -> LeakageChecks {
    let train_sessions: BTreeSet<&str> = train
        .iter()
        .filter_map(|record| record.session_id.as_deref())
        .collect();
    let holdout_sessions: BTreeSet<&str> = holdout
        .iter()
        .filter_map(|record| record.session_id.as_deref())
        .collect();
    LeakageChecks {
        train_rows_before_split: train.iter().all(|record| {
            matches!(
                (record_captured_at_unix_ms(record), split_at_unix_ms),
                (Some(captured_ms), Some(split_ms)) if captured_ms < split_ms
            )
        }),
        holdout_rows_at_or_after_split: holdout.iter().all(|record| {
            matches!(
                (record_captured_at_unix_ms(record), split_at_unix_ms),
                (Some(captured_ms), Some(split_ms)) if captured_ms >= split_ms
            )
        }),
        no_session_overlap: train_sessions.is_disjoint(&holdout_sessions),
    }
}

fn record_captured_at_unix_ms(record: &CalibrationRecord) -> Option<i64> {
    parse_rfc3339_utc_unix_ms(&record.captured_at)
}

fn label_band_name(label: f64) -> &'static str {
    if (0.0..34.0).contains(&label) {
        "0-33"
    } else if (34.0..67.0).contains(&label) {
        "34-66"
    } else if (67.0..=100.0).contains(&label) {
        "67-100"
    } else {
        "out-of-range"
    }
}

fn holdout_bias_by_label_band(holdout: &[CalibrationRecord]) -> Vec<ScoreBandBias> {
    let bands = ["0-33", "34-66", "67-100", "out-of-range"];
    let mut result = Vec::new();
    for name in bands {
        let rows: Vec<_> = holdout
            .iter()
            .filter(|record| label_band_name(record.label) == name)
            .collect();
        if rows.is_empty() {
            continue;
        }
        let mean_error = rows
            .iter()
            .map(|record| record.prediction - record.label)
            .sum::<f64>()
            / rows.len() as f64;
        result.push(ScoreBandBias {
            band: name.to_string(),
            count: rows.len(),
            mean_error,
        });
    }
    result
}

fn validate_record(record: &CalibrationRecord, issues: &mut Vec<String>) {
    validate_required("record_id", &record.record_id, issues);
    validate_required("captured_at", &record.captured_at, issues);
    if !record.captured_at.trim().is_empty() && record_captured_at_unix_ms(record).is_none() {
        issues.push(format!(
            "{} captured_at is not a UTC RFC3339 timestamp",
            record.record_id
        ));
    }
    validate_required("metric_family", &record.metric_family, issues);
    validate_required("algorithm_id", &record.algorithm_id, issues);
    validate_required("algorithm_version", &record.algorithm_version, issues);
    validate_required("label_source", &record.label_source, issues);
    if !record.prediction.is_finite() {
        issues.push(format!("{} prediction is not finite", record.record_id));
    }
    if !record.label.is_finite() {
        issues.push(format!("{} label is not finite", record.record_id));
    }
    if !is_allowed_label_source(&record.label_source) {
        issues.push(format!(
            "{} has unsupported label_source {}",
            record.record_id, record.label_source
        ));
    }
    if record.label_provenance.is_null() || record.label_provenance == json!({}) {
        issues.push(format!("{} missing label_provenance", record.record_id));
    }
}

fn is_allowed_label_source(source: &str) -> bool {
    matches!(
        source,
        "manual" | "passive_official_capture" | "user_export" | "screenshot_import" | "synthetic"
    )
}

fn validate_required(name: &str, value: &str, issues: &mut Vec<String>) {
    if value.trim().is_empty() {
        issues.push(format!("{name} is required"));
    }
}

fn min_time(records: &[CalibrationRecord]) -> Option<String> {
    records
        .iter()
        .map(|record| record.captured_at.clone())
        .min()
}

fn max_time(records: &[CalibrationRecord]) -> Option<String> {
    records
        .iter()
        .map(|record| record.captured_at.clone())
        .max()
}

fn default_min_train_rows() -> usize {
    2
}

fn default_min_holdout_rows() -> usize {
    1
}

fn parse_rfc3339_utc_unix_ms(value: &str) -> Option<i64> {
    let value = value.trim();
    let date_time = value.strip_suffix('Z')?;
    let (date, time) = date_time.split_once('T')?;
    let mut date_parts = date.split('-');
    let year = date_parts.next()?.parse::<i32>().ok()?;
    let month = date_parts.next()?.parse::<u32>().ok()?;
    let day = date_parts.next()?.parse::<u32>().ok()?;
    if date_parts.next().is_some() {
        return None;
    }

    let (time_main, fraction) = time.split_once('.').unwrap_or((time, ""));
    let mut time_parts = time_main.split(':');
    let hour = time_parts.next()?.parse::<u32>().ok()?;
    let minute = time_parts.next()?.parse::<u32>().ok()?;
    let second = time_parts.next()?.parse::<u32>().ok()?;
    if time_parts.next().is_some()
        || !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }

    let millis = if fraction.is_empty() {
        0
    } else {
        let digits = fraction
            .chars()
            .take_while(|character| character.is_ascii_digit())
            .take(3)
            .collect::<String>();
        if digits.is_empty() {
            0
        } else {
            format!("{digits:0<3}").parse::<i64>().ok()?
        }
    };

    let days = days_from_civil(year, month, day);
    let seconds = days * 86_400
        + i64::from(hour) * 3_600
        + i64::from(minute) * 60
        + i64::from(second.min(59));
    Some(seconds * 1_000 + millis)
}

fn days_from_civil(year: i32, month: u32, day: u32) -> i64 {
    let year = year - i32::from(month <= 2);
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let month = month as i32;
    let day = day as i32;
    let doy = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    i64::from(era) * 146_097 + i64::from(doe) - 719_468
}
