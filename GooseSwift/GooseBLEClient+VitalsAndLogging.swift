import CoreBluetooth
import Foundation
import OSLog


extension GooseBLEClient {
  func recordLiveHeartRate(_ bpm: Int, source: String, at date: Date = Date()) {
    guard (20...240).contains(bpm) else {
      record(level: .warn, source: source, title: "heart_rate.rejected", body: "\(bpm) bpm outside expected range")
      return
    }

    realtimeVitalsQueue.async { [weak self] in
      self?.processLiveHeartRate(bpm, source: source, at: date)
    }
  }

  func processLiveHeartRate(_ bpm: Int, source: String, at date: Date) {
    let shouldPublish = lastHeartRatePublishedBPM == nil
      || source != lastHeartRatePublishedSource
      || date.timeIntervalSince(lastHeartRatePublishedAt) >= Self.heartRatePublishInterval
    if shouldPublish {
      lastHeartRatePublishedBPM = bpm
      lastHeartRatePublishedSource = source
      lastHeartRatePublishedAt = date
      bleUIStateAggregator.publishLiveHeartRate(bpm: bpm, source: source, updatedAt: date)
    }

    let shouldLog = lastHeartRateLogAt.map { date.timeIntervalSince($0) >= 10 } ?? true
    if shouldLog || source != lastHeartRateLogSource {
      lastHeartRateLogAt = date
      lastHeartRateLogBPM = bpm
      lastHeartRateLogSource = source
      record(source: source, title: "heart_rate.live", body: "\(bpm) bpm")
    } else {
      lastHeartRateLogBPM = bpm
    }

    let shouldCallback = source != lastHeartRateCallbackSource
      || date.timeIntervalSince(lastHeartRateCallbackAt) >= Self.heartRateCallbackInterval
    if shouldCallback {
      lastHeartRateCallbackAt = date
      lastHeartRateCallbackSource = source
      onLiveHeartRate?(bpm, source, date)
    }

    processRestingHeartRateEstimate(bpm: bpm, source: source, at: date)
  }

  func processRestingHeartRateEstimate(bpm: Int, source: String, at date: Date) {
    restingHeartRateWindowBPM.append(bpm)
    if restingHeartRateWindowBPM.count > Self.restingHeartRateWindowSize {
      restingHeartRateWindowBPM.removeFirst(restingHeartRateWindowBPM.count - Self.restingHeartRateWindowSize)
    }
    guard restingHeartRateWindowBPM.count >= Self.restingHeartRateMinimumSampleCount else {
      return
    }

    let estimate = Self.lowQuartileMeanBPM(from: restingHeartRateWindowBPM)
    guard estimate.isFinite, (20...240).contains(Int(estimate.rounded())) else {
      return
    }

    let shouldPublish = lastRestingHeartRateEstimateBPM == nil
      || date.timeIntervalSince(lastRestingHeartRateEstimatePublishedAt) >= Self.restingHeartRateEstimatePublishInterval
    guard shouldPublish else {
      return
    }

    let sampleCount = restingHeartRateWindowBPM.count
    let estimateSource = "\(source).low_quartile"
    lastRestingHeartRateEstimateBPM = estimate
    lastRestingHeartRateEstimatePublishedAt = date
    bleUIStateAggregator.publishRestingHeartRate(
      bpm: estimate,
      sampleCount: sampleCount,
      source: estimateSource,
      updatedAt: date
    )
    persistRestingHeartRateEstimate(
      bpm: estimate,
      sampleCount: sampleCount,
      source: estimateSource,
      capturedAt: date
    )
  }

  func recordRRIntervals(_ intervalsMS: [Double], source: String, at date: Date = Date()) {
    let validIntervals = intervalsMS.filter { (300.0...2000.0).contains($0) }
    guard !validIntervals.isEmpty else {
      return
    }

    realtimeVitalsQueue.async { [weak self] in
      self?.processRRIntervals(validIntervals, source: source, at: date)
    }
  }

