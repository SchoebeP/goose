import Foundation
import UIKit

struct OvernightSQLiteMirrorSnapshot {
  let sessionUpserted: Int
  let rawInserted: Int
  let rawExisting: Int
  let historicalRangeInserted: Int
  let historicalRangeExisting: Int
  let queuedRows: Int
  let droppedRows: Int
  let lastError: String?

  var summary: String {
    let rawTotal = rawInserted + rawExisting
    let rangeTotal = historicalRangeInserted + historicalRangeExisting
    let base = "SQLite mirror raw \(rawTotal) | range \(rangeTotal) | sessions \(sessionUpserted) | queued \(queuedRows) | dropped \(droppedRows)"
    if let lastError {
      return "\(base) | warning \(lastError)"
    }
    return base
  }
}

final class OvernightSQLiteMirrorQueue: @unchecked Sendable {
  private static let timestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private let queue = DispatchQueue(label: "com.goose.swift.overnight-sqlite-mirror", qos: .utility)
  private let rust = GooseRustBridge()
  private let databasePath: String
  private let maxQueuedRows: Int
  private let flushBatchLimit: Int
  private let flushDelay: TimeInterval
  private var pendingSessions: [[String: Any]] = []
  private var pendingRawNotifications: [[String: Any]] = []
  private var pendingHistoricalRangePolls: [[String: Any]] = []
  private var compactRawNotificationCountsByKey: [String: Int] = [:]
  private var flushScheduled = false
  private var consecutiveFlushFailures = 0
  private var sessionUpserted = 0
  private var rawInserted = 0
  private var rawExisting = 0
  private var historicalRangeInserted = 0
  private var historicalRangeExisting = 0
  private var droppedRows = 0
  private var lastError: String?
  private var latestCompletion: (@MainActor (OvernightSQLiteMirrorSnapshot) -> Void)?

  init(
    databasePath: String,
    maxQueuedRows: Int = 4096,
    flushBatchLimit: Int = 256,
    flushDelay: TimeInterval = 2
  ) {
    self.databasePath = databasePath
    self.maxQueuedRows = maxQueuedRows
    self.flushBatchLimit = max(1, flushBatchLimit)
    self.flushDelay = flushDelay
  }

  func enqueueSession(_ row: [String: Any], completion: (@MainActor (OvernightSQLiteMirrorSnapshot) -> Void)? = nil) {
    enqueue(sessions: [row], rawNotifications: [], historicalRangePolls: [], completion: completion)
  }

  func enqueueRawNotification(
    sessionID: String?,
    event: GooseNotificationEvent,
    activeDeviceName: String,
    connectionState: String,
    completion: (@MainActor (OvernightSQLiteMirrorSnapshot) -> Void)? = nil
  ) {
    guard let sessionID else {
      return
    }
    let classification = OvernightRawNotificationStorageClassifier.classify(event)
    if let compactKey = classification.compactKey {
      let sessionCompactKey = "\(sessionID):\(compactKey)"
      let shouldMirror = queue.sync {
        let count = (compactRawNotificationCountsByKey[sessionCompactKey] ?? 0) + 1
        compactRawNotificationCountsByKey[sessionCompactKey] = count
        return OvernightRawNotificationStorageClassifier.shouldKeepCompactLiveSample(count: count)
      }
      guard shouldMirror else {
        return
      }
    }

    var row: [String: Any] = [
      "session_id": sessionID,
      "captured_at": Self.timestampFormatter.string(from: event.capturedAt),
      "source": "ios.corebluetooth.raw_notification",
      "device_id": event.deviceID.uuidString,
      "active_device_name": activeDeviceName,
      "connection_state": connectionState,
      "service_uuid": event.serviceUUID,
      "characteristic_uuid": event.characteristicUUID,
      "device_type": event.rustDeviceType,
      "frame_hex": event.value.hexString,
      "byte_count": event.value.count,
      "decode_status": classification.isCompactLiveFlood ? "sampled_live_motion" : "not_decoded",
    ]
    if let packetType = classification.packetType {
      row["packet_type"] = Int(packetType)
    }
    if let packetK = classification.packetK {
      row["k_revision"] = Int(packetK)
    }
    enqueue(sessions: [], rawNotifications: [row], historicalRangePolls: [], completion: completion)
  }

  func enqueueHistoricalRangePoll(
    sessionID: String?,
    telemetry: GooseHistoricalRangeTelemetry,
    completion: (@MainActor (OvernightSQLiteMirrorSnapshot) -> Void)? = nil
  ) {
    guard let sessionID else {
      return
    }
    let row: [String: Any] = [
      "session_id": sessionID,
      "captured_at": Self.timestampFormatter.string(from: telemetry.capturedAt),
      "status": telemetry.status,
      "command_sequence": Int(telemetry.commandSequence),
      "result_code": Int(telemetry.resultCode),
      "result_name": telemetry.resultName,
      "raw_payload_hex": telemetry.payloadHex,
      "raw_body_hex": telemetry.bodyHex,
      "revision_or_status": telemetry.revisionOrStatus.map { Int($0) } ?? NSNull(),
      "page_current": telemetry.pageCurrent.map { Int64($0) } ?? NSNull(),
      "page_oldest": telemetry.pageOldest.map { Int64($0) } ?? NSNull(),
      "page_end": telemetry.pageEnd.map { Int64($0) } ?? NSNull(),
      "pages_behind": telemetry.pagesBehind ?? NSNull(),
      "pending_response_count": telemetry.pendingResponseCount,
      "retry_count": telemetry.retryCount,
      "notes": telemetry.notes,
    ]
    enqueue(sessions: [], rawNotifications: [], historicalRangePolls: [row], completion: completion)
  }

