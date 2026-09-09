import Foundation
import UIKit

struct OvernightRawSpoolSnapshot {
  let sessionID: String?
  let directoryURL: URL?
  let rawNotificationsURL: URL?
  let historicalRangePollsURL: URL?
  let commandWritesURL: URL?
  let eventLogURL: URL?
  let checkpointsURL: URL?
  let checkpointLatestURL: URL?
  let statusURL: URL?
  let manifestURL: URL?
  let notificationCount: Int
  let historicalRangePollCount: Int
  let commandWriteCount: Int
  let eventLogCount: Int
  let checkpointCount: Int
  let byteCount: Int
  let historicalRangePollByteCount: Int
  let commandWriteByteCount: Int
  let eventLogByteCount: Int
  let checkpointByteCount: Int
  let totalByteCount: Int
  let startedAt: Date?
  let lastNotificationAt: Date?
  let lastStatusAt: Date?
  let lastCheckpointAt: Date?
  let lastError: String?
}

struct OvernightPowerState {
  let lowPowerMode: Bool
  let batteryPercent: Int?
  let batteryState: String
  let thermalState: String

  var summary: String {
    let battery = batteryPercent.map { "\($0)%" } ?? "unknown battery"
    let lowPower = lowPowerMode ? "Low Power ON" : "Low Power off"
    return "\(lowPower) | battery \(battery) \(batteryState) | thermal \(thermalState)"
  }

  var jsonObject: [String: Any] {
    [
      "low_power_mode": lowPowerMode,
      "battery_percent": batteryPercent ?? NSNull(),
      "battery_state": batteryState,
      "thermal_state": thermalState,
    ]
  }

  var statusLines: [String] {
    [
      "power=\(summary)",
      "low_power_mode=\(lowPowerMode)",
      "battery_percent=\(batteryPercent.map(String.init) ?? "unknown")",
      "battery_state=\(batteryState)",
      "thermal_state=\(thermalState)",
    ]
  }
}

final class OvernightRawNotificationSpool: @unchecked Sendable {
  private struct FileMetrics {
    let recordCount: Int
    let byteCount: Int
  }

  private static let timestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static let overnightProtection: FileProtectionType = .completeUntilFirstUserAuthentication
  private static let rawNotificationSyncRecordInterval = 4
  private static let rawNotificationSyncInterval: TimeInterval = 1
  private static let eventLogSyncInterval: TimeInterval = 5
  private static let checkpointInterval: TimeInterval = 60

  private let queue = DispatchQueue(label: "com.goose.swift.overnight-raw-spool", qos: .utility)
  // Mirrors `handle != nil` so the per-notification isActive check on the
  // CoreBluetooth/diagnostic queues never blocks behind an in-flight
  // append/fsync running on the spool queue.
  private let activeStateLock = NSLock()
  private var activeFlag = false
  private var sessionID: String?
  private var directoryURL: URL?
  private var rawNotificationsURL: URL?
  private var historicalRangePollsURL: URL?
  private var commandWritesURL: URL?
  private var eventLogURL: URL?
  private var checkpointsURL: URL?
  private var checkpointLatestURL: URL?
  private var statusURL: URL?
  private var manifestURL: URL?
  private var crashMarkerURL: URL?
  private var handle: FileHandle?
  private var historicalRangePollsHandle: FileHandle?
  private var commandWritesHandle: FileHandle?
  private var eventLogHandle: FileHandle?
  private var checkpointHandle: FileHandle?
  private var notificationCount = 0
  private var historicalRangePollCount = 0
  private var commandWriteCount = 0
  private var eventLogCount = 0
  private var checkpointCount = 0
  private var byteCount = 0
  private var historicalRangePollByteCount = 0
  private var commandWriteByteCount = 0
  private var eventLogByteCount = 0
  private var checkpointByteCount = 0
  private var startedAt: Date?
  private var endedAt: Date?
  private var lastNotificationAt: Date?
  private var lastStatusAt: Date?
  private var lastCheckpointAt: Date?
  private var statusWriteCount = 0
  private var lastError: String?
  private var lastSyncAt = Date.distantPast
  private var lastEventLogSyncAt = Date.distantPast
  private var metadata: [String: Any] = [:]
  private var finalSummary: [String: Any] = [:]
  private var handlesClosed = false
  private var postCloseStatusRefresh = false
  private var fileMetricsRecomputedAt: Date?
  private var compactRawNotificationCountsByKey: [String: Int] = [:]
  private let processLaunchID = UUID().uuidString
  private let processLaunchStartedAt = Date()