  func processRRIntervals(_ validIntervals: [Double], source: String, at date: Date) {
    rrIntervalWindowMS.append(contentsOf: validIntervals)
    if rrIntervalWindowMS.count > Self.hrvRRIntervalWindowSize {
      rrIntervalWindowMS.removeFirst(rrIntervalWindowMS.count - Self.hrvRRIntervalWindowSize)
    }

    if rrIntervalChunkStartedAt == nil {
      rrIntervalChunkStartedAt = date
    }
    rrIntervalChunkMS.append(contentsOf: validIntervals)
    let chunkAge = rrIntervalChunkStartedAt.map { date.timeIntervalSince($0) } ?? 0
    let shouldFinalizeChunk = rrIntervalChunkMS.count >= Self.hrvRRIntervalChunkSize
      || (rrIntervalChunkMS.count >= Self.hrvMinimumRRIntervalsPerChunk && chunkAge >= Self.hrvChunkMaxAge)
    guard shouldFinalizeChunk,
          let chunkRMSSD = Self.rmssdMS(from: rrIntervalChunkMS) else {
      return
    }

    let chunkRRIntervalCount = rrIntervalChunkMS.count
    rrIntervalChunkMS.removeAll(keepingCapacity: true)
    rrIntervalChunkStartedAt = nil
    onHRVSample?(chunkRMSSD, chunkRRIntervalCount, "\(source).rmssd_chunk", date)
    hrvRMSSDSamples.append((rmssd: chunkRMSSD, rrIntervalCount: chunkRRIntervalCount))
    if hrvRMSSDSamples.count > Self.hrvRMSSDAverageWindowSize {
      hrvRMSSDSamples.removeFirst(hrvRMSSDSamples.count - Self.hrvRMSSDAverageWindowSize)
    }

    let averagedRRIntervalCount = hrvRMSSDSamples.reduce(0) { $0 + $1.rrIntervalCount }
    let weightedTotal = hrvRMSSDSamples.reduce(0.0) { $0 + ($1.rmssd * Double($1.rrIntervalCount)) }
    guard averagedRRIntervalCount > 0 else {
      return
    }
    let averagedRMSSD = weightedTotal / Double(averagedRRIntervalCount)
    let shouldPublish = lastPublishedHRVRMSSD == nil
      || date.timeIntervalSince(lastHRVPublishedAt) >= Self.hrvEstimatePublishInterval
    if shouldPublish {
      let sampleCount = hrvRMSSDSamples.count
      let averageSource = "\(source).average"
      lastPublishedHRVRMSSD = averagedRMSSD
      lastHRVPublishedAt = date
      bleUIStateAggregator.publishHRV(
        rmssd: averagedRMSSD,
        rrIntervalCount: averagedRRIntervalCount,
        sampleCount: sampleCount,
        source: averageSource,
        updatedAt: date
      )
      persistHRVSample(
        rmssd: averagedRMSSD,
        rrIntervalCount: averagedRRIntervalCount,
        sampleCount: sampleCount,
        source: averageSource,
        capturedAt: date
      )
    }

    let shouldLog = lastHRVLogAt.map { date.timeIntervalSince($0) >= 30 } ?? true
    if shouldLog {
      lastHRVLogAt = date
      record(
        source: source,
        title: "hrv.rmssd.average",
        body: "avg=\(String(format: "%.1f", averagedRMSSD)) ms chunk=\(String(format: "%.1f", chunkRMSSD)) ms samples=\(hrvRMSSDSamples.count) rr=\(averagedRRIntervalCount)"
      )
    }
  }

