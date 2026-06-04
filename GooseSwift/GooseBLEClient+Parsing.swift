import CoreBluetooth
import Foundation
import OSLog


extension GooseBLEClient {
  func handleStandardHeartRate(
    _ value: Data,
    characteristic: CBCharacteristic,
    capturedAt: Date = Date()
  ) {
    guard let measurement = Self.parseStandardHeartRateMeasurement(value) else {
      record(level: .warn, source: "ble.hr.standard", title: "heart_rate.parse_failed", body: value.hexString)
      return
    }
    recordLiveHeartRate(measurement.bpm, source: "ble.hr.standard", at: capturedAt)
    recordRRIntervals(measurement.rrIntervalsMS, source: "ble.hr.standard", at: capturedAt)
    WhoopCloudForwarder.shared.forward(bpm: measurement.bpm, rrMs: measurement.rrIntervalsMS, at: capturedAt)
  }

  struct BatteryLevelStatus {
    let batteryLevelPercent: Int?
    let isCharging: Bool?
    let summary: String
  }

  func applyBatteryLevel(_ rawLevel: Int, capturedAt: Date, sourceTitle: String) {
    let normalizedLevel = min(max(rawLevel, 0), 100)
    let previousSample = lastBatteryLevelSample
    batteryLevelPercent = normalizedLevel
    batteryUpdatedAt = capturedAt
    lastSyncAt = capturedAt
    updateBatteryChargingInference(
      currentPercent: normalizedLevel,
      previousSample: previousSample,
      capturedAt: capturedAt
    )
    lastBatteryLevelSample = (normalizedLevel, capturedAt)
    persistBatterySample(percent: normalizedLevel, capturedAt: capturedAt)
    record(
      source: "ble.metadata",
      title: sourceTitle,
      body: "\(normalizedLevel)% charging=\(batteryIsCharging.map { $0 ? "true" : "false" } ?? "unknown") status=\(batteryPowerStatus)"
    )
  }

  func updateBatteryChargingInference(
    currentPercent: Int,
    previousSample: (percent: Int, capturedAt: Date)?,
    capturedAt: Date
  ) {
    guard let previousSample else {
      return
    }
    let sampleAge = capturedAt.timeIntervalSince(previousSample.capturedAt)
    guard sampleAge > 0, sampleAge <= 6 * 60 * 60 else {
      return
    }
    if currentPercent < previousSample.percent {
      // A falling level is unambiguous discharge evidence: the band is off the
      // charger. Cancel any standing "charging (inferred)" window so a battery
      // bump from an earlier charge can't keep the UI stuck on "Charging".
      if inferredBatteryChargingUntil != nil || batteryIsCharging == true {
        inferredBatteryChargingUntil = nil
        persistInferredBatteryChargingUntil(nil)
        batteryIsCharging = false
        batteryPowerStatus = "Not charging"
        record(
          source: "ble.metadata",
          title: "battery.charging.inference_cleared",
          body: "\(previousSample.percent)% -> \(currentPercent)% (level fell, not charging)"
        )
      }
      return
    }
    guard currentPercent > previousSample.percent else {
      if inferredBatteryChargingUntil.map({ $0 > capturedAt }) == true, batteryIsCharging == nil {
        batteryIsCharging = true
        batteryPowerStatus = "Charging (inferred)"
      }
      return
    }

    inferredBatteryChargingUntil = capturedAt.addingTimeInterval(30 * 60)
    persistInferredBatteryChargingUntil(inferredBatteryChargingUntil)
    if batteryIsCharging != true || batteryPowerStatus == "Unknown" {
      batteryIsCharging = true
      batteryPowerStatus = "Charging (inferred)"
      record(
        source: "ble.metadata",
        title: "battery.charging.inferred",
        body: "\(previousSample.percent)% -> \(currentPercent)% over \(Int(sampleAge.rounded()))s"
      )
    }
  }

  func hasRecentInferredBatteryCharging(at date: Date) -> Bool {
    inferredBatteryChargingUntil.map { $0 > date } == true
  }

  func applyBatteryStatus(_ status: BatteryLevelStatus, rawValue: Data, capturedAt: Date) {
    // WHOOP 4.0: this bit-packed "battery status" characteristic uses the 5.0
    // layout and decodes to garbage here — it reported 10/36% (and wrong charging)
    // against a real 96% while charging. Ignore its level AND charging entirely;
    // the standard 0x2A19 characteristic gives the percent and CHARGING_*/5V
    // events give the charging state.
    _ = status
    _ = rawValue
    batteryUpdatedAt = capturedAt
    lastSyncAt = capturedAt
  }

