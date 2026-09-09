import CoreBluetooth
import Foundation
import OSLog

extension GooseBLEClient: CBCentralManagerDelegate {
  func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, willRestoreState: dict)
    }) {
      return
    }

    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    record(source: "ble", title: "central.restore_state", body: "peripherals=\(restored.count)")
    guard let peripheral = restored.first else {
      updateReconnectState("restore empty")
      return
    }
    guard let evidence = whoopIdentityEvidence(for: peripheral) else {
      updateReconnectState("restore ignored non-WHOOP")
      rejectNonWhoopPeripheral(peripheral, reason: "restore_without_whoop_evidence", disconnect: true)
      return
    }
    whoopCandidateIDs.insert(peripheral.identifier)
    peripherals[peripheral.identifier] = peripheral
    selectedDeviceID = peripheral.identifier
    activePeripheral = peripheral
    peripheral.delegate = self
    rememberPeripheral(peripheral, evidence: evidence)
    if autoHistoricalSyncOnReady && !prioritizeLiveCaptureOnReady {
      pendingAutomaticHistoricalSyncReason = "restore"
    } else {
      pendingAutomaticHistoricalSyncReason = nil
      record(
        source: "ble.sync",
        title: "historical_sync.auto_skipped",
        body: "reason=restore autoHistoricalSync=\(autoHistoricalSyncOnReady) prioritizeLive=\(prioritizeLiveCaptureOnReady)"
      )
    }
    updateReconnectState("restored")
    switch peripheral.state {
    case .connected:
      let now = Date()
      connectedAt = now
      lastSyncAt = now
      updateConnectionState("discovering")
      peripheral.discoverServices(serviceDiscoveryIDs)
      processCachedServicesIfAvailable(peripheral, reason: "restore.connected")
      // CLAUDE.md rule: never trust restored connection state without a live
      // write. If the restored link is a ghost, no data frame will arrive and
      // the 60 s re-enable tick (gen4ReEnableTimer) stalls out — so schedule a
      // bounded verification: if nothing arrives within 25 s, tear the link
      // down and do a real reconnect.
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
        guard let self,
              self.connectionState == "ready" || self.connectionState == "discovering",
              self.activePeripheral?.identifier == peripheral.identifier,
              Date().timeIntervalSince(self.lastDataFrameAt) > 25 else {
          return
        }
        self.record(level: .warn, source: "ble", title: "restore.ghost_link",
                    body: "restored 'connected' but no data for 25s — forcing real reconnect")
        self.recoverFromDeadLink(reason: "ghost link after state restoration")
      }
    case .connecting:
      updateConnectionState("connecting")
    case .disconnected, .disconnecting:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    @unknown default:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManagerDidUpdateState(central)
    }) {
      return
    }

    updateBluetoothState()
    if central.state == .poweredOn {
      // Reconnect on every power-on, not just the first: a Bluetooth toggle or
      // bluetoothd reset invalidates peripherals without firing
      // didDisconnectPeripheral, and the once-only gate left the app stranded
      // until relaunch. attemptAutomaticReconnect self-guards when a live or
      // in-flight connection exists (e.g. right after state restoration).
      let reason = startupReconnectAttempted ? "power_on" : "startup"
      startupReconnectAttempted = true
      attemptAutomaticReconnect(reason: reason)
    } else {
      isScanning = false
      if isHistoricalSyncing {
        failHistoricalSync("Bluetooth became unavailable during historical sync. State: \(bluetoothState).")
      }
      if pendingAlarmCommand != nil {
        failAlarmCommand("Bluetooth became unavailable during alarm command. State: \(bluetoothState).")
      }
      if pendingClockCommand != nil {
        failClockCommand("Bluetooth became unavailable during clock command. State: \(bluetoothState).")
      }
      if !pendingDebugCommands.isEmpty {
        failAllDebugCommands("Bluetooth became unavailable during debug command. State: \(bluetoothState).")
      }
      // iOS drops the link WITHOUT didDisconnectPeripheral when Bluetooth
      // powers off/resets — run the same per-connection teardown so the
      // power-on reconnect never sees a stale activePeripheral.
      autoReconnectInFlight = false
      autoConnectForPhysiologyCapture = false
      autoStartedPhysiologyCapture = false
      gen4StartedPulseStream = false
      gen4StartedHistoricalBackfill = false
      gen4HistoryDeadline = nil
      gen4ReEnableTimer?.invalidate()
      gen4ReEnableTimer = nil
      WhoopCloudForwarder.shared.resetFrameReassembly()
      readySyncWorkItem?.cancel()
      pendingConnectionReason = nil
      activePeripheral = nil
      commandCharacteristic = nil
      batteryLevelCharacteristic = nil
      batteryLevelStatusCharacteristic = nil
      clientHelloSentForCurrentConnection = false
      updateConnectionState("disconnected")
      updateReconnectState("waiting for bluetooth")
      connectedAt = nil
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }) {
      return
    }

    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let advertisedServices = advertisedServiceUUIDs(from: advertisementData)
    guard let evidence = whoopIdentityEvidence(
      for: peripheral,
      fallbackName: advertisedName,
      advertisedServices: advertisedServices,
      allowRememberedValidation: false
    ) else {
      rejectNonWhoopPeripheral(peripheral, reason: "scan_without_whoop_evidence", fallbackName: advertisedName)
      return
    }

    whoopCandidateIDs.insert(peripheral.identifier)
    peripherals[peripheral.identifier] = peripheral
    let name = Self.sanitizedWhoopDisplayName(peripheral.name ?? advertisedName ?? "WHOOP strap")
    let serviceUUIDs = advertisedServices
      .map(\.uuidString)
      .joined(separator: ",")
    let device = GooseDiscoveredDevice(
      id: peripheral.identifier,
      name: name,
      rssi: RSSI.intValue
    )

    discoveredDevices.removeAll { $0.id == device.id }
    discoveredDevices.append(device)
    discoveredDevices.sort { $0.rssi > $1.rssi }
    selectedDeviceID = selectedDeviceID ?? device.id
    record(
      source: "ble",
      title: "device.discovered",
      body: "\(name) id=\(device.id.uuidString) rssi=\(device.rssi) services=\(serviceUUIDs) evidence=\(evidence)"
    )

    if autoConnectForPhysiologyCapture && activePeripheral == nil {
      record(source: "ble.sensor", title: "physiology_capture.scan.match", body: "\(peripheral.identifier.uuidString) evidence=\(evidence)")
      autoConnectForPhysiologyCapture = false
      stopScan(reason: "auto_physiology_capture_match")
      connect(peripheral, reason: "auto_physiology_scan")
      return
    }

    if autoReconnectTargetID == peripheral.identifier || shouldAutoConnectDiscoveredWhoop(peripheral) {
      record(source: "ble", title: "reconnect.scan_match", body: "\(peripheral.identifier.uuidString) evidence=\(evidence)")
      autoReconnectTargetID = nil
      stopScan(reason: "auto_reconnect_whoop_match")
      let connectReason = autoStartPhysiologyCaptureOnReady
        ? "auto_physiology_scan_remembered"
        : "auto.scan"
      connect(peripheral, reason: connectReason)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didConnect: peripheral)
    }) {
      return
    }

    let fallbackName = discoveredDevices.first { $0.id == peripheral.identifier }?.name
    guard let evidence = whoopIdentityEvidence(for: peripheral, fallbackName: fallbackName) else {
      pendingConnectionReason = nil
      autoReconnectInFlight = false
      autoReconnectTargetID = nil
      rejectNonWhoopPeripheral(peripheral, reason: "connected_without_whoop_evidence", fallbackName: fallbackName, disconnect: true)
      return
    }

    whoopCandidateIDs.insert(peripheral.identifier)
    activePeripheral = peripheral
    peripheral.delegate = self
    clientHelloSentForCurrentConnection = false
    autoReconnectInFlight = false
    autoReconnectTargetID = nil
    connectFailureCount = 0
    connectRetryWorkItem?.cancel()
    connectRetryWorkItem = nil
    deadLinkFallbackWorkItem?.cancel()
    deadLinkFallbackWorkItem = nil
    let reason = pendingConnectionReason ?? "unknown"
    pendingConnectionReason = nil
    if !prioritizeLiveCaptureOnReady,
       reason == "manual" || reason.hasPrefix("auto.") || reason == "restore" {
      if autoHistoricalSyncOnReady {
        pendingAutomaticHistoricalSyncReason = reason
      } else {
        pendingAutomaticHistoricalSyncReason = nil
        record(
          source: "ble.sync",
          title: "historical_sync.auto_skipped",
          body: "reason=\(reason) autoHistoricalSync=false"
        )
      }
    }
    rememberPeripheral(
      peripheral,
      fallbackName: fallbackName,
      evidence: evidence
    )
    let now = Date()
    connectedAt = now
    lastSyncAt = now
    updateConnectionState("discovering")
    updateReconnectState("connected")
    record(source: "ble", title: "connect.succeeded", body: "\(peripheral.name ?? fallbackName ?? "WHOOP") \(peripheral.identifier.uuidString) evidence=\(evidence)")
    peripheral.discoverServices(serviceDiscoveryIDs)
    processCachedServicesIfAvailable(peripheral, reason: "connect.\(reason)")
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didFailToConnect: peripheral, error: error)
    }) {
      return
    }

    autoReconnectInFlight = false
    autoConnectForPhysiologyCapture = false
    pendingConnectionReason = nil
    updateConnectionState("connect failed")
    updateReconnectState("connect failed")
    record(level: .error, source: "ble", title: "connect.failed", body: error?.localizedDescription ?? "unknown")
    scheduleConnectRetry(peripheral)
  }

  /// A failed attempt used to end the reconnect machine entirely: overnight the
  /// 23:45:25 "connect failed" was followed by 7.8 h of silence because nothing
  /// ever retried. Every termination now schedules the next attempt with
  /// exponential backoff (5 s doubling, 60 s cap), cleared on a real connect.
  func scheduleConnectRetry(_ peripheral: CBPeripheral) {
    guard rememberedDeviceID == peripheral.identifier || selectedDeviceID == peripheral.identifier else {
      return
    }
    connectRetryWorkItem?.cancel()
    connectFailureCount = min(connectFailureCount + 1, 6)
    let delay = min(5.0 * pow(2.0, Double(connectFailureCount - 1)), 60.0)
    updateReconnectState("retry in \(Int(delay.rounded()))s")
    record(level: .warn, source: "ble", title: "connect.retry_scheduled",
           body: "attempt=\(connectFailureCount) delay=\(Int(delay.rounded()))s")
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.activePeripheral == nil else { return }
      self.record(source: "ble", title: "connect.retry", body: "attempt=\(self.connectFailureCount)")
      self.connect(peripheral, reason: "auto.retry")
    }
    connectRetryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
    }) {
      return
    }

    let shouldReconnect = rememberedDeviceID == peripheral.identifier
    autoReconnectInFlight = false
    autoConnectForPhysiologyCapture = false
    autoStartedPhysiologyCapture = false
    connectRetryWorkItem?.cancel()
    connectRetryWorkItem = nil
    deadLinkFallbackWorkItem?.cancel()
    deadLinkFallbackWorkItem = nil
    gen4StartedPulseStream = false           // re-arm the once-per-connection 4.0 enable
    gen4StartedHistoricalBackfill = false    // re-arm the once-per-connection history pull
    isGen4Backfilling = false                // close any in-flight backfill window
    gen4HistoryDeadline = nil                // close the backfill ack window
    gen4ReEnableTimer?.invalidate()
    gen4ReEnableTimer = nil
    WhoopCloudForwarder.shared.resetFrameReassembly()  // a partial frame must not bridge connections
    readySyncWorkItem?.cancel()
    if isHistoricalSyncing {
      failHistoricalSync("WHOOP disconnected during historical sync. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    if pendingAlarmCommand != nil {
      failAlarmCommand("WHOOP disconnected during alarm command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    if pendingClockCommand != nil {
      failClockCommand("WHOOP disconnected during clock command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    if !pendingDebugCommands.isEmpty {
      failAllDebugCommands("WHOOP disconnected during debug command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    updateConnectionState(error?.localizedDescription ?? "disconnected")
    record(
      level: error == nil ? .info : .warn,
      source: "ble",
      title: "disconnect",
      body: error?.localizedDescription ?? peripheral.identifier.uuidString
    )
    activePeripheral = nil
    commandCharacteristic = nil
    batteryLevelCharacteristic = nil
    batteryLevelStatusCharacteristic = nil
    clientHelloSentForCurrentConnection = false
    connectedAt = nil
    if shouldReconnect {
      let reconnectReason = prioritizeLiveCaptureOnReady ? "auto_live_capture_disconnect" : "auto.disconnect"
      if autoHistoricalSyncOnReady && !prioritizeLiveCaptureOnReady {
        pendingAutomaticHistoricalSyncReason = reconnectReason
      } else {
        pendingAutomaticHistoricalSyncReason = nil
        record(
          source: "ble.sync",
          title: "historical_sync.auto_skipped",
          body: "reason=\(reconnectReason) autoHistoricalSync=\(autoHistoricalSyncOnReady) prioritizeLive=\(prioritizeLiveCaptureOnReady)"
        )
      }
      updateReconnectState("reconnecting after disconnect")
      connect(peripheral, reason: reconnectReason)
    }
  }
}
