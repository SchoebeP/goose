import Foundation
import UIKit

struct RawBodyDiagnostic {
  let byteCount: Int
  let nonZeroByteCount: Int
  let prefixHex: String
  let firstU16LE: [Int]
  let firstU32LE: [UInt32]

  func summary(packetK: Int) -> String {
    let words = firstU16LE.prefix(4).map(String.init).joined(separator: ",")
    return "K\(packetK) body=\(byteCount) bytes nonzero=\(nonZeroByteCount) u16=[\(words)]"
  }

  var logSummary: String {
    let u16Text = firstU16LE.map(String.init).joined(separator: ",")
    let u32Text = firstU32LE.map(String.init).joined(separator: ",")
    return "bytes=\(byteCount) nonzero=\(nonZeroByteCount) u16_le=[\(u16Text)] u32_le=[\(u32Text)] prefix=\(prefixHex)"
  }

  static func from(packetK: Int, body: Data?) -> RawBodyDiagnostic? {
    guard packetK == 2 || packetK == 20, let body else {
      return nil
    }

    let prefix = Data(body.prefix(32)).hexString
    var u16Values: [Int] = []
    var offset = 0
    while offset + 1 < body.count, u16Values.count < 12 {
      let value = UInt16(body[offset]) | (UInt16(body[offset + 1]) << 8)
      u16Values.append(Int(value))
      offset += 2
    }

    var u32Values: [UInt32] = []
    offset = 0
    while offset + 3 < body.count, u32Values.count < 6 {
      let value = UInt32(body[offset])
        | (UInt32(body[offset + 1]) << 8)
        | (UInt32(body[offset + 2]) << 16)
        | (UInt32(body[offset + 3]) << 24)
      u32Values.append(value)
      offset += 4
    }

    return RawBodyDiagnostic(
      byteCount: body.count,
      nonZeroByteCount: body.reduce(0) { $0 + ($1 == 0 ? 0 : 1) },
      prefixHex: prefix,
      firstU16LE: u16Values,
      firstU32LE: u32Values
    )
  }
}

struct HistoryTemperatureCandidate {
  let packetK: Int
  let schemaField: String
  let rawBodyOffset: Int
  let encoding: String
  let rawHex: String
  let rawI16LE: Int?
  let rawU16LE: Int?
  let temperatureC: Double?
  let semanticStatus: String

  var summary: String {
    let tempText = temperatureC.map { String(format: "%.2f C candidate", $0) } ?? "unresolved"
    return "K\(packetK) \(tempText) | \(semanticStatus) | \(schemaField)"
  }

  var logSummary: String {
    let rawI16Text = rawI16LE.map { "\($0)" } ?? "?"
    let rawU16Text = rawU16LE.map { "\($0)" } ?? "?"
    let tempText = temperatureC.map { String(format: "%.2f", $0) } ?? "?"
    return "K\(packetK) field=\(schemaField) offset=\(rawBodyOffset) encoding=\(encoding) raw=\(rawHex) raw_i16=\(rawI16Text) raw_u16=\(rawU16Text) temp_c=\(tempText) status=\(semanticStatus)"
  }

  static func from(packetK: Int, body: Data?) -> HistoryTemperatureCandidate? {
    switch packetK {
    case 18:
      return candidate(
        packetK: packetK,
        body: body,
        schemaField: "normal_history_k18_body_24_skin_temperature_c",
        rawBodyOffset: 24,
        encoding: "i16_le_x100",
        scale: 100.0,
        signed: true
      )
    case 24:
      return candidate(
        packetK: packetK,
        body: body,
        schemaField: "normal_history_k24_body_3_skin_temperature_c",
        rawBodyOffset: 3,
        encoding: "u16_le_x1000",
        scale: 1000.0,
        signed: false
      )
    default:
      return nil
    }
  }

  private static func candidate(
    packetK: Int,
    body: Data?,
    schemaField: String,
    rawBodyOffset: Int,
    encoding: String,
    scale: Double,
    signed: Bool
  ) -> HistoryTemperatureCandidate {
    guard let body, body.count >= rawBodyOffset + 2 else {
      return HistoryTemperatureCandidate(
        packetK: packetK,
        schemaField: schemaField,
        rawBodyOffset: rawBodyOffset,
        encoding: encoding,
        rawHex: "",
        rawI16LE: nil,
        rawU16LE: nil,
        temperatureC: nil,
        semanticStatus: "body_too_short"
      )
    }

    let raw = UInt16(body[rawBodyOffset]) | (UInt16(body[rawBodyOffset + 1]) << 8)
    let rawI16 = Int(Int16(bitPattern: raw))
    let rawU16 = Int(raw)
    let temp = signed ? Double(rawI16) / scale : Double(rawU16) / scale
    let rawHex = Data(body[rawBodyOffset..<(rawBodyOffset + 2)]).hexString
    return HistoryTemperatureCandidate(
      packetK: packetK,
      schemaField: schemaField,
      rawBodyOffset: rawBodyOffset,
      encoding: encoding,
      rawHex: rawHex,
      rawI16LE: rawI16,
      rawU16LE: rawU16,
      temperatureC: temp,
      semanticStatus: semanticStatus(for: temp)
    )
  }