  @discardableResult
  func handleStandardReadValue(
    _ value: Data,
    characteristic: CBCharacteristic,
    capturedAt: Date
  ) -> Bool {
    switch characteristic.uuid {
    case batteryLevelCharacteristicID:
      guard let raw = value.first else {
        record(level: .warn, source: "ble.metadata", title: "battery.read.empty")
        return true
      }
      // WHOOP 4.0: the standard 0x2A19 byte is unreliable here — it bounces
      // 10/83/100% on the same band. Trust ONLY the GET_BATTERY command response
      // (uint16/10, validated reliable). Log the raw byte for diagnosis but don't
      // let it set the level. (5.0 still uses 2A19 normally.)
      if isGen4Band {
        record(source: "ble.metadata", title: "battery.read.2a19_ignored_gen4",
               body: "raw=\(value.hexString) byte=\(Int(raw))% — using GET_BATTERY cmd instead")
        return true
      }
      applyBatteryLevel(Int(raw), capturedAt: capturedAt, sourceTitle: "battery.read")
      return true
    case batteryLevelStatusCharacteristicID:
      guard let status = Self.parseBatteryLevelStatus(value) else {
        record(level: .warn, source: "ble.metadata", title: "battery.status.parse_failed", body: value.hexString)
        return true
      }
      applyBatteryStatus(status, rawValue: value, capturedAt: capturedAt)
      record(source: "ble.metadata", title: "battery.status.read", body: "\(status.summary) raw=\(value.hexString)")
      return true
    case modelNumberCharacteristicID:
      modelNumber = decodedMetadataString(value)
    case firmwareRevisionCharacteristicID:
      firmwareVersion = decodedMetadataString(value)
    case hardwareRevisionCharacteristicID:
      hardwareRevision = decodedMetadataString(value)
    case softwareRevisionCharacteristicID:
      softwareRevision = decodedMetadataString(value)
    case manufacturerNameCharacteristicID:
      manufacturerName = decodedMetadataString(value)
    default:
      return false
    }

    lastSyncAt = capturedAt
    let stringValue = decodedMetadataString(value) ?? value.hexString
    record(source: "ble.metadata", title: "device_info.read", body: "\(characteristic.uuid.uuidString)=\(stringValue)")
    return true
  }

