import Foundation
import UIKit


extension GooseAppModel {
  func startOvernightGuard() {
    ble.record(source: "overnight.guard", title: "start.requested")
    guard !overnightGuardActive else {
      overnightGuardStatus = "Already recording overnight guard"
      refreshOvernightReadiness(reason: "start_already_active")
      return
    }
    guard ble.connectionState == "ready" else {
      overnightGuardStatus = "Connect WHOOP first. Current state: \(ble.connectionState)"
      refreshOvernightReadiness(reason: "start_blocked")
      ble.record(level: .warn, source: "overnight.guard", title: "start.blocked", body: overnightGuardStatus)
      return
    }

    let sessionID = "ios.overnight-guard.\(UUID().uuidString)"
    let startedAt = Date()
    let directoryURL = Self.overnightGuardDirectoryURL(sessionID: sessionID)
    let startPower = Self.currentOvernightPowerState()
    do {
      let snapshot = try overnightRawSpool.start(
        sessionID: sessionID,
        directoryURL: directoryURL,
        metadata: [
          "active_device_name": ble.activeDeviceName,
          "active_device_id": ble.activeDeviceIdentifier?.uuidString ?? NSNull(),
          "connection_state": ble.connectionState,
          "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
          "database_path": HealthDataStore.defaultDatabasePath(),
          "power": startPower.jsonObject,
          "roadmap": "docs/56-overnight-band-sync-roadmap.md",
        ]
      )
      overnightGuardSession = OvernightGuardSession(
        id: sessionID,
        startedAt: startedAt,
        directoryURL: directoryURL,
        rawNotificationsURL: snapshot.rawNotificationsURL
      )
      overnightGuardActive = true
      overnightGuardFinalSyncPending = false
      overnightGuardFinalSyncDrainWorkItem?.cancel()
      overnightGuardFinalSyncDrainWorkItem = nil
      overnightGuardStartedHealthCapture = false
      overnightGuardTargetCounts = OvernightGuardTargetCounts()
      overnightGuardHistoricalOrder = OvernightGuardHistoricalOrderEvidence()
      overnightGuardPowerWarning = nil
      overnightGuardWatchdogWarning = nil
      overnightGuardRawSpoolWarning = nil
      overnightGuardBLELogWarning = nil
      overnightGuardSQLiteMirrorWarning = nil
      overnightGuardWroteInitialRawNotificationStatus = false
      overnightGuardWroteInitialSQLiteMirrorStatus = false
      overnightGuardSQLiteMirrorSummary = "SQLite mirror waiting for first flush"
      overnightGuardWatchdogSummary = "Watchdog waiting for first heartbeat"
      overnightGuardLastRawStaleWarningAt = .distantPast
      overnightGuardLastRangeSuccessWarningAt = .distantPast
      overnightGuardLastTargetMissingWarningAt = .distantPast
      overnightGuardRawNotificationCount = 0
      overnightGuardRangePollCount = 0
      overnightGuardRangeTelemetryCount = 0
      overnightGuardSuccessfulRangePollCount = 0
      overnightGuardCommandWriteCount = 0
      overnightGuardEventLogCount = 0
      overnightGuardTargetSummary = overnightGuardTargetCounts.summary
      overnightGuardHistoricalOrderSummary = overnightGuardHistoricalOrder.summary
      overnightGuardLastPacketSummary = "Waiting for raw BLE notifications"
      overnightGuardSpoolPath = snapshot.rawNotificationsURL?.path ?? directoryURL.path
      overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
      applyOvernightPowerState(startPower)
      overnightGuardExportStatus = "No overnight export"
      overnightGuardExportURL = nil
      overnightGuardExportManifestURL = nil
      overnightGuardExportManifestError = nil
      overnightGuardExportInProgress = false
      overnightGuardCanExportLastSession = false
      overnightGuardStatus = "Recording overnight guard"
      refreshOvernightReadiness(reason: "started", record: true)
      enqueueOvernightSQLiteSession(finalStatus: "active", notes: "started")
      ble.record(source: "overnight.guard", title: "start.ok", body: "\(sessionID) path=\(overnightGuardSpoolPath)")
      ble.record(source: "overnight.guard", title: "power_state", body: "reason=started \(startPower.summary)")

      if activeHealthPacketCapture == nil {
        overnightGuardStartedHealthCapture = true
        startPhysiologyPacketCapture(duration: Self.overnightGuardDuration, source: "overnight_guard")
      } else {
        ble.startPhysiologySignalCapture()
      }
      writeOvernightGuardStatus(reason: "started")
      scheduleOvernightGuardHeartbeat()
      scheduleOvernightGuardRangePoll(after: 8, reason: "startup")
    } catch {
      overnightGuardStatus = "Start failed: \(String(describing: error))"
      refreshOvernightReadiness(reason: "start_failed", record: true)
      ble.record(level: .error, source: "overnight.guard", title: "start.failed", body: overnightGuardStatus)
    }
  }

