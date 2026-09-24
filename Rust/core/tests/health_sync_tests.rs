use goose_core::activity_identity::{ActivityIdentityInput, activity_idempotency_key};
use goose_core::health_sync::{
    ActivityHealthSyncDryRunInput, ActivitySyncCandidate, ActivitySyncInterval, ActivitySyncMetric,
    ExistingHealthRecord, HealthPlatform, HealthSyncCandidate, HealthSyncDeletePolicy,
    HealthSyncDryRunInput, HealthSyncPartialPlanPolicy, HealthSyncSessionKind, HealthSyncWindow,
    run_activity_health_sync_dry_run, run_health_sync_dry_run,
};
use serde_json::json;

#[test]
fn healthkit_maps_heart_rate_and_sdnn_but_blocks_rmssd_guard() {
    let input: HealthSyncDryRunInput = serde_json::from_str(include_str!(
        "../fixtures/synthetic/health_sync_dry_run_healthkit.json"
    ))
    .unwrap();
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass, "{:?}", report.issues);
    assert!(report.input_valid);
    assert!(!report.all_candidate_writes_planned);
    assert!(report.all_requested_deletes_planned);
    assert!(!report.all_records_ready);
    assert_eq!(
        report.partial_plan_policy,
        HealthSyncPartialPlanPolicy::AllowPlannedRowsAfterConfirmation
    );
    assert!(report.partial_plan);
    assert!(report.partial_plan_confirmation_required);
    assert!(!report.platform_write_blocked_by_partial_plan);
    assert!(report.permissions_ready);
    assert!(!report.mappings_ready);
    assert!(report.units_ready);
    assert!(report.provenance_ready);
    assert!(!report.source_policy_ready);
    assert!(report.idempotency_ready);
    assert!(report.cleanup_scope_ready);
    assert_eq!(report.planned_write_count, 2);
    assert_eq!(report.blocked_count, 2);
    assert!(
        report
            .planned_writes
            .iter()
            .any(|write| write.destination_type == "heartRate")
    );
    assert!(
        report
            .planned_writes
            .iter()
            .any(|write| write.destination_type == "heartRateVariabilitySDNN")
    );
    assert!(report.blocked_records.iter().any(|record| {
        record
            .reasons
            .contains(&"healthkit_rmssd_must_not_be_written_as_sdnn".to_string())
    }));
    assert!(report.blocked_records.iter().any(|record| {
        record
            .reasons
            .contains(&"benchmark_only_algorithm_not_syncable".to_string())
    }));
}

#[test]
fn health_connect_maps_rmssd_to_rmssd_record() {
    let input = input_with_candidates(
        HealthPlatform::HealthConnect,
        vec!["HeartRateVariabilityRmssdRecord".to_string()],
        vec![candidate("hrv-rmssd-1", "hrv", "hrv_rmssd", "ms")],
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert!(report.input_valid);
    assert!(report.all_candidate_writes_planned);
    assert!(report.all_requested_deletes_planned);
    assert!(report.all_records_ready);
    assert!(report.permissions_ready);
    assert!(report.mappings_ready);
    assert!(report.units_ready);
    assert!(report.provenance_ready);
    assert!(report.source_policy_ready);
    assert!(report.idempotency_ready);
    assert!(report.cleanup_scope_ready);
    assert_eq!(report.planned_write_count, 1);
    assert_eq!(
        report.planned_writes[0].destination_type,
        "HeartRateVariabilityRmssdRecord"
    );
    assert_eq!(report.planned_writes[0].unit, "ms");
}

#[test]
fn health_sync_maps_steps_and_active_energy_where_platform_supported() {
    let healthkit = run_health_sync_dry_run(&input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["stepCount".to_string(), "activeEnergyBurned".to_string()],
        vec![
            candidate("steps-1", "activity", "steps", "count"),
            candidate("active-energy-1", "activity", "active_energy", "kcal"),
        ],
    ));
    assert!(healthkit.pass);
    assert_eq!(healthkit.planned_write_count, 2);
    assert!(
        healthkit
            .planned_writes
            .iter()
            .any(|write| write.destination_type == "stepCount")
    );
    assert!(
        healthkit
            .planned_writes
            .iter()
            .any(|write| write.destination_type == "activeEnergyBurned")
    );

    let health_connect = run_health_sync_dry_run(&input_with_candidates(
        HealthPlatform::HealthConnect,
        vec![
            "StepsRecord".to_string(),
            "ActiveCaloriesBurnedRecord".to_string(),
        ],
        vec![
            candidate("steps-2", "activity", "steps", "count"),
            candidate("active-energy-2", "activity", "active_energy", "kcal"),
        ],
    ));
    assert!(health_connect.pass);
    assert_eq!(health_connect.planned_write_count, 2);
    assert!(health_connect.planned_writes.iter().any(|write| {
        write.destination_type == "StepsRecord"
            && write.goose_marker == "goose:activity:goose.test.v0:steps-2"
    }));
    assert!(
        health_connect
            .planned_writes
            .iter()
            .any(|write| write.destination_type == "ActiveCaloriesBurnedRecord")
    );
}