  func applyBLEUIStateSnapshot(_ snapshot: BLEUIStateSnapshot) {
    if let liveHeartRate = snapshot.liveHeartRate {
      liveHeartRateBPM = liveHeartRate.bpm
      liveHeartRateSource = liveHeartRate.source
      liveHeartRateUpdatedAt = liveHeartRate.updatedAt
    }
    if let restingHeartRate = snapshot.restingHeartRate {
      restingHeartRateEstimateBPM = restingHeartRate.bpm
      restingHeartRateEstimateSampleCount = restingHeartRate.sampleCount
      restingHeartRateEstimateSource = restingHeartRate.source
      restingHeartRateEstimateUpdatedAt = restingHeartRate.updatedAt
    }
    if let hrv = snapshot.hrv {
      liveHRVRMSSD = hrv.rmssd
      liveHRVRRIntervalCount = hrv.rrIntervalCount
      liveHRVRMSSDSampleCount = hrv.sampleCount
      liveHRVSource = hrv.source
      liveHRVUpdatedAt = hrv.updatedAt
    }
    if let snapshotLastSyncAt = snapshot.lastSyncAt,
       lastSyncAt.map({ $0 < snapshotLastSyncAt }) ?? true {
      lastSyncAt = snapshotLastSyncAt
    }
  }

  func record(
    level: GooseLogLevel = .info,
    source: String,
    title: String,
    body: String = ""
  ) {
    guard diagnosticLoggingEnabled || level == .warn || level == .error || shouldAlwaysRecord(source: source, title: title) else {
      return
    }

    let message = GooseMessage(
      timestamp: Date(),
      level: level,
      source: source,
      title: title,
      body: body
    )
    if shouldDisplayMessage(message) {
      enqueueDisplayedMessage(message)
    }
    if shouldWriteOSLog(message) {
      writeOSLog(message)
    }
    if onMessage != nil {
      diagnosticLogQueue.async { [weak self] in
        self?.onMessage?(message)
      }
    }
    appendDiagnosticLog(message)
    writeConsoleDiagnosticLog(message)
    WhoopCloudForwarder.shared.ingestLog(
      level: message.level.rawValue,
      source: message.source,
      title: message.title,
      body: message.body,
      at: message.timestamp
    )
  }

  func enqueueDisplayedMessage(_ message: GooseMessage) {
    messageStore.enqueue(message)
  }

  func flushDisplayedMessages() {
    messageStore.flush()
  }

  enum DiagnosticLogError: Error, CustomStringConvertible {
    case createFailed(String)

    var description: String {
      switch self {
      case .createFailed(let path):
        return "failed to create diagnostic log at \(path)"
      }
    }
  }

  func appendDiagnosticLog(_ message: GooseMessage) {
    guard shouldPersistDiagnosticLog(message) else {
      return
    }
    diagnosticLogQueue.async { [weak self] in
      guard let self else {
        return
      }
      let urls = self.uniqueLogURLs([self.diagnosticLogURL, self.diagnosticLogMirrorURL, self.overnightSideChannelLogURL].compactMap { $0 })
      guard !urls.isEmpty else {
        return
      }
      let timestamp = Self.diagnosticLogTimestampString(from: message.timestamp)
      let line = "\(timestamp) \(message.level.rawValue.uppercased()) \(message.source) \(message.title) \(message.body)\n"
      guard let data = line.data(using: .utf8) else {
        return
      }
      for url in urls {
        self.appendDiagnosticLogData(data, to: url)
      }
    }
  }

  @discardableResult
  func flushDiagnosticLogWrites() -> [String] {
    diagnosticLogQueue.sync {
      var issues = Self.diagnosticLogSetupWarningSnapshot()
      let urls = uniqueLogURLs([diagnosticLogURL, diagnosticLogMirrorURL, overnightSideChannelLogURL].compactMap { $0 })
      issues.append(contentsOf: urls.compactMap { synchronizeDiagnosticLogFile($0) })
      return issues
    }
  }

