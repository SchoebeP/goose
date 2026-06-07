import Foundation

/// Latest WHOOP 4.0 normal-history (V24-layout) body metrics, decoded on-device
/// from the band's history records.
///
/// This mirrors the Rust core's `DataPacketBodySummary::NormalHistory` decode
/// (`Rust/core/src/protocol.rs`, openwhoop layout): when a data-packet body is
/// at least 67 bytes, it carries DSP sensor fields at fixed body offsets —
/// SpO2 red/IR raw counts @ 51/53, raw skin temperature @ 55 (real captures
/// range ~464–860, unit calibration pending), raw respiratory rate @ 63
/// (u16, divided by 200 -> respirations per minute, ~15.4 typical), and a
/// signal-quality word @ 65.
///
/// The Swift notification pipeline runs the Rust parser in "4.0 quiet mode"
/// (GEN4 frames are skipped, see `NotificationFrameParser.parseBatch`), so the
/// GEN4 path decodes these fields directly from the reassembled frames here.
/// These are OUR OWN decodes of raw band values — not WHOOP's numbers, and not
/// medical readings.
struct BodyHistoryMetricsSample: Equatable {
  /// Data-packet kinds the Rust core summarises as NormalHistory (protocol.rs).
  static let normalHistoryPacketKs: Set<Int> = [7, 9, 12, 18, 24]
  /// Packet types whose payload uses the data-packet layout (protocol.rs):
  /// REALTIME_DATA(40), REALTIME_RAW_DATA(43), HISTORICAL_DATA(47),
  /// REALTIME_IMU(51), HISTORICAL_IMU(52).
  static let dataPacketTypes: Set<Int> = [40, 43, 47, 51, 52]

  let packetK: Int
  /// Wall-clock time of the record itself: the band's unix timestamp when
  /// plausible, otherwise the moment the frame arrived over BLE.
  let recordedAt: Date
  let capturedAt: Date
  let spo2Red: Int?
  let spo2IR: Int?
  let skinTempRaw: Int?
  let respiratoryRateRaw: Int?
  let signalQuality: Int?

  /// Raw u16 / 200 -> respirations per minute (our own decode; ~15.4 typical).
  var respiratoryRateRPM: Double? {
    respiratoryRateRaw.map { Double($0) / 200.0 }
  }

  /// True when the optical SpO2 channels carried signal (nonzero red/IR counts).
  var hasSpO2Signal: Bool {
    (spo2Red ?? 0) != 0 || (spo2IR ?? 0) != 0
  }

  /// True when the record itself is from the last 24 hours.
  var isRecent: Bool {
    Date().timeIntervalSince(recordedAt) < 24 * 3600
  }

  /// Decode from a complete reassembled GEN4 frame hex string. Cheap prefilter
  /// first: this runs on every GEN4 frame, including the ~100 Hz raw stream, so
  /// peek packet_type (frame byte 4) and packet_k (frame byte 5) straight from
  /// the hex characters and bail before allocating any `Data`.
  static func fromGen4FrameHex(_ frameHex: String, capturedAt: Date) -> BodyHistoryMetricsSample? {
    // Minimum: 4-byte header + 13-byte data-packet header + 67-byte DSP body
    // + 4-byte CRC = 88 bytes = 176 hex characters.
    guard frameHex.utf8.count >= 176 else {
      return nil
    }
    let utf8 = Array(frameHex.utf8.prefix(12))
    guard
      let packetType = hexByte(utf8, byteIndex: 4),
      dataPacketTypes.contains(packetType),
      let packetK = hexByte(utf8, byteIndex: 5),
      normalHistoryPacketKs.contains(packetK),
      let frame = Data(hexString: frameHex)
    else {
      return nil
    }
    return fromGen4Frame(frame, capturedAt: capturedAt)
  }

  /// Decode from complete GEN4 frame bytes
  /// (`[0xAA][len u16 LE][crc8][payload...][crc32 LE]`). Payload layout per the
  /// Rust core's `parse_data_packet_payload`: payload[0]=packet_type,
  /// payload[1]=packet_k, payload[7..11]=unix seconds LE, body=payload[13...].
  static func fromGen4Frame(_ frame: Data, capturedAt: Date) -> BodyHistoryMetricsSample? {
    let bytes = [UInt8](frame)
    guard bytes.count >= 88, bytes[0] == 0xAA else {
      return nil
    }
    let payload = Array(bytes[4..<(bytes.count - 4)])
    guard
      payload.count >= 13 + 67,
      dataPacketTypes.contains(Int(payload[0])),
      normalHistoryPacketKs.contains(Int(payload[1]))
    else {
      return nil
    }

    let body = Array(payload[13...])
    func bodyU16(_ offset: Int) -> Int? {
      guard body.count >= offset + 2 else {
        return nil
      }
      return Int(UInt16(body[offset]) | (UInt16(body[offset + 1]) << 8))
    }

    let unixSeconds = UInt32(payload[7])
      | (UInt32(payload[8]) << 8)
      | (UInt32(payload[9]) << 16)
      | (UInt32(payload[10]) << 24)
    return BodyHistoryMetricsSample(
      packetK: Int(payload[1]),
      recordedAt: recordedAt(unixSeconds: unixSeconds, capturedAt: capturedAt),
      capturedAt: capturedAt,
      spo2Red: bodyU16(51),
      spo2IR: bodyU16(53),
      skinTempRaw: bodyU16(55),
      respiratoryRateRaw: bodyU16(63),
      signalQuality: bodyU16(65)
    )
  }

  /// Use the band's own record timestamp when it is plausible wall-clock time;
  /// otherwise fall back to the BLE arrival time.
  private static func recordedAt(unixSeconds: UInt32, capturedAt: Date) -> Date {
    let candidate = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    let plausibleStart = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
    guard candidate >= plausibleStart, candidate <= capturedAt.addingTimeInterval(48 * 3600) else {
      return capturedAt
    }
    return candidate
  }

  private static func hexByte(_ utf8: [UInt8], byteIndex: Int) -> Int? {
    let index = byteIndex * 2
    guard
      index + 1 < utf8.count,
      let high = hexNibble(utf8[index]),
      let low = hexNibble(utf8[index + 1])
    else {
      return nil
    }
    return (high << 4) | low
  }

  private static func hexNibble(_ character: UInt8) -> Int? {
    switch character {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      return Int(character - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      return Int(character - UInt8(ascii: "a")) + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      return Int(character - UInt8(ascii: "A")) + 10
    default:
      return nil
    }
  }
}

extension GooseBLEClient {
  /// Publish the latest decoded body-history metrics the same way
  /// `liveHeartRateBPM` is published. Keeps the newest record by the record's
  /// own timestamp so an old backfilled chunk never overwrites a fresher value.
  /// Main thread only (`@Published`).
  func recordBodyHistoryMetrics(_ sample: BodyHistoryMetricsSample) {
    if let current = latestBodyHistoryMetrics, current.recordedAt > sample.recordedAt {
      return
    }
    latestBodyHistoryMetrics = sample
  }
}
