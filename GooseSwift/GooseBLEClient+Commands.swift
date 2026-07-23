import CoreBluetooth
import Foundation
import OSLog


extension GooseBLEClient {
  func ensureCentral() {
    if central == nil {
      record(source: "ble", title: "central.create")
      central = CBCentralManager(
        delegate: self,
        queue: coreBluetoothQueue,
        options: [
          CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier,
        ]
      )
    }
  }

  func dispatchCoreBluetoothDelegateToMainIfNeeded(_ work: @escaping () -> Void) -> Bool {
    guard !Thread.isMainThread else {
      return false
    }
    DispatchQueue.main.async(execute: work)
    return true
  }

  static var canCreateCentralWithoutPrompt: Bool {
    switch CBManager.authorization {
    case .allowedAlways:
      return true
    case .notDetermined, .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  static var authorizationStateDescription: String {
    switch CBManager.authorization {
    case .allowedAlways:
      return "allowed"
    case .notDetermined:
      return "not determined"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    @unknown default:
      return "unknown"
    }
  }

  func updateBluetoothState() {
    let previous = bluetoothState
    switch central?.state {
    case .poweredOn:
      bluetoothState = "powered on"
    case .poweredOff:
      bluetoothState = "powered off"
    case .unauthorized:
      bluetoothState = "unauthorized"
    case .unsupported:
      bluetoothState = "unsupported"
    case .resetting:
      bluetoothState = "resetting"
    case .unknown:
      bluetoothState = "unknown"
    case nil:
      switch CBManager.authorization {
      case .allowedAlways, .notDetermined:
        bluetoothState = "not requested"
      case .denied, .restricted:
        bluetoothState = "unauthorized"
      @unknown default:
        bluetoothState = "unknown"
      }
    @unknown default:
      bluetoothState = "unknown"
    }
    if previous != bluetoothState {
      record(source: "ble", title: "bluetooth.state", body: bluetoothState)
    }
  }

  func writeOSLog(_ message: GooseMessage) {
    let line = "\(message.source) \(message.title) \(message.body)"
    switch message.level {
    case .debug:
      logger.debug("\(line, privacy: .public)")
    case .info:
      logger.info("\(line, privacy: .public)")
    case .warn:
      logger.warning("\(line, privacy: .public)")
    case .error:
      logger.error("\(line, privacy: .public)")
    }
  }

  func updateConnectionState(_ value: String) {
    let previous = connectionState
    connectionState = value
    updateNotificationContext(connectionState: value)
    if previous != value {
      record(source: "ble", title: "connection.state", body: value)
      onConnectionStateChange?(value)
    }
  }

  func updateActiveDeviceName(_ value: String) {
    activeDeviceName = value
    updateNotificationContext(activeDeviceName: value)
  }

  func updateNotificationContext(
    activeDeviceName: String? = nil,
    connectionState: String? = nil
  ) {
    notificationContextLock.lock()
    if let activeDeviceName {
      notificationContextActiveDeviceName = activeDeviceName
    }
    if let connectionState {
      notificationContextConnectionState = connectionState
    }
    notificationContextLock.unlock()
  }

  func notificationContextSnapshot() -> GooseBLENotificationContext {
    notificationContextLock.lock()
    let snapshot = GooseBLENotificationContext(
      activeDeviceName: notificationContextActiveDeviceName,
      connectionState: notificationContextConnectionState
    )
    notificationContextLock.unlock()
    return snapshot
  }

  func updateReconnectState(_ value: String) {
    let previous = reconnectState
    reconnectState = value
    if previous != value {
      record(source: "ble", title: "reconnect.state", body: value)
    }
  }

  var supportsV5HistoricalSync: Bool {
    commandCharacteristic.map(isV5CommandCharacteristic) == true
  }

  var supportsV5AlarmCommands: Bool {
    commandCharacteristic.map(isV5CommandCharacteristic) == true
  }

  var supportsV5ClockCommands: Bool {
    commandCharacteristic.map(isV5CommandCharacteristic) == true
  }

  var supportsV5SensorCommands: Bool {
    commandCharacteristic.map(isV5CommandCharacteristic) == true
  }

  func isV5CommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
    characteristic.uuid.uuidString.lowercased().hasPrefix("fd4b0002")
  }

  func shouldUseCommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
    guard commandCharacteristicIDs.contains(characteristic.uuid) else {
      return false
    }
    guard let current = commandCharacteristic else {
      return true
    }
    return !isV5CommandCharacteristic(current) && isV5CommandCharacteristic(characteristic)
  }

  func validatedAlarmID(_ rawValue: Int) -> UInt8? {
    guard (0...255).contains(rawValue) else {
      alarmCommandStatus = "Alarm ID must be 0-255"
      record(level: .warn, source: "ble.alarm", title: "alarm.id.invalid", body: "\(rawValue)")
      return nil
    }
    return UInt8(rawValue)
  }

  func writeClockCommand(_ kind: ClockCommandKind, syncIfNeeded: Bool) {
    guard !isHistoricalSyncing else {
      failClockCommand("Clock command blocked during historical sync.")
      return
    }
    guard pendingClockCommand == nil else {
      strapClockStatus = "Clock command already in flight"
      record(level: .warn, source: "ble.clock", title: "clock.write.blocked", body: strapClockStatus)
      return
    }
    guard pendingAlarmCommand == nil else {
      strapClockStatus = "Clock command blocked by alarm command"
      record(level: .warn, source: "ble.clock", title: "clock.write.blocked", body: strapClockStatus)
      return
    }
    guard let activePeripheral, let commandCharacteristic else {
      failClockCommand("Clock command needs an active WHOOP command characteristic.")
      return
    }
    guard connectionState == "ready" else {
      failClockCommand("Clock command needs ready connection; current state \(connectionState).")
      return
    }
    guard supportsV5ClockCommands else {
      failClockCommand("Clock command needs fd4b0002 V5 command framing. Active command characteristic: \(commandCharacteristic.uuid.uuidString).")
      return
    }
    guard let writeType = writeType(for: commandCharacteristic) else {
      failClockCommand("Clock command blocked: command characteristic is not writable.")
      return
    }

    let sequence = nextClockSequence()
    let frame = Self.buildV5CommandFrame(
      sequence: sequence,
      command: kind.commandNumber,
      data: kind.payload
    )
    pendingClockCommand = PendingClockCommand(
      kind: kind,
      sequence: sequence,
      sentAt: Date(),
      syncIfNeeded: syncIfNeeded
    )
    scheduleClockCommandTimeout(kind: kind, sequence: sequence)
    lastClockCommandFrameHex = frame.hexString
    lastClockResponsePayloadHex = ""
    switch kind {
    case .get:
      strapClockStatus = syncIfNeeded
        ? "Reading clock; auto-sync >\(strapClockAutoSyncThresholdDisplay)"
        : "Reading clock"
    case .set:
    strapClockStatus = "Syncing clock"
    }
    activePeripheral.writeValue(frame, for: commandCharacteristic, type: writeType)
    emitCommandWrite(
      source: "ble.clock",
      commandName: kind.name,
      commandNumber: kind.commandNumber,
      sequence: sequence,
      payload: Data(kind.payload),
      frame: frame,
      peripheral: activePeripheral,
      characteristic: commandCharacteristic,
      writeType: writeType
    )
    record(
      source: "ble.clock",
      title: "clock.command.sent",
      body: "\(kind.name) seq=\(sequence) command=\(kind.commandNumber) payload=\(Data(kind.payload).hexString) writeType=\(writeTypeName(writeType)) frame=\(frame.hexString)"
    )
  }