  func decodedMetadataString(_ data: Data) -> String? {
    var trimSet = CharacterSet.whitespacesAndNewlines
    trimSet.formUnion(.controlCharacters)
    guard let string = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: trimSet),
      !string.isEmpty
    else {
      return nil
    }
    return string
  }

  static func parseBatteryLevelStatus(_ data: Data) -> BatteryLevelStatus? {
    let bytes = Array(data)
    guard bytes.count >= 3 else {
      return nil
    }

    let flags = bytes[0]
    let powerState = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
    let batteryPresent = powerState & 0x01 != 0
    let wiredPower = Int((powerState >> 1) & 0x03)
    let wirelessPower = Int((powerState >> 3) & 0x03)
    let chargeState = Int((powerState >> 5) & 0x03)
    let chargeLevel = Int((powerState >> 7) & 0x03)
    let chargingType = Int((powerState >> 9) & 0x07)
    let chargingFault = Int((powerState >> 12) & 0x07)
    let externalPowerConnected = wiredPower == 1 || wirelessPower == 1

    var index = 3
    if flags & 0x01 != 0 {
      index += 2
    }

    let statusBatteryLevel: Int?
    if flags & 0x02 != 0, bytes.count > index {
      statusBatteryLevel = min(max(Int(bytes[index]), 0), 100)
      index += 1
    } else {
      statusBatteryLevel = nil
    }

    let additionalStatus: UInt8?
    if flags & 0x04 != 0, bytes.count > index {
      additionalStatus = bytes[index]
    } else {
      additionalStatus = nil
    }

    let isCharging: Bool?
    let stateText: String
    switch chargeState {
    case 1:
      isCharging = true
      stateText = "Charging"
    case 2:
      isCharging = externalPowerConnected ? true : false
      stateText = externalPowerConnected ? "On charger" : "Discharging"
    case 3:
      isCharging = externalPowerConnected ? true : false
      stateText = externalPowerConnected ? "On charger" : "Idle"
    default:
      isCharging = externalPowerConnected ? true : nil
      stateText = externalPowerConnected ? "On charger" : "Unknown"
    }

    let externalPowerText: String
    switch (wiredPower, wirelessPower) {
    case (1, _):
      externalPowerText = "wired power"
    case (_, 1):
      externalPowerText = "wireless power"
    case (2, _), (_, 2):
      externalPowerText = "power unknown"
    default:
      externalPowerText = ""
    }

    let chargeLevelText: String
    switch chargeLevel {
    case 1:
      chargeLevelText = "good"
    case 2:
      chargeLevelText = "low"
    case 3:
      chargeLevelText = "critical"
    default:
      chargeLevelText = ""
    }

    let chargingTypeText: String
    switch chargingType {
    case 1:
      chargingTypeText = "constant current"
    case 2:
      chargingTypeText = "constant voltage"
    case 3:
      chargingTypeText = "trickle"
    case 4:
      chargingTypeText = "float"
    default:
      chargingTypeText = ""
    }

    var parts = [stateText]
    if !batteryPresent {
      parts.append("battery absent")
    }
    if !externalPowerText.isEmpty {
      parts.append(externalPowerText)
    }
    if !chargingTypeText.isEmpty {
      parts.append(chargingTypeText)
    }
    if !chargeLevelText.isEmpty {
      parts.append(chargeLevelText)
    }
    if chargingFault != 0 {
      parts.append("fault")
    }
    if let additionalStatus {
      let serviceRequired = Int(additionalStatus & 0x03)
      let batteryFault = additionalStatus & 0x04 != 0
      if serviceRequired == 1 {
        parts.append("service required")
      }
      if batteryFault {
        parts.append("battery fault")
      }
    }

    return BatteryLevelStatus(
      batteryLevelPercent: statusBatteryLevel,
      isCharging: isCharging,
      summary: parts.joined(separator: " | ")
    )
  }

  func whoopIdentityEvidence(
    for peripheral: CBPeripheral,
    fallbackName: String? = nil,
    advertisedServices: [CBUUID] = [],
    allowRememberedValidation: Bool = true
  ) -> String? {
    if advertisedServices.contains(where: isWhoopService) {
      return "advertised WHOOP service"
    }
    if whoopCandidateIDs.contains(peripheral.identifier) {
      return "cached WHOOP service match"
    }
    if isWhoopName(peripheral.name) {
      return "peripheral name \(peripheral.name ?? "")"
    }
    if isWhoopName(fallbackName) {
      return "advertised name \(fallbackName ?? "")"
    }
    if allowRememberedValidation,
       rememberedDeviceID == peripheral.identifier,
       rememberedDeviceLooksLikeWhoop {
      return "validated remembered WHOOP"
    }
    return nil
  }

  var rememberedDeviceLooksLikeWhoop: Bool {
    rememberedDeviceValidated || isWhoopName(rememberedDeviceName)
  }

  func isWhoopService(_ uuid: CBUUID) -> Bool {
    whoopServices.contains(uuid)
  }

  func isWhoopName(_ name: String?) -> Bool {
    guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return false
    }
    return name.range(of: "whoop", options: [.caseInsensitive, .diacriticInsensitive]) != nil
  }

  static func sanitizedWhoopDisplayName(_ name: String?) -> String {
    let fallback = "WHOOP"
    guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return fallback
    }
    guard let whoopRange = trimmed.range(of: "whoop", options: [.caseInsensitive, .diacriticInsensitive]) else {
      return trimmed
    }
    let publicName = String(trimmed[..<whoopRange.upperBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return publicName.isEmpty ? fallback : String(publicName)
  }

  func advertisedServiceUUIDs(from advertisementData: [String: Any]) -> [CBUUID] {
    var uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    uuids.append(contentsOf: advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
    uuids.append(contentsOf: advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? [])
    if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
      uuids.append(contentsOf: serviceData.keys)
    }
    return uuids
  }

  func shouldAutoConnectDiscoveredWhoop(_ peripheral: CBPeripheral) -> Bool {
    autoReconnectTargetID != nil
      && rememberedDeviceLooksLikeWhoop
      && activePeripheral == nil
      && rememberedDeviceID != nil
      && peripheral.identifier != rememberedDeviceID
  }

  func rejectNonWhoopPeripheral(
    _ peripheral: CBPeripheral,
    reason: String,
    fallbackName: String? = nil,
    disconnect: Bool = false
  ) {
    let name = peripheral.name ?? fallbackName ?? "unknown"
    record(
      level: .warn,
      source: "ble",
      title: "whoop_filter.rejected",
      body: "reason=\(reason) name=\(name) id=\(peripheral.identifier.uuidString)"
    )
    peripherals.removeValue(forKey: peripheral.identifier)
    whoopCandidateIDs.remove(peripheral.identifier)
    discoveredDevices.removeAll { $0.id == peripheral.identifier }
    if selectedDeviceID == peripheral.identifier {
      selectedDeviceID = discoveredDevices.first?.id
    }
    if rememberedDeviceID == peripheral.identifier {
      clearRememberedDevice(reason: "non_whoop_\(reason)")
    }
    if activePeripheral?.identifier == peripheral.identifier {
      activePeripheral = nil
      activeDeviceIdentifier = nil
      updateActiveDeviceName("WHOOP")
      commandCharacteristic = nil
      batteryLevelCharacteristic = nil
      batteryLevelStatusCharacteristic = nil
      connectedAt = nil
      failAllDebugCommands("Connection rejected as non-WHOOP device.")
      updateConnectionState("not a WHOOP device")
    }
    if disconnect {
      central?.cancelPeripheralConnection(peripheral)
    }
  }

  func discoveredName(for id: UUID) -> String? {
    discoveredDevices.first { $0.id == id }?.name
  }

  func updateActiveDevice(_ peripheral: CBPeripheral, fallbackName: String? = nil) {
    activeDeviceIdentifier = peripheral.identifier
    updateActiveDeviceName(Self.sanitizedWhoopDisplayName(peripheral.name ?? fallbackName ?? rememberedDeviceName ?? "WHOOP strap"))
  }

  func resetLiveDeviceFieldsIfNeeded(for peripheral: CBPeripheral) {
    guard activeDeviceIdentifier != peripheral.identifier else {
      return
    }
    batteryLevelCharacteristic = nil
    batteryLevelStatusCharacteristic = nil
    batteryLevelPercent = nil
    batteryUpdatedAt = nil
    batteryIsCharging = nil
    batteryPowerStatus = "Unknown"
    firmwareVersion = nil
    modelNumber = nil
    hardwareRevision = nil
    softwareRevision = nil
    manufacturerName = nil
    historicalSyncStatus = "idle"
    historicalPacketCount = 0
    liveHeartRateBPM = nil
    liveHeartRateSource = "waiting"
    liveHeartRateUpdatedAt = nil
    self.resetRealtimeHeartRatePublishState()
    connectedAt = nil
    lastSyncAt = nil
    alarmCommandTimeoutWorkItem?.cancel()
    pendingAlarmCommand = nil
    clockCommandTimeoutWorkItem?.cancel()
    pendingClockCommand = nil
    failAllDebugCommands("Device changed before debug command response.")
    alarmCommandStatus = "No alarm command sent"
    lastAlarmCommandFrameHex = ""
    lastAlarmResponseSummary = "No alarm response yet"
    lastAlarmResponsePayloadHex = ""
    lastAlarmEventSummary = "No alarm event yet"
    lastAlarmEventPayloadHex = ""
    lastAlarmScheduledAt = nil
    lastAlarmID = nil
    highFrequencyHistorySyncStatus = "Off"
    highFrequencyHistorySyncActive = false
    highFrequencyHistorySyncRequestedExpiry = nil
    highFrequencyHistorySyncExpiresAt = nil
    lastHighFrequencyHistorySyncResponse = "No high-frequency sync response yet"
    lastHighFrequencyHistorySyncEvent = "No high-frequency sync event yet"
    strapClockDate = nil
    strapClockOffsetSeconds = nil
    strapClockUpdatedAt = nil
    strapClockStatus = "Not read"
    lastClockCommandFrameHex = ""
    lastClockResponsePayloadHex = ""
  }

  func resetRealtimeHeartRatePublishState() {
    realtimeVitalsQueue.async { [weak self] in
      self?.lastHeartRateLogAt = nil
      self?.lastHeartRateLogBPM = nil
      self?.lastHeartRateLogSource = ""
      self?.lastHeartRatePublishedAt = Date.distantPast
      self?.lastHeartRatePublishedBPM = nil
      self?.lastHeartRatePublishedSource = "waiting"
      self?.lastHeartRateCallbackAt = Date.distantPast
      self?.lastHeartRateCallbackSource = ""
    }
  }

  struct StandardHeartRateMeasurement {
    let bpm: Int
    let rrIntervalsMS: [Double]
  }

  static func parseStandardHeartRateMeasurement(_ value: Data) -> StandardHeartRateMeasurement? {
    guard value.count >= 2 else {
      return nil
    }
    let flags = value[0]
    var offset = 1
    let bpm: Int
    if flags & 0x01 == 0 {
      bpm = Int(value[offset])
      offset += 1
    } else {
      guard value.count >= offset + 2 else {
        return nil
      }
      bpm = Int(UInt16(value[offset]) | UInt16(value[offset + 1]) << 8)
      offset += 2
    }

    if flags & 0x08 != 0 {
      guard value.count >= offset + 2 else {
        return StandardHeartRateMeasurement(bpm: bpm, rrIntervalsMS: [])
      }
      offset += 2
    }

    var rrIntervalsMS: [Double] = []
    if flags & 0x10 != 0 {
      while value.count >= offset + 2 {
        let raw = UInt16(value[offset]) | UInt16(value[offset + 1]) << 8
        rrIntervalsMS.append(Double(raw) * 1000.0 / 1024.0)
        offset += 2
      }
    }
    return StandardHeartRateMeasurement(bpm: bpm, rrIntervalsMS: rrIntervalsMS)
  }

  static func rmssdMS(from intervalsMS: [Double]) -> Double? {
    guard intervalsMS.count >= 2 else {
      return nil
    }
    var squaredDifferenceTotal = 0.0
    var differenceCount = 0
    for index in 1..<intervalsMS.count {
      let difference = intervalsMS[index] - intervalsMS[index - 1]
      squaredDifferenceTotal += difference * difference
      differenceCount += 1
    }
    guard differenceCount > 0 else {
      return nil
    }
    return sqrt(squaredDifferenceTotal / Double(differenceCount))
  }

  static func lowQuartileMeanBPM(from samples: [Int]) -> Double {
    let sorted = samples.sorted()
    let count = max(1, sorted.count / 4)
    let lowQuartile = sorted.prefix(count)
    let total = lowQuartile.reduce(0, +)
    return Double(total) / Double(count)
  }

  func commandResultName(_ value: UInt8) -> String {
    switch value {
    case 0:
      return "FAILURE"
    case 1:
      return "SUCCESS"
    case 2:
      return "PENDING"
    case 3:
      return "UNSUPPORTED"
    default:
      return "RESULT_\(value)"
    }
  }

  func updateHistoricalRangeDebugStatus(_ status: String) {
    lastHistoricalRangeCommandStatus = status
    defaults.set(status, forKey: DefaultsKey.debugHistoricalRangeStatus)
  }

  func isValidHistoricalRangeResponse(_ payload: [UInt8]) -> Bool {
    let body = Array(payload.dropFirst(5))
    return body.count >= 25
  }

  func historicalResponseDetail(command: HistoricalCommandKind, payload: [UInt8]) -> String {
    guard command == .getDataRange else {
      return ""
    }
    let body = Array(payload.dropFirst(5))
    guard !body.isEmpty else {
      return " body=empty"
    }

    var words: [UInt32] = []
    var offset = 1
    while offset + 3 < body.count, offset < 25 {
      if let word = Self.readUInt32LE(body, at: offset) {
        words.append(word)
      }
      offset += 4
    }

    var parts = [
      "body=\(Data(body).hexString)",
      "revision_or_status=\(body[0])",
      "u32_words_from_offset_1=[\(words.map(String.init).joined(separator: ","))]",
    ]
    if words.count >= 6 {
      let pageCurrent = words[2]
      let pageOldest = words[3]
      let pageEnd = words[5]
      let pagesBehind: Int64 = pageCurrent < pageOldest
        ? Int64(pageCurrent) + Int64(pageEnd) - Int64(pageOldest)
        : Int64(pageCurrent) - Int64(pageOldest)
      parts.append("page_current=\(pageCurrent)")
      parts.append("page_oldest=\(pageOldest)")
      parts.append("page_end=\(pageEnd)")
      parts.append("pages_behind=\(pagesBehind)")
    }
    return " | " + parts.joined(separator: " ")
  }

  func emitHistoricalRangeTelemetry(
    status: String,
    pending: PendingHistoricalCommand,
    resultCode: UInt8,
    resultName: String,
    payload: [UInt8],
    notes: String
  ) {
    let body = Array(payload.dropFirst(5))
    var words: [UInt32] = []
    var offset = 1
    while offset + 3 < body.count, offset < 25 {
      if let word = Self.readUInt32LE(body, at: offset) {
        words.append(word)
      }
      offset += 4
    }

    let pageCurrent = words.count >= 3 ? words[2] : nil
    let pageOldest = words.count >= 4 ? words[3] : nil
    let pageEnd = words.count >= 6 ? words[5] : nil
    let pagesBehind: Int64?
    if let pageCurrent, let pageOldest, let pageEnd {
      pagesBehind = pageCurrent < pageOldest
        ? Int64(pageCurrent) + Int64(pageEnd) - Int64(pageOldest)
        : Int64(pageCurrent) - Int64(pageOldest)
    } else {
      pagesBehind = nil
    }

    onHistoricalRangeTelemetry?(
      GooseHistoricalRangeTelemetry(
        capturedAt: Date(),
        status: status,
        commandSequence: pending.sequence,
        resultCode: resultCode,
        resultName: resultName,
        payloadHex: Data(payload).hexString,
        bodyHex: Data(body).hexString,
        revisionOrStatus: body.first,
        wordsFromOffset1: words,
        pageCurrent: pageCurrent,
        pageOldest: pageOldest,
        pageEnd: pageEnd,
        pagesBehind: pagesBehind,
        pendingResponseCount: historicalRangePendingResponses,
        retryCount: historicalRangeRetryCount,
        notes: notes
      )
    )
  }

  func alarmResponseDetail(command: AlarmCommandKind, body: [UInt8]) -> String {
    switch command {
    case .set, .run:
      guard body.count >= 2 else {
        return ""
      }
      return " | \(hapticsAlarmStatusName(body[1]))"
    case .get:
      guard !body.isEmpty else {
        return ""
      }
      return " | body=\(Data(body).hexString)"
    case .disableAll:
      return ""
    }
  }

  func hapticsAlarmStatusName(_ value: UInt8) -> String {
    switch value {
    case 0:
      return "UNKNOWN"
    case 1:
      return "VALID_PATTERN"
    case 2:
      return "INVALID_EFFECT"
    case 3:
      return "INVALID_LOOPS"
    case 4:
      return "INVALID_DURATION"
    case 5:
      return "SUCCESSFUL_PLAY"
    case 6:
      return "HAPTICS_FAILURE"
    case 7:
      return "HAPTICS_TIMEOUT"
    case 8:
      return "HAPTICS_BUSY"
    case 9:
      return "HAPTICS_STOPPED"
    case 10:
      return "INVALID_ALARM_TIME"
    case 11:
      return "INVALID_ALARM_ID"
    default:
      return "HAPTICS_STATUS_\(value)"
    }
  }

  func hapticsTerminationName(_ value: UInt8) -> String {
    switch value {
    case 0:
      return "expired"
    case 1:
      return "error"
    case 2:
      return "user terminated"
    case 255:
      return "undefined"
    default:
      return "code \(value)"
    }
  }

  func uuidList(_ uuids: [CBUUID]) -> String {
    uuids.map(\.uuidString).joined(separator: ",")
  }

  func propertyNames(_ properties: CBCharacteristicProperties) -> String {
    var names: [String] = []
    if properties.contains(.read) { names.append("read") }
    if properties.contains(.write) { names.append("write") }
    if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
    if properties.contains(.notify) { names.append("notify") }
    if properties.contains(.indicate) { names.append("indicate") }
    if properties.contains(.broadcast) { names.append("broadcast") }
    if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
    if properties.contains(.extendedProperties) { names.append("extendedProperties") }
    return names.isEmpty ? "none" : names.joined(separator: ",")
  }

  func writeTypeName(_ writeType: CBCharacteristicWriteType) -> String {
    switch writeType {
    case .withResponse:
      return "withResponse"
    case .withoutResponse:
      return "withoutResponse"
    @unknown default:
      return "unknown"
    }
  }

  func emitCommandWrite(
    source: String,
    commandName: String,
    commandNumber: UInt8?,
    sequence: UInt8?,
    payload: Data,
    frame: Data,
    peripheral: CBPeripheral,
    characteristic: CBCharacteristic,
    writeType: CBCharacteristicWriteType
  ) {
    onCommandWrite?(
      GooseCommandWriteEvent(
        deviceID: peripheral.identifier,
        serviceUUID: characteristic.service?.uuid.uuidString ?? "unknown",
        characteristicUUID: characteristic.uuid.uuidString,
        commandName: commandName,
        commandNumber: commandNumber,
        sequence: sequence,
        payload: payload,
        frame: frame,
        writeType: writeTypeName(writeType),
        source: source,
        capturedAt: Date()
      )
    )
  }

  static func nextFutureAlarmDate(from localWakeTime: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
    let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: localWakeTime)
    var target = calendar.dateComponents([.year, .month, .day], from: now)
    target.hour = time.hour
    target.minute = time.minute
    target.second = time.second
    target.nanosecond = time.nanosecond

    let candidate = calendar.date(from: target) ?? localWakeTime
    if candidate > now {
      return candidate
    }
    return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(24 * 60 * 60)
  }

  static func alarmTimestampParts(for date: Date) -> (seconds: UInt32, subseconds: UInt16) {
    let milliseconds = max(0, Int64((date.timeIntervalSince1970 * 1000).rounded()))
    let seconds = UInt32(min(Int64(UInt32.max), milliseconds / 1000))
    let millisecondRemainder = UInt32(milliseconds % 1000)
    let subseconds = UInt16((millisecondRemainder * 32768) / 1000)
    return (seconds, subseconds)
  }

  static func clockTimestampParts(for date: Date) -> (seconds: UInt32, subseconds: UInt32) {
    let milliseconds = max(0, Int64((date.timeIntervalSince1970 * 1000).rounded()))
    let seconds = UInt32(min(Int64(UInt32.max), milliseconds / 1000))
    let millisecondRemainder = UInt32(milliseconds % 1000)
    let subseconds = (millisecondRemainder * 32768) / 1000
    return (seconds, subseconds)
  }

  static func parseClockTimestamp(_ body: [UInt8]) -> Date? {
    guard let seconds = readUInt32LE(body, at: 0),
          let subseconds = readUInt32LE(body, at: 4) else {
      return nil
    }
    return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(subseconds) / 32768.0)
  }

  static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
    guard offset >= 0, bytes.count >= offset + 4 else {
      return nil
    }
    return UInt32(bytes[offset])
      | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }

  static func historicalDataResultPayload(fromHistoryEndMetadataPayload payload: [UInt8]) -> [UInt8]? {
    guard payload.count > 21 else {
      return nil
    }

    // Mirrors the Android ACK builder: success byte, then HistoryEnd body bytes 4...11.
    var result: [UInt8] = [1]
    result.append(contentsOf: payload[13..<21])
    return result
  }

  static func clockOffsetText(_ offset: TimeInterval) -> String {
    let rounded = Int(offset.rounded())
    if rounded == 0 {
      return "0s"
    }
    let sign = rounded > 0 ? "+" : "-"
    return "\(sign)\(abs(rounded))s"
  }

  static func appendUInt16LE(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(value & 0xff))
    bytes.append(UInt8((value >> 8) & 0xff))
  }

  static func appendUInt32LE(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(value & 0xff))
    bytes.append(UInt8((value >> 8) & 0xff))
    bytes.append(UInt8((value >> 16) & 0xff))
    bytes.append(UInt8((value >> 24) & 0xff))
  }

  static func v5Frames(in data: Data) -> [Data] {
    var bytes = Array(data)
    var frames: [Data] = []
    while let startIndex = bytes.firstIndex(of: 0xaa) {
      if startIndex > 0 {
        bytes.removeFirst(startIndex)
      }
      guard bytes.count >= 8 else {
        break
      }
      let declaredLength = Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
      guard declaredLength >= 4 else {
        bytes.removeFirst()
        continue
      }
      let expectedLength = declaredLength + 8
      guard bytes.count >= expectedLength else {
        break
      }
      frames.append(Data(bytes[0..<expectedLength]))
      bytes.removeFirst(expectedLength)
    }
    return frames
  }

  static func v5Payload(in frame: Data) -> [UInt8]? {
    let bytes = Array(frame)
    guard bytes.count >= 12 else {
      return nil
    }
    let declaredLength = Int(UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
    let expectedLength = declaredLength + 8
    guard bytes.count == expectedLength, declaredLength >= 4 else {
      return nil
    }
    return Array(bytes[8..<(bytes.count - 4)])
  }

  // Gen4 (WHOOP 4.0) deframer: 4-byte header [0xaa, len_lo, len_hi, crc8] where
  // len = payload.count + 4 (no header byte beyond the SOF/length/crc8). The
  // inner payload (packet type + body) is generation-independent, so once
  // deframed the existing payload handlers work unchanged.
  static func gen4Frames(in data: Data) -> [Data] {
    var bytes = Array(data)
    var frames: [Data] = []
    while let startIndex = bytes.firstIndex(of: 0xaa) {
      if startIndex > 0 {
        bytes.removeFirst(startIndex)
      }
      guard bytes.count >= 4 else {
        break
      }
      let declaredLength = Int(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
      guard declaredLength >= 4 else {
        bytes.removeFirst()
        continue
      }
      let expectedLength = declaredLength + 4
      guard bytes.count >= expectedLength else {
        break
      }
      frames.append(Data(bytes[0..<expectedLength]))
      bytes.removeFirst(expectedLength)
    }
    return frames
  }

  static func gen4Payload(in frame: Data) -> [UInt8]? {
    let bytes = Array(frame)
    guard bytes.count >= 8 else {
      return nil
    }
    let declaredLength = Int(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
    let expectedLength = declaredLength + 4
    guard bytes.count == expectedLength, declaredLength >= 4 else {
      return nil
    }
    return Array(bytes[4..<(bytes.count - 4)])
  }

  // Generation-aware deframing for the Swift-side command/response state
  // machines (clock, alarm, sensor, historical, debug). Dispatches on the
  // connected strap's command characteristic generation.
  func strapFrames(in data: Data) -> [Data] {
    switch activeCommandGeneration {
    case .gen4:
      return Self.gen4Frames(in: data)
    case .gen5, .none:
      return Self.v5Frames(in: data)
    }
  }

  func strapPayload(in frame: Data) -> [UInt8]? {
    switch activeCommandGeneration {
    case .gen4:
      return Self.gen4Payload(in: frame)
    case .gen5, .none:
      return Self.v5Payload(in: frame)
    }
  }

  static func buildV5CommandFrame(sequence: UInt8, command: UInt8, data: [UInt8]) -> Data {
    var payload = [V5PacketType.command, sequence, command]
    payload.append(contentsOf: data)
    let padding = payload.count % 4 == 0 ? 0 : 4 - payload.count % 4
    if padding > 0 {
      payload.append(contentsOf: repeatElement(UInt8(0), count: padding))
    }

    let payloadCRC = crc32(payload)
    let declaredLength = UInt16(payload.count + 4)
    var frame: [UInt8] = [
      0xaa,
      0x01,
      UInt8(declaredLength & 0xff),
      UInt8((declaredLength >> 8) & 0xff),
      0x00,
      0x01,
    ]
    let headerCRC = crc16Modbus(frame)
    frame.append(UInt8(headerCRC & 0xff))
    frame.append(UInt8((headerCRC >> 8) & 0xff))
    frame.append(contentsOf: payload)
    frame.append(UInt8(payloadCRC & 0xff))
    frame.append(UInt8((payloadCRC >> 8) & 0xff))
    frame.append(UInt8((payloadCRC >> 16) & 0xff))
    frame.append(UInt8((payloadCRC >> 24) & 0xff))
    return Data(frame)
  }

  // WHOOP 4.0 (Gen4) command frame: 4-byte header [0xaa, len_lo, len_hi,
  // crc8(len bytes)] + payload + crc32(payload) little-endian, where
  // len = payload.count + 4 and the payload is NOT zero-padded. Verified against
  // the openwhoop reference: buildGen4CommandFrame(0, 35, [0x00]) ==
  // aa0800a823002300ada86a2d.
  static func buildGen4CommandFrame(sequence: UInt8, command: UInt8, data: [UInt8]) -> Data {
    var payload = [V5PacketType.command, sequence, command]
    payload.append(contentsOf: data)

    let payloadCRC = crc32(payload)
    let declaredLength = UInt16(payload.count + 4)
    let lengthLow = UInt8(declaredLength & 0xff)
    let lengthHigh = UInt8((declaredLength >> 8) & 0xff)
    var frame: [UInt8] = [
      0xaa,
      lengthLow,
      lengthHigh,
      crc8([lengthLow, lengthHigh]),
    ]
    frame.append(contentsOf: payload)
    frame.append(UInt8(payloadCRC & 0xff))
    frame.append(UInt8((payloadCRC >> 8) & 0xff))
    frame.append(UInt8((payloadCRC >> 16) & 0xff))
    frame.append(UInt8((payloadCRC >> 24) & 0xff))
    return Data(frame)
  }

  // Picks the correct command frame format for the connected strap generation.
  func buildCommandFrame(sequence: UInt8, command: UInt8, data: [UInt8]) -> Data {
    switch activeCommandGeneration {
    case .gen4:
      return Self.buildGen4CommandFrame(sequence: sequence, command: command, data: data)
    case .gen5, .none:
      return Self.buildV5CommandFrame(sequence: sequence, command: command, data: data)
    }
  }

  // CRC-8 with polynomial 0x07, initial value 0, non-reflected (used for the
  // Gen4 frame header over the two length bytes).
  static func crc8(_ bytes: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0
    for byte in bytes {
      crc ^= byte
      for _ in 0..<8 {
        if crc & 0x80 != 0 {
          crc = (crc << 1) ^ 0x07
        } else {
          crc <<= 1
        }
      }
    }
    return crc
  }

  static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
    var crc = UInt16(0xffff)
    for byte in bytes {
      crc ^= UInt16(byte)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xa001
        } else {
          crc >>= 1
        }
      }
    }
    return crc
  }

  static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc = UInt32(0xffffffff)
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
    }
    return ~crc
  }
}

