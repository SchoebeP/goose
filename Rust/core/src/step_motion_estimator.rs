use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    GooseError, GooseResult,
    capture_correlation::{
        CaptureCorrelationOptions, CaptureCorrelationReport,
        DEFAULT_MIN_OWNED_CAPTURES_PER_SUMMARY, run_capture_correlation_for_store,
    },
    protocol::{
        DataPacketBodySummary, I16SeriesSummary, ParsedPayload, decode_hex_with_whitespace,
    },
    store::{DailyActivityMetricInput, DecodedFrameRow, GooseStore, MetricProvenanceInput},
    validation_labels::{
        OFFICIAL_WHOOP_LABEL_POLICY, official_label_policy_issue_action,
        official_label_policy_issues,
    },
};

pub const RAW_MOTION_STEP_ESTIMATE_REPORT_SCHEMA: &str = "goose.raw-motion-step-estimate-report.v1";
pub const GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_ID: &str = "goose.steps.raw_motion_estimate.v0";
pub const GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_VERSION: &str = "0.1.0";

#[derive(Debug, Clone)]
pub struct RawMotionStepEstimateOptions {
    pub min_owned_captures_per_summary: usize,
    pub require_trusted_evidence: bool,
    pub sample_rate_hz: f64,
    pub peak_threshold_i16: f64,
    pub min_peak_spacing_samples: usize,
    pub manual_step_delta: Option<i64>,
    pub official_whoop_step_delta: Option<i64>,
    pub tolerance_steps: i64,
    pub label_provenance: Option<Value>,
    pub date_key: Option<String>,
    pub timezone: Option<String>,
    pub write_metric: bool,
}