  func nextClockSequence() -> UInt8 {
    let sequence = nextClockCommandSequence
    nextClockCommandSequence = nextClockCommandSequence == UInt8.max ? 96 : nextClockCommandSequence + 1
    return sequence
  }

  func scheduleClockCommandTimeout(kind: ClockCommandKind, sequence: UInt8) {
    clockCommandTimeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
            let pending = self.pendingClockCommand,
            pending.kind.commandNumber == kind.commandNumber,
            pending.sequence == sequence else {
        return
      }
      self.failClockCommand("\(kind.name) timed out waiting for command response sequence \(sequence).")
    }
    clockCommandTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
  }

  func writeAlarmCommand(_ kind: AlarmCommandKind) {
    guard !isHistoricalSyncing else {
      alarmCommandStatus = "Alarm write blocked during historical sync"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: alarmCommandStatus)
      return
    }
    guard pendingAlarmCommand == nil else {
      alarmCommandStatus = "Alarm write blocked: command already in flight"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: alarmCommandStatus)
      return
    }
    guard let activePeripheral, let commandCharacteristic else {
      alarmCommandStatus = "Alarm write needs an active WHOOP command characteristic"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: alarmCommandStatus)
      return
    }
    guard connectionState == "ready" else {
      alarmCommandStatus = "Alarm write needs ready connection; current state \(connectionState)"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: alarmCommandStatus)
      return
    }
    guard supportsV5AlarmCommands else {
      alarmCommandStatus = "Alarm writes need fd4b0002 V5 command framing"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: commandCharacteristic.uuid.uuidString)
      return
    }
    guard let writeType = writeType(for: commandCharacteristic) else {
      alarmCommandStatus = "Alarm write blocked: command characteristic is not writable"
      record(level: .warn, source: "ble.alarm", title: "alarm.write.blocked", body: commandCharacteristic.uuid.uuidString)
      return
    }

    let sequence = nextAlarmSequence()
    let frame = Self.buildV5CommandFrame(
      sequence: sequence,
      command: kind.commandNumber,
      data: kind.payload
    )
    pendingAlarmCommand = PendingAlarmCommand(kind: kind, sequence: sequence)
    scheduleAlarmCommandTimeout(kind: kind, sequence: sequence)
    lastAlarmCommandFrameHex = frame.hexString
    lastAlarmResponseSummary = "Waiting for \(kind.name) response seq \(sequence)"
    lastAlarmResponsePayloadHex = ""
    lastAlarmEventSummary = "No alarm event for this command yet"
    lastAlarmEventPayloadHex = ""
    alarmCommandStatus = "\(kind.name) sent; waiting for strap response"
    activePeripheral.writeValue(frame, for: commandCharacteristic, type: writeType)
    emitCommandWrite(
      source: "ble.alarm",
      commandName: kind.name,
      commandNumber: kind.commandNumber,
      sequence: sequence,
      payload: Data(kind.payload),
      frame: frame,
      peripheral: activePeripheral,
      characteristic: commandCharacteristic,
      writeType: writeType
    )
    record(
      source: "ble.alarm",
      title: "alarm.command.sent",
      body: "\(kind.name) seq=\(sequence) command=\(kind.commandNumber) payload=\(Data(kind.payload).hexString) writeType=\(writeTypeName(writeType)) frame=\(frame.hexString)"
    )
  }

  func nextAlarmSequence() -> UInt8 {
    let sequence = nextAlarmCommandSequence
    nextAlarmCommandSequence = nextAlarmCommandSequence == UInt8.max ? 64 : nextAlarmCommandSequence + 1
    return sequence
  }

  func scheduleAlarmCommandTimeout(kind: AlarmCommandKind, sequence: UInt8) {
    alarmCommandTimeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
            let pending = self.pendingAlarmCommand,
            pending.kind.commandNumber == kind.commandNumber,
            pending.sequence == sequence else {
        return
      }
      self.failAlarmCommand("\(kind.name) timed out waiting for command response sequence \(sequence).")
    }
    alarmCommandTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
  }

  func writeSensorStreamCommands(
    _ commands: [SensorStreamCommandKind],
    requestedStatus: String,
    updatePhysiologyStatus: Bool = true
  ) {
    guard !isHistoricalSyncing else {
      if updatePhysiologyStatus {
        physiologyCaptureStatus = "Blocked during historical sync"
      }
      record(level: .warn, source: "ble.sensor", title: "sensor.write.blocked", body: "Blocked during historical sync")
      return
    }
    guard let activePeripheral, let commandCharacteristic else {
      if updatePhysiologyStatus {
        physiologyCaptureStatus = "Needs an active WHOOP command characteristic"
      }
      record(level: .warn, source: "ble.sensor", title: "sensor.write.blocked", body: "Needs an active WHOOP command characteristic")
      return
    }
    guard connectionState == "ready" else {
      if updatePhysiologyStatus {
        physiologyCaptureStatus = "Needs ready connection; current state \(connectionState)"
      }
      record(level: .warn, source: "ble.sensor", title: "sensor.write.blocked", body: "Needs ready connection; current state \(connectionState)")
      return
    }
    guard supportsV5SensorCommands else {
      if updatePhysiologyStatus {
        physiologyCaptureStatus = "Needs fd4b0002 V5 command framing"
      }
      record(level: .warn, source: "ble.sensor", title: "sensor.write.blocked", body: commandCharacteristic.uuid.uuidString)
      return
    }
    guard let writeType = writeType(for: commandCharacteristic) else {
      if updatePhysiologyStatus {
        physiologyCaptureStatus = "Command characteristic is not writable"
      }
      record(level: .warn, source: "ble.sensor", title: "sensor.write.blocked", body: commandCharacteristic.uuid.uuidString)
      return
    }

    if updatePhysiologyStatus {
      physiologyCaptureStatus = requestedStatus
    }
    for (index, command) in commands.enumerated() {
      let delay = Double(index) * 0.25
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak activePeripheral, weak commandCharacteristic] in
        guard
          let self,
          let activePeripheral,
          let commandCharacteristic
        else {
          return
        }
        self.writeSensorStreamCommand(
          command,
          peripheral: activePeripheral,
          characteristic: commandCharacteristic,
          writeType: writeType,
          updatePhysiologyStatus: updatePhysiologyStatus
        )
      }
    }
  }

  func writeSensorStreamCommand(
    _ command: SensorStreamCommandKind,
    peripheral: CBPeripheral,
    characteristic: CBCharacteristic,
    writeType: CBCharacteristicWriteType,
    updatePhysiologyStatus: Bool = true
  ) {
    let sequence = nextSensorCommandSequence
    nextSensorCommandSequence = nextSensorCommandSequence == UInt8.max ? 180 : nextSensorCommandSequence + 1
    let frame = Self.buildV5CommandFrame(
      sequence: sequence,
      command: command.commandNumber,
      data: command.payload
    )
    if updatePhysiologyStatus {
      lastPhysiologyCommandSummary = "\(command.name) seq \(sequence) sent"
    } else if command.commandNumber == 96 || command.commandNumber == 97 {
      lastHighFrequencyHistorySyncResponse = "\(command.name) seq \(sequence) sent"
    }
    peripheral.writeValue(frame, for: characteristic, type: writeType)
    emitCommandWrite(
      source: "ble.sensor",
      commandName: command.name,
      commandNumber: command.commandNumber,
      sequence: sequence,
      payload: Data(command.payload),
      frame: frame,
      peripheral: peripheral,
      characteristic: characteristic,
      writeType: writeType
    )
    record(
      source: "ble.sensor",
      title: "sensor.command.sent",
      body: "\(command.name) seq=\(sequence) command=\(command.commandNumber) payload=\(Data(command.payload).hexString) writeType=\(writeTypeName(writeType)) frame=\(frame.hexString)"
    )
  }

  func failClockCommand(_ message: String) {
    clockCommandTimeoutWorkItem?.cancel()
    pendingClockCommand = nil
    strapClockStatus = message
    record(level: .error, source: "ble.clock", title: "clock.command.failed", body: message)
  }

  func failAlarmCommand(_ message: String) {
    alarmCommandTimeoutWorkItem?.cancel()
    pendingAlarmCommand = nil
    alarmCommandStatus = message
    lastAlarmResponseSummary = message
    record(level: .error, source: "ble.alarm", title: "alarm.command.failed", body: message)
  }

  func loadRememberedDevice() {
    rememberedDeviceName = defaults.string(forKey: DefaultsKey.rememberedDeviceName)
    if let idString = defaults.string(forKey: DefaultsKey.rememberedDeviceID) {
      rememberedDeviceID = UUID(uuidString: idString)
    }
    rememberedDeviceValidated = defaults.bool(forKey: DefaultsKey.rememberedDeviceValidated)
    updateRememberedDeviceDescription()
  }

  func loadPersistedBatterySample() {
    guard defaults.object(forKey: DefaultsKey.lastBatteryPercent) != nil else {
      return
    }
    let percent = defaults.integer(forKey: DefaultsKey.lastBatteryPercent)
    let capturedAt = defaults.object(forKey: DefaultsKey.lastBatteryCapturedAt) as? Date
    let normalizedPercent = min(max(percent, 0), 100)
    batteryLevelPercent = normalizedPercent
    batteryUpdatedAt = capturedAt
    if let capturedAt {
      lastBatteryLevelSample = (normalizedPercent, capturedAt)
    }
    // Deliberately do NOT restore an "inferred charging" assertion across app
    // launches: at launch there is no fresh evidence the band is still on the
    // charger, and a stale 30-min window would keep the UI stuck on "Charging"
    // after the charger was already removed. Charging state is driven only by
    // live evidence — a rising battery level or a CHARGING_ON/OFF event.
  }

  func loadPersistedHRVSample() {
    guard defaults.object(forKey: DefaultsKey.liveHRVRMSSD) != nil else {
      return
    }
    let rmssd = defaults.double(forKey: DefaultsKey.liveHRVRMSSD)
    let count = defaults.integer(forKey: DefaultsKey.liveHRVRRIntervalCount)
    let sampleCount = defaults.integer(forKey: DefaultsKey.liveHRVRMSSDSampleCount)
    let source = defaults.string(forKey: DefaultsKey.liveHRVSource) ?? "ble.hr.standard.average"
    guard rmssd.isFinite, rmssd >= 0, count >= 2, sampleCount > 0 else {
      return
    }
    liveHRVRMSSD = rmssd
    liveHRVRRIntervalCount = count
    liveHRVRMSSDSampleCount = sampleCount
    liveHRVUpdatedAt = defaults.object(forKey: DefaultsKey.liveHRVUpdatedAt) as? Date
    liveHRVSource = source
    lastPublishedHRVRMSSD = rmssd
    lastHRVPublishedAt = liveHRVUpdatedAt ?? Date.distantPast
  }

  func loadPersistedRestingHeartRateEstimate() {
    guard defaults.object(forKey: DefaultsKey.restingHeartRateEstimateBPM) != nil else {
      return
    }
    let bpm = defaults.double(forKey: DefaultsKey.restingHeartRateEstimateBPM)
    let count = defaults.integer(forKey: DefaultsKey.restingHeartRateEstimateSampleCount)
    guard bpm.isFinite, bpm > 0, count >= Self.restingHeartRateMinimumSampleCount else {
      return
    }
    restingHeartRateEstimateBPM = bpm
    restingHeartRateEstimateSampleCount = count
    restingHeartRateEstimateUpdatedAt = defaults.object(forKey: DefaultsKey.restingHeartRateEstimateUpdatedAt) as? Date
    restingHeartRateEstimateSource = defaults.string(forKey: DefaultsKey.restingHeartRateEstimateSource) ?? "ble.hr.standard.low_quartile"
    lastRestingHeartRateEstimateBPM = bpm
    lastRestingHeartRateEstimatePublishedAt = restingHeartRateEstimateUpdatedAt ?? Date.distantPast
  }

  func persistRestingHeartRateEstimate(bpm: Double, sampleCount: Int, source: String, capturedAt: Date) {
    defaults.set(bpm, forKey: DefaultsKey.restingHeartRateEstimateBPM)
    defaults.set(sampleCount, forKey: DefaultsKey.restingHeartRateEstimateSampleCount)
    defaults.set(capturedAt, forKey: DefaultsKey.restingHeartRateEstimateUpdatedAt)
    defaults.set(source, forKey: DefaultsKey.restingHeartRateEstimateSource)
  }

  func persistHRVSample(rmssd: Double, rrIntervalCount: Int, sampleCount: Int, source: String, capturedAt: Date) {
    defaults.set(rmssd, forKey: DefaultsKey.liveHRVRMSSD)
    defaults.set(rrIntervalCount, forKey: DefaultsKey.liveHRVRRIntervalCount)
    defaults.set(sampleCount, forKey: DefaultsKey.liveHRVRMSSDSampleCount)
    defaults.set(capturedAt, forKey: DefaultsKey.liveHRVUpdatedAt)
    defaults.set(source, forKey: DefaultsKey.liveHRVSource)
  }

  func persistBatterySample(percent: Int, capturedAt: Date) {
    defaults.set(percent, forKey: DefaultsKey.lastBatteryPercent)
    defaults.set(capturedAt, forKey: DefaultsKey.lastBatteryCapturedAt)
  }

  func persistInferredBatteryChargingUntil(_ date: Date?) {
    if let date {
      defaults.set(date, forKey: DefaultsKey.inferredBatteryChargingUntil)
    } else {
      defaults.removeObject(forKey: DefaultsKey.inferredBatteryChargingUntil)
    }
  }

  func clearRememberedDevice(reason: String, source: String = "ble") {
    let previous = rememberedDeviceDescription
    defaults.removeObject(forKey: DefaultsKey.rememberedDeviceID)
    defaults.removeObject(forKey: DefaultsKey.rememberedDeviceName)
    defaults.removeObject(forKey: DefaultsKey.rememberedDeviceValidated)
    if let rememberedDeviceID {
      whoopCandidateIDs.remove(rememberedDeviceID)
    }
    rememberedDeviceID = nil
    rememberedDeviceName = nil
    rememberedDeviceValidated = false
    autoReconnectTargetID = nil
    autoReconnectInFlight = false
    if activePeripheral == nil {
      activeDeviceIdentifier = nil
      updateActiveDeviceName("WHOOP")
    }
    updateRememberedDeviceDescription()
    updateReconnectState(reason == "manual" ? "forgotten" : "remembered rejected")
    record(source: source, title: "remembered_device.forgotten", body: "reason=\(reason) previous=\(previous)")
  }

  func updateRememberedDeviceDescription() {
    guard let rememberedDeviceID else {
      rememberedDeviceDescription = "none"
      return
    }
    if let rememberedDeviceName, !rememberedDeviceName.isEmpty {
      rememberedDeviceDescription = "\(Self.sanitizedWhoopDisplayName(rememberedDeviceName)) \(rememberedDeviceID.uuidString)"
    } else {
      rememberedDeviceDescription = rememberedDeviceID.uuidString
    }
  }

  func rememberPeripheral(_ peripheral: CBPeripheral, fallbackName: String? = nil, evidence: String? = nil) {
    guard let evidence = evidence ?? whoopIdentityEvidence(for: peripheral, fallbackName: fallbackName) else {
      record(
        level: .warn,
        source: "ble",
        title: "remembered_device.rejected",
        body: "\(peripheral.name ?? fallbackName ?? "unknown") \(peripheral.identifier.uuidString)"
      )
      return
    }
    let name = Self.sanitizedWhoopDisplayName(peripheral.name ?? fallbackName ?? rememberedDeviceName ?? "WHOOP")
    whoopCandidateIDs.insert(peripheral.identifier)
    rememberedDeviceID = peripheral.identifier
    rememberedDeviceName = name
    rememberedDeviceValidated = true
    updateActiveDevice(peripheral, fallbackName: name)
    defaults.set(peripheral.identifier.uuidString, forKey: DefaultsKey.rememberedDeviceID)
    defaults.set(name, forKey: DefaultsKey.rememberedDeviceName)
    defaults.set(true, forKey: DefaultsKey.rememberedDeviceValidated)
    updateRememberedDeviceDescription()
    record(source: "ble", title: "remembered_device.saved", body: "\(rememberedDeviceDescription) evidence=\(evidence)")
  }

  func connect(_ peripheral: CBPeripheral, reason: String) {
    guard let central, central.state == .poweredOn else {
      updateConnectionState("bluetooth unavailable")
      updateReconnectState("blocked")
      record(level: .warn, source: "ble", title: "connect.blocked", body: "reason=\(reason) bluetooth unavailable")
      return
    }
    let fallbackName = discoveredName(for: peripheral.identifier)
    guard let evidence = whoopIdentityEvidence(for: peripheral, fallbackName: fallbackName) else {
      updateConnectionState("not a WHOOP device")
      updateReconnectState("blocked")
      rejectNonWhoopPeripheral(peripheral, reason: "connect_without_whoop_evidence", fallbackName: fallbackName)
      return
    }
    if activePeripheral?.identifier == peripheral.identifier,
       connectionState == "connecting" || connectionState == "discovering" || connectionState == "ready" {
      record(level: .debug, source: "ble", title: "connect.skipped", body: "already \(connectionState)")
      return
    }
    whoopCandidateIDs.insert(peripheral.identifier)
    resetLiveDeviceFieldsIfNeeded(for: peripheral)
    clientHelloSentForCurrentConnection = false
    updateActiveDevice(peripheral, fallbackName: fallbackName)
    activePeripheral = peripheral
    peripheral.delegate = self
    updateConnectionState("connecting")
    updateReconnectState(reason.hasPrefix("auto") || reason == "restore" ? "connecting" : reconnectState)
    record(source: "ble", title: "connect.started", body: "reason=\(reason) evidence=\(evidence) \(peripheral.name ?? fallbackName ?? rememberedDeviceName ?? "WHOOP") \(peripheral.identifier.uuidString)")
    pendingConnectionReason = reason
    central.connect(
      peripheral,
      options: [
        CBConnectPeripheralOptionNotifyOnConnectionKey: true,
        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
      ]
    )
  }

  /// A "zombie" connection: iOS reports the peripheral as connected (often after
  /// background state-restoration) but its characteristic handles are dead, so
  /// every command write fails with "device is not connected" / "the handle is
  /// invalid". The app would otherwise hammer the dead handles forever. Detect
  /// these and recover.
  func isDeadLinkWriteError(_ error: Error) -> Bool {
    let ns = error as NSError
    if ns.domain == CBErrorDomain {
      // CoreBluetooth-domain write errors mean the link itself is gone.
      return true
    }
    let d = error.localizedDescription.lowercased()
    return d.contains("not connected") || d.contains("handle is invalid")
      || d.contains("invalid handle")
  }

  /// Tear down a dead link and let the normal disconnect path reconnect cleanly,
  /// re-running the GEN4 enable on a fresh connection. Throttled so a burst of
  /// failed writes triggers exactly one recovery.
  /// One-shot watchdog armed at every connect: the existing 60 s stall watchdog
  /// only guards the "ready" state, so a link that dies BEFORE ready (silent
  /// write failures during bond/enable) previously hung forever as "connected".
  /// If no data frame lands within the grace window, force a fresh reconnect.
  func armFirstDataWatchdog(graceSeconds: TimeInterval = 35) {
    firstDataWatchdogTimer?.invalidate()
    firstDataWatchdogTimer = Timer.scheduledTimer(withTimeInterval: graceSeconds, repeats: false) { [weak self] _ in
      guard let self,
            self.connectionState != "disconnected",
            let connectedAt = self.connectedAt,
            self.lastDataFrameAt < connectedAt else {
        return
      }
      self.record(level: .warn, source: "ble", title: "connection.firstdata.timeout",
                  body: "state=\(self.connectionState), no data \(Int(graceSeconds))s after connect — forcing reconnect")
      self.recoverFromDeadLink(reason: "no first data within \(Int(graceSeconds))s")
    }
  }

  func recoverFromDeadLink(reason: String) {
    guard Date().timeIntervalSince(lastDeadLinkRecovery) > 10 else { return }
    lastDeadLinkRecovery = Date()
    record(level: .warn, source: "ble", title: "connection.recover",
           body: "dead link (\(reason)) — tearing down for a fresh reconnect")
    // Clear stale per-connection GEN4 state so the enable + history pull re-run.
    gen4StartedPulseStream = false
    gen4StartedHistoricalBackfill = false
    gen4HistoryDeadline = nil
    gen4ReEnableTimer?.invalidate()
    gen4ReEnableTimer = nil
    // Cancel the zombie connection. didDisconnectPeripheral fires the normal
    // auto-reconnect, which rediscovers services with valid handles.
    if let peripheral = activePeripheral, let central {
      central.cancelPeripheralConnection(peripheral)
    }
  }

  func attemptAutomaticReconnect(reason: String) {
    guard let central, central.state == .poweredOn else {
      updateReconnectState("waiting for bluetooth")
      return
    }
    guard activePeripheral == nil else {
      updateReconnectState("already connected")
      return
    }
    guard !autoReconnectInFlight else {
      record(level: .debug, source: "ble", title: "reconnect.skipped", body: "already in flight")
      return
    }

    if let rememberedDeviceID {
      if !rememberedDeviceValidated,
         let rememberedDeviceName,
         !isWhoopName(rememberedDeviceName) {
        clearRememberedDevice(reason: "legacy_name_mismatch")
        updateReconnectState("no remembered device")
        return
      }
      updateReconnectState("retrieving remembered")
      autoReconnectInFlight = true
      let retrieved = central.retrievePeripherals(withIdentifiers: [rememberedDeviceID])
      if let peripheral = retrieved.first {
        peripherals[peripheral.identifier] = peripheral
        if whoopIdentityEvidence(for: peripheral) != nil {
          selectedDeviceID = peripheral.identifier
          let connectReason = prioritizeLiveCaptureOnReady
            ? "auto_live_capture_remembered"
            : "auto.\(reason).remembered"
          connect(peripheral, reason: connectReason)
        } else if let name = peripheral.name, !isWhoopName(name) {
          autoReconnectInFlight = false
          updateReconnectState("remembered was not WHOOP")
          rejectNonWhoopPeripheral(peripheral, reason: "remembered_name_mismatch")
        } else {
          autoReconnectTargetID = rememberedDeviceID
          updateReconnectState("scanning for remembered WHOOP")
          record(source: "ble", title: "reconnect.remembered_unverified", body: rememberedDeviceID.uuidString)
          startScan(reason: "auto_reconnect_unverified", clearDiscovered: false)
        }
      } else {
        autoReconnectTargetID = rememberedDeviceID
        updateReconnectState("scanning for remembered")
        record(source: "ble", title: "reconnect.scan_fallback", body: rememberedDeviceID.uuidString)
        startScan(reason: "auto_reconnect", clearDiscovered: false)
      }
      return
    }

    if prioritizeLiveCaptureOnReady {
      beginAutoPhysiologyDiscovery(reason: reason)
      return
    }
    updateReconnectState("no remembered device")
  }

  func beginAutoPhysiologyDiscovery(reason: String) {
    guard central?.state == .poweredOn else {
      updateReconnectState("waiting for bluetooth")
      return
    }
    guard activePeripheral == nil else {
      updateReconnectState("already connected")
      return
    }
    guard !autoConnectForPhysiologyCapture else {
      record(level: .debug, source: "ble.sensor", title: "physiology_capture.scan.skipped", body: "already scanning")
      return
    }
    autoConnectForPhysiologyCapture = true
    updateReconnectState("scanning for WHOOP physiology")
    record(source: "ble.sensor", title: "physiology_capture.scan.started", body: "reason=\(reason)")
    startScan(reason: "auto_physiology_capture", clearDiscovered: false)
  }

  func notificationCandidate(_ characteristic: CBCharacteristic) -> Bool {
    notificationCharacteristicIDs.contains(characteristic.uuid)
      || characteristic.uuid == standardHeartRateMeasurementID
      || characteristic.uuid == batteryLevelCharacteristicID
      || characteristic.uuid == batteryLevelStatusCharacteristicID
  }

  func debugMenuCandidate(_ characteristic: CBCharacteristic) -> Bool {
    let uuid = characteristic.uuid.uuidString.lowercased()
    return uuid.hasPrefix("fd4b0007") || uuid.hasPrefix("61080007")
  }

  func standardReadableCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
    characteristic.uuid == batteryLevelCharacteristicID
      || characteristic.uuid == batteryLevelStatusCharacteristicID
      || characteristic.uuid == modelNumberCharacteristicID
      || characteristic.uuid == firmwareRevisionCharacteristicID
      || characteristic.uuid == hardwareRevisionCharacteristicID
      || characteristic.uuid == softwareRevisionCharacteristicID
      || characteristic.uuid == manufacturerNameCharacteristicID
  }

  func readStandardValueIfPossible(
    _ peripheral: CBPeripheral,
    _ characteristic: CBCharacteristic,
    reason: String = "discovery"
  ) {
    guard standardReadableCharacteristic(characteristic) else {
      return
    }
    guard characteristic.properties.contains(.read) else {
      record(
        level: .debug,
        source: "ble",
        title: "metadata.read.skipped",
        body: "\(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
      )
      return
    }
    peripheral.readValue(for: characteristic)
    record(source: "ble", title: "metadata.read.requested", body: "\(characteristic.uuid.uuidString) reason=\(reason)")
  }

  func subscribeIfPossible(_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
    guard notificationCandidate(characteristic) else {
      return
    }
    guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
      record(
        level: .warn,
        source: "ble",
        title: "notify.blocked",
        body: "\(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
      )
      return
    }
    peripheral.setNotifyValue(true, for: characteristic)
    record(source: "ble", title: "notify.requested", body: "\(characteristic.uuid.uuidString)")
    if debugMenuCandidate(characteristic) {
      debugMenuCharacteristic = characteristic
      record(
        source: "ble.debug_menu",
        title: "debug_menu.characteristic.subscribed",
        body: "\(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
      )
      scheduleDebugSkinTemperatureCommandIfNeeded(reason: "notify_subscribe")
    }
  }

  func processCachedServicesIfAvailable(_ peripheral: CBPeripheral, reason: String) {
    guard let services = peripheral.services, !services.isEmpty else {
      return
    }
    record(source: "ble", title: "gatt.services.cached", body: "\(reason) \(uuidList(services.map(\.uuid)))")
    if services.contains(where: { isWhoopService($0.uuid) }) {
      whoopCandidateIDs.insert(peripheral.identifier)
    }
    for service in services {
      if let characteristics = service.characteristics, !characteristics.isEmpty {
        processDiscoveredCharacteristics(characteristics, for: service, peripheral: peripheral, cached: true)
      } else {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }

  func processDiscoveredCharacteristics(
    _ characteristics: [CBCharacteristic],
    for service: CBService,
    peripheral: CBPeripheral,
    cached: Bool
  ) {
    for characteristic in characteristics {
      if shouldUseCommandCharacteristic(characteristic) {
        commandCharacteristic = characteristic
        record(
          source: "ble",
          title: cached ? "command_characteristic.cached" : "command_characteristic.discovered",
          body: "\(service.uuid.uuidString) \(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
      } else if commandCharacteristicIDs.contains(characteristic.uuid) {
        record(
          level: .debug,
          source: "ble",
          title: "command_characteristic.ignored",
          body: "\(service.uuid.uuidString) \(characteristic.uuid.uuidString) keeping=\(commandCharacteristic?.uuid.uuidString ?? "none")"
        )
      }
      if debugMenuCandidate(characteristic) {
        debugMenuCharacteristic = characteristic
        record(
          source: "ble.debug_menu",
          title: cached ? "debug_menu.characteristic.cached" : "debug_menu.characteristic.discovered",
          body: "\(service.uuid.uuidString) \(characteristic.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
        scheduleDebugSkinTemperatureCommandIfNeeded(reason: cached ? "cached_gatt" : "gatt_discovery")
      }
      if characteristic.uuid == batteryLevelCharacteristicID {
        batteryLevelCharacteristic = characteristic
        record(
          source: "ble.metadata",
          title: cached ? "battery_characteristic.cached" : "battery_characteristic.discovered",
          body: "\(service.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
      }
      if characteristic.uuid == batteryLevelStatusCharacteristicID {
        batteryLevelStatusCharacteristic = characteristic
        record(
          source: "ble.metadata",
          title: cached ? "battery_status_characteristic.cached" : "battery_status_characteristic.discovered",
          body: "\(service.uuid.uuidString) properties=\(propertyNames(characteristic.properties))"
        )
      }
      subscribeIfPossible(peripheral, characteristic)
      readStandardValueIfPossible(peripheral, characteristic)
    }

    if commandCharacteristic != nil {
      updateConnectionState("ready")
      sendClientHelloIfNeeded(reason: cached ? "cached_gatt" : "gatt_discovery")
      scheduleDebugSkinTemperatureCommandIfNeeded(reason: cached ? "cached_ready" : "ready")
      scheduleAutomaticHistoricalSyncIfNeeded()
      scheduleAutomaticPhysiologyCaptureIfNeeded()
      scheduleGen4PulseStreamIfNeeded()
    } else if connectionState == "discovering" {
      updateConnectionState("connected")
    }
  }

  func scheduleAutomaticPhysiologyCaptureIfNeeded() {
    guard autoStartPhysiologyCaptureOnReady,
          !autoStartedPhysiologyCapture,
          connectionState == "ready",
          activePeripheral != nil,
          commandCharacteristic != nil,
          supportsV5SensorCommands else {
      return
    }

    autoStartedPhysiologyCapture = true
    record(source: "ble.sensor", title: "physiology_capture.auto_scheduled")
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self else {
        return
      }
      self.record(source: "ble.sensor", title: "physiology_capture.auto_start")
      self.startPhysiologySignalCapture()
    }
  }

  func scheduleAutomaticHistoricalSyncIfNeeded() {
    guard let reason = pendingAutomaticHistoricalSyncReason,
          autoHistoricalSyncOnReady,
          connectionState == "ready",
          activePeripheral != nil,
          commandCharacteristic != nil,
          supportsV5HistoricalSync,
          !isHistoricalSyncing else {
      return
    }

    readySyncWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else {
        return
      }
      guard self.pendingAutomaticHistoricalSyncReason == reason else {
        return
      }
      self.pendingAutomaticHistoricalSyncReason = nil
      self.beginHistoricalSync(trigger: reason, automatic: true)
    }
    readySyncWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    record(source: "ble.sync", title: "historical_sync.scheduled", body: reason)
  }

}

// WHOOP 4.0 (GEN4) raw-pulse stream support.
//
// The app's normal sensor-command path (`writeSensorStreamCommand`) builds V5
// frames — 8-byte header, CRC16 — which only the WHOOP 5.0 understands. The 4.0
// uses a different framing (4-byte header: [0xAA][len u16 LE][crc8], body
// [type=35][seq][cmd][payload], trailing CRC32 LE) and silently ignores V5
// frames. That is why the app has only ever seen standard-characteristic HR +
// battery on a 4.0, never its optical/PPG pulse stream.
//
// This module sends the proven GEN4 enable sequence (validated on the owner's
// band from macOS) so the 4.0 streams its raw optical frames (type 43, sub 0):
//   GET_BATTERY(26) to bond → TOGGLE_REALTIME_HR(3) → SEND_R10_R11_REALTIME(63)
//   → SET_RESEARCH_PACKET(131) x3 with ascii payloads enable_r19_packets /
//   sigproc_10_sec_dp / sigproc_pdaf. Re-sent every 60 s (the band lets the
//   stream lapse otherwise). The builder here is byte-for-byte identical to the
//   reference Python implementation (verified against captured command frames).
extension GooseBLEClient {

  // MARK: GEN4 frame builder (verified byte-identical to the reference encoder)

  static func crc8Gen4(_ bytes: [UInt8]) -> UInt8 {
    var c: UInt8 = 0
    for b in bytes {
      c ^= b
      for _ in 0..<8 {
        c = (c & 0x80) != 0 ? (c << 1) ^ 0x07 : (c << 1)
      }
    }
    return c
  }

  static func crc32Gen4(_ bytes: [UInt8]) -> UInt32 {
    var crc = UInt32(0xffff_ffff)
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc & 1 == 1) ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1
      }
    }
    return ~crc
  }

  static func buildGen4CommandFrame(sequence: UInt8, command: UInt8, payload: [UInt8]) -> [UInt8] {
    let body: [UInt8] = [35, sequence, command] + payload
    let declaredLength = UInt16(body.count + 4)
    let lenBytes: [UInt8] = [UInt8(declaredLength & 0xff), UInt8((declaredLength >> 8) & 0xff)]
    var frame: [UInt8] = [0xAA]
    frame.append(contentsOf: lenBytes)
    frame.append(crc8Gen4(lenBytes))
    frame.append(contentsOf: body)
    let crc = crc32Gen4(body)
    frame.append(UInt8(crc & 0xff))
    frame.append(UInt8((crc >> 8) & 0xff))
    frame.append(UInt8((crc >> 16) & 0xff))
    frame.append(UInt8((crc >> 24) & 0xff))
    return frame
  }

  // MARK: Activation

  /// True for the WHOOP 4.0 command characteristic (61080002); the V5 path uses fd4b0002.
  func isGen4CommandCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
    characteristic.uuid.uuidString.lowercased().hasPrefix("61080002")
  }

  /// True once connected to a WHOOP 4.0. Used to put the app in "4.0 quiet mode":
  /// the 5.0-oriented subsystems (overnight-guard resume, V5 physiology capture +
  /// its 8 s retries, historical/range polling, Rust frame parsing) all fight the
  /// 4.0 link and cause it to time out — so they're suppressed, leaving only the
  /// GEN4 pulse stream, which is what kept the macOS capture stable.
  var isGen4Band: Bool {
    commandCharacteristic.map(isGen4CommandCharacteristic) == true
  }

  /// Defaults on; set UserDefaults "gen4PulseStream" = false to disable.
  var gen4PulseStreamEnabled: Bool {
    UserDefaults.standard.object(forKey: "gen4PulseStream") as? Bool ?? true
  }

  /// Called when a connection becomes ready (sibling of the V5 auto-capture).
  /// No-op unless this is a 4.0 band and the feature is enabled.
  func scheduleGen4PulseStreamIfNeeded() {
    guard gen4PulseStreamEnabled,
          connectionState == "ready",
          activePeripheral != nil,
          let characteristic = commandCharacteristic,
          isGen4CommandCharacteristic(characteristic) else {
      return
    }
    // Fire ONCE per connection. processDiscoveredCharacteristics() (our caller)
    // runs once per GATT service — 4× for the WHOOP — so without this guard the
    // whole enable sequence was sent 4× on every connect, a write-storm that
    // overwhelmed the 4.0 link and timed it out. Reset on disconnect.
    guard !gen4StartedPulseStream else { return }
    gen4StartedPulseStream = true
    record(source: "ble.gen4", title: "gen4.pulse.scheduled",
           body: "4.0 band detected — enabling raw optical pulse stream")
    startGen4PulseStreamSequence(reason: "ready", bond: true)
    gen4ReEnableTimer?.invalidate()
    gen4ReEnableTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      guard let self,
            self.connectionState == "ready",
            let ch = self.commandCharacteristic,
            self.isGen4CommandCharacteristic(ch) else {
        return
      }
      // Stall watchdog: if we're "ready" but no frame has arrived for >70 s, the
      // link is silently dead — re-enabling won't help, so force a reconnect.
      let stale = Date().timeIntervalSince(self.lastDataFrameAt)
      if stale > 70 {
        self.record(level: .warn, source: "ble.gen4", title: "gen4.stall.detected",
                    body: "no data for \(Int(stale))s while ready — forcing reconnect")
        self.recoverFromDeadLink(reason: "silent stall \(Int(stale))s")
      } else {
        self.startGen4PulseStreamSequence(reason: "re_enable", bond: false)
        // Periodic history re-pull. The backfill used to fire only on bond, so a
        // long-lived background link (which this app deliberately maintains)
        // never pulled again and buffered history stopped reaching the VPS.
        // Overlapping pulls are safe: the server dedupes frames by sha256.
        if Date().timeIntervalSince(self.gen4LastHistoryPullAt) >= Self.gen4HistoryPullInterval {
          self.gen4StartedHistoricalBackfill = false
          self.requestGen4HistoricalBackfillIfNeeded()
        }
      }
    }
  }

  /// Called when the app returns to the foreground: if we appear connected but
  /// data has gone stale (a silent stall iOS didn't surface), recover now rather
  /// than making the user wait for the watchdog tick. If nothing's connected,
  /// kick a reconnect. Cheap to call; no-op when data is flowing.
  func healConnectionIfStale(reason: String) {
    let believedLive = ["ready", "connected", "discovering", "bonding"].contains(connectionState)
    let freshness = max(lastDataFrameAt, connectedAt ?? .distantPast)
    if believedLive,
       Date().timeIntervalSince(freshness) > 30 {
      record(level: .warn, source: "ble", title: "connection.heal",
             body: "stale on \(reason) — recovering")
      recoverFromDeadLink(reason: "stale on \(reason)")
    } else if activePeripheral == nil {
      attemptAutomaticReconnect(reason: "heal_\(reason)")
    }
  }

  private func gen4ResearchPayload(_ token: String) -> [UInt8] {
    Array(token.utf8) + [0]
  }

  /// Send the enable sequence with the proven inter-command timing.
  func startGen4PulseStreamSequence(reason: String, bond: Bool) {
    record(source: "ble.gen4", title: "gen4.pulse.enable.start", body: "reason=\(reason) bond=\(bond)")
    // Always read battery via GET_BATTERY (the reliable uint16/10 source); this
    // also serves as the bond write on connect, and refreshes battery every
    // re-enable (~60 s). On the initial bond, wait for it to settle first.
    writeGen4Command(26, payload: [0x00], label: bond ? "GET_BATTERY(bond)" : "GET_BATTERY(refresh)")
    let base = bond ? 1.2 : 0.3
    let steps: [(UInt8, [UInt8], String)] = [
      (3, [0x01], "TOGGLE_REALTIME_HR"),
      (63, [0x01], "SEND_R10_R11_REALTIME"),
      (131, gen4ResearchPayload("enable_r19_packets"), "SET_RESEARCH_PACKET:r19"),
      (131, gen4ResearchPayload("sigproc_10_sec_dp"), "SET_RESEARCH_PACKET:dp"),
      (131, gen4ResearchPayload("sigproc_pdaf"), "SET_RESEARCH_PACKET:pdaf"),
    ]
    for (index, step) in steps.enumerated() {
      let delay = base + Double(index) * 0.25
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.writeGen4Command(step.0, payload: step.1, label: step.2)
      }
    }
    // After the initial bond enable settles, pull the band's buffered HR history
    // once (backfills the gap since the last sync). Only on bond (first connect),
    // never on the 60 s re-enable.
    if bond {
      let after = base + Double(steps.count) * 0.25 + 1.0
      DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
        self?.requestGen4HistoricalBackfillIfNeeded()
      }
    }
  }

  /// One-shot request for the band's onboard HR history. GET_DATA_RANGE(34) asks
  /// what's buffered; SEND_HISTORICAL_DATA(22) starts the stream of type-47
  /// frames, which we forward to the VPS (stamped at their own past time). The
  /// band paginates: each type-47 frame is ACKed with HISTORICAL_DATA_RESULT(23)
  /// in gen4ObserveRawNotification to pull the next chunk. UNVERIFIED against the
  /// 4.0 firmware — logged at .warn so we can confirm it live via the log stream.
  func requestGen4HistoricalBackfillIfNeeded() {
    guard connectionState == "ready",
          let ch = commandCharacteristic, isGen4CommandCharacteristic(ch) else { return }
    guard !gen4StartedHistoricalBackfill else { return }
    gen4StartedHistoricalBackfill = true
    gen4LastHistoryPullAt = Date()
    gen4HistoryDeadline = Date().addingTimeInterval(90)   // bound the ack loop
    record(level: .warn, source: "ble.gen4", title: "gen4.history.request",
           body: "pulling buffered HR history (GET_DATA_RANGE -> SEND_HISTORICAL_DATA), 90s window")
    writeGen4Command(34, payload: [], label: "GET_DATA_RANGE")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      // Payload MUST be [0x00]: an empty payload is answered with zero frames
      // (reference-verified on a real WHOOP 4.0 — the cause of our forever-empty
      // backfills, logged as historical_range.success_missing).
      self?.writeGen4Command(22, payload: [0x00], label: "SEND_HISTORICAL_DATA")
    }
  }

  private func writeGen4Command(_ command: UInt8, payload: [UInt8], label: String) {
    guard let peripheral = activePeripheral,
          let characteristic = commandCharacteristic,
          let writeType = writeType(for: characteristic) else {
      record(level: .warn, source: "ble.gen4", title: "gen4.command.blocked", body: label)
      return
    }
    let sequence = nextSensorCommandSequence
    nextSensorCommandSequence = nextSensorCommandSequence == UInt8.max ? 180 : nextSensorCommandSequence + 1
    let frame = Data(Self.buildGen4CommandFrame(sequence: sequence, command: command, payload: payload))
    peripheral.writeValue(frame, for: characteristic, type: writeType)
    record(source: "ble.gen4", title: "gen4.command.sent",
           body: "\(label) cmd=\(command) seq=\(sequence) frame=\(frame.hexString)")
  }

  // MARK: Probe — count optical/HR frames so the device test is observable

  /// Tap every raw notification: count the first fragment of each GEN4 frame
  /// (begins 0xAA; type at byte 4, sub at byte 6) so we can confirm the band is
  /// actually streaming the optical pulse. Logged (throttled) at .warn so it is
  /// always visible. Thread-safe; safe to call off the main thread.
  func gen4ObserveRawNotification(_ value: Data, characteristicUUID: String) {
    let uuid = characteristicUUID.lowercased()
    guard uuid.hasPrefix("61080005") || uuid.hasPrefix("61080003") || uuid.hasPrefix("61080004") else {
      return
    }
    lastDataFrameAt = Date()   // stall watchdog: any notification = data is flowing
    // Forward every fragment to the cloud reassembler (powers the live /pulse).
    WhoopCloudForwarder.shared.ingestRawFrame(value, characteristicUUID: characteristicUUID)
    guard value.count >= 7 else { return }
    let bytes = [UInt8](value)
    guard bytes[0] == 0xAA else { return }   // only a frame's first fragment
    let type = bytes[4]
    let sub = bytes[6]

    // GET_BATTERY(26) response = type-36 command response; battery is uint16/10
    // at byte 9 (validated reliable, unlike the bouncing 0x2A19 byte).
    if type == 36 && bytes[6] == 26 && bytes.count >= 11 {
      let raw = Int(bytes[9]) | (Int(bytes[10]) << 8)
      let pct = Int((Double(raw) / 10.0).rounded())
      DispatchQueue.main.async { [weak self] in
        self?.record(source: "ble.metadata", title: "battery.gen4_cmd.raw",
                     body: "raw=\(raw) -> \(pct)% frame=\(value.hexString.prefix(28))")
        self?.applyBatteryLevel(pct, capturedAt: Date(), sourceTitle: "battery.gen4_cmd")
      }
    }

    // type-47 HISTORICAL_DATA: the band is streaming buffered history. ACK with
    // HISTORICAL_DATA_RESULT(23) to pull the next chunk (throttled so a burst of
    // frames doesn't flood the command channel). The frames themselves are
    // forwarded to the VPS by ingestRawFrame above.
    if type == 47 {
      gen4ProbeLock.lock()
      let now = Date()
      // ACK only inside the bounded backfill window, throttled to ≤2/sec, so a
      // long historical stream can't pressure the command channel into a timeout.
      let withinWindow = (gen4HistoryDeadline.map { now < $0 }) ?? false
      let due = withinWindow && now.timeIntervalSince(gen4LastHistoryAck) >= 0.5
      if due { gen4LastHistoryAck = now }
      gen4ProbeLock.unlock()
      if due {
        DispatchQueue.main.async { [weak self] in
          self?.writeGen4Command(23, payload: [1, 0, 0, 0, 0, 0, 0, 0, 0],
                                 label: "HISTORICAL_DATA_RESULT(ack)")
        }
      }
    }

    // type-48 EVENT: event id is frame[6]. Decode charging directly here — the
    // authoritative signal the VPS uses — instead of relying on the Rust parser,
    // which does not surface these events on the 4.0 path.
    if type == 48 {
      let eventID = Int(bytes[6])
      var charging: Bool? = nil
      var detail = "event=\(eventID)"
      switch eventID {
      case 5, 7, 21: charging = true    // EXTERNAL_5V_ON, CHARGING_ON, PACK_CONNECTED
      case 6, 8, 22: charging = false   // EXTERNAL_5V_OFF, CHARGING_OFF, PACK_REMOVED
      case 3, 63:
        // BATTERY_LEVEL / EXTENDED_BATTERY_INFORMATION carry a signed battery
        // current as int16-LE at offset 20 (derived + validated on this band):
        // positive = charging, negative = discharging. This is our reliable
        // "not charging" signal, since the band drops the CHARGING_OFF event.
        // Deadband ±400 ignores the ~0 current of a topped-off full battery.
        if bytes.count >= 22 {
          let cur = Int(Int16(bitPattern: UInt16(bytes[20]) | (UInt16(bytes[21]) << 8)))
          detail = "event=\(eventID) current=\(cur)"
          if cur > 400 { charging = true } else if cur < -400 { charging = false }
        }
      default: break
      }
      if let charging {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.batteryIsCharging = charging
          self.batteryPowerStatus = charging ? "Charging" : "Not charging"
          self.inferredBatteryChargingUntil = nil
          self.persistInferredBatteryChargingUntil(nil)
          self.record(level: .warn, source: "ble.gen4", title: "battery.charging.gen4_event",
                      body: "\(detail) -> charging=\(charging)")
        }
      }
    }

    gen4ProbeLock.lock()
    if type == 43 && sub == 0 {
      gen4OpticalFrameCount += 1
    } else if type == 40 {
      gen4HeartRateFrameCount += 1
    }
    let optical = gen4OpticalFrameCount
    let heartRate = gen4HeartRateFrameCount
    let shouldLog = Date().timeIntervalSince(gen4LastProbeLogAt) >= 5
    if shouldLog {
      gen4LastProbeLogAt = Date()
    }
    gen4ProbeLock.unlock()

    if shouldLog {
      DispatchQueue.main.async { [weak self] in
        self?.record(
          level: .warn,
          source: "ble.gen4",
          title: "gen4.pulse.frames",
          body: "optical(type43)=\(optical) heart_rate(type40)=\(heartRate) — optical>0 means the 4.0 pulse stream is LIVE"
        )
      }
    }
  }
}