  func requestOvernightGuardFinalSync() {
    ble.record(source: "overnight.guard", title: "final_sync.requested")
    guard overnightGuardActive else {
      overnightGuardStatus = "Start overnight guard before final sync"
      return
    }
    guard !overnightGuardFinalSyncPending else {
      overnightGuardStatus = "Final sync already running"
      return
    }
    guard ble.canSyncHistorical else {
      overnightGuardStatus = "Final sync blocked: \(ble.historicalSyncStatus)"
      ble.record(level: .warn, source: "overnight.guard", title: "final_sync.blocked", body: overnightGuardStatus)
      writeOvernightGuardStatus(reason: "final_sync_blocked")
      return
    }

    overnightGuardRangePollWorkItem?.cancel()
    overnightGuardRangePollWorkItem = nil
    beginOvernightGuardCriticalBackgroundTask(reason: "final_sync")
    overnightGuardFinalSyncPending = true
    overnightGuardStatus = "Pausing live streams before final historical sync"
    refreshOvernightReadiness(reason: "final_sync_started")
    writeOvernightGuardStatus(reason: "final_sync_started")

    if overnightGuardStartedHealthCapture, activeHealthPacketCapture != nil {
      stopHealthPacketCapture(reason: "overnight_guard_final_sync_live_stream_pause")
      overnightGuardStartedHealthCapture = false
    } else {
      ble.stopPhysiologySignalCapture()
    }
    ble.record(source: "overnight.guard", title: "final_sync.live_stream_pause_requested")

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
      guard let self, self.overnightGuardActive, self.overnightGuardFinalSyncPending else {
        return
      }
      guard self.ble.canSyncHistorical else {
        // Without this cleanup the guard wedges: the pending flag blocks every
        // retry and range poll, streams stay paused, and the critical
        // background task leaks until iOS force-expires it.
        self.overnightGuardFinalSyncPending = false
        self.endOvernightGuardCriticalBackgroundTask(reason: "final_sync_blocked_after_live_stream_pause")
        self.overnightGuardStatus = "Final sync blocked after live-stream pause: \(self.ble.historicalSyncStatus)"
        self.ble.record(level: .warn, source: "overnight.guard", title: "final_sync.blocked_after_live_stream_pause", body: self.overnightGuardStatus)
        self.writeOvernightGuardStatus(reason: "final_sync_blocked_after_live_stream_pause")
        self.resumeOvernightGuardStreamsIfReady(reason: "final_sync_blocked_after_live_stream_pause")
        let retrySessionID = self.overnightGuardSession?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.overnightGuardRangeBlockedRetryInterval) { [weak self] in
          guard let self,
                self.overnightGuardActive,
                !self.overnightGuardFinalSyncPending,
                self.overnightGuardSession?.id == retrySessionID else {
            return
          }
          self.requestOvernightGuardFinalSync()
        }
        return
      }
      self.overnightGuardStatus = "Running final historical sync before export"
      self.refreshOvernightReadiness(reason: "final_sync_history_started")
      self.writeOvernightGuardStatus(reason: "final_sync_history_started")
      self.ble.syncHistoricalPacketsPreservingUnreadQueue(rangeFirst: true)
    }
  }

  func stopOvernightGuard(reason: String = "manual_stop") {
    completeOvernightGuard(reason: reason, stopHealthCapture: true)
  }

  func exportLastOvernightGuardBundle() {
    guard !overnightGuardActive else {
      overnightGuardExportStatus = "Stop or final sync the active guard before exporting"
      return
    }
    guard !overnightGuardExportInProgress else {
      overnightGuardExportStatus = "Final export already running"
      writeOvernightGuardStatus(reason: "last_session_export_already_running")
      ble.record(level: .warn, source: "overnight.guard", title: "last_session_export.already_running")
      return
    }
    guard let sessionID = overnightGuardSession?.id else {
      overnightGuardExportStatus = "No overnight guard session to export"
      return
    }
    beginOvernightGuardCriticalBackgroundTask(reason: "last_session_export")
    do {
      try Self.finalizeRecoveredOvernightGuardSessionForExport(
        sessionID: sessionID,
        summary: overnightGuardManifestSummary(reason: "recovered_export")
      )
      ble.record(source: "overnight.guard", title: "recovered_export.finalized", body: sessionID)
    } catch {
      overnightGuardExportStatus = "Recovered manifest finalization failed: \(String(describing: error))"
      ble.record(level: .error, source: "overnight.guard", title: "recovered_export.finalize_failed", body: overnightGuardExportStatus)
    }
    exportOvernightGuardBundle(sessionID: sessionID, reason: "last_session_export")
  }

  // The persistOvernight* handlers run on the CoreBluetooth/diagnostic queues.
  // The spool's blocking JSONL + SHA-256 + fsync appends must never run there
  // (they starve the BLE link — see localOvernightCaptureEnabled history), so
  // each handler hops to the serial ingest queue, which preserves arrival order.

  nonisolated func persistOvernightRawNotificationBeforeInterpretation(
    _ event: GooseNotificationEvent,
    activeDeviceName: String,
    connectionState: String
  ) {
    guard overnightRawSpool.isActive else {
      return
    }
    guard admitOvernightSpoolIngest(label: "raw_notification") else {
      return
    }
    overnightSpoolIngestQueue.async { [weak self] in
      guard let self else {
        return
      }
      defer {
        self.overnightSpoolIngestGate.finish()
      }
      let snapshot = self.overnightRawSpool.append(
        event: event,
        activeDeviceName: activeDeviceName,
        connectionState: connectionState
      )
      self.overnightSQLiteMirror.enqueueRawNotification(
        sessionID: snapshot.sessionID,
        event: event,
        activeDeviceName: activeDeviceName,
        connectionState: connectionState
      ) { [weak self] snapshot in
        self?.applyOvernightSQLiteMirrorSnapshot(
          snapshot,
          reason: "sqlite_mirror_raw",
          writeSidecars: true
        )
      }
      if Self.shouldPublishOvernightRawSpoolSnapshot(snapshot) {
        Task { @MainActor [weak self] in
          self?.applyOvernightRawNotificationSnapshot(snapshot, event: event)
        }
      }
    }
  }

  nonisolated func admitOvernightSpoolIngest(label: String) -> Bool {
    switch overnightSpoolIngestGate.admit() {
    case .admitted:
      return true
    case .dropped(let totalDropped):
      if totalDropped == 1 || totalDropped.isMultiple(of: 100) {
        let maxDepth = overnightSpoolIngestGate.maxDepth
        Task { @MainActor [weak self] in
          self?.ble.record(
            level: .warn,
            source: "overnight.guard",
            title: "spool_ingest.dropped",
            body: "label=\(label) dropped_total=\(totalDropped) max_in_flight=\(maxDepth)"
          )
        }
      }
      return false
    }
  }

  nonisolated func persistOvernightHistoricalRangeTelemetry(_ telemetry: GooseHistoricalRangeTelemetry) {
    guard overnightRawSpool.isActive else {
      return
    }
    guard admitOvernightSpoolIngest(label: "historical_range") else {
      return
    }
    overnightSpoolIngestQueue.async { [weak self] in
      guard let self else {
        return
      }
      defer {
        self.overnightSpoolIngestGate.finish()
      }
      let snapshot = self.overnightRawSpool.appendHistoricalRangeTelemetry(telemetry)
      self.overnightSQLiteMirror.enqueueHistoricalRangePoll(
        sessionID: snapshot.sessionID,
        telemetry: telemetry
      ) { [weak self] snapshot in
        self?.applyOvernightSQLiteMirrorSnapshot(
          snapshot,
          reason: "sqlite_mirror_range",
          writeSidecars: true,
          forceSidecarsAfterFlush: true
        )
      }
      Task { @MainActor [weak self] in
        self?.applyOvernightHistoricalRangeTelemetrySnapshot(snapshot, telemetry: telemetry)
      }
    }
  }

  nonisolated func persistOvernightCommandWrite(
    _ event: GooseCommandWriteEvent,
    activeDeviceName: String,
    connectionState: String
  ) {
    guard overnightRawSpool.isActive else {
      return
    }
    guard admitOvernightSpoolIngest(label: "command_write") else {
      return
    }
    overnightSpoolIngestQueue.async { [weak self] in
      guard let self else {
        return
      }
      defer {
        self.overnightSpoolIngestGate.finish()
      }
      let snapshot = self.overnightRawSpool.appendCommandWrite(
        event,
        activeDeviceName: activeDeviceName,
        connectionState: connectionState
      )
      Task { @MainActor [weak self] in
        self?.applyOvernightCommandWriteSnapshot(snapshot, event: event)
      }
    }
  }

  nonisolated func persistOvernightEventLog(_ message: GooseMessage) {
    guard overnightRawSpool.isActive else {
      return
    }
    guard admitOvernightSpoolIngest(label: "event_log") else {
      return
    }
    overnightSpoolIngestQueue.async { [weak self] in
      guard let self else {
        return
      }
      defer {
        self.overnightSpoolIngestGate.finish()
      }
      let snapshot = self.overnightRawSpool.appendEventLog(message)
      guard Self.shouldPublishOvernightEventLogSnapshot(snapshot) else {
        return
      }
      Task { @MainActor [weak self] in
        guard let self, self.overnightGuardActive else {
          return
        }
        self.overnightGuardEventLogCount = snapshot.eventLogCount
        self.overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
        if snapshot.lastError != nil {
          self.applyOvernightRawSpoolWarning(
            from: snapshot,
            reason: "event_log_spool",
            warningStatus: "Recording with event log warning"
          )
        }
        self.refreshOvernightReadiness(reason: "event_log")
        self.writeOvernightGuardStatus(reason: "event_log")
      }
    }
  }

  nonisolated static func shouldPublishOvernightRawSpoolSnapshot(_ snapshot: OvernightRawSpoolSnapshot) -> Bool {
    snapshot.notificationCount <= 1 || snapshot.notificationCount.isMultiple(of: 50) || snapshot.lastError != nil
  }

  nonisolated static func shouldPublishOvernightEventLogSnapshot(_ snapshot: OvernightRawSpoolSnapshot) -> Bool {
    snapshot.eventLogCount <= 1 || snapshot.eventLogCount.isMultiple(of: 20) || snapshot.lastError != nil
  }

  func applyOvernightRawNotificationSnapshot(_ snapshot: OvernightRawSpoolSnapshot, event: GooseNotificationEvent) {
    guard overnightGuardActive else {
      return
    }
    overnightGuardRawNotificationCount = snapshot.notificationCount
    if let rawURL = snapshot.rawNotificationsURL {
      overnightGuardSpoolPath = rawURL.path
    }
    overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
    overnightGuardLastPacketSummary = "\(event.characteristicUUID) \(event.value.count) bytes @ \(event.capturedAt.formatted(date: .omitted, time: .standard))"
    if snapshot.lastError != nil {
      applyOvernightRawSpoolWarning(
        from: snapshot,
        reason: "raw_notification_spool",
        warningStatus: "Recording with raw-spool warning"
      )
    }
    refreshOvernightReadiness(reason: "raw_notification")
    if !overnightGuardWroteInitialRawNotificationStatus, snapshot.notificationCount > 0 {
      overnightGuardWroteInitialRawNotificationStatus = true
      writeOvernightGuardStatus(reason: "raw_notification_first")
    }
  }

  func applyOvernightHistoricalRangeTelemetrySnapshot(
    _ snapshot: OvernightRawSpoolSnapshot,
    telemetry: GooseHistoricalRangeTelemetry
  ) {
    guard overnightGuardActive else {
      return
    }
    overnightGuardRangeTelemetryCount = snapshot.historicalRangePollCount
    if telemetry.status == "success" {
      overnightGuardSuccessfulRangePollCount += 1
    }
    overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
    let pageSummary = telemetry.pagesBehind.map { "pages_behind \($0)" } ?? telemetry.resultName
    if snapshot.lastError != nil {
      applyOvernightRawSpoolWarning(
        from: snapshot,
        reason: "range_telemetry_spool",
        warningStatus: "Recording with range telemetry warning"
      )
    } else {
      overnightGuardStatus = "Range telemetry \(telemetry.status): \(pageSummary)"
    }
    refreshOvernightReadiness(reason: "range_telemetry_\(telemetry.status)", record: telemetry.status == "success")
    writeOvernightGuardStatus(reason: "range_telemetry_\(telemetry.status)")
  }

  func applyOvernightCommandWriteSnapshot(_ snapshot: OvernightRawSpoolSnapshot, event: GooseCommandWriteEvent) {
    guard overnightGuardActive else {
      return
    }
    overnightGuardCommandWriteCount = snapshot.commandWriteCount
    overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
    if snapshot.lastError != nil {
      applyOvernightRawSpoolWarning(
        from: snapshot,
        reason: "command_write_spool",
        warningStatus: "Recording with command-write warning"
      )
    } else if event.commandName == "GET_DATA_RANGE" || event.commandName == "SEND_HISTORICAL_DATA" || snapshot.commandWriteCount <= 5 {
      overnightGuardStatus = "Command write persisted: \(event.commandName) | writes \(snapshot.commandWriteCount)"
    }
    refreshOvernightReadiness(reason: "command_write", record: true)
    writeOvernightGuardStatusThrottled(reason: "command_write_\(event.commandName)")
  }

  func scheduleOvernightGuardHeartbeat() {
    overnightGuardHeartbeatWorkItem?.cancel()
    guard overnightGuardActive else {
      return
    }
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.refreshOvernightPowerState(reason: "heartbeat", record: true)
        self?.refreshOvernightWatchdogState(reason: "heartbeat")
        self?.writeOvernightGuardStatus(reason: "heartbeat")
        self?.scheduleOvernightGuardHeartbeat()
      }
    }
    overnightGuardHeartbeatWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.overnightGuardHeartbeatInterval, execute: workItem)
  }

  func scheduleOvernightGuardRangePoll(after delay: TimeInterval? = nil, reason: String) {
    overnightGuardRangePollWorkItem?.cancel()
    guard overnightGuardActive, !overnightGuardFinalSyncPending else {
      return
    }
    // 4.0 quiet mode: GET_DATA_RANGE / historical polling churns the 4.0 link.
    guard !ble.isGen4Band else { return }
    let delay = delay ?? Self.overnightGuardRangePollInterval
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        self?.runOvernightGuardRangePoll(reason: reason)
      }
    }
    overnightGuardRangePollWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  func runOvernightGuardRangePoll(reason: String) {
    overnightGuardRangePollWorkItem = nil
    guard overnightGuardActive, !overnightGuardFinalSyncPending else {
      return
    }

    guard ble.canSyncHistorical else {
      overnightGuardStatus = "Range poll waiting: \(ble.historicalSyncStatus)"
      refreshOvernightReadiness(reason: "range_poll_blocked")
      ble.record(level: .warn, source: "overnight.guard", title: "range_poll.blocked", body: overnightGuardStatus)
      writeOvernightGuardStatus(reason: "range_poll_blocked")
      let retryDelay = overnightGuardSuccessfulRangePollCount == 0
        ? Self.overnightGuardRangeBlockedRetryInterval
        : Self.overnightGuardRangePollInterval
      let retryReason = overnightGuardSuccessfulRangePollCount == 0
        ? "blocked_startup_retry"
        : "periodic"
      scheduleOvernightGuardRangePoll(after: retryDelay, reason: retryReason)
      return
    }

    overnightGuardRangePollCount += 1
    overnightGuardStatus = "Polling historical range \(overnightGuardRangePollCount)"
    refreshOvernightReadiness(reason: "range_poll_started")
    writeOvernightGuardStatus(reason: "range_poll_started")
    ble.pollHistoricalRange(source: "overnight.guard.\(reason)")
    scheduleOvernightGuardRangePoll(reason: "periodic")
  }

  func handleOvernightHistoricalSyncProgress(_ progress: GooseHistoricalSyncProgress) {
    guard overnightGuardActive else {
      return
    }

    if overnightGuardFinalSyncPending {
      overnightGuardStatus = "Final sync \(progress.status): \(progress.detail)"
      refreshOvernightReadiness(reason: "final_sync_progress")
      writeOvernightGuardStatus(reason: "final_sync_progress")
      if progress.isTerminal {
        scheduleOvernightGuardFinalSyncDrain(
          reason: progress.failed ? "final_sync_failed" : "final_sync_complete",
          progress: progress
        )
      }
      return
    }

    if progress.isTerminal {
      let retryFirstRange = progress.failed && overnightGuardSuccessfulRangePollCount == 0
      overnightGuardStatus = retryFirstRange
        ? "Range poll \(progress.status): \(progress.detail) | retrying in \(Int(Self.overnightGuardRangeFailureRetryInterval / 60))m"
        : "Range poll \(progress.status): \(progress.detail)"
      refreshOvernightReadiness(reason: "range_poll_finished")
      writeOvernightGuardStatus(reason: "range_poll_finished")
      if retryFirstRange {
        scheduleOvernightGuardRangePoll(
          after: Self.overnightGuardRangeFailureRetryInterval,
          reason: "failed_startup_retry"
        )
      }
    }
  }

  func scheduleOvernightGuardFinalSyncDrain(reason: String, progress: GooseHistoricalSyncProgress) {
    guard overnightGuardActive else {
      return
    }
    if overnightGuardFinalSyncDrainWorkItem != nil {
      overnightGuardStatus = "Final sync complete; draining trailing BLE frames"
      writeOvernightGuardStatus(reason: "final_sync_drain_already_scheduled")
      return
    }

    overnightGuardStatus = "Final sync \(progress.status); draining trailing BLE frames for \(Int(Self.overnightGuardFinalSyncDrainInterval))s"
    refreshOvernightReadiness(reason: "final_sync_drain_started")
    writeOvernightGuardStatus(reason: "final_sync_drain_started")
    ble.record(
      source: "overnight.guard",
      title: "final_sync.drain_started",
      body: "reason=\(reason) status=\(progress.status) packets=\(progress.packetCount)"
    )

    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        guard let self, self.overnightGuardActive else {
          return
        }
        self.overnightGuardFinalSyncDrainWorkItem = nil
        self.completeOvernightGuard(reason: reason, stopHealthCapture: true)
      }
    }
    overnightGuardFinalSyncDrainWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.overnightGuardFinalSyncDrainInterval, execute: workItem)
  }

  func completeOvernightGuard(reason: String, stopHealthCapture: Bool) {
    guard overnightGuardActive else {
      overnightGuardStatus = "No overnight guard session"
      return
    }
    overnightGuardHeartbeatWorkItem?.cancel()
    overnightGuardHeartbeatWorkItem = nil
    overnightGuardRangePollWorkItem?.cancel()
    overnightGuardRangePollWorkItem = nil
    overnightGuardFinalSyncDrainWorkItem?.cancel()
    overnightGuardFinalSyncDrainWorkItem = nil
    overnightGuardFinalSyncPending = false

    if stopHealthCapture, overnightGuardStartedHealthCapture, activeHealthPacketCapture != nil {
      stopHealthPacketCapture(reason: "overnight_guard_\(reason)")
    } else if stopHealthCapture {
      ble.stopPhysiologySignalCapture()
    }

    let endedAt = Date()
    // Drain handed-off spool appends (see persistOvernight*) so the terminal
    // manifest/status counts include every record that arrived before the stop.
    overnightSpoolIngestQueue.sync {}
    let snapshot = overnightRawSpool.finish(status: reason, summary: overnightGuardManifestSummary(reason: reason))
    overnightGuardActive = false
    overnightGuardRawNotificationCount = snapshot.notificationCount
    overnightGuardRangeTelemetryCount = snapshot.historicalRangePollCount
    overnightGuardCommandWriteCount = snapshot.commandWriteCount
    if let historicalRangePollsURL = snapshot.historicalRangePollsURL {
      let fileSuccessfulRangePollCount = Self.countSuccessfulHistoricalRangePolls(at: historicalRangePollsURL)
      overnightGuardSuccessfulRangePollCount = max(
        overnightGuardSuccessfulRangePollCount,
        fileSuccessfulRangePollCount
      )
    }
    overnightGuardEventLogCount = snapshot.eventLogCount
    overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(snapshot)
    overnightGuardStatus = "Stopped overnight guard: \(reason) | raw \(snapshot.notificationCount)"
    if snapshot.lastError != nil {
      applyOvernightRawSpoolWarning(
        from: snapshot,
        reason: "finish_spool",
        warningStatus: "Stopped overnight guard with proof warning"
      )
    }
    if let rawURL = snapshot.rawNotificationsURL {
      overnightGuardSpoolPath = rawURL.path
    }
    overnightGuardCanExportLastSession = true
    refreshOvernightReadiness(reason: reason, record: true)
    enqueueOvernightSQLiteSession(finalStatus: reason, endedAt: endedAt, notes: "stopped")
    writeOvernightGuardStatus(reason: reason)
    let finalManifestSnapshot = overnightRawSpool.updateFinalSummary(
      status: reason,
      summary: overnightGuardManifestSummary(reason: reason)
    )
    overnightGuardCommandWriteCount = finalManifestSnapshot.commandWriteCount
    overnightGuardSpoolSizeSummary = Self.overnightSpoolSizeSummary(finalManifestSnapshot)
    if finalManifestSnapshot.lastError != nil {
      applyOvernightRawSpoolWarning(
        from: finalManifestSnapshot,
        reason: "final_manifest_spool",
        warningStatus: "Stopped overnight guard with final-manifest warning"
      )
    }
    ble.record(source: "overnight.guard", title: "stopped", body: overnightGuardStatus)
    if reason.hasPrefix("final_sync") {
      exportOvernightGuardBundle(sessionID: snapshot.sessionID, reason: reason)
    } else {
      // A final-sync critical background task may still be active if the guard
      // was stopped mid-sync; with no export to end it, it would burn
      // background time until iOS force-expires it.
      endOvernightGuardCriticalBackgroundTask(reason: "guard_complete_\(reason)")
    }
  }

  func exportOvernightGuardBundle(sessionID: String?, reason: String) {
    guard !overnightGuardExportInProgress else {
      overnightGuardExportStatus = "Final export already running"
      writeOvernightGuardStatus(reason: "final_export_already_running")
      return
    }

    overnightGuardExportInProgress = true
    beginOvernightGuardCriticalBackgroundTask(reason: "final_export_\(reason)")
    overnightGuardExportURL = nil
    overnightGuardExportManifestURL = nil
    overnightGuardExportManifestError = nil
    overnightGuardExportStatus = "Saving final sync bundle..."
    refreshOvernightReadiness(reason: "final_export_started")
    writeOvernightGuardStatus(reason: "final_export_started")
    ble.record(source: "overnight.guard", title: "final_export.started", body: "reason=\(reason) session=\(sessionID ?? "none")")
    let bleLogFlushIssues = ble.flushDiagnosticLogWrites()
    applyOvernightBLELogFlushIssues(bleLogFlushIssues, reason: "final_export_ble_log_flush")

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let mirrorSnapshot = self?.overnightSQLiteMirror.flushSynchronously()
        let result = try GooseLocalDataExporter.createBundle(requiredOvernightSessionID: sessionID)
        DispatchQueue.main.async { [weak self] in
          guard let self else {
            return
          }
          if let mirrorSnapshot {
            self.applyOvernightSQLiteMirrorSnapshot(mirrorSnapshot)
          }
          self.overnightGuardExportInProgress = false
          self.overnightGuardExportURL = result.url
          self.overnightGuardExportManifestURL = result.manifestURL
          self.overnightGuardExportManifestError = result.manifestError
          self.overnightGuardCanExportLastSession = true
          let byteText = ByteCountFormatter.string(fromByteCount: Int64(result.byteCount), countStyle: .file)
          let validationText = result.validation.passed ? "validated" : "validation issues"
          self.overnightGuardExportStatus = "Saved \(result.fileCount) files, \(byteText)\(result.manifestStatusSuffix) | \(validationText): \(result.validation.summary)"
          self.refreshOvernightReadiness(reason: "final_export_finished", record: true)
          let statusReason: String
          let recordLevel: GooseLogLevel
          let recordTitle: String
          if !result.validation.passed {
            statusReason = "final_export_validation_failed"
            recordLevel = .warn
            recordTitle = "final_export.validation_failed"
          } else if result.manifestError != nil {
            statusReason = "final_export_manifest_sidecar_error"
            recordLevel = .warn
            recordTitle = "final_export.manifest_sidecar_error"
          } else {
            statusReason = "final_export_validated"
            recordLevel = .info
            recordTitle = "final_export.ok"
          }
          self.endOvernightGuardCriticalBackgroundTask(reason: statusReason)
          self.writeOvernightGuardStatus(reason: statusReason)
          self.ble.record(
            level: recordLevel,
            source: "overnight.guard",
            title: recordTitle,
            body: "\(self.overnightGuardExportStatus) path=\(result.url.path)"
          )
        }
      } catch {
        DispatchQueue.main.async { [weak self] in
          guard let self else {
            return
          }
          self.overnightGuardExportInProgress = false
          self.overnightGuardExportStatus = "Final export failed: \(String(describing: error))"
          self.overnightGuardCanExportLastSession = sessionID != nil
          self.refreshOvernightReadiness(reason: "final_export_failed", record: true)
          self.endOvernightGuardCriticalBackgroundTask(reason: "final_export_failed")
          self.writeOvernightGuardStatus(reason: "final_export_failed")
          self.ble.record(level: .error, source: "overnight.guard", title: "final_export.failed", body: self.overnightGuardExportStatus)
        }
      }
    }
  }

  func overnightGuardManifestSummary(reason: String) -> [String: Any] {
    let power = refreshOvernightPowerState(reason: "manifest_\(reason)")
    refreshOvernightReadiness(reason: "manifest_\(reason)")
    let snapshot = overnightRawSpool.snapshot
    return [
      "reason": reason,
      "guard_active": overnightGuardActive,
      "critical_background_task_active": overnightGuardCriticalBackgroundTaskID != .invalid,
      "critical_background_task_reason": overnightGuardCriticalBackgroundTaskReason ?? NSNull(),
      "last_status_at": snapshot.lastStatusAt.map { Self.captureTimestampFormatter.string(from: $0) } ?? NSNull(),
      "final_sync_pending": overnightGuardFinalSyncPending,
      "final_sync_drain_pending": overnightGuardFinalSyncDrainWorkItem != nil,
      "readiness_status": overnightGuardReadinessStatus,
      "readiness": overnightGuardReadinessSummary,
      "raw_notification_count": overnightGuardRawNotificationCount,
      "range_poll_count": overnightGuardRangePollCount,
      "range_poll_response_count": overnightGuardRangeTelemetryCount,
      "successful_range_poll_response_count": overnightGuardSuccessfulRangePollCount,
      "successful_historical_range_poll_count": overnightGuardSuccessfulRangePollCount,
      "command_write_count": overnightGuardCommandWriteCount,
      "event_log_count": overnightGuardEventLogCount,
      "historical_sync_status": ble.historicalSyncStatus,
      "historical_packet_count": ble.historicalPacketCount,
      "last_historical_range": ble.lastHistoricalRangeCommandStatus,
      "historical_transfer_order": overnightGuardHistoricalOrder.summary,
      "historical_transfer_order_verdict": overnightGuardHistoricalOrder.verdict.rawValue,
      "historical_transfer_order_evidence": overnightGuardHistoricalOrder.jsonObject,
      "target_summary": overnightGuardTargetSummary,
      "k18_count": overnightGuardTargetCounts.k18,
      "k24_count": overnightGuardTargetCounts.k24,
      "k25_count": overnightGuardTargetCounts.k25,
      "k26_count": overnightGuardTargetCounts.k26,
      "packet47_count": overnightGuardTargetCounts.packet47,
      "event17_count": overnightGuardTargetCounts.event17,
      "event29_count": overnightGuardTargetCounts.event29,
      "metadata49_count": overnightGuardTargetCounts.metadata49,
      "metadata56_count": overnightGuardTargetCounts.metadata56,
      "event49_count": overnightGuardTargetCounts.metadata49,
      "event56_count": overnightGuardTargetCounts.metadata56,
      "last_packet": overnightGuardLastPacketSummary,
      "spool_size": overnightGuardSpoolSizeSummary,
      "raw_spool_warning": overnightGuardRawSpoolWarning ?? NSNull(),
      "ble_log_warning": overnightGuardBLELogWarning ?? NSNull(),
      "sqlite_mirror": overnightGuardSQLiteMirrorSummary,
      "power": power.jsonObject,
      "watchdog": overnightGuardWatchdogSummary,
      "warning": overnightGuardWarning,
      "export_status": overnightGuardExportStatus,
      "export_url": overnightGuardExportURL?.path ?? NSNull(),
      "export_manifest_url": overnightGuardExportManifestURL?.path ?? NSNull(),
      "export_manifest_error": overnightGuardExportManifestError ?? NSNull(),
    ]
  }

  func writeOvernightGuardStatus(reason: String) {
    guard overnightGuardSession != nil || overnightGuardActive else {
      return
    }
    let power = refreshOvernightPowerState(reason: reason)
    refreshOvernightReadiness(reason: reason)
    enqueueOvernightSQLiteSession(finalStatus: overnightGuardActive ? "active" : reason, notes: reason)
    let lines = [
      "reason=\(reason)",
      "active=\(overnightGuardActive)",
      "critical_background_task_active=\(overnightGuardCriticalBackgroundTaskID != .invalid)",
      "critical_background_task_reason=\(overnightGuardCriticalBackgroundTaskReason ?? "none")",
      "final_sync_pending=\(overnightGuardFinalSyncPending)",
      "final_sync_drain_pending=\(overnightGuardFinalSyncDrainWorkItem != nil)",
      "status=\(overnightGuardStatus)",
      "readiness_status=\(overnightGuardReadinessStatus)",
      "readiness=\(overnightGuardReadinessSummary)",
      "connection=\(ble.connectionState)",
      "device=\(ble.activeDeviceName)",
      "raw_notifications=\(overnightGuardRawNotificationCount)",
      "range_polls=\(overnightGuardRangePollCount)",
      "range_poll_responses=\(overnightGuardRangeTelemetryCount)",
      "successful_range_poll_responses=\(overnightGuardSuccessfulRangePollCount)",
      "successful_historical_range_poll_count=\(overnightGuardSuccessfulRangePollCount)",
      "command_write_count=\(overnightGuardCommandWriteCount)",
      "event_log_count=\(overnightGuardEventLogCount)",
      "last_range=\(ble.lastHistoricalRangeCommandStatus)",
      "historical_sync=\(ble.historicalSyncStatus)",
      "historical_packets=\(ble.historicalPacketCount)",
      "historical_transfer_order=\(overnightGuardHistoricalOrder.summary)",
      "targets=\(overnightGuardTargetSummary)",
      "last_packet=\(overnightGuardLastPacketSummary)",
      "spool_size=\(overnightGuardSpoolSizeSummary)",
      "raw_spool_warning=\(overnightGuardRawSpoolWarning ?? "none")",
      "ble_log_warning=\(overnightGuardBLELogWarning ?? "none")",
      "sqlite_mirror=\(overnightGuardSQLiteMirrorSummary)",
      "watchdog=\(overnightGuardWatchdogSummary)",
      "export_status=\(overnightGuardExportStatus)",
      "export_url=\(overnightGuardExportURL?.path ?? "none")",
      "export_manifest_url=\(overnightGuardExportManifestURL?.path ?? "none")",
      "export_manifest_error=\(overnightGuardExportManifestError ?? "none")",
      "warning=\(overnightGuardWarning)",
    ] + power.statusLines
    let snapshot = overnightRawSpool.writeStatus(lines: lines)
    applyOvernightRawSpoolStatusSnapshot(snapshot, reason: reason)
  }

  /// Coalesces high-frequency callers (per data packet during sync bursts) to
  /// one status write per interval — each write is a full status-file rewrite,
  /// SQLite enqueue, and battery poll on the main thread. A trailing write
  /// ensures the final burst state still lands; lifecycle/warning transitions
  /// keep calling writeOvernightGuardStatus directly for immediate writes.
  func writeOvernightGuardStatusThrottled(reason: String, minimumInterval: TimeInterval = 10) {
    let now = Date()
    if now.timeIntervalSince(overnightGuardLastStatusWriteAt) >= minimumInterval {
      overnightGuardLastStatusWriteAt = now
      overnightGuardStatusWriteWorkItem?.cancel()
      overnightGuardStatusWriteWorkItem = nil
      writeOvernightGuardStatus(reason: reason)
      return
    }
    guard overnightGuardStatusWriteWorkItem == nil else {
      return
    }
    let workItem = DispatchWorkItem { [weak self] in
      Task { @MainActor in
        guard let self else {
          return
        }
        self.overnightGuardStatusWriteWorkItem = nil
        self.overnightGuardLastStatusWriteAt = Date()
        self.writeOvernightGuardStatus(reason: reason)
      }
    }
    overnightGuardStatusWriteWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + minimumInterval, execute: workItem)
  }

  func recordOvernightDataSignalTarget(_ sample: WhoopDataSignalSample) {
    guard overnightGuardActive else {
      return
    }
    let orderChanged = overnightGuardHistoricalOrder.record(sample)
    overnightGuardHistoricalOrderSummary = overnightGuardHistoricalOrder.summary
    switch sample.packetK {
    case 18:
      overnightGuardTargetCounts.k18 += 1
    case 24:
      overnightGuardTargetCounts.k24 += 1
    case 25:
      overnightGuardTargetCounts.k25 += 1
    case 26:
      overnightGuardTargetCounts.k26 += 1
    default:
      break
    }
    overnightGuardTargetSummary = overnightGuardTargetCounts.summary
    overnightGuardWatchdogWarning = nil
    overnightGuardWatchdogSummary = "Watchdog ok | target packet received | \(overnightGuardTargetSummary) | \(overnightGuardHistoricalOrder.summary)"
    updateOvernightGuardWarning()
    refreshOvernightReadiness(reason: "target_data_packet", record: true)
    if orderChanged {
      ble.record(
        source: "overnight.guard",
        title: "historical_transfer_order.updated",
        body: overnightGuardHistoricalOrder.summary
      )
    }
    writeOvernightGuardStatusThrottled(reason: "target_data_packet")
  }

  func recordOvernightPacketTypeTarget(_ packetType: Int?) {
    guard overnightGuardActive, let packetType else {
      return
    }
    switch packetType {
    case 47:
      overnightGuardTargetCounts.packet47 += 1
    case 49:
      overnightGuardTargetCounts.metadata49 += 1
    case 56:
      overnightGuardTargetCounts.metadata56 += 1
    default:
      return
    }
    overnightGuardTargetSummary = overnightGuardTargetCounts.summary
    overnightGuardWatchdogWarning = nil
    overnightGuardWatchdogSummary = "Watchdog ok | target packet type received | \(overnightGuardTargetSummary)"
    updateOvernightGuardWarning()
    refreshOvernightReadiness(reason: "target_packet_type", record: true)
    writeOvernightGuardStatusThrottled(reason: "target_packet_type")
  }

  func recordOvernightEventTarget(_ sample: WhoopEventSample) {
    guard overnightGuardActive else {
      return
    }
    if sample.eventID == 17 || sample.eventName == "TEMPERATURE_LEVEL" {
      overnightGuardTargetCounts.event17 += 1
    }
    if sample.eventID == 29 {
      overnightGuardTargetCounts.event29 += 1
    }
    if sample.eventID == 49 {
      overnightGuardTargetCounts.metadata49 += 1
    }
    if sample.eventID == 56 {
      overnightGuardTargetCounts.metadata56 += 1
    }
    overnightGuardTargetSummary = overnightGuardTargetCounts.summary
    overnightGuardWatchdogWarning = nil
    overnightGuardWatchdogSummary = "Watchdog ok | target event received | \(overnightGuardTargetSummary)"
    updateOvernightGuardWarning()
    refreshOvernightReadiness(reason: "target_event", record: true)
    writeOvernightGuardStatusThrottled(reason: "target_event")
  }

}