impl Default for RawMotionStepEstimateOptions {
    fn default() -> Self {
        Self {
            min_owned_captures_per_summary: DEFAULT_MIN_OWNED_CAPTURES_PER_SUMMARY,
            require_trusted_evidence: false,
            // Field-verified on this band: type-43 sub==41 accelerometer
            // streams at ~100 Hz. The spacing keeps a 0.2 s peak debounce.
            sample_rate_hz: 100.0,
            peak_threshold_i16: 1_200.0,
            min_peak_spacing_samples: 20,
            manual_step_delta: None,
            official_whoop_step_delta: None,
            tolerance_steps: 10,
            label_provenance: None,
            date_key: None,
            timezone: None,
            write_metric: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RawMotionStepEstimateReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub database_path: String,
    pub start: String,
    pub end: String,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub label_policy: String,
    pub source_kind_if_promoted: String,
    pub promotion_status: String,
    pub user_visible_value_allowed: bool,
    pub require_trusted_evidence: bool,
    pub capture_correlation_pass: bool,
    pub decoded_frame_count: usize,
    pub candidate_frame_count: usize,
    pub trusted_candidate_frame_count: usize,
    pub estimated_steps: Option<i64>,
    pub estimated_cadence_spm: Option<f64>,
    pub estimated_duration_seconds: f64,
    pub sample_rate_hz: f64,
    pub peak_threshold_i16: f64,
    pub min_peak_spacing_samples: usize,
    pub manual_step_delta: Option<i64>,
    pub official_whoop_step_delta: Option<i64>,
    pub tolerance_steps: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label_provenance: Option<Value>,
    pub manual_delta_error: Option<i64>,
    pub official_delta_error: Option<i64>,
    pub matches_manual_label: Option<bool>,
    pub matches_official_label: Option<bool>,
    pub matching_label_count: usize,
    pub provided_label_count: usize,
    pub confidence: f64,
    pub date_key: Option<String>,
    pub timezone: Option<String>,
    pub start_time_unix_ms: Option<i64>,
    pub end_time_unix_ms: Option<i64>,
    pub write_metric: bool,
    pub daily_metric_id: Option<String>,
    pub daily_metric_written: bool,
    pub metric_provenance_id: Option<String>,
    pub metric_provenance_written: bool,
    pub quality_flags: Vec<String>,
    pub frames: Vec<RawMotionStepFrameEstimate>,
    pub issues: Vec<String>,
    pub next_actions: Vec<RawMotionStepEstimateNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RawMotionStepFrameEstimate {
    pub frame_id: String,
    pub evidence_id: String,
    pub captured_at: String,
    pub body_summary_kind: String,
    pub packet_k: Option<u8>,
    pub trusted_candidate_evidence: bool,
    pub sample_count: usize,
    pub axis_count: usize,
    pub peak_count: usize,
    pub estimated_steps: i64,
    pub duration_seconds: f64,
    pub cadence_spm: Option<f64>,
    pub mean_abs_i16: f64,
    pub peak_abs_i16: f64,
    pub quality_flags: Vec<String>,
    pub provenance: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct RawMotionStepEstimateNextAction {
    pub scope: String,
    pub reason: String,
    pub action: String,
}

#[derive(Debug, Clone)]
struct MotionPlan {
    body_summary_kind: &'static str,
    packet_k: Option<u8>,
    axes: Vec<I16SeriesSummary>,
    summary_warnings: Vec<String>,
}

pub fn run_raw_motion_step_estimate_for_store(
    store: &GooseStore,
    database_path: &str,
    start: &str,
    end: &str,
    options: RawMotionStepEstimateOptions,
) -> GooseResult<RawMotionStepEstimateReport> {
    validate_options(&options)?;
    let write_options = options.clone();
    let decoded_rows = store.decoded_frames_between(start, end)?;
    let correlation = run_capture_correlation_for_store(
        store,
        database_path,
        start,
        end,
        CaptureCorrelationOptions {
            min_owned_captures_per_summary: options.min_owned_captures_per_summary,
            require_owned_captures: options.require_trusted_evidence,
        },
    )?;
    let mut report = run_raw_motion_step_estimate(
        &decoded_rows,
        &correlation,
        database_path,
        start,
        end,
        options,
    )?;
    persist_validated_raw_motion_step_metric(store, &mut report, &write_options)?;
    Ok(report)
}

pub fn run_raw_motion_step_estimate(
    decoded_rows: &[DecodedFrameRow],
    correlation: &CaptureCorrelationReport,
    database_path: &str,
    start: &str,
    end: &str,
    options: RawMotionStepEstimateOptions,
) -> GooseResult<RawMotionStepEstimateReport> {
    validate_options(&options)?;
    let trusted_frames =
        trusted_frames_for_summary_kinds(correlation, &["raw_motion_k10", "raw_motion_k21"]);
    let mut issues = Vec::new();
    if options.require_trusted_evidence && !correlation.pass {
        issues.push("capture_correlation_report_not_passed".to_string());
    }

    let mut frames = Vec::new();
    for row in decoded_rows {
        let Some(plan) = motion_plan_from_row(row)? else {
            continue;
        };
        let payload = decode_hex_with_whitespace(&row.payload_hex)?;
        if let Some(frame) = estimate_frame_steps(row, &payload, plan, &trusted_frames, &options)? {
            frames.push(frame);
        }
    }

    let candidate_frame_count = frames.len();
    let trusted_candidate_frame_count = frames
        .iter()
        .filter(|frame| frame.trusted_candidate_evidence)
        .count();
    if candidate_frame_count == 0 {
        issues.push("no_raw_motion_step_estimator_frames".to_string());
    }
    if options.require_trusted_evidence && trusted_candidate_frame_count == 0 {
        issues.push("no_trusted_raw_motion_step_frames".to_string());
    }

    let input_frames = frames
        .iter()
        .filter(|frame| !options.require_trusted_evidence || frame.trusted_candidate_evidence)
        .collect::<Vec<_>>();
    let estimated_step_count = input_frames
        .iter()
        .map(|frame| frame.estimated_steps)
        .sum::<i64>();
    let estimated_duration_seconds = input_frames
        .iter()
        .map(|frame| frame.duration_seconds)
        .sum::<f64>();
    let estimated_steps = (candidate_frame_count > 0).then_some(estimated_step_count);
    if estimated_steps.unwrap_or(0) == 0 {
        issues.push("no_raw_motion_step_peaks".to_string());
    }
    let estimated_cadence_spm = if estimated_duration_seconds > 0.0 && estimated_step_count > 0 {
        Some(estimated_step_count as f64 / estimated_duration_seconds * 60.0)
    } else {
        None
    };

    let manual_delta_error = compare_label_error(estimated_steps, options.manual_step_delta);
    let official_delta_error =
        compare_label_error(estimated_steps, options.official_whoop_step_delta);
    let matches_manual_label = label_match(
        manual_delta_error,
        options.manual_step_delta,
        options.tolerance_steps,
    );
    let matches_official_label = label_match(
        official_delta_error,
        options.official_whoop_step_delta,
        options.tolerance_steps,
    );
    let provided_label_count = [options.manual_step_delta, options.official_whoop_step_delta]
        .into_iter()
        .flatten()
        .count();
    let matching_label_count = [matches_manual_label, matches_official_label]
        .into_iter()
        .flatten()
        .filter(|matches| *matches)
        .count();
    if provided_label_count == 0 {
        issues.push("no_step_estimator_validation_label".to_string());
    }
    issues.extend(official_label_policy_issues(
        options.official_whoop_step_delta.is_some(),
        options.label_provenance.as_ref(),
    ));
    if provided_label_count > 0 && matching_label_count != provided_label_count {
        issues.push("raw_motion_step_estimate_outside_tolerance".to_string());
    }

    let mut quality_flags = frames
        .iter()
        .flat_map(|frame| frame.quality_flags.iter().cloned())
        .collect::<BTreeSet<_>>();
    quality_flags.insert("raw_motion_step_estimate".to_string());
    quality_flags.insert("not_device_counter".to_string());
    if estimated_cadence_spm.is_some_and(|cadence| !(40.0..=220.0).contains(&cadence)) {
        quality_flags.insert("aggregate_cadence_outside_plausible_walk_range".to_string());
    }

    issues.sort();
    issues.dedup();
    let confidence = raw_motion_step_confidence(
        issues.is_empty(),
        provided_label_count,
        matching_label_count,
        trusted_candidate_frame_count,
        candidate_frame_count,
        estimated_cadence_spm,
    );
    let pass = issues.is_empty();
    if pass {
        quality_flags.insert("validated_local_estimate".to_string());
    } else {
        quality_flags.insert("local_estimate_unvalidated".to_string());
    }
    let start_time_unix_ms = parse_rfc3339_utc_unix_ms(start);
    let end_time_unix_ms = parse_rfc3339_utc_unix_ms(end);

    Ok(RawMotionStepEstimateReport {
        schema: RAW_MOTION_STEP_ESTIMATE_REPORT_SCHEMA.to_string(),
        generated_by: "goose-raw-motion-step-estimator".to_string(),
        pass,
        database_path: database_path.to_string(),
        start: start.to_string(),
        end: end.to_string(),
        algorithm_id: GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_ID.to_string(),
        algorithm_version: GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_VERSION.to_string(),
        label_policy: OFFICIAL_WHOOP_LABEL_POLICY.to_string(),
        source_kind_if_promoted: "local_estimate".to_string(),
        promotion_status: if pass {
            "validated_candidate"
        } else if candidate_frame_count > 0 {
            "candidate_unvalidated"
        } else {
            "unavailable"
        }
        .to_string(),
        user_visible_value_allowed: pass,
        require_trusted_evidence: options.require_trusted_evidence,
        capture_correlation_pass: correlation.pass,
        decoded_frame_count: decoded_rows.len(),
        candidate_frame_count,
        trusted_candidate_frame_count,
        estimated_steps,
        estimated_cadence_spm,
        estimated_duration_seconds,
        sample_rate_hz: options.sample_rate_hz,
        peak_threshold_i16: options.peak_threshold_i16,
        min_peak_spacing_samples: options.min_peak_spacing_samples,
        manual_step_delta: options.manual_step_delta,
        official_whoop_step_delta: options.official_whoop_step_delta,
        tolerance_steps: options.tolerance_steps,
        label_provenance: options.label_provenance.clone(),
        manual_delta_error,
        official_delta_error,
        matches_manual_label,
        matches_official_label,
        matching_label_count,
        provided_label_count,
        confidence,
        date_key: options.date_key.clone(),
        timezone: options.timezone.clone(),
        start_time_unix_ms,
        end_time_unix_ms,
        write_metric: options.write_metric,
        daily_metric_id: None,
        daily_metric_written: false,
        metric_provenance_id: None,
        metric_provenance_written: false,
        quality_flags: quality_flags.into_iter().collect(),
        frames,
        next_actions: next_actions(&issues),
        issues,
    })
}

fn persist_validated_raw_motion_step_metric(
    store: &GooseStore,
    report: &mut RawMotionStepEstimateReport,
    options: &RawMotionStepEstimateOptions,
) -> GooseResult<()> {
    if !options.write_metric || !report.pass {
        return Ok(());
    }
    let date_key = options
        .date_key
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| GooseError::message("date_key is required when write_metric is true"))?;
    let timezone = options
        .timezone
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| GooseError::message("timezone is required when write_metric is true"))?;
    let start_time_unix_ms = report.start_time_unix_ms.ok_or_else(|| {
        GooseError::message("start must be an RFC3339 UTC timestamp when write_metric is true")
    })?;
    let end_time_unix_ms = report.end_time_unix_ms.ok_or_else(|| {
        GooseError::message("end must be an RFC3339 UTC timestamp when write_metric is true")
    })?;
    if end_time_unix_ms <= start_time_unix_ms {
        return Err(GooseError::message(
            "end must be after start when write_metric is true",
        ));
    }
    let estimated_steps = report.estimated_steps.ok_or_else(|| {
        GooseError::message("estimated_steps is required before writing a step metric")
    })?;
    let metric_id = daily_activity_metric_id(date_key, timezone);
    let provenance_id = format!("prov-{metric_id}");
    let inputs_json = json!({
        "frame_ids": report.frames.iter().map(|frame| frame.frame_id.as_str()).collect::<Vec<_>>(),
        "evidence_ids": report.frames.iter().map(|frame| frame.evidence_id.as_str()).collect::<Vec<_>>(),
        "body_summary_kinds": report.frames.iter().map(|frame| frame.body_summary_kind.as_str()).collect::<BTreeSet<_>>(),
        "candidate_frame_count": report.candidate_frame_count,
        "trusted_candidate_frame_count": report.trusted_candidate_frame_count,
        "estimated_duration_seconds": report.estimated_duration_seconds,
        "estimated_cadence_spm": report.estimated_cadence_spm,
        "sample_rate_hz": report.sample_rate_hz,
        "peak_threshold_i16": report.peak_threshold_i16,
        "min_peak_spacing_samples": report.min_peak_spacing_samples,
        "manual_step_delta_label": report.manual_step_delta,
        "official_whoop_step_delta_label": report.official_whoop_step_delta,
        "label_policy": report.label_policy,
        "label_provenance": report.label_provenance.clone(),
    })
    .to_string();
    let quality_flags_json = serde_json::to_string(&report.quality_flags).map_err(|error| {
        GooseError::message(format!(
            "cannot serialize raw-motion step quality flags: {error}"
        ))
    })?;
    let provenance_json = json!({
        "algorithm": GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_ID,
        "algorithm_version": GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_VERSION,
        "source_kind": "local_estimate",
        "date_key": date_key,
        "timezone": timezone,
        "start": report.start,
        "end": report.end,
        "start_time_unix_ms": start_time_unix_ms,
        "end_time_unix_ms": end_time_unix_ms,
        "promotion_status": report.promotion_status,
        "official_labels_policy": "validation_label_only",
        "official_whoop_step_delta_used_as_label": report.official_whoop_step_delta.is_some(),
        "manual_step_delta_used_as_label": report.manual_step_delta.is_some(),
        "label_policy": OFFICIAL_WHOOP_LABEL_POLICY,
    })
    .to_string();

    report.daily_metric_written = store.upsert_daily_activity_metric(DailyActivityMetricInput {
        daily_metric_id: &metric_id,
        date_key,
        timezone,
        start_time_unix_ms,
        end_time_unix_ms,
        steps: Some(estimated_steps),
        active_kcal: None,
        resting_kcal: None,
        total_kcal: None,
        average_cadence_spm: report.estimated_cadence_spm,
        source_kind: "local_estimate",
        confidence: report.confidence,
        inputs_json: &inputs_json,
        quality_flags_json: &quality_flags_json,
        provenance_json: &provenance_json,
    })?;
    report.metric_provenance_written = store.upsert_metric_provenance(MetricProvenanceInput {
        provenance_id: &provenance_id,
        metric_scope: "daily_activity",
        metric_id: &metric_id,
        source_kind: "local_estimate",
        source_detail: "validated raw-motion local step estimate",
        confidence: Some(report.confidence),
        inputs_json: &inputs_json,
        quality_flags_json: &quality_flags_json,
        provenance_json: &provenance_json,
    })?;
    report.daily_metric_id = Some(metric_id);
    report.metric_provenance_id = Some(provenance_id);
    Ok(())
}

fn estimate_frame_steps(
    row: &DecodedFrameRow,
    payload: &[u8],
    plan: MotionPlan,
    trusted_frames: &BTreeMap<String, bool>,
    options: &RawMotionStepEstimateOptions,
) -> GooseResult<Option<RawMotionStepFrameEstimate>> {
    let selected_axes = selected_motion_axes(&plan.axes);
    let axes = selected_axes
        .into_iter()
        .filter(|axis| axis.parsed_count >= 3)
        .collect::<Vec<_>>();
    if axes.is_empty() {
        return Ok(None);
    }
    let sample_count = axes
        .iter()
        .map(|axis| axis.parsed_count)
        .min()
        .unwrap_or_default();
    if sample_count < 3 {
        return Ok(None);
    }

    let mut quality_flags = BTreeSet::new();
    quality_flags.insert("preliminary_raw_motion_peak_detector".to_string());
    quality_flags.insert("requires_controlled_capture_validation".to_string());
    for warning in parse_warnings(row)? {
        quality_flags.insert(warning);
    }
    for warning in &plan.summary_warnings {
        quality_flags.insert(warning.clone());
    }
    if axes.len() < 3 {
        quality_flags.insert("partial_axis_motion_estimator".to_string());
    }
    if axes.len() == 1 {
        quality_flags.insert("single_axis_motion_estimator".to_string());
    }

    let mut series = Vec::with_capacity(sample_count);
    for index in 0..sample_count {
        let mut sum_squares = 0.0;
        let mut axis_count = 0usize;
        for axis in &axes {
            let offset = axis.offset + index * 2;
            let Some(value) = read_i16_le(payload, offset) else {
                quality_flags.insert(format!("{}_sample_missing", axis.name));
                continue;
            };
            sum_squares += f64::from(value).powi(2);
            axis_count += 1;
        }
        if axis_count == 0 {
            series.push(0.0);
        } else {
            series.push(sum_squares.sqrt());
        }
    }

    let mean_abs_i16 = series.iter().sum::<f64>() / series.len() as f64;
    let peak_abs_i16 = series.iter().copied().fold(0.0, f64::max);
    let peak_count = count_peaks(
        &series,
        options.peak_threshold_i16,
        options.min_peak_spacing_samples,
    );
    if peak_count == 0 {
        quality_flags.insert("no_peaks_detected".to_string());
    }
    let duration_seconds = sample_count as f64 / options.sample_rate_hz;
    let cadence_spm = if duration_seconds > 0.0 && peak_count > 0 {
        Some(peak_count as f64 / duration_seconds * 60.0)
    } else {
        None
    };
    if cadence_spm.is_some_and(|cadence| !(40.0..=220.0).contains(&cadence)) {
        quality_flags.insert("cadence_outside_plausible_walk_range".to_string());
    }
    let trusted_candidate_evidence = trusted_frames
        .get(&row.frame_id)
        .copied()
        .unwrap_or_default();
    if !trusted_candidate_evidence {
        quality_flags.insert("untrusted_capture_evidence".to_string());
    }

    Ok(Some(RawMotionStepFrameEstimate {
        frame_id: row.frame_id.clone(),
        evidence_id: row.evidence_id.clone(),
        captured_at: row.captured_at.clone(),
        body_summary_kind: plan.body_summary_kind.to_string(),
        packet_k: plan.packet_k,
        trusted_candidate_evidence,
        sample_count,
        axis_count: axes.len(),
        peak_count,
        estimated_steps: peak_count as i64,
        duration_seconds,
        cadence_spm,
        mean_abs_i16,
        peak_abs_i16,
        quality_flags: quality_flags.into_iter().collect(),
        provenance: json!({
            "input_source": "decoded_frame",
            "frame_id": row.frame_id,
            "evidence_id": row.evidence_id,
            "parser_version": row.parser_version,
            "body_summary_kind": plan.body_summary_kind,
            "packet_k": plan.packet_k,
            "algorithm": GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_ID,
            "algorithm_version": GOOSE_STEPS_RAW_MOTION_ESTIMATE_V0_VERSION,
            "source_kind_if_promoted": "local_estimate",
            "promotion_policy": "requires_controlled_capture_labels",
            "sample_rate_hz": options.sample_rate_hz,
            "peak_threshold_i16": options.peak_threshold_i16,
            "min_peak_spacing_samples": options.min_peak_spacing_samples,
            "axis_names": axes.iter().map(|axis| axis.name.as_str()).collect::<Vec<_>>(),
        }),
    }))
}

fn motion_plan_from_row(row: &DecodedFrameRow) -> GooseResult<Option<MotionPlan>> {
    let parsed_payload: Option<ParsedPayload> = serde_json::from_str(&row.parsed_payload_json)
        .map_err(|error| {
            GooseError::message(format!(
                "{} parsed_payload_json invalid: {error}",
                row.frame_id
            ))
        })?;
    let Some(ParsedPayload::DataPacket {
        packet_k,
        body_summary: Some(body_summary),
        ..
    }) = parsed_payload
    else {
        return Ok(None);
    };

    Ok(match body_summary {
        DataPacketBodySummary::RawMotionK10 { axes, warnings, .. } => Some(MotionPlan {
            body_summary_kind: "raw_motion_k10",
            packet_k,
            axes,
            summary_warnings: warnings,
        }),
        DataPacketBodySummary::RawMotionK21 { axes, warnings, .. } => Some(MotionPlan {
            body_summary_kind: "raw_motion_k21",
            packet_k,
            axes,
            summary_warnings: warnings,
        }),
        _ => None,
    })
}

fn selected_motion_axes(axes: &[I16SeriesSummary]) -> Vec<I16SeriesSummary> {
    let accelerometer = axes
        .iter()
        .filter(|axis| axis.name.starts_with("accelerometer_"))
        .take(3)
        .cloned()
        .collect::<Vec<_>>();
    if !accelerometer.is_empty() {
        return accelerometer;
    }
    axes.iter().take(3).cloned().collect()
}

fn count_peaks(series: &[f64], threshold: f64, min_spacing: usize) -> usize {
    if series.len() < 3 {
        return 0;
    }
    let mut peak_count = 0usize;
    let mut last_peak = None::<usize>;
    for index in 1..series.len() - 1 {
        if series[index] < threshold
            || series[index] <= series[index - 1]
            || series[index] <= series[index + 1]
        {
            continue;
        }
        if last_peak.is_some_and(|last| index.saturating_sub(last) < min_spacing) {
            continue;
        }
        peak_count += 1;
        last_peak = Some(index);
    }
    peak_count
}

fn compare_label_error(estimated_steps: Option<i64>, label: Option<i64>) -> Option<i64> {
    Some(estimated_steps? - label?)
}

fn label_match(error: Option<i64>, label: Option<i64>, tolerance_steps: i64) -> Option<bool> {
    label.map(|_| error.is_some_and(|error| error.abs() <= tolerance_steps.max(0)))
}

fn raw_motion_step_confidence(
    pass: bool,
    provided_label_count: usize,
    matching_label_count: usize,
    trusted_frame_count: usize,
    candidate_frame_count: usize,
    cadence_spm: Option<f64>,
) -> f64 {
    if !pass {
        return 0.0;
    }
    let label_score = if provided_label_count > 0 {
        matching_label_count as f64 / provided_label_count as f64 * 0.30
    } else {
        0.0
    };
    let trust_score = if candidate_frame_count > 0 {
        trusted_frame_count as f64 / candidate_frame_count as f64 * 0.15
    } else {
        0.0
    };
    let cadence_score = cadence_spm
        .map(|cadence| {
            if (60.0..=180.0).contains(&cadence) {
                0.10
            } else {
                0.03
            }
        })
        .unwrap_or(0.0);
    (0.20 + label_score + trust_score + cadence_score).clamp(0.20, 0.65)
}

fn trusted_frames_for_summary_kinds(
    correlation: &CaptureCorrelationReport,
    allowed_summary_kinds: &[&str],
) -> BTreeMap<String, bool> {
    let allowed_summary_kinds = allowed_summary_kinds
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let trusted_summary_kinds = correlation
        .summaries
        .iter()
        .filter(|summary| {
            summary.trusted_metric_ready
                && allowed_summary_kinds.contains(summary.body_summary_kind.as_str())
        })
        .map(|summary| summary.body_summary_kind.as_str())
        .collect::<BTreeSet<_>>();
    let mut frames = BTreeMap::new();
    for observation in &correlation.observations {
        if !observation.owned_capture
            || !trusted_summary_kinds.contains(observation.body_summary_kind.as_str())
        {
            continue;
        }
        let frame_id = observation
            .fixture_id
            .strip_prefix("sqlite:")
            .unwrap_or(&observation.path);
        frames.insert(frame_id.to_string(), true);
    }
    frames
}

fn parse_warnings(row: &DecodedFrameRow) -> GooseResult<Vec<String>> {
    serde_json::from_str(&row.warnings_json).map_err(|error| {
        GooseError::message(format!("{} warnings_json invalid: {error}", row.frame_id))
    })
}

fn read_i16_le(bytes: &[u8], offset: usize) -> Option<i16> {
    Some(i16::from_le_bytes([
        *bytes.get(offset)?,
        *bytes.get(offset + 1)?,
    ]))
}

fn validate_options(options: &RawMotionStepEstimateOptions) -> GooseResult<()> {
    if !options.sample_rate_hz.is_finite() || options.sample_rate_hz <= 0.0 {
        return Err(GooseError::message(
            "sample_rate_hz must be finite and positive",
        ));
    }
    if !options.peak_threshold_i16.is_finite() || options.peak_threshold_i16 <= 0.0 {
        return Err(GooseError::message(
            "peak_threshold_i16 must be finite and positive",
        ));
    }
    if options.min_peak_spacing_samples == 0 {
        return Err(GooseError::message(
            "min_peak_spacing_samples must be at least 1",
        ));
    }
    if options.tolerance_steps < 0 {
        return Err(GooseError::message("tolerance_steps must be non-negative"));
    }
    if options.write_metric {
        if options
            .date_key
            .as_deref()
            .map(str::trim)
            .unwrap_or_default()
            .is_empty()
        {
            return Err(GooseError::message(
                "date_key is required when write_metric is true",
            ));
        }
        if options
            .timezone
            .as_deref()
            .map(str::trim)
            .unwrap_or_default()
            .is_empty()
        {
            return Err(GooseError::message(
                "timezone is required when write_metric is true",
            ));
        }
    }
    Ok(())
}

fn daily_activity_metric_id(date_key: &str, timezone: &str) -> String {
    format!(
        "daily-activity-raw-motion-steps-{}-{}-local-estimate-v0",
        sanitize_id_part(date_key),
        sanitize_id_part(timezone)
    )
}

fn sanitize_id_part(value: &str) -> String {
    let mut sanitized = value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>();
    while sanitized.contains("--") {
        sanitized = sanitized.replace("--", "-");
    }
    sanitized.trim_matches('-').to_string()
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

fn next_actions(issues: &[String]) -> Vec<RawMotionStepEstimateNextAction> {
    issues
        .iter()
        .map(|issue| RawMotionStepEstimateNextAction {
            scope: issue_scope(issue).to_string(),
            reason: issue.clone(),
            action: issue_action(issue).to_string(),
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn issue_scope(issue: &str) -> &'static str {
    match issue {
        "no_raw_motion_step_estimator_frames" | "no_trusted_raw_motion_step_frames" => {
            "steps.raw_motion_capture"
        }
        "no_raw_motion_step_peaks" => "steps.raw_motion_signal",
        "no_step_estimator_validation_label" | "raw_motion_step_estimate_outside_tolerance" => {
            "steps.validation_label"
        }
        "official_label_provenance_missing" | "official_label_policy_not_marked" => {
            "steps.validation_label"
        }
        "capture_correlation_report_not_passed" => "capture_correlation",
        _ => "steps.raw_motion_estimator",
    }
}

fn issue_action(issue: &str) -> &'static str {
    if let Some(action) = official_label_policy_issue_action(issue) {
        return action;
    }
    match issue {
        "no_raw_motion_step_estimator_frames" => {
            "Capture or import trusted K10/K21 raw-motion packets for the step window."
        }
        "no_trusted_raw_motion_step_frames" => {
            "Use user-owned raw-motion capture evidence before considering the local step estimator."
        }
        "no_raw_motion_step_peaks" => {
            "Inspect the raw-motion samples and adjust the capture/threshold only with controlled still, hand-motion, and counted-step labels."
        }
        "no_step_estimator_validation_label" => {
            "Provide a manual counted-step delta or official WHOOP app step delta as a validation label."
        }
        "raw_motion_step_estimate_outside_tolerance" => {
            "Keep local-estimate steps blocked; compare against controlled captures before tuning the peak detector."
        }
        "capture_correlation_report_not_passed" => {
            "Satisfy owned-capture trust for raw-motion packets before promoting estimator evidence."
        }
        _ => "Resolve this raw-motion step estimator blocker before using estimated steps.",
    }
}
