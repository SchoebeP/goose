import Foundation

@MainActor
enum CoachLocalToolContext {
  static func build(
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) -> [String: Any] {
    let tools: [String: Any] = [
      "load_stats": loadStats(healthStore: healthStore, appModel: appModel),
      "get_activities": activities(appModel: appModel),
      "get_capture_sessions": captureSessions(appModel: appModel),
      "get_raw_session_data": rawSessionData(healthStore: healthStore, appModel: appModel),
    ]

    return [
      "generated_at": timestamp(Date()),
      "tool_count": tools.count,
      "tools": tools,
    ]
  }

  private static func loadStats(
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) -> [String: Any] {
    [
      "readiness": [
        "input": healthStore.metricInputReadinessSummary(),
        "next_action": healthStore.metricInputReadinessNextActionSummary(),
        "packet_feature_next_action": healthStore.packetDerivedFeatureNextActionSummary(),
        "packet_score_next_action": healthStore.packetDerivedScoreNextActionSummary(),
      ],
      "scores": [
        "sleep": healthStore.sleepFeatureScoreSummary(),
        "recovery": healthStore.recoveryFeatureScoreSummary(),
        "strain": healthStore.strainFeatureScoreSummary(),
        "stress": healthStore.stressFeatureScoreSummary(),
      ],
      "score_provenance": [
        "sleep": healthStore.packetScoreProvenanceSummary("sleep"),
        "recovery": healthStore.packetScoreProvenanceSummary("recovery"),
        "strain": healthStore.packetScoreProvenanceSummary("strain"),
        "stress": healthStore.packetScoreProvenanceSummary("stress"),
      ],
      "vitals": vitals(healthStore: healthStore, appModel: appModel),
      "status": [
        "packet_inputs": healthStore.packetInputStatus,
        "packet_scores": healthStore.packetScoreStatus,
        "band_sleep_import": healthStore.bandSleepImportStatus,
        "external_sleep_import": healthStore.externalSleepImportStatus,
      ],
    ]
  }

  private static func vitals(
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) -> [[String: Any]] {
    var rows = healthStore.healthMonitorSnapshots(
      restingHeartRateEstimateBPM: appModel.ble.restingHeartRateEstimateBPM,
      restingHeartRateEstimateSampleCount: appModel.ble.restingHeartRateEstimateSampleCount,
      restingHeartRateEstimateUpdatedAt: appModel.ble.restingHeartRateEstimateUpdatedAt,
      restingHeartRateEstimateSource: appModel.ble.restingHeartRateEstimateSource,
      allowLiveFallbacks: true
    ).map(snapshot)

    rows.insert(
      [
        "id": "live-heart-rate",
        "title": "Live Heart Rate",
        "value": healthStore.latestHeartRateSummary(
          bpm: appModel.ble.liveHeartRateBPM,
          source: appModel.ble.liveHeartRateSource,
          updatedAt: appModel.ble.liveHeartRateUpdatedAt
        ),
        "status": appModel.ble.liveHeartRateBPM == nil ? "Unavailable" : "Trusted",
        "freshness": relativeText(appModel.ble.liveHeartRateUpdatedAt),
        "provenance": healthStore.latestHeartRateProvenanceSummary(source: appModel.ble.liveHeartRateSource),
      ],
      at: 0
    )

    return rows
  }

  private static func activities(appModel: GooseAppModel) -> [String: Any] {
    let session = appModel.activitySession
    return [
      "active_session": [
        "status": session.statusText,
        "activity": session.selectedActivity.title,
        "is_active": session.isActive,
        "is_paused": session.isPaused,
        "started_at": session.startedAt.map(timestamp) ?? NSNull(),
        "elapsed_seconds": Int(session.elapsed.rounded()),
        "average_hr": session.averageHeartRate ?? NSNull(),
        "max_hr": session.maxHeartRate ?? NSNull(),
      ],
      "timeline_status": appModel.homeActivityTimelineStatus,
      "timeline": appModel.homeActivityTimelineItems.prefix(8).map(activityTimelineItem),
      "persistence_status": appModel.activityPersistenceStatus,
      "detection_status": appModel.activityDetectionStatus,
      "movement_packet_status": appModel.movementPacketStatus,
      "movement_validation_status": appModel.movementPacketValidationStatus,
    ]
  }