  func flushSynchronously() -> OvernightSQLiteMirrorSnapshot {
    queue.sync {
      flushPendingLocked()
      return snapshotLocked()
    }
  }

  var snapshot: OvernightSQLiteMirrorSnapshot {
    queue.sync {
      snapshotLocked()
    }
  }

  private func enqueue(
    sessions: [[String: Any]],
    rawNotifications: [[String: Any]],
    historicalRangePolls: [[String: Any]],
    completion: (@MainActor (OvernightSQLiteMirrorSnapshot) -> Void)?
  ) {
    queue.async { [weak self] in
      guard let self else {
        return
      }
      let incomingCount = sessions.count + rawNotifications.count + historicalRangePolls.count
      let capacity = max(0, self.maxQueuedRows - self.pendingRowCountLocked)
      if incomingCount > capacity {
        self.droppedRows += incomingCount - capacity
        self.lastError = "queue full"
      }
      if capacity > 0 {
        var remaining = capacity
        let acceptedSessions = Array(sessions.prefix(remaining))
        remaining -= acceptedSessions.count
        let acceptedRaw = Array(rawNotifications.prefix(remaining))
        remaining -= acceptedRaw.count
        let acceptedRange = Array(historicalRangePolls.prefix(remaining))
        self.pendingSessions.append(contentsOf: acceptedSessions)
        self.pendingRawNotifications.append(contentsOf: acceptedRaw)
        self.pendingHistoricalRangePolls.append(contentsOf: acceptedRange)
      }
      if let completion {
        self.latestCompletion = completion
      }
      self.scheduleFlushLocked()
    }
  }

  private var pendingRowCountLocked: Int {
    pendingSessions.count + pendingRawNotifications.count + pendingHistoricalRangePolls.count
  }

  private func scheduleFlushLocked() {
    guard !flushScheduled else {
      return
    }
    flushScheduled = true
    queue.asyncAfter(deadline: .now() + flushDelay) { [weak self] in
      guard let self else {
        return
      }
      self.flushScheduled = false
      self.flushPendingLocked()
    }
  }

  private func flushPendingLocked() {
    guard pendingRowCountLocked > 0 else {
      return
    }
    let sessions = Array(pendingSessions.prefix(flushBatchLimit))
    pendingSessions.removeFirst(sessions.count)
    let remainingAfterSessions = max(0, flushBatchLimit - sessions.count)
    let rawNotifications = Array(pendingRawNotifications.prefix(remainingAfterSessions))
    pendingRawNotifications.removeFirst(rawNotifications.count)
    let remainingAfterRaw = max(0, remainingAfterSessions - rawNotifications.count)
    let historicalRangePolls = Array(pendingHistoricalRangePolls.prefix(remainingAfterRaw))
    pendingHistoricalRangePolls.removeFirst(historicalRangePolls.count)

    do {
      let report = try rust.request(
        method: "overnight.mirror_batch",
        args: [
          "database_path": databasePath,
          "sessions": sessions,
          "raw_notifications": rawNotifications,
          "historical_range_polls": historicalRangePolls,
        ]
      )
      sessionUpserted += Self.intValue(report["session_upserted"]) ?? 0
      rawInserted += Self.intValue(report["raw_inserted"]) ?? 0
      rawExisting += Self.intValue(report["raw_existing"]) ?? 0
      historicalRangeInserted += Self.intValue(report["historical_range_inserted"]) ?? 0
      historicalRangeExisting += Self.intValue(report["historical_range_existing"]) ?? 0
      let issues = Self.stringArray(report["issues"])
      lastError = issues.isEmpty ? nil : issues.prefix(2).joined(separator: " | ")
      consecutiveFlushFailures = 0
    } catch {
      pendingSessions.insert(contentsOf: sessions, at: 0)
      pendingRawNotifications.insert(contentsOf: rawNotifications, at: 0)
      pendingHistoricalRangePolls.insert(contentsOf: historicalRangePolls, at: 0)
      consecutiveFlushFailures += 1
      lastError = String(describing: error)
      publishLatestSnapshotLocked()
      // Retry with capped backoff instead of stalling until the next enqueue.
      let delay = flushDelay * Double(min(consecutiveFlushFailures, 30))
      queue.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self, self.pendingRowCountLocked > 0 else {
          return
        }
        self.flushPendingLocked()
      }
      return
    }

    if pendingRowCountLocked > 0 {
      flushPendingLocked()
    } else {
      publishLatestSnapshotLocked()
    }
  }

  private func snapshotLocked() -> OvernightSQLiteMirrorSnapshot {
    OvernightSQLiteMirrorSnapshot(
      sessionUpserted: sessionUpserted,
      rawInserted: rawInserted,
      rawExisting: rawExisting,
      historicalRangeInserted: historicalRangeInserted,
      historicalRangeExisting: historicalRangeExisting,
      queuedRows: pendingRowCountLocked,
      droppedRows: droppedRows,
      lastError: lastError
    )
  }

  private func publishLatestSnapshotLocked() {
    guard let completion = latestCompletion else {
      return
    }
    latestCompletion = nil
    let snapshot = snapshotLocked()
    Task { @MainActor in
      completion(snapshot)
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    if let value = value as? String {
      return Int(value)
    }
    return nil
  }

  private static func stringArray(_ value: Any?) -> [String] {
    (value as? [Any])?.compactMap { $0 as? String } ?? []
  }
}