/// Forwards live HR + R-R intervals from the WHOOP 4.0 (standard HR characteristic)
/// to the self-hosted whoop-band cloud (VPS). Fire-and-forget; never blocks BLE.
final class WhoopCloudForwarder {
  static let shared = WhoopCloudForwarder()

  /// Self-hosted ingest endpoint (token-protected; no basic auth on this path).
  private let endpoint = URL(string: "https://latenightgames.fr/whoop/ingest/samples")!
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"
  private let queue = DispatchQueue(label: "com.goose.swift.cloud-forward", qos: .utility)
  private let iso = ISO8601DateFormatter()
  private var lastSent = Date.distantPast
  private var frameBuffers: [String: [UInt8]] = [:]   // per-characteristic frame reassembly
  private var pendingFrames: [String] = []            // complete-frame hex awaiting POST
  private var lastFrameFlush = Date.distantPast

  /// Enable/disable the cloud feed (defaults on; flip via UserDefaults "whoopCloudForwarding").
  var isEnabled: Bool {
    UserDefaults.standard.object(forKey: "whoopCloudForwarding") as? Bool ?? true
  }

  func forward(bpm: Int, rrMs: [Double], at date: Date) {
    guard isEnabled, bpm > 0 else { return }
    queue.async {
      // throttle to at most ~1 post/sec to keep it light
      guard date.timeIntervalSince(self.lastSent) >= 0.9 else { return }
      self.lastSent = date
      var req = URLRequest(url: self.endpoint)
      req.httpMethod = "POST"
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.setValue(self.token, forHTTPHeaderField: "X-Ingest-Token")
      let body: [String: Any] = [
        "bpm": bpm,
        "rr_intervals_ms": rrMs,
        "wall_ts": self.iso.string(from: date),
      ]
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
      URLSession.shared.dataTask(with: req).resume()  // fire-and-forget
    }
  }