#[test]
fn activity_health_sync_plans_generic_sessions_for_platforms() {
    let session = activity_session("activity-session-1", "cycling", 0.92, true);
    let healthkit = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![session.clone()],
    ));
    assert!(healthkit.pass);
    assert_eq!(healthkit.planned_session_count, 1);
    assert_eq!(healthkit.blocked_session_count, 0);
    assert_eq!(healthkit.planned_sessions[0].destination_type, "HKWorkout");
    assert_eq!(healthkit.planned_sessions[0].activity_type, "cycling");
    assert_eq!(
        healthkit.planned_sessions[0].destination_activity_type,
        "cycling"
    );
    assert_eq!(healthkit.planned_sessions[0].attached_metric_count, 1);
    assert_eq!(healthkit.planned_sessions[0].attached_interval_count, 1);

    let health_connect = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthConnect,
        vec!["ExerciseSessionRecord".to_string()],
        vec![session],
    ));
    assert!(health_connect.pass);
    assert_eq!(health_connect.planned_session_count, 1);
    assert_eq!(
        health_connect.planned_sessions[0].destination_type,
        "ExerciseSessionRecord"
    );
    assert_eq!(
        health_connect.planned_sessions[0].destination_activity_type,
        "biking"
    );
}

#[test]
fn activity_health_sync_ignores_unsupported_route_metrics_without_broadening_permissions() {
    let mut session = activity_session("activity-session-route-only", "cycling", 0.92, true);
    session.metrics = vec![activity_metric(
        "route",
        1.0,
        "n/a",
        "activity_metric_fixture",
        None,
        None,
    )];
    session.intervals = Vec::new();

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![session],
    ));

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 1);
    assert_eq!(report.blocked_session_count, 0);
    assert_eq!(report.planned_sessions[0].attached_metric_count, 0);
    assert_eq!(report.permission_grants, vec!["HKWorkout".to_string()]);
    assert!(
        !report
            .next_actions
            .iter()
            .any(|action| action.action.contains("Request"))
    );
}

#[test]
fn activity_health_sync_surfaces_out_of_window_metrics_and_intervals_as_ignored() {
    let mut session = activity_session("activity-session-out-of-window", "cycling", 0.92, true);
    // Session window is 06:00:00Z-06:45:00Z; both samples fall outside it.
    session.metrics = vec![activity_metric(
        "heart_rate",
        140.0,
        "count/min",
        "activity_metric_fixture",
        Some("2026-05-27T07:00:00Z"),
        Some("2026-05-27T07:10:00Z"),
    )];
    session.intervals = vec![activity_interval(
        "activity-session-out-of-window-interval-1",
        "lap",
        "2026-05-27T07:00:00Z",
        "2026-05-27T07:10:00Z",
        Vec::new(),
    )];

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![session],
    ));

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 1);
    assert_eq!(report.blocked_session_count, 0);
    assert_eq!(report.planned_sessions[0].attached_metric_count, 0);
    assert_eq!(report.planned_sessions[0].attached_interval_count, 0);
    assert_eq!(report.planned_sessions[0].ignored_metric_count, 1);
    assert_eq!(report.planned_sessions[0].ignored_interval_count, 1);
}

#[test]
fn activity_health_sync_attaches_supported_heart_rate_energy_distance_samples_and_segments() {
    let mut session = activity_session("activity-session-supported", "cycling", 0.94, true);
    session.metrics = vec![
        activity_metric(
            "heart_rate",
            144.0,
            "count/min",
            "activity_metric_fixture",
            None,
            None,
        ),
        activity_metric(
            "active_energy",
            520.0,
            "kcal",
            "activity_metric_fixture",
            None,
            None,
        ),
        activity_metric(
            "distance",
            16.5,
            "km",
            "activity_metric_fixture",
            None,
            None,
        ),
        activity_metric("route", 1.0, "n/a", "activity_metric_fixture", None, None),
    ];
    session.intervals = vec![
        activity_interval(
            "activity-session-supported-interval-1",
            "lap",
            "2026-05-27T06:05:00Z",
            "2026-05-27T06:15:00Z",
            vec![
                activity_metric(
                    "heart_rate",
                    150.0,
                    "bpm",
                    "activity_interval_fixture",
                    None,
                    None,
                ),
                activity_metric(
                    "distance",
                    2.2,
                    "mi",
                    "activity_interval_fixture",
                    None,
                    None,
                ),
                activity_metric("route", 1.0, "n/a", "activity_interval_fixture", None, None),
            ],
        ),
        activity_interval(
            "activity-session-supported-interval-2",
            "split",
            "2026-05-27T06:15:00Z",
            "2026-05-27T06:30:00Z",
            vec![activity_metric(
                "active_energy",
                188.0,
                "kcal",
                "activity_interval_fixture",
                None,
                None,
            )],
        ),
    ];

    let healthkit = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![session.clone()],
    ));
    assert!(healthkit.pass);
    assert_eq!(healthkit.planned_session_count, 1);
    assert_eq!(healthkit.blocked_session_count, 0);
    assert_eq!(healthkit.planned_sessions[0].attached_metric_count, 6);
    assert_eq!(healthkit.planned_sessions[0].attached_interval_count, 2);
    assert_eq!(healthkit.permission_grants, vec!["HKWorkout".to_string()]);
    assert_eq!(
        healthkit.planned_sessions[0].destination_activity_type,
        "cycling"
    );

    let health_connect = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthConnect,
        vec!["ExerciseSessionRecord".to_string()],
        vec![session],
    ));
    assert!(health_connect.pass);
    assert_eq!(health_connect.planned_session_count, 1);
    assert_eq!(health_connect.blocked_session_count, 0);
    assert_eq!(health_connect.planned_sessions[0].attached_metric_count, 6);
    assert_eq!(
        health_connect.planned_sessions[0].attached_interval_count,
        2
    );
    assert_eq!(
        health_connect.planned_sessions[0].destination_activity_type,
        "biking"
    );
}