  func start(sessionID: String, directoryURL: URL, metadata: [String: Any]) throws -> OvernightRawSpoolSnapshot {
    var result: Result<OvernightRawSpoolSnapshot, Error>!
    queue.sync {
      do {
        finishLocked(status: "replaced_by_new_session")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.applyOvernightProtection(to: directoryURL.deletingLastPathComponent().deletingLastPathComponent())
        try Self.applyOvernightProtection(to: directoryURL.deletingLastPathComponent())
        try Self.applyOvernightProtection(to: directoryURL)
        let rawURL = directoryURL.appendingPathComponent("raw-notifications.jsonl")
        let rangePollsURL = directoryURL.appendingPathComponent("historical-range-polls.jsonl")
        let commandWritesURL = directoryURL.appendingPathComponent("command-writes.jsonl")
        let eventLogURL = directoryURL.appendingPathComponent("event-log.jsonl")
        let checkpointsURL = directoryURL.appendingPathComponent("checkpoints.jsonl")
        let checkpointLatestURL = directoryURL.appendingPathComponent("checkpoint-latest.json")
        let statusURL = directoryURL.appendingPathComponent("status.txt")
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let crashMarkerURL = directoryURL.appendingPathComponent("crash-marker.json")
        try Self.createFileIfMissing(rawURL)
        try Self.createFileIfMissing(rangePollsURL)
        try Self.createFileIfMissing(commandWritesURL)
        try Self.createFileIfMissing(eventLogURL)
        try Self.createFileIfMissing(checkpointsURL)
        try Self.createFileIfMissing(checkpointLatestURL)
        try Self.createFileIfMissing(statusURL)
        try Self.createFileIfMissing(manifestURL)
        try Self.createFileIfMissing(crashMarkerURL)
        try Self.applyOvernightProtection(to: rawURL)
        try Self.applyOvernightProtection(to: rangePollsURL)
        try Self.applyOvernightProtection(to: commandWritesURL)
        try Self.applyOvernightProtection(to: eventLogURL)
        try Self.applyOvernightProtection(to: checkpointsURL)
        try Self.applyOvernightProtection(to: checkpointLatestURL)
        try Self.applyOvernightProtection(to: statusURL)
        try Self.applyOvernightProtection(to: manifestURL)
        try Self.applyOvernightProtection(to: crashMarkerURL)
        let handle = try FileHandle(forWritingTo: rawURL)
        let historicalRangePollsHandle = try FileHandle(forWritingTo: rangePollsURL)
        let commandWritesHandle = try FileHandle(forWritingTo: commandWritesURL)
        let eventLogHandle = try FileHandle(forWritingTo: eventLogURL)
        let checkpointHandle = try FileHandle(forWritingTo: checkpointsURL)
        self.sessionID = sessionID
        self.directoryURL = directoryURL
        self.rawNotificationsURL = rawURL
        self.historicalRangePollsURL = rangePollsURL
        self.commandWritesURL = commandWritesURL
        self.eventLogURL = eventLogURL
        self.checkpointsURL = checkpointsURL
        self.checkpointLatestURL = checkpointLatestURL
        self.statusURL = statusURL
        self.manifestURL = manifestURL
        self.crashMarkerURL = crashMarkerURL
        self.handle = handle
        self.historicalRangePollsHandle = historicalRangePollsHandle
        self.commandWritesHandle = commandWritesHandle
        self.eventLogHandle = eventLogHandle
        self.checkpointHandle = checkpointHandle
        setActiveFlag(true)
        self.notificationCount = 0
        self.historicalRangePollCount = 0
        self.commandWriteCount = 0
        self.eventLogCount = 0
        self.checkpointCount = 0
        self.byteCount = 0
        self.historicalRangePollByteCount = 0
        self.commandWriteByteCount = 0
        self.eventLogByteCount = 0
        self.checkpointByteCount = 0
        self.startedAt = Date()
        self.endedAt = nil
        self.lastNotificationAt = nil
        self.lastStatusAt = nil
        self.lastCheckpointAt = nil
        self.statusWriteCount = 0
        self.lastError = nil
        self.lastSyncAt = .distantPast
        self.lastEventLogSyncAt = .distantPast
        self.metadata = metadata
        self.finalSummary = [:]
        self.handlesClosed = false
        self.postCloseStatusRefresh = false
        self.fileMetricsRecomputedAt = nil
        self.compactRawNotificationCountsByKey = [:]
        try writeManifestLocked(status: "active")
        writeStatusLocked(lines: ["status=active"])
        result = .success(snapshotLocked())
      } catch {
        self.lastError = String(describing: error)
        result = .failure(error)
      }
    }
    return try result.get()
  }

  func resume(
    sessionID: String,
    directoryURL: URL,
    metadata: [String: Any],
    notificationCount: Int,
    historicalRangePollCount: Int,
    commandWriteCount: Int,
    eventLogCount: Int,
    rawByteCount: Int,
    historicalRangePollByteCount: Int,
    commandWriteByteCount: Int,
    eventLogByteCount: Int,
    startedAt: Date,
    lastNotificationAt: Date?
  ) throws -> OvernightRawSpoolSnapshot {
    var result: Result<OvernightRawSpoolSnapshot, Error>!
    queue.sync {
      do {
        finishLocked(status: "replaced_by_resumed_session")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.applyOvernightProtection(to: directoryURL.deletingLastPathComponent().deletingLastPathComponent())
        try Self.applyOvernightProtection(to: directoryURL.deletingLastPathComponent())
        try Self.applyOvernightProtection(to: directoryURL)
        let rawURL = directoryURL.appendingPathComponent("raw-notifications.jsonl")
        let rangePollsURL = directoryURL.appendingPathComponent("historical-range-polls.jsonl")
        let commandWritesURL = directoryURL.appendingPathComponent("command-writes.jsonl")
        let eventLogURL = directoryURL.appendingPathComponent("event-log.jsonl")
        let checkpointsURL = directoryURL.appendingPathComponent("checkpoints.jsonl")
        let checkpointLatestURL = directoryURL.appendingPathComponent("checkpoint-latest.json")
        let statusURL = directoryURL.appendingPathComponent("status.txt")
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let crashMarkerURL = directoryURL.appendingPathComponent("crash-marker.json")
        try Self.createFileIfMissing(rawURL)
        try Self.createFileIfMissing(rangePollsURL)
        try Self.createFileIfMissing(commandWritesURL)
        try Self.createFileIfMissing(eventLogURL)
        try Self.createFileIfMissing(checkpointsURL)
        try Self.createFileIfMissing(checkpointLatestURL)
        try Self.createFileIfMissing(statusURL)
        try Self.createFileIfMissing(manifestURL)
        try Self.createFileIfMissing(crashMarkerURL)
        try Self.applyOvernightProtection(to: rawURL)
        try Self.applyOvernightProtection(to: rangePollsURL)
        try Self.applyOvernightProtection(to: commandWritesURL)
        try Self.applyOvernightProtection(to: eventLogURL)
        try Self.applyOvernightProtection(to: checkpointsURL)
        try Self.applyOvernightProtection(to: checkpointLatestURL)
        try Self.applyOvernightProtection(to: statusURL)
        try Self.applyOvernightProtection(to: manifestURL)
        try Self.applyOvernightProtection(to: crashMarkerURL)
        let handle = try FileHandle(forWritingTo: rawURL)
        let historicalRangePollsHandle = try FileHandle(forWritingTo: rangePollsURL)
        let commandWritesHandle = try FileHandle(forWritingTo: commandWritesURL)
        let eventLogHandle = try FileHandle(forWritingTo: eventLogURL)
        let checkpointHandle = try FileHandle(forWritingTo: checkpointsURL)
        try handle.seekToEnd()
        try historicalRangePollsHandle.seekToEnd()
        try commandWritesHandle.seekToEnd()
        try eventLogHandle.seekToEnd()
        try checkpointHandle.seekToEnd()
        let checkpointMetrics = (try? Self.jsonlFileMetrics(at: checkpointsURL)) ?? FileMetrics(recordCount: 0, byteCount: 0)
        self.sessionID = sessionID
        self.directoryURL = directoryURL
        self.rawNotificationsURL = rawURL
        self.historicalRangePollsURL = rangePollsURL
        self.commandWritesURL = commandWritesURL
        self.eventLogURL = eventLogURL
        self.checkpointsURL = checkpointsURL
        self.checkpointLatestURL = checkpointLatestURL
        self.statusURL = statusURL
        self.manifestURL = manifestURL
        self.crashMarkerURL = crashMarkerURL
        self.handle = handle
        self.historicalRangePollsHandle = historicalRangePollsHandle
        self.commandWritesHandle = commandWritesHandle
        self.eventLogHandle = eventLogHandle
        self.checkpointHandle = checkpointHandle
        setActiveFlag(true)
        self.notificationCount = notificationCount
        self.historicalRangePollCount = historicalRangePollCount
        self.commandWriteCount = commandWriteCount
        self.eventLogCount = eventLogCount
        self.checkpointCount = checkpointMetrics.recordCount
        self.byteCount = rawByteCount
        self.historicalRangePollByteCount = historicalRangePollByteCount
        self.commandWriteByteCount = commandWriteByteCount
        self.eventLogByteCount = eventLogByteCount
        self.checkpointByteCount = checkpointMetrics.byteCount
        self.startedAt = startedAt
        self.endedAt = nil
        self.lastNotificationAt = lastNotificationAt
        self.lastStatusAt = nil
        self.lastCheckpointAt = nil
        self.statusWriteCount = 0
        self.lastError = nil
        self.lastSyncAt = .distantPast
        self.lastEventLogSyncAt = .distantPast
        self.metadata = metadata
        self.finalSummary = [:]
        self.handlesClosed = false
        self.postCloseStatusRefresh = false
        self.fileMetricsRecomputedAt = nil
        self.compactRawNotificationCountsByKey = [:]
        try writeManifestLocked(status: "active")
        writeStatusLocked(lines: ["status=active", "active=true", "resumed=true"])
        result = .success(snapshotLocked())
      } catch {
        self.lastError = String(describing: error)
        result = .failure(error)
      }
    }
    return try result.get()
  }

