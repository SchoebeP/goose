import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

extension GooseLocalDataExporter {
  static func bundleJSONStructureIssue(at url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return "could not open bundle for JSON validation"
    }
    defer {
      try? handle.close()
    }

    var stack: [UInt8] = []
    var inString = false
    var escaped = false
    var firstNonWhitespace: UInt8?
    var lastNonWhitespace: UInt8?
    var sawFilesKey = false
    var sawSummaryKey = false
    var recent = [UInt8]()
    let filesPattern = Array("\"files\"".utf8)
    let summaryPattern = Array("\"summary\"".utf8)

    while true {
      let chunk: Data
      do {
        chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
      } catch {
        return "could not read bundle for JSON validation: \(error.localizedDescription)"
      }
      if chunk.isEmpty {
        break
      }
      for byte in chunk {
        if byte > 0x20 {
          if firstNonWhitespace == nil {
            firstNonWhitespace = byte
          }
          lastNonWhitespace = byte
        }

        recent.append(byte)
        if recent.count > summaryPattern.count {
          recent.removeFirst(recent.count - summaryPattern.count)
        }
        if recent.suffix(filesPattern.count) == filesPattern[...] {
          sawFilesKey = true
        }
        if recent.suffix(summaryPattern.count) == summaryPattern[...] {
          sawSummaryKey = true
        }

        if inString {
          if escaped {
            escaped = false
          } else if byte == 0x5c {
            escaped = true
          } else if byte == 0x22 {
            inString = false
          } else if byte < 0x20 {
            return "control character inside JSON string"
          }
          continue
        }

        switch byte {
        case 0x09, 0x0a, 0x0d, 0x20:
          continue
        case 0x22:
          inString = true
        case 0x7b, 0x5b:
          stack.append(byte)
        case 0x7d:
          guard stack.popLast() == 0x7b else {
            return "unbalanced JSON object delimiter"
          }
        case 0x5d:
          guard stack.popLast() == 0x5b else {
            return "unbalanced JSON array delimiter"
          }
        default:
          continue
        }
      }
    }