#[test]
fn activity_health_sync_blocks_supported_metrics_with_wrong_units_without_requesting_permissions() {
    let mut session = activity_session("activity-session-bad-unit", "cycling", 0.93, true);
    session.metrics = vec![activity_metric(
        "heart_rate",
        142.0,
        "count",
        "activity_metric_fixture",
        None,
        None,
    )];
    session.intervals = Vec::new();

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![session],
    ));

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 0);
    assert_eq!(report.blocked_session_count, 1);
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"unit_mismatch_expected_count_per_min".to_string())
    );
    assert_eq!(report.permission_grants, vec!["HKWorkout".to_string()]);
    assert!(
        !report
            .next_actions
            .iter()
            .any(|action| action.action.contains("Request"))
    );
}

#[test]
fn activity_health_sync_maps_workout_and_sleep_session_candidates() {
    let mut workout = activity_session("workout-session-1", "strength", 0.95, true);
    workout.session_kind = HealthSyncSessionKind::Workout;
    workout.source_kind = "workout_session".to_string();
    let sleep = sleep_session("sleep-session-1");

    let healthkit = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string(), "sleepAnalysis".to_string()],
        vec![workout.clone(), sleep.clone()],
    ));
    assert!(healthkit.pass);
    assert_eq!(healthkit.planned_session_count, 2);
    assert!(healthkit.planned_sessions.iter().any(|session| {
        session.session_kind == HealthSyncSessionKind::Workout
            && session.destination_type == "HKWorkout"
            && session.destination_activity_type == "strength_training"
    }));
    assert!(healthkit.planned_sessions.iter().any(|session| {
        session.session_kind == HealthSyncSessionKind::Sleep
            && session.destination_type == "sleepAnalysis"
            && session.destination_activity_type == "sleep"
    }));

    let health_connect = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthConnect,
        vec![
            "ExerciseSessionRecord".to_string(),
            "SleepSessionRecord".to_string(),
        ],
        vec![workout, sleep],
    ));
    assert!(health_connect.pass);
    assert_eq!(health_connect.planned_session_count, 2);
    assert!(health_connect.planned_sessions.iter().any(|session| {
        session.session_kind == HealthSyncSessionKind::Workout
            && session.destination_type == "ExerciseSessionRecord"
    }));
    assert!(health_connect.planned_sessions.iter().any(|session| {
        session.session_kind == HealthSyncSessionKind::Sleep
            && session.destination_type == "SleepSessionRecord"
    }));
}

#[test]
fn activity_health_sync_keeps_imported_platform_sleep_external() {
    let mut imported = sleep_session("imported-healthkit-sleep-1");
    imported.source_kind = "sleep_session".to_string();
    imported.provenance = json!({
        "source": "healthkit_sleep_analysis",
        "platform": "healthkit",
        "platform_record_id": "HK-sleep-1",
        "import_policy": "external_history_context_only"
    });

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["sleepAnalysis".to_string()],
        vec![imported],
    ));

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 0);
    assert_eq!(report.blocked_session_count, 1);
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"imported_platform_sleep_not_syncable".to_string())
    );
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"platform_import_not_syncable".to_string())
    );
}

#[test]
fn activity_health_sync_blocks_platform_imported_sessions_and_metrics() {
    let mut imported_session =
        activity_session("imported-healthkit-workout-1", "walking", 0.92, true);
    imported_session.provenance = json!({
        "source": "healthkit_workout",
        "platform": "healthkit",
        "platform_record_id": "HK-workout-1"
    });

    let mut metric_import =
        activity_session("activity-with-healthkit-metric", "walking", 0.92, true);
    metric_import.metrics = vec![activity_metric(
        "heart_rate",
        120.0,
        "count/min",
        "healthkit",
        None,
        None,
    )];
    metric_import.intervals = Vec::new();

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![imported_session, metric_import],
    ));

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 0);
    assert_eq!(report.blocked_session_count, 2);
    assert!(report.blocked_sessions.iter().any(|session| {
        session.session_id == "imported-healthkit-workout-1"
            && session
                .reasons
                .contains(&"platform_import_not_syncable".to_string())
    }));
    assert!(report.blocked_sessions.iter().any(|session| {
        session.session_id == "activity-with-healthkit-metric"
            && session
                .reasons
                .contains(&"platform_import_not_syncable".to_string())
    }));
}

#[test]
fn activity_health_sync_blocks_candidate_sessions_without_approval() {
    let input = activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![activity_session(
            "activity-candidate-1",
            "unknown",
            0.61,
            false,
        )],
    );
    let report = run_activity_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 0);
    assert_eq!(report.blocked_session_count, 1);
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"candidate_activity_requires_user_approval".to_string())
    );
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"not_user_approved".to_string())
    );
}

#[test]
fn activity_health_sync_permission_scope_is_session_destination_only() {
    let input = activity_input(
        HealthPlatform::HealthConnect,
        Vec::new(),
        vec![activity_session(
            "activity-session-2",
            "strength",
            0.95,
            true,
        )],
    );
    let report = run_activity_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_session_count, 0);
    assert_eq!(report.blocked_session_count, 1);
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"permission_denied".to_string())
    );
    assert!(report.next_actions.iter().any(|action| {
        action.scope == "activity-session-2"
            && action
                .action
                .contains("Request ExerciseSessionRecord permission")
    }));
}

