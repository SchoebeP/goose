use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    GooseError, GooseResult,
    step_discovery::{
        StepPacketDiscoveryCandidate, StepPacketDiscoveryOptions, StepPacketDiscoveryReport,
        run_step_packet_discovery_for_store,
    },
    store::{
        DailyActivityMetricInput, GooseStore, HourlyActivityMetricInput, MetricProvenanceInput,
        StepCounterSampleInput, StepCounterSampleRow,
    },
};

pub const STEP_COUNTER_INGEST_REPORT_SCHEMA: &str = "goose.step-counter-ingest-report.v1";
pub const STEP_COUNTER_DAILY_ROLLUP_REPORT_SCHEMA: &str =
    "goose.step-counter-daily-rollup-report.v1";
pub const STEP_COUNTER_HOURLY_ROLLUP_REPORT_SCHEMA: &str =
    "goose.step-counter-hourly-rollup-report.v1";
pub const ACTIVITY_UNAVAILABLE_DAILY_STATUS_REPORT_SCHEMA: &str =
    "goose.activity-unavailable-daily-status-report.v1";
pub const GOOSE_STEPS_DEVICE_COUNTER_V0_ID: &str = "goose.steps.device_counter.v0";
pub const GOOSE_STEPS_DEVICE_COUNTER_V0_VERSION: &str = "0.1.0";
pub const GOOSE_ACTIVITY_UNAVAILABLE_STATUS_V0_ID: &str = "goose.activity.unavailable_status.v0";
pub const GOOSE_ACTIVITY_UNAVAILABLE_STATUS_V0_VERSION: &str = "0.1.0";

#[derive(Debug, Clone, Copy)]
pub struct StepCounterIngestOptions {
    pub max_candidate_fields: usize,
}