  func appendDiagnosticLogData(_ data: Data, to url: URL) {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.applyDiagnosticLogProtection(to: url.deletingLastPathComponent())
      if !FileManager.default.fileExists(atPath: url.path) {
        let created = FileManager.default.createFile(atPath: url.path, contents: nil)
        if !created {
          throw DiagnosticLogError.createFailed(url.path)
        }
      }
      try Self.applyDiagnosticLogProtection(to: url)
      let handle = try FileHandle(forWritingTo: url)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try Self.synchronizeAndCloseDiagnosticLogHandle(handle)
    } catch {
      logDiagnosticLogError(url: url, error: error)
    }
  }

  func synchronizeDiagnosticLogFile(_ url: URL) -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    do {
      try Self.applyDiagnosticLogProtection(to: url)
      let handle = try FileHandle(forUpdating: url)
      try Self.synchronizeAndCloseDiagnosticLogHandle(handle)
      return nil
    } catch {
      logDiagnosticLogError(url: url, error: error)
      return "\(url.lastPathComponent): \(String(describing: error))"
    }
  }

  func logDiagnosticLogError(url: URL, error: Error) {
    let message = "\(url.path): \(String(describing: error))"
    logger.error("BLE diagnostic log write failed: \(message, privacy: .public)")
  }

  static func prepareDiagnosticLogFile(at url: URL, directory: URL) throws {
    try prepareDiagnosticLogDirectory(directory)
    if !FileManager.default.fileExists(atPath: url.path) {
      let created = FileManager.default.createFile(atPath: url.path, contents: nil)
      if !created {
        throw DiagnosticLogError.createFailed(url.path)
      }
    }
    try applyDiagnosticLogProtection(to: url)
  }

  static func prepareDiagnosticLogDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try applyDiagnosticLogProtection(to: directory)
  }

  static func recordDiagnosticLogSetupWarning(_ warning: String) {
    diagnosticLogSetupWarningLock.lock()
    if !diagnosticLogSetupWarnings.contains(warning) {
      diagnosticLogSetupWarnings.append(warning)
    }
    diagnosticLogSetupWarningLock.unlock()
    Logger(subsystem: "com.goose.swift", category: "ble")
      .error("BLE diagnostic log setup failed: \(warning, privacy: .public)")
  }

  static func diagnosticLogSetupWarningSnapshot() -> [String] {
    diagnosticLogSetupWarningLock.lock()
    let warnings = diagnosticLogSetupWarnings
    diagnosticLogSetupWarningLock.unlock()
    return warnings
  }

  static func applyDiagnosticLogProtection(to url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: diagnosticLogProtection],
      ofItemAtPath: url.path
    )
  }

  static func synchronizeAndCloseDiagnosticLogHandle(_ handle: FileHandle) throws {
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

  func uniqueLogURLs(_ urls: [URL]) -> [URL] {
    var unique: [URL] = []
    for url in urls {
      let normalized = url.resolvingSymlinksInPath().standardizedFileURL
      if !unique.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == normalized }) {
        unique.append(url)
      }
    }
    return unique
  }

  func writeConsoleDiagnosticLog(_ message: GooseMessage) {
    guard diagnosticLoggingEnabled else {
      return
    }
    guard message.source == "ble.sync"
        || message.source == "respiratory.packet_watch"
        || (consoleCaptureStatusEnabled && message.source == "health.packet_capture")
        || message.level == .warn
        || message.level == .error else {
      return
    }
    diagnosticLogQueue.async {
      let timestamp = Self.diagnosticLogTimestampString(from: message.timestamp)
      let line = "\(timestamp) \(message.level.rawValue.uppercased()) \(message.source) \(message.title) \(message.body)\n"
      guard let data = line.data(using: .utf8) else {
        return
      }
      FileHandle.standardError.write(data)
    }
  }

  static func diagnosticLogTimestampString(from date: Date) -> String {
    diagnosticLogFormatterLock.lock()
    let timestamp = diagnosticLogFormatter.string(from: date)
    diagnosticLogFormatterLock.unlock()
    return timestamp
  }

  func shouldDisplayMessage(_ message: GooseMessage) -> Bool {
    if message.level == .warn || message.level == .error {
      return true
    }
    return !isHighVolumeDiagnostic(message)
  }

  func shouldAlwaysRecord(source: String, title: String) -> Bool {
    if source == "ble.perf" {
      return true
    }
    if source == "ble.high_frequency_sync" {
      return true
    }
    if source == "ble.debug_command" {
      return true
    }
    if source == "ble.sync" || source == "respiratory.packet_watch" {
      return true
    }
    if source == "overnight.guard" || source == "app.lifecycle" || source == "health.packet_capture" {
      return true
    }
    if isLowVolumeBLELifecycleRecord(source: source, title: title) {
      return true
    }
    if source == "ble.metadata" && title.hasPrefix("battery.") {
      return true
    }
    return source == "ble.hr.standard" && title == "hrv.rmssd.average"
  }

  func isLowVolumeBLELifecycleRecord(source: String, title: String) -> Bool {
    if source == "ble.sensor", title.hasPrefix("live_capture.") {
      return true
    }
    guard source == "ble" else {
      return false
    }
    if title.hasPrefix("central.")
      || title.hasPrefix("bluetooth.")
      || title.hasPrefix("connection.")
      || title.hasPrefix("reconnect.")
      || title.hasPrefix("connect.")
      || title.hasPrefix("disconnect")
      || title.hasPrefix("scan.")
      || title.hasPrefix("gatt.")
      || title.hasPrefix("command_characteristic.")
      || title.hasPrefix("notify.")
      || title.hasPrefix("write.")
      || title.hasPrefix("hello.") {
      return true
    }
    return false
  }

  func shouldWriteOSLog(_ message: GooseMessage) -> Bool {
    if message.level == .warn || message.level == .error {
      return true
    }
    return !isHighVolumeDiagnostic(message)
  }

  func isHighVolumeDiagnostic(_ message: GooseMessage) -> Bool {
    if message.source == "ble.perf" {
      return true
    }
    if message.source == "ble", message.title == "notification.received" {
      return true
    }
    if message.title == "heart_rate.live" {
      return true
    }
    if message.source == "activity.detect",
       message.title == "movement.packet" || message.title == "movement.packet.ignored_temperature_capture" {
      return true
    }
    if message.source == "whoop.event", message.title == "event.received" {
      return true
    }
    if message.source == "whoop.data",
       message.title == "data_packet.received" || message.title == "raw_stream_counted.captured" {
      return true
    }
    if message.source == "rust" {
      if message.title == "capture.import.ok" {
        return true
      }
      if message.title == "notification.frame.parsed" ||
          message.title == "notification.frame.reassembly.buffered" ||
          message.title == "notification.frame.reassembled" ||
          message.title == "notification.parser.skipped" {
        return true
      }
    }
    return false
  }

  func shouldPersistDiagnosticLog(_ message: GooseMessage) -> Bool {
    if message.source == "ble.perf" {
      return true
    }
    if message.source == "ble.high_frequency_sync" {
      return true
    }
    if message.source == "ble.sync" || message.source == "ble.metadata" || message.source == "ble.sensor" {
      return true
    }
    if message.source == "ble.debug_menu" {
      return true
    }
    if message.source == "ble.debug_command" {
      return true
    }
    if message.source == "overnight.guard" || message.source == "app.lifecycle" {
      return true
    }
    if message.source == "activity.detect" {
      return true
    }
    if message.source == "activity.timeline" {
      return true
    }
    if message.source == "app",
       message.title == "physiology_capture.launch_config" || message.title == "ble.init" {
      return true
    }
    if message.source == "whoop.event" || message.source == "whoop.data" {
      return true
    }
    if message.source == "health.packet_capture" {
      return true
    }
    if message.source == "respiratory.packet_watch" {
      return true
    }
    if message.source == "rust" {
      if message.title.hasPrefix("capture.") || message.title.hasPrefix("notification.frame") {
        return true
      }
      if message.title.hasPrefix("notification.parser.skipped") {
        return true
      }
    }
    if message.title.hasPrefix("central.")
      || message.title.hasPrefix("bluetooth.")
      || message.title.hasPrefix("connection.")
      || message.title.hasPrefix("reconnect.")
      || message.title.hasPrefix("connect.")
      || message.title.hasPrefix("disconnect")
      || message.title.hasPrefix("gatt.")
      || message.title.hasPrefix("command_characteristic.")
      || message.title.hasPrefix("notify.")
      || message.title.hasPrefix("write.")
      || message.title.hasPrefix("hello.") {
      return true
    }
    return false
  }
}