#[test]
fn permission_denial_blocks_without_losing_candidate_context() {
    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        Vec::new(),
        vec![candidate("hr-1", "heart_rate", "heart_rate", "count/min")],
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert!(report.input_valid);
    assert!(!report.all_candidate_writes_planned);
    assert!(report.all_requested_deletes_planned);
    assert!(!report.all_records_ready);
    assert!(!report.permissions_ready);
    assert!(report.mappings_ready);
    assert!(report.units_ready);
    assert!(report.provenance_ready);
    assert!(report.source_policy_ready);
    assert!(report.idempotency_ready);
    assert!(report.cleanup_scope_ready);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(report.blocked_records[0].source_record_id, "hr-1");
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"permission_denied".to_string())
    );
    assert!(report.blocked_records[0].next_actions.iter().any(|action| {
        action.scope == "hr-1"
            && action.reason == "permission_denied"
            && action.action.contains("Request heartRate permission")
    }));
    assert!(report.next_actions.iter().any(|action| {
        action.scope == "hr-1" && action.action.contains("Request heartRate permission")
    }));
}

#[test]
fn dry_run_report_preserves_explicit_permission_grants_without_writes() {
    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["restingHeartRate".to_string(), "heartRate".to_string()],
        Vec::new(),
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(
        report.permission_grants,
        vec!["heartRate".to_string(), "restingHeartRate".to_string()]
    );
}

#[test]
fn backfill_window_is_half_open() {
    let mut inside = candidate("inside", "heart_rate", "heart_rate", "count/min");
    inside.start_time = "2026-05-27T23:59:59Z".to_string();
    inside.end_time = "2026-05-28T00:00:00Z".to_string();
    let mut outside = candidate("outside", "heart_rate", "heart_rate", "count/min");
    outside.start_time = "2026-05-28T00:00:00Z".to_string();
    outside.end_time = "2026-05-28T00:00:05Z".to_string();

    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![inside, outside],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 1);
    assert_eq!(report.blocked_count, 1);
    assert_eq!(report.planned_writes[0].source_record_id, "inside");
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"outside_backfill_window".to_string())
    );
}

#[test]
fn health_sync_compares_timestamps_as_utc_instants() {
    let mut candidate = candidate("offset-inside", "heart_rate", "heart_rate", "count/min");
    candidate.start_time = "2026-05-26T23:30:00.250Z".to_string();
    candidate.end_time = "2026-05-26T23:30:01+00:00".to_string();
    let mut input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![candidate],
    );
    input.backfill = HealthSyncWindow {
        start: "2026-05-27T00:00:00+01:00".to_string(),
        end: "2026-05-27T01:00:00+01:00".to_string(),
    };

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.planned_write_count, 1);
    assert_eq!(report.blocked_count, 0);
    assert_eq!(report.planned_writes[0].source_record_id, "offset-inside");
}

#[test]
fn health_sync_blocks_malformed_timestamps() {
    let mut candidate = candidate("bad-time", "heart_rate", "heart_rate", "count/min");
    candidate.start_time = "2026-05-27 00:00:00".to_string();
    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![candidate],
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(report.blocked_count, 1);
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"start_time_invalid_timestamp".to_string())
    );

    let mut input = input_with_candidates(HealthPlatform::HealthKit, Vec::new(), Vec::new());
    input.backfill.start = "not-a-timestamp".to_string();
    let report = run_health_sync_dry_run(&input);

    assert!(!report.pass);
    assert!(
        report
            .issues
            .contains(&"backfill.start_invalid_timestamp".to_string())
    );
}

#[test]
fn partial_plan_policy_can_require_all_records_before_platform_writes() {
    let mut input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![
            candidate("hr-ready", "heart_rate", "heart_rate", "count/min"),
            candidate("rmssd-blocked", "hrv", "hrv_rmssd", "ms"),
        ],
    );
    input.partial_plan_policy = HealthSyncPartialPlanPolicy::RequireAllRecordsReady;

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(
        report.partial_plan_policy,
        HealthSyncPartialPlanPolicy::RequireAllRecordsReady
    );
    assert!(report.partial_plan);
    assert!(!report.partial_plan_confirmation_required);
    assert!(report.platform_write_blocked_by_partial_plan);
    assert!(report.next_actions.iter().any(|action| {
        action.scope == "health_sync_report" && action.reason == "partial_plan_blocked_by_policy"
    }));
}

#[test]
fn unsafe_sources_and_missing_provenance_are_blocked() {
    let mut official_label = candidate("label", "recovery", "resting_heart_rate", "count/min");
    official_label.source_kind = "official_label".to_string();
    let mut missing_provenance = candidate("missing", "heart_rate", "heart_rate", "count/min");
    missing_provenance.provenance = serde_json::Value::Null;

    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string(), "restingHeartRate".to_string()],
        vec![official_label, missing_provenance],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert!(!report.provenance_ready);
    assert!(!report.source_policy_ready);
    assert!(
        report
            .blocked_records
            .iter()
            .any(|record| record.reasons.contains(&"unsafe_source_kind".to_string()))
    );
    assert!(
        report
            .blocked_records
            .iter()
            .any(|record| record.reasons.contains(&"missing_provenance".to_string()))
    );
}

#[test]
fn platform_import_provenance_is_blocked_for_metric_candidates() {
    let mut imported_steps = candidate("hk-steps", "activity", "steps", "count");
    imported_steps.source_kind = "user_approved_algorithm".to_string();
    imported_steps.provenance = json!({
        "source": "healthkit",
        "platform_record_id": "HK-step-count-1",
        "import_policy": "external_history_context_only"
    });

    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["stepCount".to_string()],
        vec![imported_steps],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(report.blocked_count, 1);
    assert!(!report.provenance_ready);
    assert!(!report.source_policy_ready);
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"platform_import_not_syncable".to_string())
    );
    assert!(report.blocked_records[0].next_actions.iter().any(|action| {
        action.reason == "platform_import_not_syncable"
            && action
                .action
                .contains("Keep HealthKit and Health Connect values out")
    }));
}