  func append(event: GooseNotificationEvent, activeDeviceName: String, connectionState: String) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard let handle, let sessionID else {
        lastError = "raw spool is not active"
        return snapshotLocked()
      }
      let capturedAt = Self.timestampFormatter.string(from: event.capturedAt)
      let classification = OvernightRawNotificationStorageClassifier.classify(event)
      let compactFamilyCount: Int?
      let includeFullPayload: Bool
      if let compactKey = classification.compactKey {
        let count = (compactRawNotificationCountsByKey[compactKey] ?? 0) + 1
        compactRawNotificationCountsByKey[compactKey] = count
        compactFamilyCount = count
        includeFullPayload = OvernightRawNotificationStorageClassifier.shouldKeepCompactLiveSample(count: count)
      } else {
        compactFamilyCount = nil
        includeFullPayload = true
      }
      let storagePolicy: String
      if classification.isCompactLiveFlood {
        storagePolicy = includeFullPayload ? "sampled_full_payload" : "compact_live_motion"
      } else {
        storagePolicy = "full_payload"
      }

      var row: [String: Any] = [
        "schema": "goose.overnight.raw_notification.v2",
        "session_id": sessionID,
        "captured_at": capturedAt,
        "source": "ios.corebluetooth.raw_notification",
        "device_id": event.deviceID.uuidString,
        "active_device_name": activeDeviceName,
        "connection_state": connectionState,
        "service_uuid": event.serviceUUID,
        "characteristic_uuid": event.characteristicUUID,
        "device_type": event.rustDeviceType,
        "byte_count": event.value.count,
        "sha256": event.value.sha256HexString,
        "checksum_algorithm": OvernightRawNotificationStorageClassifier.checksumAlgorithm,
        "lean_spool": true,
        "storage_policy": storagePolicy,
      ]
      if let packetType = classification.packetType {
        row["packet_type"] = Int(packetType)
      }
      if let packetK = classification.packetK {
        row["packet_k"] = Int(packetK)
      }
      if let compactKey = classification.compactKey, let compactFamilyCount {
        row["compact_key"] = compactKey
        row["compact_family_count"] = compactFamilyCount
        row["compact_sample_policy"] = OvernightRawNotificationStorageClassifier.compactLiveSamplePolicy
      }
      if includeFullPayload {
        let valueHex = event.value.hexString
        row["value_hex"] = valueHex
        row["frame_hex"] = valueHex
      } else {
        row["value_hex_omitted"] = true
        row["frame_hex_omitted"] = true
        row["omitted_reason"] = "known_repeating_live_motion_family"
      }
      do {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0a]))
        notificationCount += 1
        byteCount += data.count + 1
        lastNotificationAt = event.capturedAt
        let now = Date()
        if notificationCount.isMultiple(of: Self.rawNotificationSyncRecordInterval)
          || now.timeIntervalSince(lastSyncAt) >= Self.rawNotificationSyncInterval,
          synchronizeHandleLocked(handle, label: "raw notifications sync") {
          lastSyncAt = now
        }
      } catch {
        recordFileErrorLocked("raw notification append", error)
      }
      return snapshotLocked()
    }
  }

  func appendHistoricalRangeTelemetry(_ telemetry: GooseHistoricalRangeTelemetry) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard let handle = historicalRangePollsHandle, let sessionID else {
        lastError = "historical range spool is not active"
        return snapshotLocked()
      }
      let payloadData = Data(hexString: telemetry.payloadHex) ?? Data()
      let bodyData = Data(hexString: telemetry.bodyHex) ?? Data()
      let row: [String: Any] = [
        "schema": "goose.overnight.historical_range_poll.v1",
        "session_id": sessionID,
        "captured_at": Self.timestampFormatter.string(from: telemetry.capturedAt),
        "status": telemetry.status,
        "command_sequence": Int(telemetry.commandSequence),
        "result_code": Int(telemetry.resultCode),
        "result_name": telemetry.resultName,
        "raw_payload_hex": telemetry.payloadHex,
        "raw_body_hex": telemetry.bodyHex,
        "raw_payload_sha256": payloadData.sha256HexString,
        "raw_body_sha256": bodyData.sha256HexString,
        "checksum_algorithm": "sha256(raw_payload_hex/raw_body_hex)",
        "revision_or_status": telemetry.revisionOrStatus.map { Int($0) } ?? NSNull(),
        "u32_words_from_offset_1": telemetry.wordsFromOffset1.map { Int64($0) },
        "page_current": telemetry.pageCurrent.map { Int64($0) } ?? NSNull(),
        "page_oldest": telemetry.pageOldest.map { Int64($0) } ?? NSNull(),
        "page_end": telemetry.pageEnd.map { Int64($0) } ?? NSNull(),
        "pages_behind": telemetry.pagesBehind ?? NSNull(),
        "pending_response_count": telemetry.pendingResponseCount,
        "retry_count": telemetry.retryCount,
        "notes": telemetry.notes,
      ]
      do {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0a]))
        historicalRangePollCount += 1
        historicalRangePollByteCount += data.count + 1
        synchronizeHandleLocked(handle, label: "historical range sync")
      } catch {
        recordFileErrorLocked("historical range append", error)
      }
      return snapshotLocked()
    }
  }

  func appendCommandWrite(_ event: GooseCommandWriteEvent, activeDeviceName: String, connectionState: String) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard let handle = commandWritesHandle, let sessionID else {
        lastError = "command write spool is not active"
        return snapshotLocked()
      }
      let payloadHex = event.payload.hexString
      let frameHex = event.frame.hexString
      let row: [String: Any] = [
        "schema": "goose.overnight.command_write.v1",
        "session_id": sessionID,
        "captured_at": Self.timestampFormatter.string(from: event.capturedAt),
        "source": event.source,
        "device_id": event.deviceID.uuidString,
        "active_device_name": activeDeviceName,
        "connection_state": connectionState,
        "service_uuid": event.serviceUUID,
        "characteristic_uuid": event.characteristicUUID,
        "command_name": event.commandName,
        "command_number": event.commandNumber.map { Int($0) } ?? NSNull(),
        "sequence": event.sequence.map { Int($0) } ?? NSNull(),
        "write_type": event.writeType,
        "payload_byte_count": event.payload.count,
        "frame_byte_count": event.frame.count,
        "payload_hex": payloadHex,
        "frame_hex": frameHex,
        "payload_sha256": event.payload.sha256HexString,
        "frame_sha256": event.frame.sha256HexString,
        "checksum_algorithm": "sha256(payload_hex/frame_hex)",
      ]
      do {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0a]))
        commandWriteCount += 1
        commandWriteByteCount += data.count + 1
        synchronizeHandleLocked(handle, label: "command writes sync")
      } catch {
        recordFileErrorLocked("command write append", error)
      }
      return snapshotLocked()
    }
  }

  func appendEventLog(_ message: GooseMessage) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard let handle = eventLogHandle, let sessionID else {
        lastError = "event log spool is not active"
        return snapshotLocked()
      }
      let row: [String: Any] = [
        "schema": "goose.overnight.event_log.v1",
        "session_id": sessionID,
        "captured_at": Self.timestampFormatter.string(from: message.timestamp),
        "level": message.level.rawValue,
        "source": message.source,
        "title": message.title,
        "body": message.body,
      ]
      do {
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0a]))
        eventLogCount += 1
        eventLogByteCount += data.count + 1
        let now = Date()
        if (eventLogCount % 16 == 0 || now.timeIntervalSince(lastEventLogSyncAt) >= Self.eventLogSyncInterval)
          && synchronizeHandleLocked(handle, label: "event log sync") {
          lastEventLogSyncAt = now
        }
      } catch {
        recordFileErrorLocked("event log append", error)
      }
      return snapshotLocked()
    }
  }

  func writeStatus(lines: [String]) -> OvernightRawSpoolSnapshot {
    queue.sync {
      writeStatusLocked(lines: lines)
      return snapshotLocked()
    }
  }

  func finish(status: String, summary: [String: Any] = [:]) -> OvernightRawSpoolSnapshot {
    queue.sync {
      finishLocked(status: status, summary: summary)
      return snapshotLocked()
    }
  }

  func updateFinalSummary(status: String, summary: [String: Any]) -> OvernightRawSpoolSnapshot {
    queue.sync {
      finalSummary = summary
      writeManifestWithErrorLocked(status: status)
      return snapshotLocked()
    }
  }

  func synchronizeActive(reason: String) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard handle != nil || historicalRangePollsHandle != nil || commandWritesHandle != nil || eventLogHandle != nil || checkpointHandle != nil else {
        return snapshotLocked()
      }
      synchronizeHandleLocked(handle, label: "raw notifications \(reason) sync")
      synchronizeHandleLocked(historicalRangePollsHandle, label: "historical range \(reason) sync")
      synchronizeHandleLocked(commandWritesHandle, label: "command writes \(reason) sync")
      synchronizeHandleLocked(eventLogHandle, label: "event log \(reason) sync")
      synchronizeHandleLocked(checkpointHandle, label: "checkpoint \(reason) sync")
      writeManifestWithErrorLocked(status: "active")
      writeCheckpointLocked(reason: "synchronize_\(reason)", force: true)
      return snapshotLocked()
    }
  }

  func suspendActive(reason: String) -> OvernightRawSpoolSnapshot {
    queue.sync {
      guard handle != nil || sessionID != nil else {
        return snapshotLocked()
      }
      synchronizeHandleLocked(handle, label: "raw notifications suspend sync")
      synchronizeHandleLocked(historicalRangePollsHandle, label: "historical range suspend sync")
      synchronizeHandleLocked(commandWritesHandle, label: "command writes suspend sync")
      synchronizeHandleLocked(eventLogHandle, label: "event log suspend sync")
      synchronizeHandleLocked(checkpointHandle, label: "checkpoint suspend sync")
      writeManifestWithErrorLocked(status: "active")
      writeStatusLocked(lines: ["status=active", "active=true", "suspended_reason=\(reason)"])
      closeHandleLocked(handle, label: "raw notifications suspend close")
      closeHandleLocked(historicalRangePollsHandle, label: "historical range suspend close")
      closeHandleLocked(commandWritesHandle, label: "command writes suspend close")
      closeHandleLocked(eventLogHandle, label: "event log suspend close")
      handle = nil
      historicalRangePollsHandle = nil
      commandWritesHandle = nil
      eventLogHandle = nil
      setActiveFlag(false)
      handlesClosed = true
      recomputeFileMetricsLocked(reason: "suspend")
      postCloseStatusRefresh = true
      writeStatusLocked(lines: [
        "status=active",
        "active=true",
        "suspended_reason=\(reason)",
        "handles_closed=true",
        "post_close_status_refresh=true",
      ])
      writeManifestWithErrorLocked(status: "active")
      writeCheckpointLocked(reason: "suspend_\(reason)", force: true)
      closeHandleLocked(checkpointHandle, label: "checkpoint suspend close")
      checkpointHandle = nil
      return snapshotLocked()
    }
  }

  var snapshot: OvernightRawSpoolSnapshot {
    queue.sync {
      snapshotLocked()
    }
  }

  var isActive: Bool {
    activeStateLock.lock()
    defer {
      activeStateLock.unlock()
    }
    return activeFlag
  }

  private func setActiveFlag(_ active: Bool) {
    activeStateLock.lock()
    activeFlag = active
    activeStateLock.unlock()
  }

  private func finishLocked(status: String, summary: [String: Any] = [:]) {
    guard handle != nil || sessionID != nil else {
      return
    }
    endedAt = Date()
    if !summary.isEmpty {
      finalSummary = summary
    }
    synchronizeHandleLocked(handle, label: "raw notifications final sync")
    synchronizeHandleLocked(historicalRangePollsHandle, label: "historical range final sync")
    synchronizeHandleLocked(commandWritesHandle, label: "command writes final sync")
    synchronizeHandleLocked(eventLogHandle, label: "event log final sync")
    synchronizeHandleLocked(checkpointHandle, label: "checkpoint final sync")
    writeManifestWithErrorLocked(status: status)
    writeStatusLocked(lines: [
      "status=\(status)",
      "active=false",
      "reason=\(status)",
      "terminal_status_written_by=overnight_raw_spool",
    ])
    closeHandleLocked(handle, label: "raw notifications final close")
    closeHandleLocked(historicalRangePollsHandle, label: "historical range final close")
    closeHandleLocked(commandWritesHandle, label: "command writes final close")
    closeHandleLocked(eventLogHandle, label: "event log final close")
    handle = nil
    historicalRangePollsHandle = nil
    commandWritesHandle = nil
    eventLogHandle = nil
    setActiveFlag(false)
    handlesClosed = true
    recomputeFileMetricsLocked(reason: "final")
    postCloseStatusRefresh = true
    writeStatusLocked(lines: [
      "status=\(status)",
      "active=false",
      "reason=\(status)",
      "terminal_status_written_by=overnight_raw_spool",
      "handles_closed=true",
      "post_close_status_refresh=true",
    ])
    writeManifestWithErrorLocked(status: status)
    writeCheckpointLocked(reason: "finish_\(status)", force: true)
    closeHandleLocked(checkpointHandle, label: "checkpoint final close")
    checkpointHandle = nil
  }

  @discardableResult
  private func synchronizeHandleLocked(_ handle: FileHandle?, label: String) -> Bool {
    guard let handle else {
      return true
    }
    do {
      try handle.synchronize()
      return true
    } catch {
      recordFileErrorLocked(label, error)
      return false
    }
  }

  private func closeHandleLocked(_ handle: FileHandle?, label: String) {
    guard let handle else {
      return
    }
    do {
      try handle.close()
    } catch {
      recordFileErrorLocked(label, error)
    }
  }

  private func writeManifestWithErrorLocked(status: String) {
    do {
      try writeManifestLocked(status: status)
    } catch {
      recordFileErrorLocked("manifest write", error)
    }
  }

  private func recordFileErrorLocked(_ label: String, _ error: Error) {
    lastError = "\(label) failed: \(String(describing: error))"
  }

  private func writeManifestLocked(status: String) throws {
    guard let manifestURL, let sessionID else {
      return
    }
    var manifest: [String: Any] = [
      "schema": "goose.overnight.manifest.v1",
      "session_id": sessionID,
      "status": status,
      "notification_count": notificationCount,
      "historical_range_poll_count": historicalRangePollCount,
      "command_write_count": commandWriteCount,
      "event_log_count": eventLogCount,
      "checkpoint_count": checkpointCount,
      "byte_count": byteCount,
      "historical_range_poll_byte_count": historicalRangePollByteCount,
      "command_write_byte_count": commandWriteByteCount,
      "event_log_byte_count": eventLogByteCount,
      "checkpoint_byte_count": checkpointByteCount,
      "total_byte_count": byteCount + historicalRangePollByteCount + commandWriteByteCount + eventLogByteCount,
      "started_at": startedAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "ended_at": endedAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "last_notification_at": lastNotificationAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "raw_notifications_path": rawNotificationsURL?.lastPathComponent ?? NSNull(),
      "historical_range_polls_path": historicalRangePollsURL?.lastPathComponent ?? NSNull(),
      "command_writes_path": commandWritesURL?.lastPathComponent ?? NSNull(),
      "event_log_path": eventLogURL?.lastPathComponent ?? NSNull(),
      "checkpoints_path": checkpointsURL?.lastPathComponent ?? NSNull(),
      "checkpoint_latest_path": checkpointLatestURL?.lastPathComponent ?? NSNull(),
      "crash_marker_path": crashMarkerURL?.lastPathComponent ?? NSNull(),
      "raw_notification_checksum_algorithm": OvernightRawNotificationStorageClassifier.checksumAlgorithm,
      "historical_range_checksum_algorithm": "sha256(raw_payload_hex/raw_body_hex)",
      "command_write_checksum_algorithm": "sha256(payload_hex/frame_hex)",
      "file_protection": Self.overnightProtection.rawValue,
      "process_launch_id": processLaunchID,
      "process_launch_started_at": Self.timestampFormatter.string(from: processLaunchStartedAt),
      "last_status_at": lastStatusAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "last_checkpoint_at": lastCheckpointAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "status_write_count": statusWriteCount,
      "last_error": lastError ?? NSNull(),
      "handles_closed": handlesClosed,
      "post_close_status_refresh": postCloseStatusRefresh,
      "file_metrics_recomputed_at": fileMetricsRecomputedAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
    ]
    if !metadata.isEmpty {
      manifest["metadata"] = metadata
    }
    if !finalSummary.isEmpty {
      manifest["summary"] = finalSummary
    }
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try writeProtectedSidecarLocked(data, to: manifestURL)
  }

  private func writeStatusLocked(lines: [String]) {
    guard let statusURL else {
      return
    }
    let now = Date()
    lastStatusAt = now
    statusWriteCount += 1
    let timestamp = Self.timestampFormatter.string(from: now)
    var output = [
      "timestamp=\(timestamp)",
      "heartbeat_at=\(timestamp)",
      "session_id=\(sessionID ?? "none")",
      "process_launch_id=\(processLaunchID)",
      "process_launch_started_at=\(Self.timestampFormatter.string(from: processLaunchStartedAt))",
      "status_write_count=\(statusWriteCount)",
      "notification_count=\(notificationCount)",
      "historical_range_poll_count=\(historicalRangePollCount)",
      "command_write_count=\(commandWriteCount)",
      "event_log_count=\(eventLogCount)",
      "checkpoint_count=\(checkpointCount)",
      "byte_count=\(byteCount)",
      "raw_byte_count=\(byteCount)",
      "historical_range_poll_byte_count=\(historicalRangePollByteCount)",
      "command_write_byte_count=\(commandWriteByteCount)",
      "event_log_byte_count=\(eventLogByteCount)",
      "checkpoint_byte_count=\(checkpointByteCount)",
      "total_byte_count=\(byteCount + historicalRangePollByteCount + commandWriteByteCount + eventLogByteCount)",
      "raw_notifications=\(rawNotificationsURL?.path ?? "none")",
      "historical_range_polls=\(historicalRangePollsURL?.path ?? "none")",
      "command_writes=\(commandWritesURL?.path ?? "none")",
      "event_log=\(eventLogURL?.path ?? "none")",
      "checkpoints=\(checkpointsURL?.path ?? "none")",
      "checkpoint_latest=\(checkpointLatestURL?.path ?? "none")",
      "crash_marker=\(crashMarkerURL?.path ?? "none")",
      "raw_notification_checksum_algorithm=\(OvernightRawNotificationStorageClassifier.checksumAlgorithm)",
      "historical_range_checksum_algorithm=sha256(raw_payload_hex/raw_body_hex)",
      "command_write_checksum_algorithm=sha256(payload_hex/frame_hex)",
      "last_notification_at=\(lastNotificationAt.map { Self.timestampFormatter.string(from: $0) } ?? "none")",
      "last_checkpoint_at=\(lastCheckpointAt.map { Self.timestampFormatter.string(from: $0) } ?? "none")",
      "last_error=\(lastError ?? "none")",
      "handles_closed=\(handlesClosed)",
      "post_close_status_refresh=\(postCloseStatusRefresh)",
      "file_metrics_recomputed_at=\(fileMetricsRecomputedAt.map { Self.timestampFormatter.string(from: $0) } ?? "none")",
    ]
    output.append(contentsOf: lines)
    do {
      let data = Data(output.joined(separator: "\n").appending("\n").utf8)
      try writeProtectedSidecarLocked(data, to: statusURL)
    } catch {
      recordFileErrorLocked("status write", error)
    }
    writeCrashMarkerLocked(timestamp: timestamp, statusLines: output)
    let values = Self.statusValueMap(output)
    writeCheckpointLocked(
      reason: values["reason"] ?? values["status"] ?? "status",
      statusLines: output,
      force: false,
      timestamp: timestamp,
      now: now
    )
  }

  private func writeCrashMarkerLocked(timestamp: String, statusLines: [String]) {
    guard let crashMarkerURL else {
      return
    }
    let values = Self.statusValueMap(statusLines)
    let activeText = values["active"] ?? (handle != nil ? "true" : "false")
    let active = activeText == "true"
    let markerLastError: Any
    if let lastError {
      markerLastError = lastError
    } else if let statusLastError = values["last_error"] {
      markerLastError = statusLastError
    } else {
      markerLastError = NSNull()
    }
    let marker: [String: Any] = [
      "schema": "goose.overnight.crash_marker.v1",
      "session_id": sessionID ?? "none",
      "active": active,
      "status": values["status"] ?? (active ? "active" : "inactive"),
      "reason": values["reason"] ?? NSNull(),
      "last_status_at": timestamp,
      "process_launch_id": processLaunchID,
      "process_launch_started_at": Self.timestampFormatter.string(from: processLaunchStartedAt),
      "status_write_count": statusWriteCount,
      "notification_count": notificationCount,
      "historical_range_poll_count": historicalRangePollCount,
      "command_write_count": commandWriteCount,
      "event_log_count": eventLogCount,
      "checkpoint_count": checkpointCount,
      "raw_byte_count": byteCount,
      "historical_range_poll_byte_count": historicalRangePollByteCount,
      "command_write_byte_count": commandWriteByteCount,
      "event_log_byte_count": eventLogByteCount,
      "checkpoint_byte_count": checkpointByteCount,
      "total_byte_count": byteCount + historicalRangePollByteCount + commandWriteByteCount + eventLogByteCount,
      "last_notification_at": lastNotificationAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "last_checkpoint_at": lastCheckpointAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "raw_notifications_path": rawNotificationsURL?.lastPathComponent ?? NSNull(),
      "historical_range_polls_path": historicalRangePollsURL?.lastPathComponent ?? NSNull(),
      "command_writes_path": commandWritesURL?.lastPathComponent ?? NSNull(),
      "event_log_path": eventLogURL?.lastPathComponent ?? NSNull(),
      "checkpoints_path": checkpointsURL?.lastPathComponent ?? NSNull(),
      "checkpoint_latest_path": checkpointLatestURL?.lastPathComponent ?? NSNull(),
      "status_path": statusURL?.lastPathComponent ?? NSNull(),
      "manifest_path": manifestURL?.lastPathComponent ?? NSNull(),
      "raw_notification_checksum_algorithm": OvernightRawNotificationStorageClassifier.checksumAlgorithm,
      "historical_range_checksum_algorithm": "sha256(raw_payload_hex/raw_body_hex)",
      "command_write_checksum_algorithm": "sha256(payload_hex/frame_hex)",
	      "file_protection": Self.overnightProtection.rawValue,
	      "last_error": markerLastError,
	      "raw_spool_warning": values["raw_spool_warning"] ?? NSNull(),
	      "ble_log_warning": values["ble_log_warning"] ?? NSNull(),
	      "export_manifest_error": values["export_manifest_error"] ?? NSNull(),
	      "handles_closed": Self.statusBoolValue(values["handles_closed"]) ?? handlesClosed,
	      "post_close_status_refresh": Self.statusBoolValue(values["post_close_status_refresh"]) ?? postCloseStatusRefresh,
	      "file_metrics_recomputed_at": values["file_metrics_recomputed_at"] ?? fileMetricsRecomputedAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
      try writeProtectedSidecarLocked(data, to: crashMarkerURL)
    } catch {
      recordFileErrorLocked("crash marker write", error)
    }
  }

  private func writeCheckpointLocked(
    reason: String,
    statusLines: [String]? = nil,
    force: Bool,
    timestamp: String? = nil,
    now: Date = Date()
  ) {
    guard let checkpointHandle, let checkpointLatestURL, let sessionID else {
      return
    }
    if !force, let lastCheckpointAt, now.timeIntervalSince(lastCheckpointAt) < Self.checkpointInterval {
      return
    }

    let checkpointTimestamp = timestamp ?? Self.timestampFormatter.string(from: now)
    let statusValues = statusLines.map(Self.statusValueMap) ?? [:]
    let activeText = statusValues["active"] ?? (handle != nil ? "true" : "false")
    let checkpointIndex = checkpointCount + 1
    var checkpoint: [String: Any] = [
      "schema": "goose.overnight.checkpoint.v1",
      "session_id": sessionID,
      "checkpoint_index": checkpointIndex,
      "checkpoint_at": checkpointTimestamp,
      "reason": reason,
      "active": Self.statusBoolValue(activeText) ?? (handle != nil),
      "status": statusValues["status"] ?? (handle != nil ? "active" : "inactive"),
      "process_launch_id": processLaunchID,
      "process_launch_started_at": Self.timestampFormatter.string(from: processLaunchStartedAt),
      "notification_count": notificationCount,
      "historical_range_poll_count": historicalRangePollCount,
      "command_write_count": commandWriteCount,
      "event_log_count": eventLogCount,
      "raw_byte_count": byteCount,
      "historical_range_poll_byte_count": historicalRangePollByteCount,
      "command_write_byte_count": commandWriteByteCount,
      "event_log_byte_count": eventLogByteCount,
      "total_byte_count": byteCount + historicalRangePollByteCount + commandWriteByteCount + eventLogByteCount,
      "last_notification_at": lastNotificationAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "last_status_at": lastStatusAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "raw_notifications_path": rawNotificationsURL?.lastPathComponent ?? NSNull(),
      "historical_range_polls_path": historicalRangePollsURL?.lastPathComponent ?? NSNull(),
      "command_writes_path": commandWritesURL?.lastPathComponent ?? NSNull(),
      "event_log_path": eventLogURL?.lastPathComponent ?? NSNull(),
      "checkpoints_path": checkpointsURL?.lastPathComponent ?? NSNull(),
      "checkpoint_latest_path": checkpointLatestURL.lastPathComponent,
      "manifest_path": manifestURL?.lastPathComponent ?? NSNull(),
      "status_path": statusURL?.lastPathComponent ?? NSNull(),
      "crash_marker_path": crashMarkerURL?.lastPathComponent ?? NSNull(),
      "handles_closed": handlesClosed,
      "post_close_status_refresh": postCloseStatusRefresh,
      "file_metrics_recomputed_at": fileMetricsRecomputedAt.map { Self.timestampFormatter.string(from: $0) } ?? NSNull(),
      "last_error": lastError ?? NSNull(),
      "raw_spool_warning": statusValues["raw_spool_warning"] ?? NSNull(),
      "ble_log_warning": statusValues["ble_log_warning"] ?? NSNull(),
      "export_manifest_error": statusValues["export_manifest_error"] ?? NSNull(),
      "file_protection": Self.overnightProtection.rawValue,
    ]
    if !statusValues.isEmpty {
      checkpoint["status_values"] = statusValues
    }

    do {
      let data = try JSONSerialization.data(withJSONObject: checkpoint, options: [.sortedKeys])
      try checkpointHandle.write(contentsOf: data)
      try checkpointHandle.write(contentsOf: Data([0x0a]))
      checkpointCount = checkpointIndex
      checkpointByteCount += data.count + 1
      lastCheckpointAt = now
      synchronizeHandleLocked(checkpointHandle, label: "checkpoint append sync")

      var latest = checkpoint
      latest["checkpoint_count"] = checkpointCount
      latest["checkpoint_byte_count"] = checkpointByteCount
      let latestData = try JSONSerialization.data(withJSONObject: latest, options: [.prettyPrinted, .sortedKeys])
      try writeProtectedSidecarLocked(latestData, to: checkpointLatestURL)
    } catch {
      recordFileErrorLocked("checkpoint write", error)
    }
  }

  private func writeProtectedSidecarLocked(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try Self.applyOvernightProtection(to: url)

    let handle = try FileHandle(forUpdating: url)
    var fileError: Error?
    do {
      try handle.synchronize()
    } catch {
      fileError = error
    }
    do {
      try handle.close()
    } catch {
      if fileError == nil {
        fileError = error
      }
    }
    if let fileError {
      throw fileError
    }
  }

  private static func statusValueMap(_ lines: [String]) -> [String: String] {
    var values: [String: String] = [:]
    for line in lines {
      guard let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<separator])
      let value = String(line[line.index(after: separator)...])
      values[key] = value
    }
    return values
  }

  private static func statusBoolValue(_ value: String?) -> Bool? {
    guard let value else {
      return nil
    }
    switch value.lowercased() {
    case "true", "1", "yes":
      return true
    case "false", "0", "no":
      return false
    default:
      return nil
    }
  }

  private static func applyOvernightProtection(to url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: overnightProtection],
      ofItemAtPath: url.path
    )
  }

  private static func createFileIfMissing(_ url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else {
      return
    }
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
      if FileManager.default.fileExists(atPath: url.path) {
        return
      }
      throw NSError(
        domain: NSCocoaErrorDomain,
        code: NSFileWriteUnknownError,
        userInfo: [
          NSFilePathErrorKey: url.path,
          NSLocalizedDescriptionKey: "Failed to create overnight proof file \(url.lastPathComponent)",
        ]
      )
    }
  }

  private func recomputeFileMetricsLocked(reason: String) {
    if let rawNotificationsURL {
      do {
        let metrics = try Self.jsonlFileMetrics(at: rawNotificationsURL)
        notificationCount = metrics.recordCount
        byteCount = metrics.byteCount
      } catch {
        recordFileErrorLocked("raw notification file metrics \(reason)", error)
      }
    }
    if let historicalRangePollsURL {
      do {
        let metrics = try Self.jsonlFileMetrics(at: historicalRangePollsURL)
        historicalRangePollCount = metrics.recordCount
        historicalRangePollByteCount = metrics.byteCount
      } catch {
        recordFileErrorLocked("historical range file metrics \(reason)", error)
      }
    }
    if let commandWritesURL {
      do {
        let metrics = try Self.jsonlFileMetrics(at: commandWritesURL)
        commandWriteCount = metrics.recordCount
        commandWriteByteCount = metrics.byteCount
      } catch {
        recordFileErrorLocked("command write file metrics \(reason)", error)
      }
    }
    if let eventLogURL {
      do {
        let metrics = try Self.jsonlFileMetrics(at: eventLogURL)
        eventLogCount = metrics.recordCount
        eventLogByteCount = metrics.byteCount
      } catch {
        recordFileErrorLocked("event log file metrics \(reason)", error)
      }
    }
    if let checkpointsURL {
      do {
        let metrics = try Self.jsonlFileMetrics(at: checkpointsURL)
        checkpointCount = metrics.recordCount
        checkpointByteCount = metrics.byteCount
      } catch {
        recordFileErrorLocked("checkpoint file metrics \(reason)", error)
      }
    }
    fileMetricsRecomputedAt = Date()
  }

  private static func jsonlFileMetrics(at url: URL) throws -> FileMetrics {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }

    var recordCount = 0
    var hasBytesInCurrentLine = false
    while true {
      let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
      if chunk.isEmpty {
        break
      }
      for byte in chunk {
        if byte == 0x0a {
          if hasBytesInCurrentLine {
            recordCount += 1
            hasBytesInCurrentLine = false
          }
        } else if byte != 0x0d {
          hasBytesInCurrentLine = true
        }
      }
    }
    if hasBytesInCurrentLine {
      recordCount += 1
    }
    return FileMetrics(recordCount: recordCount, byteCount: byteCount)
  }

  private func snapshotLocked() -> OvernightRawSpoolSnapshot {
    OvernightRawSpoolSnapshot(
      sessionID: sessionID,
      directoryURL: directoryURL,
      rawNotificationsURL: rawNotificationsURL,
      historicalRangePollsURL: historicalRangePollsURL,
      commandWritesURL: commandWritesURL,
      eventLogURL: eventLogURL,
      checkpointsURL: checkpointsURL,
      checkpointLatestURL: checkpointLatestURL,
      statusURL: statusURL,
      manifestURL: manifestURL,
      notificationCount: notificationCount,
      historicalRangePollCount: historicalRangePollCount,
      commandWriteCount: commandWriteCount,
      eventLogCount: eventLogCount,
      checkpointCount: checkpointCount,
      byteCount: byteCount,
      historicalRangePollByteCount: historicalRangePollByteCount,
      commandWriteByteCount: commandWriteByteCount,
      eventLogByteCount: eventLogByteCount,
      checkpointByteCount: checkpointByteCount,
      totalByteCount: byteCount + historicalRangePollByteCount + commandWriteByteCount + eventLogByteCount,
      startedAt: startedAt,
      lastNotificationAt: lastNotificationAt,
      lastStatusAt: lastStatusAt,
      lastCheckpointAt: lastCheckpointAt,
      lastError: lastError
    )
  }
}