  // MARK: Raw GEN4 frame forwarding (powers the live /pulse waveform)

  private static let framesEndpoint = URL(string: "https://latenightgames.fr/whoop/ingest/frames")!

  /// Feed every raw BLE notification fragment from the 4.0 data characteristics.
  /// The band fragments frames across notifications, so we reassemble whole
  /// frames on-device (by the length header) and forward the realtime/optical/
  /// event frames — the server decodes the pulse from them. All buffer state
  /// lives on `queue`, so this is thread-safe and never blocks the BLE thread.
  func ingestRawFrame(_ data: Data, characteristicUUID: String) {
    guard isEnabled else { return }
    let uuid = characteristicUUID.lowercased()
    guard uuid.hasPrefix("61080005") || uuid.hasPrefix("61080003") || uuid.hasPrefix("61080004") else { return }
    let bytes = [UInt8](data)
    queue.async {
      var buf = self.frameBuffers[uuid] ?? []
      buf.append(contentsOf: bytes)
      var i = 0
      while i + 4 <= buf.count {
        if buf[i] != 0xAA { i += 1; continue }
        let len = Int(buf[i + 1]) | (Int(buf[i + 2]) << 8)
        let end = i + 4 + len
        if end > buf.count { break }                 // frame not fully arrived yet
        let frame = Array(buf[i..<end])
        let type = frame.count > 4 ? frame[4] : 0
        if type == 40 || type == 43 || type == 48 || type == 36 || type == 47 {
          // HR / optical / event / cmd-resp / historical-backfill
          self.pendingFrames.append(frame.map { String(format: "%02x", $0) }.joined())
        }
        i = end
      }
      if i > 0 { buf.removeFirst(i) }
      if buf.count > 16384 { buf.removeFirst(buf.count - 8192) }     // guard against runaway
      self.frameBuffers[uuid] = buf
      let now = Date()
      if self.pendingFrames.count >= 30
          || (!self.pendingFrames.isEmpty && now.timeIntervalSince(self.lastFrameFlush) >= 3) {
        self.flushFramesOnQueue(now)
      }
    }
  }