#[test]
fn private_api_and_official_whoop_label_provenance_are_blocked() {
    let mut private_api = candidate("private-api", "heart_rate", "heart_rate", "count/min");
    private_api.source_kind = "local_derived".to_string();
    private_api.provenance = json!({
        "source": "private_api_replay",
        "run_id": "private-api"
    });

    let mut official_label = candidate(
        "official-label",
        "recovery",
        "resting_heart_rate",
        "count/min",
    );
    official_label.source_kind = "user_approved_algorithm".to_string();
    official_label.provenance = json!({
        "label_source": "whoop_official",
        "record_id": "official-label"
    });

    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string(), "restingHeartRate".to_string()],
        vec![private_api, official_label],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert!(!report.provenance_ready);
    assert!(!report.source_policy_ready);
    assert!(report.blocked_records.iter().any(|record| {
        record.source_record_id == "private-api"
            && record
                .reasons
                .contains(&"private_api_provenance_not_syncable".to_string())
    }));
    assert!(report.blocked_records.iter().any(|record| {
        record.source_record_id == "official-label"
            && record
                .reasons
                .contains(&"official_whoop_label_not_syncable".to_string())
    }));
}

#[test]
fn health_sync_provenance_must_be_non_empty_object() {
    let mut string_provenance =
        candidate("string-provenance", "heart_rate", "heart_rate", "count/min");
    string_provenance.provenance = json!("manual-note");

    let mut array_provenance =
        candidate("array-provenance", "heart_rate", "heart_rate", "count/min");
    array_provenance.provenance = json!(["manual-note"]);

    let mut empty_object = candidate("empty-object", "heart_rate", "heart_rate", "count/min");
    empty_object.provenance = json!({});

    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![string_provenance, array_provenance, empty_object],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(report.blocked_count, 3);
    assert!(!report.provenance_ready);
    assert!(report.source_policy_ready);
    assert!(report.blocked_records.iter().any(|record| {
        record.source_record_id == "string-provenance"
            && record
                .reasons
                .contains(&"provenance_must_be_object".to_string())
    }));
    assert!(report.blocked_records.iter().any(|record| {
        record.source_record_id == "array-provenance"
            && record
                .reasons
                .contains(&"provenance_must_be_object".to_string())
    }));
    assert!(report.blocked_records.iter().any(|record| {
        record.source_record_id == "empty-object"
            && record.reasons.contains(&"missing_provenance".to_string())
    }));
}

#[test]
fn benchmark_only_algorithm_outputs_are_blocked_even_when_user_approved() {
    let mut benchmark_candidate = candidate("reference-hrv", "hrv", "hrv_rmssd", "ms");
    benchmark_candidate.algorithm_id = Some("reference.hrv.time_domain.v1".to_string());
    benchmark_candidate.algorithm_version = Some("1.0.0".to_string());
    benchmark_candidate.provenance = json!({
        "run_id": "reference-hrv-run",
        "algorithm_status": "benchmark-only"
    });

    let input = input_with_candidates(
        HealthPlatform::HealthConnect,
        vec!["HeartRateVariabilityRmssdRecord".to_string()],
        vec![benchmark_candidate],
    );
    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert_eq!(report.blocked_count, 1);
    assert!(report.provenance_ready);
    assert!(!report.source_policy_ready);
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"benchmark_only_algorithm_not_syncable".to_string())
    );
}

#[test]
fn duplicate_idempotency_keys_are_de_duplicated() {
    let first = candidate("same", "heart_rate", "heart_rate", "count/min");
    let second = candidate("same", "heart_rate", "heart_rate", "count/min");
    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![first, second],
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 1);
    assert_eq!(report.blocked_count, 1);
    assert!(!report.idempotency_ready);
    assert!(
        report.blocked_records[0]
            .reasons
            .contains(&"duplicate_idempotency_key".to_string())
    );
}

#[test]
fn duplicate_activity_sessions_are_de_duplicated_even_when_session_ids_change() {
    let mut first = activity_session("session-a", "running", 0.92, true);
    first.raw_activity_type = Some("Running".to_string());
    first.custom_label = Some("Morning Tempo Run".to_string());
    first.provenance = json!({
        "source": "activity_session_fixture",
        "nested": {
            "alpha": 1,
            "beta": 2
        },
        "activity_session_id": "stable-session-source"
    });

    let mut second = activity_session("session-b", "running", 0.92, true);
    second.raw_activity_type = Some(" running ".to_string());
    second.custom_label = Some(" morning tempo run ".to_string());
    second.provenance = json!({
        "activity_session_id": "stable-session-source",
        "nested": {
            "beta": 2,
            "alpha": 1
        },
        "source": "activity_session_fixture"
    });
    let expected_key = activity_idempotency_key(&activity_identity_input(&first));
    assert_eq!(
        expected_key,
        activity_idempotency_key(&activity_identity_input(&second))
    );

    let input = activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![first, second],
    );

    let report = run_activity_health_sync_dry_run(&input);

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.planned_session_count, 1);
    assert_eq!(report.blocked_session_count, 1);
    assert_eq!(report.planned_sessions[0].idempotency_key, expected_key);
    assert_eq!(report.planned_sessions[0].session_id, "session-a");
    assert_eq!(report.blocked_sessions[0].session_id, "session-b");
    assert!(
        report.blocked_sessions[0]
            .reasons
            .contains(&"duplicate_idempotency_key".to_string())
    );
}