  private static func captureSessions(appModel: GooseAppModel) -> [String: Any] {
    [
      "packet_import_status": appModel.packetImportStatus,
      "last_parsed_frame": appModel.lastParsedFrameSummary,
      "health_packet_capture": [
        "status": appModel.healthPacketCaptureStatus,
        "session_id": appModel.healthPacketCaptureSessionID ?? NSNull(),
        "started_at": appModel.healthPacketCaptureStartedAt.map(timestamp) ?? NSNull(),
        "frame_count": appModel.healthPacketCaptureFrameCount,
        "target_summary": appModel.healthPacketCaptureTargetSummary,
        "last_packet": appModel.healthPacketCaptureLastPacketSummary,
        "families": appModel.healthPacketCaptureFamilyRows.prefix(12).map(captureFamily),
      ],
      "device_signals": [
        "summary": appModel.liveDeviceDataSummary,
        "recent": appModel.recentDeviceSignalPoints.prefix(8).map(deviceSignal),
      ],
      "overnight_guard": [
        "active": appModel.overnightGuardActive,
        "status": appModel.overnightGuardStatus,
        "readiness": appModel.overnightGuardReadinessSummary,
        "targets": appModel.overnightGuardTargetSummary,
        "last_packet": appModel.overnightGuardLastPacketSummary,
        "spool": appModel.overnightGuardSpoolSizeSummary,
      ],
      "ble": [
        "device": appModel.ble.activeDeviceName,
        "connection_state": appModel.ble.connectionState,
        "historical_sync": appModel.ble.historicalSyncStatus,
        "physiology_capture": appModel.ble.physiologyCaptureStatus,
        "last_physiology_command": appModel.ble.lastPhysiologyCommandSummary,
      ],
    ]
  }

  private static func rawSessionData(
    healthStore: HealthDataStore,
    appModel: GooseAppModel
  ) -> [String: Any] {
    [
      "packet_inputs_status": healthStore.packetInputStatus,
      "packet_scores_status": healthStore.packetScoreStatus,
      "capture_status": captureSessions(appModel: appModel),
      "activity_status": activities(appModel: appModel),
    ]
  }

  private static func snapshot(_ snapshot: HealthMetricSnapshot) -> [String: Any] {
    [
      "id": snapshot.id,
      "title": snapshot.title,
      "value": snapshot.displayValue,
      "status": snapshot.status,
      "freshness": snapshot.freshness,
      "provenance": snapshot.provenance,
      "source": snapshot.source.detail,
    ]
  }

  private static func activityTimelineItem(_ item: ActivityTimelineItem) -> [String: Any] {
    [
      "id": item.id,
      "started_at": timestamp(item.startedAt),
      "title": item.title,
      "activity_type": item.activityType,
      "sync_status": item.syncStatus,
      "duration_seconds": Int(item.durationSeconds.rounded()),
      "distance_meters": item.distanceMeters ?? NSNull(),
      "average_hr": item.averageHeartRate ?? NSNull(),
    ]
  }

  private static func captureFamily(_ family: HealthPacketCaptureFamily) -> [String: Any] {
    [
      "id": family.id,
      "title": family.title,
      "count": family.count,
      "last_seen": timestamp(family.lastSeen),
      "status": family.status.rawValue,
      "detail": family.detail,
    ]
  }

  private static func deviceSignal(_ point: DeviceSignalPoint) -> [String: Any] {
    [
      "id": point.id.uuidString,
      "family": point.family,
      "value": point.value,
      "captured_at": timestamp(point.capturedAt),
      // Strip raw frame hex: uninterpreted band bytes (potentially PPG) stay
      // on-device — the coach backend receives bounded summaries only.
      // The full detail still renders in the local debug UI.
      "detail": point.detail
        .replacingOccurrences(
          of: " body_hex=[0-9a-fA-F]+",
          with: "",
          options: .regularExpression
        )
        .replacingOccurrences(
          of: " raw=\\{[^}]*\\}",
          with: "",
          options: .regularExpression
        ),
    ]
  }

  private static func relativeText(_ date: Date?) -> String {
    guard let date else {
      return "Unavailable"
    }
    return HealthDataStore.relativeText(for: date) ?? timestamp(date)
  }

  private static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