  private static func semanticStatus(for temperatureC: Double) -> String {
    if temperatureC == 0 {
      return "zero_candidate_unresolved"
    }
    if (20.0...45.0).contains(temperatureC) {
      return "plausible_unverified_units"
    }
    return "outside_plausible_skin_temperature_range"
  }
}

struct HistoryRespiratoryRateCandidate {
  let packetK: Int
  let schemaField: String
  let rawBodyOffset: Int
  let encoding: String
  let rawHex: String
  let rawU16LE: Int?
  let respiratoryRateRPM: Double?
  let semanticStatus: String

  var summary: String {
    let rateText = respiratoryRateRPM.map { String(format: "%.1f rpm candidate", $0) } ?? "unresolved"
    return "K\(packetK) \(rateText) | \(semanticStatus) | \(schemaField)"
  }

  var logSummary: String {
    let rawText = rawU16LE.map { "\($0)" } ?? "?"
    let rateText = respiratoryRateRPM.map { String(format: "%.1f", $0) } ?? "?"
    return "K\(packetK) field=\(schemaField) offset=\(rawBodyOffset) encoding=\(encoding) raw=\(rawHex) raw_u16=\(rawText) rpm=\(rateText) status=\(semanticStatus)"
  }

  static func from(packetK: Int, body: Data?) -> HistoryRespiratoryRateCandidate? {
    guard packetK == 18 else {
      return nil
    }

    let schemaField = "normal_history_k18_body_26_respiratory_rate_rpm_candidate"
    let rawBodyOffset = 26
    let encoding = "u16_le_x10"
    guard let body, body.count >= rawBodyOffset + 2 else {
      return HistoryRespiratoryRateCandidate(
        packetK: packetK,
        schemaField: schemaField,
        rawBodyOffset: rawBodyOffset,
        encoding: encoding,
        rawHex: "",
        rawU16LE: nil,
        respiratoryRateRPM: nil,
        semanticStatus: "body_too_short"
      )
    }

    let raw = UInt16(body[rawBodyOffset]) | (UInt16(body[rawBodyOffset + 1]) << 8)
    let rawU16 = Int(raw)
    let rpm = Double(rawU16) / 10.0
    let rawHex = Data(body[rawBodyOffset..<(rawBodyOffset + 2)]).hexString
    return HistoryRespiratoryRateCandidate(
      packetK: packetK,
      schemaField: schemaField,
      rawBodyOffset: rawBodyOffset,
      encoding: encoding,
      rawHex: rawHex,
      rawU16LE: rawU16,
      respiratoryRateRPM: rpm,
      semanticStatus: semanticStatus(for: rpm)
    )
  }

  private static func semanticStatus(for rpm: Double) -> String {
    if rpm == 0 {
      return "zero_candidate_unresolved"
    }
    if (6.0...30.0).contains(rpm) {
      return "plausible_unverified_units"
    }
    return "outside_plausible_respiratory_rate_range"
  }
}

struct R21MotionCandidate {
  struct ChannelSummary {
    let name: String
    let parsedCount: Int
    let mean: Double
    let rmsAC: Double
    let min: Int
    let max: Int

    var logSummary: String {
      "\(name):count=\(parsedCount),mean=\(String(format: "%.1f", mean)),rms_ac=\(String(format: "%.1f", rmsAC)),range=\(min)...\(max)"
    }
  }

  let fieldX: Int?
  let group1Count: Int?
  let group2Count: Int?
  let group1Axis0: ChannelSummary?
  let group1Axis1: ChannelSummary?
  let group1Axis2: ChannelSummary?
  let group2Axis0: ChannelSummary?
  let group2Axis1: ChannelSummary?
  let group2Axis2: ChannelSummary?

  var summary: String {
    let firstGroupText = group1Axis0.map { "\($0.parsedCount)" } ?? "0"
    let secondGroupText = group2Axis0.map { "\($0.parsedCount)" } ?? "0"
    return "R21 motion group1=\(firstGroupText) group2=\(secondGroupText)"
  }

  var compactLogSummary: String {
    [
      group1Axis0?.logSummary,
      group1Axis1?.logSummary,
      group1Axis2?.logSummary,
      group2Axis0?.logSummary,
      group2Axis1?.logSummary,
      group2Axis2?.logSummary,
    ]
      .compactMap { $0 }
      .prefix(3)
      .joined(separator: " ")
  }