#[test]
fn activity_session_idempotency_changes_when_source_window_or_type_change() {
    let mut source_changed = activity_session("session-base", "running", 0.92, true);
    source_changed.source_kind = "manual_activity".to_string();

    let mut window_changed = activity_session("session-base", "running", 0.92, true);
    window_changed.end_time = "2026-05-27T06:50:00Z".to_string();

    let mut type_changed = activity_session("session-base", "cycling", 0.92, true);
    type_changed.raw_activity_type = Some("running".to_string());

    let base = activity_session("session-base", "running", 0.92, true);
    let base_key = activity_idempotency_key(&activity_identity_input(&base));
    let source_key = activity_idempotency_key(&activity_identity_input(&source_changed));
    let window_key = activity_idempotency_key(&activity_identity_input(&window_changed));
    let type_key = activity_idempotency_key(&activity_identity_input(&type_changed));

    assert_ne!(base_key, source_key);
    assert_ne!(base_key, window_key);
    assert_ne!(base_key, type_key);

    let report = run_activity_health_sync_dry_run(&activity_input(
        HealthPlatform::HealthKit,
        vec!["HKWorkout".to_string()],
        vec![base, source_changed, window_changed, type_changed],
    ));

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.planned_session_count, 4);
    assert_eq!(report.blocked_session_count, 0);
    assert_eq!(
        report
            .planned_sessions
            .iter()
            .map(|write| write.idempotency_key.as_str())
            .collect::<Vec<_>>(),
        vec![
            base_key.as_str(),
            source_key.as_str(),
            window_key.as_str(),
            type_key.as_str(),
        ]
    );
}

#[test]
fn stale_goose_records_inside_backfill_are_planned_for_delete() {
    let current = candidate("current", "heart_rate", "heart_rate", "count/min");
    let input = HealthSyncDryRunInput {
        delete_policy: HealthSyncDeletePolicy::StaleInBackfill,
        existing_records: vec![
            existing_record(
                "stale-platform-record",
                "heartRate",
                "goose:HealthKit:heartRate:old:2026-05-27T01:00:00Z:2026-05-27T01:05:00Z",
                "goose:heart_rate:goose.test.v0:old",
                "2026-05-27T01:00:00Z",
                "2026-05-27T01:05:00Z",
            ),
            existing_record(
                "current-platform-record",
                "heartRate",
                "goose:HealthKit:heartRate:current:2026-05-27T00:00:00Z:2026-05-27T00:05:00Z",
                "goose:heart_rate:goose.test.v0:current",
                "2026-05-27T00:00:00Z",
                "2026-05-27T00:05:00Z",
            ),
        ],
        ..input_with_candidates(
            HealthPlatform::HealthKit,
            vec!["heartRate".to_string()],
            vec![current],
        )
    };

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.planned_write_count, 1);
    assert_eq!(report.existing_record_count, 2);
    assert_eq!(report.planned_delete_count, 1);
    assert_eq!(report.blocked_delete_count, 0);
    assert_eq!(
        report.planned_deletes[0].platform_record_id,
        "stale-platform-record"
    );
    assert_eq!(
        report.planned_deletes[0].reason,
        "stale_goose_record_in_backfill"
    );
}

#[test]
fn delete_planning_blocks_non_goose_external_or_unsupported_records() {
    let input = HealthSyncDryRunInput {
        delete_policy: HealthSyncDeletePolicy::StaleInBackfill,
        existing_records: vec![
            existing_record(
                "external-platform-record",
                "heartRate",
                "apple:external",
                "apple:external",
                "2026-05-27T01:00:00Z",
                "2026-05-27T01:05:00Z",
            ),
            existing_record(
                "unsupported-platform-record",
                "WorkoutRoute",
                "goose:HealthKit:WorkoutRoute:old:2026-05-27T01:00:00Z:2026-05-27T01:05:00Z",
                "goose:route:goose.test.v0:old",
                "2026-05-27T01:00:00Z",
                "2026-05-27T01:05:00Z",
            ),
            existing_record(
                "outside-platform-record",
                "heartRate",
                "goose:HealthKit:heartRate:outside:2026-05-28T01:00:00Z:2026-05-28T01:05:00Z",
                "goose:heart_rate:goose.test.v0:outside",
                "2026-05-28T01:00:00Z",
                "2026-05-28T01:05:00Z",
            ),
        ],
        ..input_with_candidates(HealthPlatform::HealthKit, Vec::new(), Vec::new())
    };

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.planned_delete_count, 0);
    assert_eq!(report.blocked_delete_count, 3);
    assert!(!report.permissions_ready);
    assert!(!report.mappings_ready);
    assert!(!report.cleanup_scope_ready);
    assert!(report.blocked_deletes.iter().any(|record| {
        record.platform_record_id == "external-platform-record"
            && record.reasons.contains(&"not_goose_owned".to_string())
    }));
    assert!(report.blocked_deletes.iter().any(|record| {
        record.platform_record_id == "unsupported-platform-record"
            && record
                .reasons
                .contains(&"unsupported_delete_mapping".to_string())
    }));
    assert!(report.blocked_deletes.iter().any(|record| {
        record.platform_record_id == "outside-platform-record"
            && record
                .reasons
                .contains(&"outside_backfill_window".to_string())
    }));
}