impl Default for StepCounterIngestOptions {
    fn default() -> Self {
        Self {
            max_candidate_fields: 1_000,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StepCounterIngestReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub database_path: String,
    pub start: String,
    pub end: String,
    pub discovery_pass: bool,
    pub explicit_step_counter_found: bool,
    pub counter_candidate_count: usize,
    pub cadence_sample_count: usize,
    pub activity_state_sample_count: usize,
    pub persisted_sample_count: usize,
    pub inserted_sample_count: usize,
    pub idempotent_sample_count: usize,
    pub rejected_sample_count: usize,
    pub discovery: StepPacketDiscoveryReport,
    pub issues: Vec<String>,
    pub next_actions: Vec<StepCounterNextAction>,
}

#[derive(Debug, Clone)]
pub struct StepCounterDailyRollupOptions<'a> {
    pub date_key: &'a str,
    pub timezone: &'a str,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub write_metric: bool,
}

#[derive(Debug, Clone)]
pub struct StepCounterHourlyRollupOptions<'a> {
    pub date_key: &'a str,
    pub timezone: &'a str,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub write_metric: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct ActivityUnavailableDailyStatusOptions<'a> {
    pub date_key: &'a str,
    pub timezone: &'a str,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub write_metric: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StepCounterDailyRollupReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub date_key: String,
    pub timezone: String,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub sample_count: usize,
    pub cadence_sample_count: usize,
    pub activity_state_sample_count: usize,
    pub usable_segment_count: usize,
    pub reset_count: usize,
    pub duplicate_sample_count: usize,
    pub same_timestamp_conflict_count: usize,
    pub steps: Option<i64>,
    pub average_cadence_spm: Option<f64>,
    pub activity_state_counts: BTreeMap<String, usize>,
    pub first_counter_value: Option<i64>,
    pub last_counter_value: Option<i64>,
    pub confidence: f64,
    pub daily_metric_id: Option<String>,
    pub daily_metric_written: bool,
    pub metric_provenance_id: Option<String>,
    pub metric_provenance_written: bool,
    pub quality_flags: Vec<String>,
    pub packet_fields: Vec<StepCounterPacketField>,
    #[serde(default)]
    pub per_source_step_totals: BTreeMap<String, i64>,
    pub issues: Vec<String>,
    pub next_actions: Vec<StepCounterNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StepCounterHourlyRollupReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub date_key: String,
    pub timezone: String,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub sample_count: usize,
    pub cadence_sample_count: usize,
    pub activity_state_sample_count: usize,
    pub usable_segment_count: usize,
    pub reset_count: usize,
    pub duplicate_sample_count: usize,
    pub same_timestamp_conflict_count: usize,
    pub steps: Option<i64>,
    pub average_cadence_spm: Option<f64>,
    pub activity_state_counts: BTreeMap<String, usize>,
    pub first_counter_value: Option<i64>,
    pub last_counter_value: Option<i64>,
    pub confidence: f64,
    pub hourly_metric_id: Option<String>,
    pub hourly_metric_written: bool,
    pub metric_provenance_id: Option<String>,
    pub metric_provenance_written: bool,
    pub quality_flags: Vec<String>,
    pub packet_fields: Vec<StepCounterPacketField>,
    #[serde(default)]
    pub per_source_step_totals: BTreeMap<String, i64>,
    pub issues: Vec<String>,
    pub next_actions: Vec<StepCounterNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActivityUnavailableDailyStatusReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub date_key: String,
    pub timezone: String,
    pub start_time_unix_ms: i64,
    pub end_time_unix_ms: i64,
    pub min_sample_count: usize,
    pub write_metric: bool,
    pub available_step_metric_count: usize,
    pub unavailable_metric_count: usize,
    pub written_metric_count: usize,
    pub metric_provenance_written_count: usize,
    pub statuses: Vec<ActivityUnavailableMetricStatus>,
    pub step_counter_daily_rollup: StepCounterDailyRollupReport,
    pub issues: Vec<String>,
    pub next_actions: Vec<StepCounterNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActivityUnavailableMetricStatus {
    pub metric_id: String,
    pub metric_name: String,
    pub source_kind: String,
    pub promotion_status: String,
    pub available_metric_count: usize,
    pub sample_count: usize,
    pub min_sample_count: usize,
    pub usable_segment_count: usize,
    pub blocker_reasons: Vec<String>,
    pub quality_flags: Vec<String>,
    pub daily_metric_id: Option<String>,
    pub daily_metric_written: bool,
    pub metric_provenance_id: Option<String>,
    pub metric_provenance_written: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct StepCounterPacketField {
    pub packet_family: String,
    pub json_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct StepCounterNextAction {
    pub scope: String,
    pub reason: String,
    pub action: String,
}

#[derive(Debug, Clone)]
struct StepSegmentSummary {
    steps: i64,
    usable_segment_count: usize,
    reset_count: usize,
    duplicate_sample_count: usize,
    same_timestamp_conflict_count: usize,
    first_counter_value: Option<i64>,
    last_counter_value: Option<i64>,
    quality_flags: BTreeSet<String>,
    counter_source_count: usize,
    per_source_steps: BTreeMap<String, i64>,
}

pub fn run_step_counter_ingest_for_store(
    store: &GooseStore,
    database_path: &str,
    start: &str,
    end: &str,
    options: StepCounterIngestOptions,
) -> GooseResult<StepCounterIngestReport> {
    let discovery = run_step_packet_discovery_for_store(
        store,
        database_path,
        start,
        end,
        StepPacketDiscoveryOptions {
            max_candidate_fields: options.max_candidate_fields,
        },
    )?;
    persist_step_counter_discovery(store, database_path, start, end, discovery)
}

pub fn persist_step_counter_discovery(
    store: &GooseStore,
    database_path: &str,
    start: &str,
    end: &str,
    discovery: StepPacketDiscoveryReport,
) -> GooseResult<StepCounterIngestReport> {
    let mut issues = Vec::new();
    let mut counter_candidate_count = 0;
    let mut cadence_sample_count = 0;
    let mut activity_state_sample_count = 0;
    let mut persisted_sample_count = 0;
    let mut inserted_sample_count = 0;
    let mut idempotent_sample_count = 0;
    let mut rejected_sample_count = 0;

    for candidate in discovery
        .candidate_fields
        .iter()
        .filter(|candidate| candidate.match_kind == "step_count")
    {
        counter_candidate_count += 1;
        let Some(counter_value) = scalar_i64(&candidate.value) else {
            rejected_sample_count += 1;
            issues.push(format!(
                "step_counter_candidate_not_integer:{}:{}",
                candidate.frame_id, candidate.json_path
            ));
            continue;
        };
        let Some(sample_time_unix_ms) = parse_rfc3339_utc_unix_ms(&candidate.captured_at) else {
            rejected_sample_count += 1;
            issues.push(format!(
                "step_counter_candidate_unparseable_time:{}:{}",
                candidate.frame_id, candidate.captured_at
            ));
            continue;
        };
        let sample_id = step_counter_sample_id(
            &candidate.frame_id,
            &candidate.json_path,
            sample_time_unix_ms,
            counter_value,
        );
        let cadence_candidate =
            related_candidate(&discovery.candidate_fields, candidate, "cadence");
        let cadence_spm =
            cadence_candidate.and_then(|candidate| scalar_non_negative_f64(&candidate.value));
        let activity_state_candidate =
            related_candidate(&discovery.candidate_fields, candidate, "activity_state");
        let activity_state =
            activity_state_candidate.and_then(|candidate| scalar_activity_state(&candidate.value));
        if cadence_spm.is_some() {
            cadence_sample_count += 1;
        }
        if activity_state.is_some() {
            activity_state_sample_count += 1;
        }
        let mut sample_quality_flags = Vec::new();
        if cadence_candidate.is_some() && cadence_spm.is_none() {
            sample_quality_flags.push("cadence_unparseable".to_string());
        }
        if activity_state_candidate.is_some() && activity_state.is_none() {
            sample_quality_flags.push("activity_state_unparseable".to_string());
        }
        let quality_flags_json = serde_json::to_string(&sample_quality_flags).map_err(|error| {
            GooseError::message(format!(
                "cannot serialize step sample quality flags: {error}"
            ))
        })?;
        let provenance_json = json!({
            "algorithm": "goose.step_counter_ingest.v1",
            "report_schema": STEP_COUNTER_INGEST_REPORT_SCHEMA,
            "discovery_schema": discovery.schema,
            "database_path": database_path,
            "start": start,
            "end": end,
            "frame_id": candidate.frame_id,
            "evidence_id": candidate.evidence_id,
            "captured_at": candidate.captured_at,
            "packet_type_name": candidate.packet_type_name,
            "packet_k": candidate.packet_k,
            "domain": candidate.domain,
            "body_summary_kind": candidate.body_summary_kind,
            "reason": candidate.reason,
            "cadence_source_kind": cadence_candidate.map(|candidate| candidate.source_kind_inference.as_str()),
            "cadence_json_path": cadence_candidate.map(|candidate| candidate.json_path.as_str()),
            "activity_state_source_kind": activity_state_candidate.map(|candidate| candidate.source_kind_inference.as_str()),
            "activity_state_json_path": activity_state_candidate.map(|candidate| candidate.json_path.as_str()),
        })
        .to_string();
        let inserted = store.insert_step_counter_sample(StepCounterSampleInput {
            sample_id: &sample_id,
            sample_time_unix_ms,
            counter_value,
            cadence_spm,
            activity_state: activity_state.as_deref(),
            source_kind: "device_counter",
            packet_family: &candidate.packet_family,
            json_path: &candidate.json_path,
            frame_id: Some(candidate.frame_id.as_str()),
            evidence_id: Some(candidate.evidence_id.as_str()),
            capture_session_id: None,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;
        persisted_sample_count += 1;
        if inserted {
            inserted_sample_count += 1;
        } else {
            idempotent_sample_count += 1;
        }
    }

    if counter_candidate_count == 0 {
        issues.push("no_step_counter_candidates_to_persist".to_string());
    }
    if persisted_sample_count == 0 {
        issues.push("no_step_counter_samples_persisted".to_string());
    }
    for issue in &discovery.issues {
        if !issues.contains(issue) {
            issues.push(issue.clone());
        }
    }

    let next_actions = ingest_next_actions(&issues);
    Ok(StepCounterIngestReport {
        schema: STEP_COUNTER_INGEST_REPORT_SCHEMA.to_string(),
        generated_by: "goose-step-counter-ingest".to_string(),
        pass: issues.is_empty(),
        database_path: database_path.to_string(),
        start: start.to_string(),
        end: end.to_string(),
        discovery_pass: discovery.pass,
        explicit_step_counter_found: discovery.explicit_step_counter_found,
        counter_candidate_count,
        cadence_sample_count,
        activity_state_sample_count,
        persisted_sample_count,
        inserted_sample_count,
        idempotent_sample_count,
        rejected_sample_count,
        discovery,
        issues,
        next_actions,
    })
}

pub fn rollup_device_step_counter_day(
    store: &GooseStore,
    options: StepCounterDailyRollupOptions<'_>,
) -> GooseResult<StepCounterDailyRollupReport> {
    validate_rollup_options(&options)?;
    let samples =
        store.step_counter_samples_between(options.start_time_unix_ms, options.end_time_unix_ms)?;
    let mut issues = Vec::new();
    if samples.len() < options.min_sample_count {
        issues.push("insufficient_step_counter_samples".to_string());
    }

    let segment_summary = summarize_step_counter_segments(&samples);
    let mut quality_flags = segment_summary
        .quality_flags
        .iter()
        .cloned()
        .collect::<Vec<_>>();
    if samples.len() >= options.min_sample_count {
        quality_flags.insert(0, "counter_delta".to_string());
    }
    if segment_summary.counter_source_count > 1 {
        issues.push("multiple_step_counter_sources".to_string());
    }
    if segment_summary.usable_segment_count == 0 && samples.len() >= options.min_sample_count {
        issues.push("no_usable_step_counter_segments".to_string());
    }
    quality_flags.sort();
    quality_flags.dedup();

    let pass = issues.is_empty();
    let confidence = if pass {
        step_counter_confidence(&segment_summary)
    } else {
        0.0
    };
    let cadence_sample_count = samples
        .iter()
        .filter(|sample| sample.cadence_spm.is_some())
        .count();
    let average_cadence_spm = average_cadence_spm(&samples);
    let activity_state_counts = activity_state_counts(&samples);
    let activity_state_sample_count = activity_state_counts.values().sum::<usize>();
    let packet_fields = packet_fields(&samples);
    let metric_id = daily_activity_metric_id(options.date_key, options.timezone);
    let provenance_id = format!("prov-{metric_id}");
    let mut daily_metric_written = false;
    let mut metric_provenance_written = false;

    if pass && options.write_metric {
        let inputs_json = json!({
            "step_counter_sample_ids": samples.iter().map(|sample| sample.sample_id.as_str()).collect::<Vec<_>>(),
            "sample_count": samples.len(),
            "cadence_sample_count": cadence_sample_count,
            "average_cadence_spm": average_cadence_spm,
            "activity_state_sample_count": activity_state_sample_count,
            "activity_state_counts": activity_state_counts,
            "usable_segment_count": segment_summary.usable_segment_count,
            "reset_count": segment_summary.reset_count,
            "packet_fields": packet_fields,
            "per_source_step_totals": segment_summary.per_source_steps,
        })
        .to_string();
        let quality_flags_json = serde_json::to_string(&quality_flags).map_err(|error| {
            GooseError::message(format!("cannot serialize quality flags: {error}"))
        })?;
        let provenance_json = json!({
            "algorithm": GOOSE_STEPS_DEVICE_COUNTER_V0_ID,
            "algorithm_version": GOOSE_STEPS_DEVICE_COUNTER_V0_VERSION,
            "source_kind": "device_counter",
            "date_key": options.date_key,
            "timezone": options.timezone,
            "start_time_unix_ms": options.start_time_unix_ms,
            "end_time_unix_ms": options.end_time_unix_ms,
        })
        .to_string();

        daily_metric_written = store.upsert_daily_activity_metric(DailyActivityMetricInput {
            daily_metric_id: &metric_id,
            date_key: options.date_key,
            timezone: options.timezone,
            start_time_unix_ms: options.start_time_unix_ms,
            end_time_unix_ms: options.end_time_unix_ms,
            steps: Some(segment_summary.steps),
            active_kcal: None,
            resting_kcal: None,
            total_kcal: None,
            average_cadence_spm,
            source_kind: "device_counter",
            confidence,
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;

        metric_provenance_written = store.upsert_metric_provenance(MetricProvenanceInput {
            provenance_id: &provenance_id,
            metric_scope: "daily_activity",
            metric_id: &metric_id,
            source_kind: "device_counter",
            source_detail: "WHOOP decoded step counter",
            confidence: Some(confidence),
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;
    }

    let next_actions = rollup_next_actions(&issues);
    Ok(StepCounterDailyRollupReport {
        schema: STEP_COUNTER_DAILY_ROLLUP_REPORT_SCHEMA.to_string(),
        generated_by: "goose-step-counter-daily-rollup".to_string(),
        pass,
        date_key: options.date_key.to_string(),
        timezone: options.timezone.to_string(),
        start_time_unix_ms: options.start_time_unix_ms,
        end_time_unix_ms: options.end_time_unix_ms,
        min_sample_count: options.min_sample_count,
        sample_count: samples.len(),
        cadence_sample_count,
        activity_state_sample_count,
        usable_segment_count: segment_summary.usable_segment_count,
        reset_count: segment_summary.reset_count,
        duplicate_sample_count: segment_summary.duplicate_sample_count,
        same_timestamp_conflict_count: segment_summary.same_timestamp_conflict_count,
        steps: pass.then_some(segment_summary.steps),
        average_cadence_spm: pass.then_some(average_cadence_spm).flatten(),
        activity_state_counts,
        first_counter_value: segment_summary.first_counter_value,
        last_counter_value: segment_summary.last_counter_value,
        confidence,
        daily_metric_id: (pass && options.write_metric).then_some(metric_id),
        daily_metric_written,
        metric_provenance_id: (pass && options.write_metric).then_some(provenance_id),
        metric_provenance_written,
        quality_flags,
        packet_fields,
        per_source_step_totals: segment_summary.per_source_steps,
        issues,
        next_actions,
    })
}

pub fn rollup_device_step_counter_hour(
    store: &GooseStore,
    options: StepCounterHourlyRollupOptions<'_>,
) -> GooseResult<StepCounterHourlyRollupReport> {
    validate_hourly_rollup_options(&options)?;
    let samples =
        store.step_counter_samples_between(options.start_time_unix_ms, options.end_time_unix_ms)?;
    let mut issues = Vec::new();
    if samples.len() < options.min_sample_count {
        issues.push("insufficient_step_counter_samples".to_string());
    }

    let segment_summary = summarize_step_counter_segments(&samples);
    let mut quality_flags = segment_summary
        .quality_flags
        .iter()
        .cloned()
        .collect::<Vec<_>>();
    if samples.len() >= options.min_sample_count {
        quality_flags.insert(0, "counter_delta".to_string());
    }
    if segment_summary.counter_source_count > 1 {
        issues.push("multiple_step_counter_sources".to_string());
    }
    if segment_summary.usable_segment_count == 0 && samples.len() >= options.min_sample_count {
        issues.push("no_usable_step_counter_segments".to_string());
    }
    quality_flags.sort();
    quality_flags.dedup();

    let pass = issues.is_empty();
    let confidence = if pass {
        step_counter_confidence(&segment_summary)
    } else {
        0.0
    };
    let cadence_sample_count = samples
        .iter()
        .filter(|sample| sample.cadence_spm.is_some())
        .count();
    let average_cadence_spm = average_cadence_spm(&samples);
    let activity_state_counts = activity_state_counts(&samples);
    let activity_state_sample_count = activity_state_counts.values().sum::<usize>();
    let packet_fields = packet_fields(&samples);
    let metric_id = hourly_activity_metric_id(
        options.date_key,
        options.timezone,
        options.start_time_unix_ms,
        options.end_time_unix_ms,
    );
    let provenance_id = format!("prov-{metric_id}");
    let mut hourly_metric_written = false;
    let mut metric_provenance_written = false;

    if pass && options.write_metric {
        let inputs_json = json!({
            "step_counter_sample_ids": samples.iter().map(|sample| sample.sample_id.as_str()).collect::<Vec<_>>(),
            "sample_count": samples.len(),
            "cadence_sample_count": cadence_sample_count,
            "average_cadence_spm": average_cadence_spm,
            "activity_state_sample_count": activity_state_sample_count,
            "activity_state_counts": activity_state_counts,
            "usable_segment_count": segment_summary.usable_segment_count,
            "reset_count": segment_summary.reset_count,
            "packet_fields": packet_fields,
            "per_source_step_totals": segment_summary.per_source_steps,
        })
        .to_string();
        let quality_flags_json = serde_json::to_string(&quality_flags).map_err(|error| {
            GooseError::message(format!("cannot serialize quality flags: {error}"))
        })?;
        let provenance_json = json!({
            "algorithm": GOOSE_STEPS_DEVICE_COUNTER_V0_ID,
            "algorithm_version": GOOSE_STEPS_DEVICE_COUNTER_V0_VERSION,
            "source_kind": "device_counter",
            "date_key": options.date_key,
            "timezone": options.timezone,
            "start_time_unix_ms": options.start_time_unix_ms,
            "end_time_unix_ms": options.end_time_unix_ms,
        })
        .to_string();

        hourly_metric_written = store.upsert_hourly_activity_metric(HourlyActivityMetricInput {
            hourly_metric_id: &metric_id,
            date_key: options.date_key,
            timezone: options.timezone,
            start_time_unix_ms: options.start_time_unix_ms,
            end_time_unix_ms: options.end_time_unix_ms,
            steps: Some(segment_summary.steps),
            active_kcal: None,
            resting_kcal: None,
            total_kcal: None,
            average_cadence_spm,
            source_kind: "device_counter",
            confidence,
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;

        metric_provenance_written = store.upsert_metric_provenance(MetricProvenanceInput {
            provenance_id: &provenance_id,
            metric_scope: "hourly_activity",
            metric_id: &metric_id,
            source_kind: "device_counter",
            source_detail: "WHOOP decoded step counter",
            confidence: Some(confidence),
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;
    }

    let next_actions = rollup_next_actions(&issues);
    Ok(StepCounterHourlyRollupReport {
        schema: STEP_COUNTER_HOURLY_ROLLUP_REPORT_SCHEMA.to_string(),
        generated_by: "goose-step-counter-hourly-rollup".to_string(),
        pass,
        date_key: options.date_key.to_string(),
        timezone: options.timezone.to_string(),
        start_time_unix_ms: options.start_time_unix_ms,
        end_time_unix_ms: options.end_time_unix_ms,
        min_sample_count: options.min_sample_count,
        sample_count: samples.len(),
        cadence_sample_count,
        activity_state_sample_count,
        usable_segment_count: segment_summary.usable_segment_count,
        reset_count: segment_summary.reset_count,
        duplicate_sample_count: segment_summary.duplicate_sample_count,
        same_timestamp_conflict_count: segment_summary.same_timestamp_conflict_count,
        steps: pass.then_some(segment_summary.steps),
        average_cadence_spm: pass.then_some(average_cadence_spm).flatten(),
        activity_state_counts,
        first_counter_value: segment_summary.first_counter_value,
        last_counter_value: segment_summary.last_counter_value,
        confidence,
        hourly_metric_id: (pass && options.write_metric).then_some(metric_id),
        hourly_metric_written,
        metric_provenance_id: (pass && options.write_metric).then_some(provenance_id),
        metric_provenance_written,
        quality_flags,
        packet_fields,
        per_source_step_totals: segment_summary.per_source_steps,
        issues,
        next_actions,
    })
}

pub fn rollup_activity_unavailable_daily_status_for_store(
    store: &GooseStore,
    options: ActivityUnavailableDailyStatusOptions<'_>,
) -> GooseResult<ActivityUnavailableDailyStatusReport> {
    let rollup_options = StepCounterDailyRollupOptions {
        date_key: options.date_key,
        timezone: options.timezone,
        start_time_unix_ms: options.start_time_unix_ms,
        end_time_unix_ms: options.end_time_unix_ms,
        min_sample_count: options.min_sample_count,
        write_metric: false,
    };
    validate_rollup_options(&rollup_options)?;

    let step_counter_daily_rollup = rollup_device_step_counter_day(store, rollup_options)?;
    let available_step_metric_count = available_step_metric_count(
        store,
        options.date_key,
        options.timezone,
        options.start_time_unix_ms,
        options.end_time_unix_ms,
    )?;

    let mut statuses = Vec::new();
    if available_step_metric_count == 0 && !step_counter_daily_rollup.pass {
        statuses.push(activity_steps_unavailable_status_for_rollup(
            store,
            &step_counter_daily_rollup,
            available_step_metric_count,
            options,
        )?);
    }

    let written_metric_count = statuses
        .iter()
        .filter(|status| status.daily_metric_written)
        .count();
    let metric_provenance_written_count = statuses
        .iter()
        .filter(|status| status.metric_provenance_written)
        .count();
    let next_actions = if statuses.is_empty() {
        Vec::new()
    } else {
        step_counter_daily_rollup.next_actions.clone()
    };

    Ok(ActivityUnavailableDailyStatusReport {
        schema: ACTIVITY_UNAVAILABLE_DAILY_STATUS_REPORT_SCHEMA.to_string(),
        generated_by: "goose-activity-unavailable-daily-status".to_string(),
        pass: true,
        date_key: options.date_key.to_string(),
        timezone: options.timezone.to_string(),
        start_time_unix_ms: options.start_time_unix_ms,
        end_time_unix_ms: options.end_time_unix_ms,
        min_sample_count: options.min_sample_count,
        write_metric: options.write_metric,
        available_step_metric_count,
        unavailable_metric_count: statuses.len(),
        written_metric_count,
        metric_provenance_written_count,
        statuses,
        step_counter_daily_rollup,
        issues: Vec::new(),
        next_actions,
    })
}

fn activity_steps_unavailable_status_for_rollup(
    store: &GooseStore,
    rollup: &StepCounterDailyRollupReport,
    available_step_metric_count: usize,
    options: ActivityUnavailableDailyStatusOptions<'_>,
) -> GooseResult<ActivityUnavailableMetricStatus> {
    let metric_id = activity_unavailable_metric_id("steps", options.date_key, options.timezone);
    let provenance_id = format!("prov-{metric_id}");
    let blocker_reasons = unavailable_step_blocker_reasons(rollup);
    let quality_flags = unavailable_step_quality_flags(rollup, &blocker_reasons);
    let mut daily_metric_written = false;
    let mut metric_provenance_written = false;

    if options.write_metric {
        let inputs_json = json!({
            "metric_id": "steps",
            "metric_name": "steps",
            "step_counter_daily_rollup_schema": rollup.schema,
            "date_key": options.date_key,
            "timezone": options.timezone,
            "start_time_unix_ms": options.start_time_unix_ms,
            "end_time_unix_ms": options.end_time_unix_ms,
            "min_sample_count": options.min_sample_count,
            "sample_count": rollup.sample_count,
            "cadence_sample_count": rollup.cadence_sample_count,
            "activity_state_sample_count": rollup.activity_state_sample_count,
            "usable_segment_count": rollup.usable_segment_count,
            "reset_count": rollup.reset_count,
            "duplicate_sample_count": rollup.duplicate_sample_count,
            "same_timestamp_conflict_count": rollup.same_timestamp_conflict_count,
            "packet_fields": rollup.packet_fields,
            "available_step_metric_count": available_step_metric_count,
            "blocker_reasons": blocker_reasons,
            "rollup_next_actions": rollup.next_actions,
        })
        .to_string();
        let quality_flags_json = serde_json::to_string(&quality_flags).map_err(|error| {
            GooseError::message(format!(
                "cannot serialize activity unavailable quality flags: {error}"
            ))
        })?;
        let provenance_json = json!({
            "algorithm": GOOSE_ACTIVITY_UNAVAILABLE_STATUS_V0_ID,
            "algorithm_version": GOOSE_ACTIVITY_UNAVAILABLE_STATUS_V0_VERSION,
            "source_kind": "unavailable",
            "metric_id": "steps",
            "metric_name": "steps",
            "date_key": options.date_key,
            "timezone": options.timezone,
            "start_time_unix_ms": options.start_time_unix_ms,
            "end_time_unix_ms": options.end_time_unix_ms,
            "promotion_status": "blocked",
            "promotion_allowed": false,
            "user_visible_value_allowed": false,
            "blocker_reasons": blocker_reasons,
            "step_counter_daily_rollup_schema": rollup.schema,
            "official_labels_policy": "not_used",
            "value_policy": "no_step_value_written_until_whoop_device_counter_or_validated_local_estimator_exists",
        })
        .to_string();

        daily_metric_written = store.upsert_daily_activity_metric(DailyActivityMetricInput {
            daily_metric_id: &metric_id,
            date_key: options.date_key,
            timezone: options.timezone,
            start_time_unix_ms: options.start_time_unix_ms,
            end_time_unix_ms: options.end_time_unix_ms,
            steps: None,
            active_kcal: None,
            resting_kcal: None,
            total_kcal: None,
            average_cadence_spm: None,
            source_kind: "unavailable",
            confidence: 0.0,
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;

        metric_provenance_written = store.upsert_metric_provenance(MetricProvenanceInput {
            provenance_id: &provenance_id,
            metric_scope: "daily_activity",
            metric_id: &metric_id,
            source_kind: "unavailable",
            source_detail: "activity steps blocked by local WHOOP packet promotion gate",
            confidence: Some(0.0),
            inputs_json: &inputs_json,
            quality_flags_json: &quality_flags_json,
            provenance_json: &provenance_json,
        })?;
    }

    Ok(ActivityUnavailableMetricStatus {
        metric_id: "steps".to_string(),
        metric_name: "steps".to_string(),
        source_kind: "unavailable".to_string(),
        promotion_status: "blocked".to_string(),
        available_metric_count: available_step_metric_count,
        sample_count: rollup.sample_count,
        min_sample_count: rollup.min_sample_count,
        usable_segment_count: rollup.usable_segment_count,
        blocker_reasons,
        quality_flags,
        daily_metric_id: options.write_metric.then_some(metric_id),
        daily_metric_written,
        metric_provenance_id: options.write_metric.then_some(provenance_id),
        metric_provenance_written,
    })
}

fn available_step_metric_count(
    store: &GooseStore,
    date_key: &str,
    timezone: &str,
    start_time_unix_ms: i64,
    end_time_unix_ms: i64,
) -> GooseResult<usize> {
    Ok(store
        .daily_activity_metrics_between(start_time_unix_ms, end_time_unix_ms)?
        .into_iter()
        .filter(|row| row.date_key == date_key)
        .filter(|row| row.timezone == timezone)
        .filter(|row| row.source_kind != "unavailable")
        .filter(|row| row.steps.is_some())
        .count())
}

fn activity_unavailable_metric_id(metric_id: &str, date_key: &str, timezone: &str) -> String {
    format!(
        "daily-activity-{}-{}-{}-unavailable-v0",
        sanitize_id_part(metric_id),
        sanitize_id_part(date_key),
        sanitize_id_part(timezone)
    )
}

fn unavailable_step_blocker_reasons(rollup: &StepCounterDailyRollupReport) -> Vec<String> {
    let mut blockers = rollup.issues.clone();
    if blockers.is_empty() {
        blockers.push("no_available_whoop_step_metric".to_string());
    }
    blockers.sort();
    blockers.dedup();
    blockers
}

fn unavailable_step_quality_flags(
    rollup: &StepCounterDailyRollupReport,
    blocker_reasons: &[String],
) -> Vec<String> {
    rollup
        .quality_flags
        .iter()
        .chain(blocker_reasons.iter())
        .cloned()
        .chain([
            "activity_steps_unavailable".to_string(),
            "source_kind_unavailable".to_string(),
        ])
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn summarize_step_counter_segments(samples: &[StepCounterSampleRow]) -> StepSegmentSummary {
    // Deltas are only meaningful within one counter source: interleaved
    // samples from different (packet_family, json_path) fields would
    // otherwise produce spurious giant deltas or phantom resets.
    let mut groups: BTreeMap<(&str, &str), Vec<&StepCounterSampleRow>> = BTreeMap::new();
    for sample in samples {
        groups
            .entry((sample.packet_family.as_str(), sample.json_path.as_str()))
            .or_default()
            .push(sample);
    }

    let mut summary = StepSegmentSummary {
        steps: 0,
        usable_segment_count: 0,
        reset_count: 0,
        duplicate_sample_count: 0,
        same_timestamp_conflict_count: 0,
        first_counter_value: None,
        last_counter_value: None,
        quality_flags: BTreeSet::new(),
        counter_source_count: groups.len(),
        per_source_steps: BTreeMap::new(),
    };

    for ((packet_family, json_path), group) in &groups {
        let mut source_steps = 0i64;
        for pair in group.windows(2) {
            let previous = pair[0];
            let current = pair[1];
            if current.sample_time_unix_ms == previous.sample_time_unix_ms {
                if current.counter_value == previous.counter_value {
                    summary.duplicate_sample_count += 1;
                    summary.quality_flags.insert("duplicate_sample".to_string());
                } else {
                    summary.same_timestamp_conflict_count += 1;
                    summary
                        .quality_flags
                        .insert("same_timestamp_counter_conflict".to_string());
                }
                continue;
            }
            if current.counter_value >= previous.counter_value {
                source_steps += current.counter_value - previous.counter_value;
                summary.usable_segment_count += 1;
            } else {
                summary.reset_count += 1;
                summary
                    .quality_flags
                    .insert("counter_reset_detected".to_string());
            }
        }
        summary
            .per_source_steps
            .insert(format!("{packet_family}:{json_path}"), source_steps);
    }

    if groups.len() == 1 {
        let group = groups.values().next().expect("single counter source");
        summary.steps = summary.per_source_steps.values().sum();
        summary.first_counter_value = group.first().map(|sample| sample.counter_value);
        summary.last_counter_value = group.last().map(|sample| sample.counter_value);
    } else if groups.len() > 1 {
        // No single promoted source: never sum across sources, and leave the
        // first/last counter values unset rather than mixing sources.
        summary
            .quality_flags
            .insert("multiple_counter_sources".to_string());
    }

    summary
}

fn related_candidate<'a>(
    candidates: &'a [StepPacketDiscoveryCandidate],
    step_candidate: &StepPacketDiscoveryCandidate,
    match_kind: &str,
) -> Option<&'a StepPacketDiscoveryCandidate> {
    candidates.iter().find(|candidate| {
        candidate.frame_id == step_candidate.frame_id
            && candidate.packet_family == step_candidate.packet_family
            && candidate.match_kind == match_kind
    })
}

fn scalar_i64(value: &Value) -> Option<i64> {
    match value {
        Value::Number(number) => number.as_i64().or_else(|| {
            number.as_u64().and_then(|value| {
                if value <= i64::MAX as u64 {
                    Some(value as i64)
                } else {
                    None
                }
            })
        }),
        Value::String(value) => value.trim().parse::<i64>().ok(),
        _ => None,
    }
}

fn scalar_non_negative_f64(value: &Value) -> Option<f64> {
    let parsed = match value {
        Value::Number(number) => number.as_f64(),
        Value::String(value) => value.trim().parse::<f64>().ok(),
        _ => None,
    }?;
    (parsed.is_finite() && parsed >= 0.0).then_some(parsed)
}

fn scalar_activity_state(value: &Value) -> Option<String> {
    let state = match value {
        Value::String(value) => value.trim().to_string(),
        Value::Number(number) => number.to_string(),
        Value::Bool(value) => value.to_string(),
        _ => return None,
    };
    (!state.is_empty()).then_some(state)
}

fn step_counter_sample_id(
    frame_id: &str,
    json_path: &str,
    sample_time_unix_ms: i64,
    counter_value: i64,
) -> String {
    format!(
        "step-counter-{}-{}-{}-{}",
        sanitize_id_part(frame_id),
        sanitize_id_part(json_path),
        sample_time_unix_ms,
        counter_value
    )
}

fn daily_activity_metric_id(date_key: &str, timezone: &str) -> String {
    format!(
        "daily-activity-steps-{}-{}-device-counter-v0",
        sanitize_id_part(date_key),
        sanitize_id_part(timezone)
    )
}

fn hourly_activity_metric_id(
    date_key: &str,
    timezone: &str,
    start_time_unix_ms: i64,
    end_time_unix_ms: i64,
) -> String {
    format!(
        "hourly-activity-steps-{}-{}-{}-{}-device-counter-v0",
        sanitize_id_part(date_key),
        sanitize_id_part(timezone),
        start_time_unix_ms,
        end_time_unix_ms
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

fn average_cadence_spm(samples: &[StepCounterSampleRow]) -> Option<f64> {
    let cadences = samples
        .iter()
        .filter_map(|sample| sample.cadence_spm)
        .collect::<Vec<_>>();
    if cadences.is_empty() {
        return None;
    }
    Some(cadences.iter().sum::<f64>() / cadences.len() as f64)
}

fn activity_state_counts(samples: &[StepCounterSampleRow]) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for state in samples
        .iter()
        .filter_map(|sample| sample.activity_state.as_deref())
    {
        *counts.entry(state.to_string()).or_insert(0) += 1;
    }
    counts
}

fn packet_fields(samples: &[StepCounterSampleRow]) -> Vec<StepCounterPacketField> {
    let mut fields = samples
        .iter()
        .map(|sample| StepCounterPacketField {
            packet_family: sample.packet_family.clone(),
            json_path: sample.json_path.clone(),
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    fields.sort();
    fields
}

fn step_counter_confidence(summary: &StepSegmentSummary) -> f64 {
    let penalty = summary.reset_count as f64 * 0.10
        + summary.duplicate_sample_count as f64 * 0.02
        + summary.same_timestamp_conflict_count as f64 * 0.10;
    (0.95 - penalty).clamp(0.50, 0.95)
}

fn validate_rollup_options(options: &StepCounterDailyRollupOptions<'_>) -> GooseResult<()> {
    if options.date_key.trim().is_empty() {
        return Err(GooseError::message("date_key is required"));
    }
    if options.timezone.trim().is_empty() {
        return Err(GooseError::message("timezone is required"));
    }
    if options.start_time_unix_ms < 0 {
        return Err(GooseError::message(
            "start_time_unix_ms must be non-negative",
        ));
    }
    if options.end_time_unix_ms <= options.start_time_unix_ms {
        return Err(GooseError::message(
            "end_time_unix_ms must be greater than start_time_unix_ms",
        ));
    }
    if options.min_sample_count < 2 {
        return Err(GooseError::message("min_sample_count must be at least 2"));
    }
    Ok(())
}

fn validate_hourly_rollup_options(options: &StepCounterHourlyRollupOptions<'_>) -> GooseResult<()> {
    if options.date_key.trim().is_empty() {
        return Err(GooseError::message("date_key is required"));
    }
    if options.timezone.trim().is_empty() {
        return Err(GooseError::message("timezone is required"));
    }
    if options.start_time_unix_ms < 0 {
        return Err(GooseError::message(
            "start_time_unix_ms must be non-negative",
        ));
    }
    if options.end_time_unix_ms <= options.start_time_unix_ms {
        return Err(GooseError::message(
            "end_time_unix_ms must be greater than start_time_unix_ms",
        ));
    }
    if options.min_sample_count < 2 {
        return Err(GooseError::message("min_sample_count must be at least 2"));
    }
    Ok(())
}

fn ingest_next_actions(issues: &[String]) -> Vec<StepCounterNextAction> {
    let mut actions = Vec::new();
    if issues
        .iter()
        .any(|issue| issue == "no_step_counter_candidates_to_persist")
    {
        actions.push(StepCounterNextAction {
            scope: "steps:counter-ingest".to_string(),
            reason: "no_decoded_counter".to_string(),
            action: "Run the controlled still/hand-motion/100-step/walk captures and inspect K10/K11/K21/history decode output for a monotonic step_count-style field.".to_string(),
        });
    }
    if issues.iter().any(|issue| {
        issue.starts_with("step_counter_candidate_unparseable_time")
            || issue.starts_with("step_counter_candidate_not_integer")
    }) {
        actions.push(StepCounterNextAction {
            scope: "steps:counter-ingest".to_string(),
            reason: "candidate_not_promotable".to_string(),
            action: "Keep the candidate as debug evidence until its timestamp and scalar integer semantics are decoded cleanly.".to_string(),
        });
    }
    dedupe_actions(actions)
}

fn rollup_next_actions(issues: &[String]) -> Vec<StepCounterNextAction> {
    let mut actions = Vec::new();
    if issues
        .iter()
        .any(|issue| issue == "insufficient_step_counter_samples")
    {
        actions.push(StepCounterNextAction {
            scope: "steps:daily-rollup".to_string(),
            reason: "insufficient_samples".to_string(),
            action: "Persist at least two decoded device-counter samples inside the day window before writing WHOOP-derived daily steps.".to_string(),
        });
    }
    if issues
        .iter()
        .any(|issue| issue == "no_usable_step_counter_segments")
    {
        actions.push(StepCounterNextAction {
            scope: "steps:daily-rollup".to_string(),
            reason: "no_positive_or_flat_segments".to_string(),
            action: "Capture a longer step-counter window or verify whether the decoded counter resets on every packet/reconnect.".to_string(),
        });
    }
    if issues
        .iter()
        .any(|issue| issue == "multiple_step_counter_sources")
    {
        actions.push(StepCounterNextAction {
            scope: "steps:daily-rollup".to_string(),
            reason: "multiple_counter_sources".to_string(),
            action: "Multiple decoded step-counter fields coexist in this window; promote a single (packet_family, json_path) counter source before writing device-counter steps.".to_string(),
        });
    }
    dedupe_actions(actions)
}

fn dedupe_actions(actions: Vec<StepCounterNextAction>) -> Vec<StepCounterNextAction> {
    let mut seen = BTreeSet::new();
    actions
        .into_iter()
        .filter(|action| {
            seen.insert(format!(
                "{}:{}:{}",
                action.scope, action.reason, action.action
            ))
        })
        .collect()
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