  // MARK: Disk-backed outbox — no internet must never lose biometric frames

  private static let outboxDir: URL = {
    let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask, appropriateFor: nil, create: true))
      ?? URL.documentsDirectory
    let dir = base.appendingPathComponent("whoop_outbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()
  private var outboxSeq = 0
  private let maxOutboxFiles = 4000   // ~hours of backlog; oldest dropped beyond this

  /// Build the POST body, tagging it with the capture time so frames that upload
  /// late (after an outage) are stamped at when they happened, not when they land.
  private func framesBody(_ frames: [String]) -> Data? {
    try? JSONSerialization.data(withJSONObject: [
      "frames": frames,
      "base_wall_ts": iso.string(from: Date()),
    ])
  }

  private func postFrames(_ body: Data, completion: @escaping (Bool) -> Void) {
    var req = URLRequest(url: Self.framesEndpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    req.httpBody = body
    URLSession.shared.dataTask(with: req) { _, resp, err in
      let ok = err == nil
        && ((resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
      completion(ok)
    }.resume()
  }

  /// POST the batched complete frames to /ingest/frames. On failure (e.g. no
  /// internet) the batch is saved to the disk outbox and retried later; on
  /// success we also drain any backlog. Call on `queue` only.
  private func flushFramesOnQueue(_ now: Date) {
    let batch = pendingFrames
    pendingFrames = []
    lastFrameFlush = now
    if batch.isEmpty { drainOutbox(); return }
    guard let body = framesBody(batch) else { return }
    postFrames(body) { [weak self] ok in
      self?.queue.async {
        if ok { self?.drainOutbox() } else { self?.persistFailedBody(body) }
      }
    }
  }

  /// Persist a body that failed to upload, ordered by time for in-order replay.
  private func persistFailedBody(_ body: Data) {
    outboxSeq += 1
    let name = String(format: "%015.0f-%05d.json", Date().timeIntervalSince1970 * 1000, outboxSeq)
    try? body.write(to: Self.outboxDir.appendingPathComponent(name))
    trimOutboxIfNeeded()
  }

  /// Send the oldest backlog file; on success delete it and continue draining,
  /// on failure stop (still offline) and leave it for the next attempt.
  private func drainOutbox() {
    let fm = FileManager.default
    guard let url = (try? fm.contentsOfDirectory(at: Self.outboxDir, includingPropertiesForKeys: nil))?
      .filter({ $0.pathExtension == "json" })
      .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else { return }
    guard let body = try? Data(contentsOf: url) else { try? fm.removeItem(at: url); return }
    postFrames(body) { [weak self] ok in
      self?.queue.async {
        guard ok else { return }
        try? fm.removeItem(at: url)
        self?.drainOutbox()
      }
    }
  }

  private func trimOutboxIfNeeded() {
    let fm = FileManager.default
    guard let files = (try? fm.contentsOfDirectory(at: Self.outboxDir, includingPropertiesForKeys: nil))?
      .filter({ $0.pathExtension == "json" })
      .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }), files.count > maxOutboxFiles else { return }
    for url in files.prefix(files.count - maxOutboxFiles) { try? fm.removeItem(at: url) }
  }

  // MARK: Diagnostic log streaming (so we can debug live without the Export step)

  private static let logsEndpoint = URL(string: "https://latenightgames.fr/whoop/ingest/logs")!
  private var pendingLogs: [[String: Any]] = []
  private var lastLogFlush = Date.distantPast

  /// Stream the app's diagnostic log lines to the VPS. On by default; flip via
  /// UserDefaults "whoopLogStreaming".
  var logStreamEnabled: Bool {
    UserDefaults.standard.object(forKey: "whoopLogStreaming") as? Bool ?? true
  }

  /// Called from `GooseBLEClient.record` for every recorded message. Batches and
  /// forwards to /ingest/logs. Fire-and-forget; never blocks the caller.
  func ingestLog(level: String, source: String, title: String, body: String, at date: Date) {
    guard isEnabled, logStreamEnabled else { return }
    if source == "cloud.logstream" { return }   // never recurse on our own logs
    queue.async {
      let entry: [String: Any] = [
        "ts": self.iso.string(from: date), "level": level,
        "source": source, "title": title, "body": body,
      ]
      self.pendingLogs.append(entry)
      let now = Date()
      if self.pendingLogs.count >= 40
          || (!self.pendingLogs.isEmpty && now.timeIntervalSince(self.lastLogFlush) >= 5) {
        self.flushLogsOnQueue(now)
      }
      if self.pendingLogs.count > 500 {          // runaway guard if VPS unreachable
        self.pendingLogs.removeFirst(self.pendingLogs.count - 250)
      }
    }
  }

  /// POST the batched log lines to /ingest/logs. Call on `queue` only.
  private func flushLogsOnQueue(_ now: Date) {
    let batch = pendingLogs
    pendingLogs = []
    lastLogFlush = now
    guard !batch.isEmpty else { return }
    var req = URLRequest(url: Self.logsEndpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["logs": batch])
    URLSession.shared.dataTask(with: req).resume()
  }
}