#[test]
fn unit_mismatch_blocks_record() {
    let input = input_with_candidates(
        HealthPlatform::HealthKit,
        vec!["heartRate".to_string()],
        vec![candidate(
            "hr-wrong-unit",
            "heart_rate",
            "heart_rate",
            "bpm",
        )],
    );

    let report = run_health_sync_dry_run(&input);

    assert!(report.pass);
    assert_eq!(report.planned_write_count, 0);
    assert!(!report.units_ready);
    assert!(
        report.blocked_records[0]
            .reasons
            .iter()
            .any(|reason| reason.starts_with("unit_mismatch"))
    );
    assert!(report.blocked_records[0].next_actions.iter().any(|action| {
        action.reason == "unit_mismatch_expected_count_per_min"
            && action.action.contains("count/min")
    }));
}

#[test]
fn dry_run_report_next_actions_cover_report_and_cleanup_blockers() {
    let input = HealthSyncDryRunInput {
        schema: "goose.health-sync-dry-run.v1".to_string(),
        platform: HealthPlatform::HealthKit,
        permission_grants: Vec::new(),
        backfill: HealthSyncWindow {
            start: "2026-05-28T00:00:00Z".to_string(),
            end: "2026-05-27T00:00:00Z".to_string(),
        },
        candidates: Vec::new(),
        partial_plan_policy: HealthSyncPartialPlanPolicy::AllowPlannedRowsAfterConfirmation,
        delete_policy: HealthSyncDeletePolicy::StaleInBackfill,
        existing_records: vec![existing_record(
            "external-platform-record",
            "heartRate",
            "apple:external",
            "apple:external",
            "2026-05-27T01:00:00Z",
            "2026-05-27T01:05:00Z",
        )],
    };

    let report = run_health_sync_dry_run(&input);

    assert!(!report.pass);
    assert!(!report.input_valid);
    assert!(report.all_candidate_writes_planned);
    assert!(!report.all_requested_deletes_planned);
    assert!(!report.all_records_ready);
    assert!(!report.permissions_ready);
    assert!(report.mappings_ready);
    assert!(report.units_ready);
    assert!(report.provenance_ready);
    assert!(report.source_policy_ready);
    assert!(report.idempotency_ready);
    assert!(!report.cleanup_scope_ready);
    assert!(
        report
            .next_actions
            .iter()
            .any(|action| action.reason == "backfill.start must be earlier than backfill.end")
    );
    let blocked_delete = report
        .blocked_deletes
        .iter()
        .find(|delete| delete.platform_record_id == "external-platform-record")
        .unwrap();
    assert!(blocked_delete.next_actions.iter().any(|action| {
        action.reason == "not_goose_owned" && action.action.contains("Do not delete external")
    }));
    assert!(report.next_actions.iter().any(|action| {
        action.scope == "external-platform-record"
            && action.reason == "not_goose_owned"
            && action.action.contains("Do not delete external")
    }));
}

#[test]
fn health_sync_cli_report_separates_valid_input_from_partial_plan() {
    let input_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/synthetic/health_sync_dry_run_healthkit.json");

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_goose-health-sync-dry-run"))
        .arg("--input")
        .arg(input_path)
        .output()
        .unwrap();

    assert!(output.status.success(), "{output:?}");
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["pass"], true);
    assert_eq!(report["input_valid"], true);
    assert_eq!(report["all_candidate_writes_planned"], false);
    assert_eq!(report["all_requested_deletes_planned"], true);
    assert_eq!(report["all_records_ready"], false);
    assert_eq!(
        report["partial_plan_policy"],
        "allow_planned_rows_after_confirmation"
    );
    assert_eq!(report["partial_plan"], true);
    assert_eq!(report["partial_plan_confirmation_required"], true);
    assert_eq!(report["platform_write_blocked_by_partial_plan"], false);
    assert_eq!(report["permissions_ready"], true);
    assert_eq!(report["mappings_ready"], false);
    assert_eq!(report["units_ready"], true);
    assert_eq!(report["provenance_ready"], true);
    assert_eq!(report["source_policy_ready"], false);
    assert_eq!(report["idempotency_ready"], true);
    assert_eq!(report["cleanup_scope_ready"], true);
    assert_eq!(report["planned_write_count"], 2);
    assert_eq!(report["blocked_count"], 2);
}

fn input_with_candidates(
    platform: HealthPlatform,
    permission_grants: Vec<String>,
    candidates: Vec<HealthSyncCandidate>,
) -> HealthSyncDryRunInput {
    HealthSyncDryRunInput {
        schema: "goose.health-sync-dry-run.v1".to_string(),
        platform,
        permission_grants,
        backfill: HealthSyncWindow {
            start: "2026-05-27T00:00:00Z".to_string(),
            end: "2026-05-28T00:00:00Z".to_string(),
        },
        candidates,
        partial_plan_policy: HealthSyncPartialPlanPolicy::AllowPlannedRowsAfterConfirmation,
        delete_policy: HealthSyncDeletePolicy::None,
        existing_records: Vec::new(),
    }
}

fn activity_input(
    platform: HealthPlatform,
    permission_grants: Vec<String>,
    sessions: Vec<ActivitySyncCandidate>,
) -> ActivityHealthSyncDryRunInput {
    ActivityHealthSyncDryRunInput {
        schema: "goose.activity-health-sync-dry-run.v1".to_string(),
        platform,
        permission_grants,
        backfill: HealthSyncWindow {
            start: "2026-05-27T00:00:00Z".to_string(),
            end: "2026-05-28T00:00:00Z".to_string(),
        },
        sessions,
        partial_plan_policy: HealthSyncPartialPlanPolicy::AllowPlannedRowsAfterConfirmation,
    }
}