    if inString || escaped {
      return "bundle JSON ended inside a string"
    }
    if !stack.isEmpty {
      return "bundle JSON ended with unclosed containers"
    }
    guard firstNonWhitespace == 0x7b, lastNonWhitespace == 0x7d else {
      return "bundle JSON does not start and end as an object"
    }
    guard sawFilesKey else {
      return "bundle JSON is missing files array"
    }
    guard sawSummaryKey else {
      return "bundle JSON is missing summary object"
    }
    return nil
  }

  static func applyRawNotificationMetrics(from url: URL, to metrics: inout GooseOvernightExportMetrics) {
    var previousDate: Date?
    if enumerateJSONLines(at: url, body: { object in
      guard let object else {
        metrics.rawNotificationParseErrorCount += 1
        return
      }
      metrics.rawNotificationCount += 1
      guard let capturedAt = object["captured_at"] as? String,
            let date = jsonlTimestampFormatter.date(from: capturedAt) else {
        metrics.rawNotificationParseErrorCount += 1
        return
      }
      if metrics.firstRawNotificationAt == nil {
        metrics.firstRawNotificationAt = capturedAt
      }
      metrics.lastRawNotificationAt = capturedAt
      let valueHex = (object["value_hex"] as? String) ?? (object["frame_hex"] as? String)
      let valueHexOmitted = boolValue(object["value_hex_omitted"]) == true
        || boolValue(object["frame_hex_omitted"]) == true
      let valueData = valueHex.flatMap { Data(hexString: $0) }
      if valueData == nil && !valueHexOmitted {
        metrics.rawNotificationValueHexInvalidCount += 1
      }
      if let checksum = object["sha256"] as? String, !checksum.isEmpty {
        let normalizedChecksum = checksum.lowercased()
        metrics.rawNotificationChecksumPresentCount += 1
        let checksumMismatch = !isSHA256Hex(normalizedChecksum)
          || (!valueHexOmitted && valueData?.sha256HexString != normalizedChecksum)
        if checksumMismatch {
          metrics.rawNotificationChecksumMismatchCount += 1
        }
      } else {
        metrics.rawNotificationChecksumMissingCount += 1
      }
      if let previousDate {
        let gap = date.timeIntervalSince(previousDate)
        if gap > 0 {
          metrics.maxRawNotificationGapSeconds = max(metrics.maxRawNotificationGapSeconds ?? 0, gap)
          if gap > 5 * 60 {
            metrics.rawNotificationGapsOver5Minutes += 1
          }
        }
      }
      previousDate = date
    }) != nil {
      metrics.rawNotificationParseErrorCount += 1
    }
  }

  static func isSHA256Hex(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
      (48...57).contains(Int(scalar.value)) || (97...102).contains(Int(scalar.value))
    }
  }

  static func applyHistoricalRangeMetrics(from url: URL, to metrics: inout GooseOvernightExportMetrics) {
    if enumerateJSONLines(at: url, body: { object in
      guard let object else {
        metrics.historicalRangePollParseErrorCount += 1
        return
      }
      metrics.historicalRangePollRecordCount += 1
      if (object["status"] as? String) == "success" {
        metrics.successfulHistoricalRangePollCount += 1
      }
      let payloadData = (object["raw_payload_hex"] as? String).flatMap { Data(hexString: $0) }
      let bodyData = (object["raw_body_hex"] as? String).flatMap { Data(hexString: $0) }
      if payloadData == nil || bodyData == nil {
        metrics.historicalRangeHexInvalidCount += 1
      }
      let payloadChecksum = object["raw_payload_sha256"] as? String
      let bodyChecksum = object["raw_body_sha256"] as? String
      if let payloadChecksum, !payloadChecksum.isEmpty,
         let bodyChecksum, !bodyChecksum.isEmpty {
        let normalizedPayloadChecksum = payloadChecksum.lowercased()
        let normalizedBodyChecksum = bodyChecksum.lowercased()
        metrics.historicalRangeChecksumPresentCount += 1
        if !isSHA256Hex(normalizedPayloadChecksum)
          || !isSHA256Hex(normalizedBodyChecksum)
          || payloadData?.sha256HexString != normalizedPayloadChecksum
          || bodyData?.sha256HexString != normalizedBodyChecksum {
          metrics.historicalRangeChecksumMismatchCount += 1
        }
      } else {
        metrics.historicalRangeChecksumMissingCount += 1
      }
    }) != nil {
      metrics.historicalRangePollParseErrorCount += 1
    }
  }

  static func applyCommandWriteMetrics(from url: URL, to metrics: inout GooseOvernightExportMetrics) {
    if enumerateJSONLines(at: url, body: { object in
      guard let object else {
        metrics.commandWriteParseErrorCount += 1
        return
      }
      metrics.commandWriteRecordCount += 1
      let payloadData = (object["payload_hex"] as? String).flatMap { Data(hexString: $0) }
      let frameData = (object["frame_hex"] as? String).flatMap { Data(hexString: $0) }
      if payloadData == nil || frameData == nil {
        metrics.commandWriteHexInvalidCount += 1
      }
      let payloadChecksum = object["payload_sha256"] as? String
      let frameChecksum = object["frame_sha256"] as? String
      if let payloadChecksum, !payloadChecksum.isEmpty,
         let frameChecksum, !frameChecksum.isEmpty {
        let normalizedPayloadChecksum = payloadChecksum.lowercased()
        let normalizedFrameChecksum = frameChecksum.lowercased()
        metrics.commandWriteChecksumPresentCount += 1
        if !isSHA256Hex(normalizedPayloadChecksum)
          || !isSHA256Hex(normalizedFrameChecksum)
          || payloadData?.sha256HexString != normalizedPayloadChecksum
          || frameData?.sha256HexString != normalizedFrameChecksum {
          metrics.commandWriteChecksumMismatchCount += 1
        }
      } else {
        metrics.commandWriteChecksumMissingCount += 1
      }
    }) != nil {
      metrics.commandWriteParseErrorCount += 1
    }
  }

  static func applyEventLogMetrics(from url: URL, to metrics: inout GooseOvernightExportMetrics) {
    if enumerateJSONLines(at: url, body: { object in
      guard object != nil else {
        metrics.overnightEventLogParseErrorCount += 1
        return
      }
      metrics.overnightEventLogRecordCount += 1
    }) != nil {
      metrics.overnightEventLogParseErrorCount += 1
    }
  }

  static func applySQLiteMirrorMetrics(
    databasePath: String,
    sessionID: String,
    to metrics: inout GooseOvernightExportMetrics,
    issues: inout [String]
  ) {
    do {
      let report = try GooseRustBridge().request(
        method: "overnight.mirror_counts",
        args: [
          "database_path": databasePath,
          "session_id": sessionID,
        ]
      )
      metrics.sqliteMirrorSessionExists = (report["session_exists"] as? Bool) ?? false
      metrics.sqliteMirrorRawNotificationCount = intValue(report["raw_notification_count"]) ?? 0
      metrics.sqliteMirrorHistoricalRangePollCount = intValue(report["historical_range_poll_count"]) ?? 0
      metrics.sqliteMirrorSuccessfulHistoricalRangePollCount = intValue(report["successful_historical_range_poll_count"]) ?? 0
      if !metrics.sqliteMirrorSessionExists {
        issues.append("overnight_sync_sessions has no current session row")
      }
      if metrics.sqliteMirrorRawNotificationCount == 0 {
        issues.append("ble_raw_notifications has no mirrored current-session rows")
      }
      if metrics.sqliteMirrorHistoricalRangePollCount == 0 {
        issues.append("historical_range_polls has no mirrored current-session rows")
      }
      if metrics.sqliteMirrorSuccessfulHistoricalRangePollCount == 0 {
        issues.append("historical_range_polls has no mirrored successful GET_DATA_RANGE response")
      }
    } catch {
      issues.append("SQLite mirror validation failed: \(errorSummary(error))")
    }
  }

  static func validateOvernightStatusFile(
    from url: URL,
    expectedSessionID: String,
    to metrics: inout GooseOvernightExportMetrics,
    sessionMatches: inout Bool,
    finalized: inout Bool,
    issues: inout [String]
  ) {
    let values = readStatusValues(at: url)
    guard !values.isEmpty else {
      issues.append("status.txt is empty or unreadable")
      return
    }
    if values["session_id"] == expectedSessionID {
      sessionMatches = true
    } else {
      issues.append("status.txt session_id does not match current overnight session")
    }
    if values["timestamp"] == nil, values["heartbeat_at"] == nil {
      issues.append("status.txt is missing timestamp/heartbeat_at")
    }
    if values["active"] == "false" {
      finalized = true
    } else {
      issues.append("status.txt still marks overnight session active")
    }
    if values["handles_closed"] != "true" {
      issues.append("status.txt does not prove overnight file handles were closed")
    }
    if values["post_close_status_refresh"] != "true" {
      issues.append("status.txt does not prove post-close sidecar refresh")
    }
    recordProofSidecarWarning(
      source: "status.txt",
      key: "last_error",
      value: values["last_error"],
      to: &metrics,
      issues: &issues
    )
    recordProofSidecarWarning(
      source: "status.txt",
      key: "raw_spool_warning",
      value: values["raw_spool_warning"],
      to: &metrics,
      issues: &issues
    )
    recordProofSidecarWarning(
      source: "status.txt",
      key: "ble_log_warning",
      value: values["ble_log_warning"],
      to: &metrics,
      issues: &issues
    )
    recordProofSidecarWarning(
      source: "status.txt",
      key: "export_manifest_error",
      value: values["export_manifest_error"],
      to: &metrics,
      issues: &issues
    )
  }

  static func validateCrashMarker(
    from url: URL,
    expectedSessionID: String,
    to metrics: inout GooseOvernightExportMetrics,
    jsonValid: inout Bool,
    sessionMatches: inout Bool,
    finalized: inout Bool,
    issues: inout [String]
  ) {
    guard let data = try? Data(contentsOf: url),
          let marker = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          marker["schema"] as? String == "goose.overnight.crash_marker.v1" else {
      issues.append("crash-marker.json is not valid marker JSON")
      return
    }
    jsonValid = true
    if marker["session_id"] as? String == expectedSessionID {
      sessionMatches = true
    } else {
      issues.append("crash-marker.json session_id does not match current overnight session")
    }
    if marker["last_status_at"] as? String == nil {
      issues.append("crash-marker.json is missing last_status_at")
    }
    if (marker["active"] as? Bool) == false {
      finalized = true
    } else {
      issues.append("crash-marker.json still marks overnight session active")
    }
    if boolValue(marker["handles_closed"]) != true {
      issues.append("crash-marker.json does not prove overnight file handles were closed")
    }
    if boolValue(marker["post_close_status_refresh"]) != true {
      issues.append("crash-marker.json does not prove post-close sidecar refresh")
    }
	    recordProofSidecarWarning(
	      source: "crash-marker.json",
	      key: "last_error",
	      value: marker["last_error"],
	      to: &metrics,
	      issues: &issues
	    )
	    recordProofSidecarWarning(
	      source: "crash-marker.json",
	      key: "raw_spool_warning",
	      value: marker["raw_spool_warning"],
	      to: &metrics,
	      issues: &issues
	    )
	    recordProofSidecarWarning(
	      source: "crash-marker.json",
	      key: "ble_log_warning",
	      value: marker["ble_log_warning"],
	      to: &metrics,
	      issues: &issues
	    )
	    recordProofSidecarWarning(
	      source: "crash-marker.json",
	      key: "export_manifest_error",
	      value: marker["export_manifest_error"],
	      to: &metrics,
	      issues: &issues
	    )
	  }

  static func applyManifestMetrics(
    from url: URL,
    expectedSessionID: String,
    to metrics: inout GooseOvernightExportMetrics,
    sessionMatches: inout Bool,
    finalized: inout Bool,
    issues: inout [String]
  ) {
    guard let data = try? Data(contentsOf: url),
          let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      issues.append("manifest.json is not valid JSON")
      return
    }
    if manifest["session_id"] as? String == expectedSessionID {
      sessionMatches = true
    } else {
      issues.append("manifest.json session_id does not match current overnight session")
    }
    if manifest["started_at"] == nil || manifest["started_at"] is NSNull {
      issues.append("manifest.json is missing started_at")
    }
    if manifest["ended_at"] == nil || manifest["ended_at"] is NSNull {
      issues.append("manifest.json is missing ended_at")
    }
    if let status = manifest["status"] as? String, status != "active" {
      finalized = true
    } else {
      issues.append("manifest.json still marks overnight session active")
    }
    if boolValue(manifest["handles_closed"]) != true {
      issues.append("manifest.json does not prove overnight file handles were closed")
    }
    if boolValue(manifest["post_close_status_refresh"]) != true {
      issues.append("manifest.json does not prove post-close sidecar refresh")
    }
    recordProofSidecarWarning(
      source: "manifest.json",
      key: "last_error",
      value: manifest["last_error"],
      to: &metrics,
      issues: &issues
    )
    guard let summary = manifest["summary"] as? [String: Any] else {
      issues.append("manifest.json is missing final summary")
      return
    }
    recordProofSidecarWarning(
      source: "manifest.json summary",
      key: "raw_spool_warning",
      value: summary["raw_spool_warning"],
      to: &metrics,
      issues: &issues
    )
    recordProofSidecarWarning(
      source: "manifest.json summary",
      key: "ble_log_warning",
      value: summary["ble_log_warning"],
      to: &metrics,
      issues: &issues
    )
    recordProofSidecarWarning(
      source: "manifest.json summary",
      key: "export_manifest_error",
      value: summary["export_manifest_error"],
      to: &metrics,
      issues: &issues
    )
    metrics.historicalPacketCount = intValue(summary["historical_packet_count"])
    metrics.k18Count = intValue(summary["k18_count"])
    metrics.k24Count = intValue(summary["k24_count"])
    metrics.k25Count = intValue(summary["k25_count"])
    metrics.k26Count = intValue(summary["k26_count"])
    metrics.packet47Count = intValue(summary["packet47_count"])
    metrics.event17Count = intValue(summary["event17_count"])
    metrics.event29Count = intValue(summary["event29_count"])
    metrics.metadata49Count = intValue(summary["metadata49_count"]) ?? intValue(summary["event49_count"])
    metrics.metadata56Count = intValue(summary["metadata56_count"]) ?? intValue(summary["event56_count"])
  }

  static func recordProofSidecarWarning(
    source: String,
    key: String,
    value: Any?,
    to metrics: inout GooseOvernightExportMetrics,
    issues: inout [String]
  ) {
    guard let text = proofSidecarWarningText(value) else {
      return
    }
    let issue = "\(source) records \(key): \(text)"
    metrics.proofSidecarWarningCount += 1
    if metrics.proofSidecarWarnings.count < 12 {
      metrics.proofSidecarWarnings.append(issue)
    }
    issues.append(issue)
  }

  static func proofSidecarWarningText(_ value: Any?) -> String? {
    guard let value, !(value is NSNull) else {
      return nil
    }
    if let array = value as? [Any], array.isEmpty {
      return nil
    }
    if let dictionary = value as? [String: Any], dictionary.isEmpty {
      return nil
    }

    let text: String
    if let string = value as? String {
      text = string
    } else if let number = value as? NSNumber {
      text = number.stringValue
    } else {
      text = String(describing: value)
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()
    switch normalized {
    case "", "0", "false", "n/a", "na", "nil", "no", "no warning", "no warnings", "none", "null", "ok":
      return nil
    default:
      return trimmed.count > 240 ? String(trimmed.prefix(240)) + "..." : trimmed
    }
  }

  static func readStatusValues(at url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      return [:]
    }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
      guard let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<separator])
      let value = String(line[line.index(after: separator)...])
      values[key] = value
    }
    return values
  }

}