  var logSummary: String {
    let fieldText = fieldX.map { "\($0)" } ?? "?"
    let group1Text = group1Count.map { "\($0)" } ?? "?"
    let group2Text = group2Count.map { "\($0)" } ?? "?"
    let axes = [
      group1Axis0?.logSummary ?? "group_1_axis_0:none",
      group1Axis1?.logSummary ?? "group_1_axis_1:none",
      group1Axis2?.logSummary ?? "group_1_axis_2:none",
      group2Axis0?.logSummary ?? "group_2_axis_0:none",
      group2Axis1?.logSummary ?? "group_2_axis_1:none",
      group2Axis2?.logSummary ?? "group_2_axis_2:none",
    ].joined(separator: " ")
    return "field_x=\(fieldText) group1=\(group1Text) group2=\(group2Text) \(axes)"
  }

  static func from(packetK: Int, body: Data?) -> R21MotionCandidate? {
    guard packetK == 21, let body else {
      return nil
    }

    let group1Count = intFromUInt16(body, offset: 16)
    let group2Count = intFromUInt16(body, offset: 622)

    return R21MotionCandidate(
      fieldX: intFromUInt16(body, offset: 14),
      group1Count: group1Count,
      group2Count: group2Count,
      group1Axis0: channelSummary(name: "group_1_axis_0", body: body, offset: 20, expectedCount: group1Count ?? 100),
      group1Axis1: channelSummary(name: "group_1_axis_1", body: body, offset: 220, expectedCount: group1Count ?? 100),
      group1Axis2: channelSummary(name: "group_1_axis_2", body: body, offset: 420, expectedCount: group1Count ?? 100),
      group2Axis0: channelSummary(name: "group_2_axis_0", body: body, offset: 632, expectedCount: group2Count ?? 100),
      group2Axis1: channelSummary(name: "group_2_axis_1", body: body, offset: 832, expectedCount: group2Count ?? 100),
      group2Axis2: channelSummary(name: "group_2_axis_2", body: body, offset: 1032, expectedCount: group2Count ?? 100)
    )
  }

  static func from(packetK: Int, bodySummary: [String: Any]?) -> R21MotionCandidate? {
    guard packetK == 21,
          let bodySummary,
          bodySummary["kind"] as? String == "raw_motion_k21" else {
      return nil
    }

    let axes = bodySummary["axes"] as? [[String: Any]] ?? []
    func axis(_ name: String) -> ChannelSummary? {
      guard let row = axes.first(where: { $0["name"] as? String == name }) else {
        return nil
      }
      return channelSummary(name: name, row: row)
    }

    return R21MotionCandidate(
      fieldX: intValue(bodySummary["field_x"]),
      group1Count: intValue(bodySummary["group_1_count"]),
      group2Count: intValue(bodySummary["group_2_count"]),
      group1Axis0: axis("group_1_axis_0"),
      group1Axis1: axis("group_1_axis_1"),
      group1Axis2: axis("group_1_axis_2"),
      group2Axis0: axis("group_2_axis_0"),
      group2Axis1: axis("group_2_axis_1"),
      group2Axis2: axis("group_2_axis_2")
    )
  }

  private static func channelSummary(
    name: String,
    body: Data,
    offset: Int,
    expectedCount: Int
  ) -> ChannelSummary? {
    guard offset < body.count, expectedCount > 0 else {
      return nil
    }

    let availableCount = max(0, min(expectedCount, (body.count - offset) / 2))
    guard availableCount > 0 else {
      return nil
    }

    var values: [Int] = []
    values.reserveCapacity(availableCount)
    for index in 0..<availableCount {
      guard let value = intFromInt16(body, offset: offset + index * 2) else {
        continue
      }
      values.append(value)
    }
    guard !values.isEmpty else {
      return nil
    }

    let sum = values.reduce(0, +)
    let mean = Double(sum) / Double(values.count)
    let variance = values
      .map { pow(Double($0) - mean, 2) }
      .reduce(0, +) / Double(values.count)
    return ChannelSummary(
      name: name,
      parsedCount: values.count,
      mean: mean,
      rmsAC: sqrt(variance),
      min: values.min() ?? 0,
      max: values.max() ?? 0
    )
  }

  private static func channelSummary(name: String, row: [String: Any]) -> ChannelSummary? {
    let parsedCount = intValue(row["parsed_count"]) ?? 0
    guard parsedCount > 0,
          let min = intValue(row["min"]),
          let max = intValue(row["max"]) else {
      return nil
    }

    let sum = doubleValue(row["sum"]) ?? 0
    let mean = sum / Double(parsedCount)
    return ChannelSummary(
      name: name,
      parsedCount: parsedCount,
      mean: mean,
      rmsAC: Double(max - min) / 2,
      min: min,
      max: max
    )
  }

  private static func intFromUInt16(_ data: Data, offset: Int) -> Int? {
    guard data.count >= offset + 2 else {
      return nil
    }
    return Int(UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
  }

  private static func intFromInt16(_ data: Data, offset: Int) -> Int? {
    guard data.count >= offset + 2 else {
      return nil
    }
    // R21 IMU sample channels are signed little-endian (matches the Rust
    // decoder's read_i16_le over the same offsets) — unsigned wraps negatives.
    let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    return Int(Int16(bitPattern: raw))
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
      return int
    }
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let string = value as? String {
      return Int(string)
    }
    return nil
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }
}