fn activity_identity_input(session: &ActivitySyncCandidate) -> ActivityIdentityInput {
    ActivityIdentityInput {
        source: session.source_kind.clone(),
        provenance: session.provenance.clone(),
        start_time: session.start_time.clone(),
        end_time: session.end_time.clone(),
        activity_type: session.activity_type.clone(),
        raw_identifiers: Vec::new(),
        labels: session
            .raw_activity_type
            .iter()
            .chain(session.custom_label.iter())
            .cloned()
            .collect(),
    }
}

fn activity_session(
    session_id: &str,
    activity_type: &str,
    confidence_0_to_1: f64,
    approved_by_user: bool,
) -> ActivitySyncCandidate {
    ActivitySyncCandidate {
        session_id: session_id.to_string(),
        session_kind: HealthSyncSessionKind::Activity,
        activity_type: activity_type.to_string(),
        raw_activity_type: Some(activity_type.to_string()),
        custom_label: None,
        source_kind: "activity_session".to_string(),
        start_time: "2026-05-27T06:00:00Z".to_string(),
        end_time: "2026-05-27T06:45:00Z".to_string(),
        confidence_0_to_1,
        approved_by_user,
        metrics: vec![
            ActivitySyncMetric {
                name: "average_heart_rate".to_string(),
                value: 142.0,
                unit: "count/min".to_string(),
                start_time: None,
                end_time: None,
                quality_flags: vec!["trusted_packet_derived".to_string()],
                provenance: json!({"source": "activity_metric_fixture"}),
            },
            ActivitySyncMetric {
                name: "strain".to_string(),
                value: 7.4,
                unit: "score_0_to_21".to_string(),
                start_time: None,
                end_time: None,
                quality_flags: Vec::new(),
                provenance: json!({"source": "activity_metric_fixture"}),
            },
        ],
        intervals: vec![ActivitySyncInterval {
            interval_id: format!("{session_id}-interval-1"),
            kind: "work".to_string(),
            start_time: "2026-05-27T06:05:00Z".to_string(),
            end_time: "2026-05-27T06:15:00Z".to_string(),
            metrics: Vec::new(),
            provenance: json!({"source": "activity_interval_fixture"}),
        }],
        provenance: json!({
            "source": "activity_session_fixture",
            "activity_session_id": session_id
        }),
    }
}

fn sleep_session(session_id: &str) -> ActivitySyncCandidate {
    ActivitySyncCandidate {
        session_id: session_id.to_string(),
        session_kind: HealthSyncSessionKind::Sleep,
        activity_type: "sleep".to_string(),
        raw_activity_type: Some("sleep".to_string()),
        custom_label: None,
        source_kind: "sleep_session".to_string(),
        start_time: "2026-05-27T22:00:00Z".to_string(),
        end_time: "2026-05-28T06:30:00Z".to_string(),
        confidence_0_to_1: 0.91,
        approved_by_user: true,
        metrics: Vec::new(),
        intervals: Vec::new(),
        provenance: json!({
            "source": "sleep_session_fixture",
            "sleep_session_id": session_id
        }),
    }
}

fn activity_metric(
    name: &str,
    value: f64,
    unit: &str,
    provenance_source: &str,
    start_time: Option<&str>,
    end_time: Option<&str>,
) -> ActivitySyncMetric {
    ActivitySyncMetric {
        name: name.to_string(),
        value,
        unit: unit.to_string(),
        start_time: start_time.map(str::to_string),
        end_time: end_time.map(str::to_string),
        quality_flags: Vec::new(),
        provenance: json!({"source": provenance_source}),
    }
}

fn activity_interval(
    interval_id: &str,
    kind: &str,
    start_time: &str,
    end_time: &str,
    metrics: Vec<ActivitySyncMetric>,
) -> ActivitySyncInterval {
    ActivitySyncInterval {
        interval_id: interval_id.to_string(),
        kind: kind.to_string(),
        start_time: start_time.to_string(),
        end_time: end_time.to_string(),
        metrics,
        provenance: json!({"source": "activity_interval_fixture"}),
    }
}

fn candidate(
    record_id: &str,
    metric_family: &str,
    semantic: &str,
    unit: &str,
) -> HealthSyncCandidate {
    HealthSyncCandidate {
        record_id: record_id.to_string(),
        metric_family: metric_family.to_string(),
        semantic: semantic.to_string(),
        source_kind: "user_approved_algorithm".to_string(),
        start_time: "2026-05-27T00:00:00Z".to_string(),
        end_time: "2026-05-27T00:05:00Z".to_string(),
        value: 60.0,
        unit: unit.to_string(),
        algorithm_id: Some("goose.test.v0".to_string()),
        algorithm_version: Some("0.1.0".to_string()),
        approved_by_user: true,
        provenance: json!({"run_id": record_id}),
    }
}

fn existing_record(
    platform_record_id: &str,
    destination_type: &str,
    idempotency_key: &str,
    goose_marker: &str,
    start_time: &str,
    end_time: &str,
) -> ExistingHealthRecord {
    ExistingHealthRecord {
        platform_record_id: platform_record_id.to_string(),
        destination_type: destination_type.to_string(),
        idempotency_key: idempotency_key.to_string(),
        goose_marker: goose_marker.to_string(),
        start_time: start_time.to_string(),
        end_time: end_time.to_string(),
        provenance: json!({"source": "platform_snapshot"}),
    }
}
