import Foundation
import UIKit

enum PassiveActivityDetectionEvent {
  case status(String)
  case primeGPS(String)
  case started(PassiveDetectedActivityRecording)
  case finished(PassiveDetectedActivitySummary, reason: String)
  case stopGPS(String)
}

final class PassiveActivityDetector {
  private let gpsPrimeDuration: TimeInterval = 8
  private let startDuration: TimeInterval = 45
  private let candidateQuietReset: TimeInterval = 20
  private let stopQuietDuration: TimeInterval = 120
  private let minimumRecordingDuration: TimeInterval = 60
  private let sampleRetention: TimeInterval = 360

  private(set) var totalPacketCount = 0
  private var candidateStartedAt: Date?
  private var lastMovingAt: Date?
  private var gpsPrimed = false
  private var samples: [MovementPacketSample] = []
  private var activeRecording: PassiveDetectedActivityRecording?

  func ingest(
    _ sample: MovementPacketSample,
    manualActivityActive: Bool,
    currentPaceSecondsPerKilometer: TimeInterval?,
    distanceMeters: Double
  ) -> [PassiveActivityDetectionEvent] {
    totalPacketCount += 1
    samples.append(sample)
    trimSamples(now: sample.capturedAt)

    if manualActivityActive {
      candidateStartedAt = nil
      lastMovingAt = nil
      gpsPrimed = false
      activeRecording = nil
      return [.status("Manual activity active; movement packets logged")]
    }

    if sample.isMoving {
      lastMovingAt = sample.capturedAt
    }

    if var activeRecording {
      if sample.isMoving {
        activeRecording.ingest(sample)
        let updatedActivity = classifyActivity(
          currentPaceSecondsPerKilometer: currentPaceSecondsPerKilometer,
          distanceMeters: distanceMeters,
          recentHeartRate: sample.heartRateBPM,
          motionIntensity: sample.motionIntensity
        )
        if shouldReclassifyActivity(from: activeRecording.activity, to: updatedActivity) {
          activeRecording.activity = updatedActivity
        }
        self.activeRecording = activeRecording
      }

      let quietDuration = sample.capturedAt.timeIntervalSince(lastMovingAt ?? activeRecording.endedAt)
      if quietDuration >= stopQuietDuration && activeRecording.elapsed >= minimumRecordingDuration {
        return finish(recording: activeRecording, endedAt: lastMovingAt ?? sample.capturedAt, reason: "motion_quiet", distanceMeters: distanceMeters)
      }

      let duration = Int(activeRecording.elapsed.rounded())
      return [.status("Candidate \(activeRecording.activity.title) active \(duration)s")]
    }

    guard sample.isMoving else {
      return handleQuietSample(sample)
    }

    if candidateStartedAt == nil {
      candidateStartedAt = sample.capturedAt
    }

    let candidateStart = candidateStartedAt ?? sample.capturedAt
    let candidateDuration = sample.capturedAt.timeIntervalSince(candidateStart)
    var events: [PassiveActivityDetectionEvent] = []

    if candidateDuration >= gpsPrimeDuration && !gpsPrimed {
      gpsPrimed = true
      events.append(.primeGPS("sustained movement \(Int(candidateDuration.rounded()))s"))
    }

    if candidateDuration >= startDuration {
      let activity = classifyActivity(
        currentPaceSecondsPerKilometer: currentPaceSecondsPerKilometer,
        distanceMeters: distanceMeters,
        recentHeartRate: sample.heartRateBPM,
        motionIntensity: sample.motionIntensity
      )
      var recording = PassiveDetectedActivityRecording(activity: activity, startedAt: candidateStart)
      for retainedSample in samples where retainedSample.capturedAt >= candidateStart && retainedSample.isMoving {
        recording.ingest(retainedSample)
      }
      activeRecording = recording
      candidateStartedAt = nil
      events.append(.started(recording))
      events.append(.status("Candidate \(activity.title) active"))
    } else {
      events.append(.status("Movement candidate \(Int(candidateDuration.rounded()))s"))
    }

    return events
  }

  func finishIfIdle(now: Date, distanceMeters: Double) -> [PassiveActivityDetectionEvent] {
    if let activeRecording {
      let quietDuration = now.timeIntervalSince(lastMovingAt ?? activeRecording.endedAt)
      if quietDuration >= stopQuietDuration && activeRecording.elapsed >= minimumRecordingDuration {
        return finish(recording: activeRecording, endedAt: lastMovingAt ?? activeRecording.endedAt, reason: "idle_timeout", distanceMeters: distanceMeters)
      }
      return []
    }

    guard let candidateStartedAt, let lastMovingAt else {
      return []
    }

    if now.timeIntervalSince(lastMovingAt) >= candidateQuietReset {
      self.candidateStartedAt = nil
      self.lastMovingAt = nil
      if gpsPrimed {
        gpsPrimed = false
        return [.stopGPS("movement candidate quiet before start")]
      }
      return [.status("Watching for movement packets")]
    }

    if now.timeIntervalSince(candidateStartedAt) >= candidateQuietReset {
      self.candidateStartedAt = nil
      return [.status("Watching for movement packets")]
    }

    return []
  }

  func forceFinish(now: Date, reason: String, distanceMeters: Double) -> [PassiveActivityDetectionEvent] {
    guard let activeRecording else {
      candidateStartedAt = nil
      lastMovingAt = nil
      gpsPrimed = false
      return []
    }
    return finish(recording: activeRecording, endedAt: now, reason: reason, distanceMeters: distanceMeters)
  }

  private func handleQuietSample(_ sample: MovementPacketSample) -> [PassiveActivityDetectionEvent] {
    guard let candidateStartedAt else {
      return [.status("Watching for movement packets")]
    }

    let quietDuration = sample.capturedAt.timeIntervalSince(lastMovingAt ?? candidateStartedAt)
    guard quietDuration >= candidateQuietReset else {
      return [.status("Movement candidate quiet \(Int(quietDuration.rounded()))s")]
    }

    self.candidateStartedAt = nil
    self.lastMovingAt = nil
    if gpsPrimed {
      gpsPrimed = false
      return [.stopGPS("movement candidate quiet before start"), .status("Watching for movement packets")]
    }
    return [.status("Watching for movement packets")]
  }

  private func finish(
    recording: PassiveDetectedActivityRecording,
    endedAt: Date,
    reason: String,
    distanceMeters: Double
  ) -> [PassiveActivityDetectionEvent] {
    let confidence = confidenceFor(recording: recording, distanceMeters: distanceMeters)
    let summary = recording.summary(endedAt: endedAt, confidence: confidence)
    activeRecording = nil
    candidateStartedAt = nil
    lastMovingAt = nil
    gpsPrimed = false
    return [.finished(summary, reason: reason), .status("Candidate \(summary.activity.title) finished")]
  }

  private func classifyActivity(
    currentPaceSecondsPerKilometer: TimeInterval?,
    distanceMeters: Double,
    recentHeartRate: Int?,
    motionIntensity: Double
  ) -> ActivityKind {
    if let currentPaceSecondsPerKilometer, currentPaceSecondsPerKilometer > 0 {
      let metersPerSecond = 1000 / currentPaceSecondsPerKilometer
      if metersPerSecond >= 5.0 {
        return .roadRide
      }
      if metersPerSecond >= 2.1 {
        return .run
      }
      if metersPerSecond >= 0.4 {
        return .walk
      }
    }

    if distanceMeters >= 250, motionIntensity >= 0.12 {
      return .walk
    }
    if let recentHeartRate, recentHeartRate >= 135, motionIntensity >= 0.18 {
      return .run
    }
    return .walk
  }

  private func shouldReclassifyActivity(from current: ActivityKind, to next: ActivityKind) -> Bool {
    guard current != next else {
      return false
    }
    switch (current, next) {
    case (.walk, .run), (.walk, .roadRide), (.run, .roadRide):
      return true
    default:
      return false
    }
  }

  private func confidenceFor(recording: PassiveDetectedActivityRecording, distanceMeters: Double) -> Double {
    var confidence = 0.55
    confidence += min(0.20, recording.elapsed / 900)
    confidence += min(0.15, Double(recording.packetCount) / 200)
    if distanceMeters >= 75 {
      confidence += 0.10
    }
    if recording.averageHeartRate != nil {
      confidence += 0.05
    }
    return min(confidence, 0.90)
  }

  private func trimSamples(now: Date) {
    samples.removeAll { now.timeIntervalSince($0.capturedAt) > sampleRetention }
  }
}

final class PassiveActivityDetectionPipeline {
  var onEvents: (([PassiveActivityDetectionEvent]) -> Void)?
  var onStatus: ((String) -> Void)?

  private let queue = DispatchQueue(label: "com.goose.swift.passive-activity-detection", qos: .utility)
  private let detector = PassiveActivityDetector()
  private let stateLock = NSLock()
  private var queuedOperationCount = 0
  private var queueHighWatermark = 0
  private var lastStatusEmittedAt = Date.distantPast
  private let statusInterval: TimeInterval = 5

  func ingest(
    _ sample: MovementPacketSample,
    manualActivityActive: Bool,
    currentPaceSecondsPerKilometer: TimeInterval?,
    distanceMeters: Double
  ) {
    enqueue("ingest") { [detector] in
      detector.ingest(
        sample,
        manualActivityActive: manualActivityActive,
        currentPaceSecondsPerKilometer: currentPaceSecondsPerKilometer,
        distanceMeters: distanceMeters
      )
    }
  }

  func finishIfIdle(now: Date, distanceMeters: Double) {
    enqueue("idle") { [detector] in
      detector.finishIfIdle(
        now: now,
        distanceMeters: distanceMeters
      )
    }
  }

  func forceFinish(now: Date, reason: String, distanceMeters: Double) {
    enqueue("force_finish") { [detector] in
      detector.forceFinish(
        now: now,
        reason: reason,
        distanceMeters: distanceMeters
      )
    }
  }

  private func enqueue(
    _ label: String,
    work: @escaping () -> [PassiveActivityDetectionEvent]
  ) {
    let queued = incrementQueueDepth()
    emitStatusIfNeeded(label: "\(label).queued", depth: queued.depth, highWatermark: queued.highWatermark)
    queue.async { [weak self] in
      guard let self else {
        return
      }
      let events = work()
      let completed = self.decrementQueueDepth()
      self.emitStatusIfNeeded(label: "\(label).completed", depth: completed.depth, highWatermark: completed.highWatermark)
      self.emit(events)
    }
  }

  private func emit(_ events: [PassiveActivityDetectionEvent]) {
    guard !events.isEmpty else {
      return
    }
    onEvents?(events)
  }

  private func incrementQueueDepth() -> (depth: Int, highWatermark: Int) {
    stateLock.lock()
    queuedOperationCount += 1
    queueHighWatermark = max(queueHighWatermark, queuedOperationCount)
    let snapshot = (queuedOperationCount, queueHighWatermark)
    stateLock.unlock()
    return snapshot
  }

  private func decrementQueueDepth() -> (depth: Int, highWatermark: Int) {
    stateLock.lock()
    queuedOperationCount = max(0, queuedOperationCount - 1)
    let snapshot = (queuedOperationCount, queueHighWatermark)
    stateLock.unlock()
    return snapshot
  }

  private func emitStatusIfNeeded(label: String, depth: Int, highWatermark: Int) {
    let now = Date()
    stateLock.lock()
    let shouldEmit = depth >= 4 || now.timeIntervalSince(lastStatusEmittedAt) >= statusInterval
    if shouldEmit {
      lastStatusEmittedAt = now
    }
    stateLock.unlock()
    guard shouldEmit else {
      return
    }
    onStatus?("passive activity \(label) | detectQ \(depth) hwm \(highWatermark)")
  }
}

struct PassiveDetectedActivityRecording {
  var activity: ActivityKind
  let startedAt: Date
  var endedAt: Date
  var elapsed: TimeInterval = 0
  var averageHeartRate: Int?
  var maxHeartRate: Int?
  var zoneDurations: [Int: TimeInterval] = [:]
  var packetCount = 0
  var meanMotionIntensity = 0.0
  var peakMotionIntensity = 0.0

  private var lastSampleAt: Date?
  private var lastHeartRate: Int?
  private var heartRateWeightedTotal = 0.0
  private var heartRateMeasuredSeconds: TimeInterval = 0
  private var motionIntensityTotal = 0.0

  init(activity: ActivityKind, startedAt: Date) {
    self.activity = activity
    self.startedAt = startedAt
    self.endedAt = startedAt
  }

  mutating func ingest(_ sample: MovementPacketSample) {
    let delta = lastSampleAt.map { min(max(sample.capturedAt.timeIntervalSince($0), 0), 15) } ?? 0
    elapsed += delta
    endedAt = maxDate(endedAt, sample.capturedAt)
    lastSampleAt = sample.capturedAt
    packetCount += 1
    motionIntensityTotal += sample.motionIntensity
    meanMotionIntensity = motionIntensityTotal / Double(max(packetCount, 1))
    peakMotionIntensity = max(peakMotionIntensity, sample.motionIntensity)

    if let heartRateBPM = sample.heartRateBPM {
      lastHeartRate = heartRateBPM
      maxHeartRate = max(maxHeartRate ?? heartRateBPM, heartRateBPM)
    }

    guard delta > 0, let heartRateBPM = sample.heartRateBPM ?? lastHeartRate else {
      return
    }

    let zoneID = HeartRateZone.zoneID(for: heartRateBPM)
    zoneDurations[zoneID, default: 0] += delta
    heartRateWeightedTotal += Double(heartRateBPM) * delta
    heartRateMeasuredSeconds += delta
    // Divide by the real measured time — a max(...,1) floor turns sub-second
    // early windows into absurd averages (100 bpm over 0.1 s -> 10 bpm).
    if heartRateMeasuredSeconds > 0 {
      averageHeartRate = Int((heartRateWeightedTotal / heartRateMeasuredSeconds).rounded())
    }
  }

  func summary(endedAt requestedEnd: Date, confidence: Double) -> PassiveDetectedActivitySummary {
    let minimumEnd = startedAt.addingTimeInterval(1)
    let finalEnd = maxDate(maxDate(endedAt, requestedEnd), minimumEnd)
    let finalElapsed = max(elapsed, finalEnd.timeIntervalSince(startedAt))
    return PassiveDetectedActivitySummary(
      activity: activity,
      startedAt: startedAt,
      endedAt: finalEnd,
      elapsed: finalElapsed,
      averageHeartRate: averageHeartRate,
      maxHeartRate: maxHeartRate,
      zoneDurations: zoneDurations,
      packetCount: packetCount,
      meanMotionIntensity: meanMotionIntensity,
      peakMotionIntensity: peakMotionIntensity,
      confidence: confidence
    )
  }
}

struct PassiveDetectedActivitySummary {
  let activity: ActivityKind
  let startedAt: Date
  let endedAt: Date
  let elapsed: TimeInterval
  let averageHeartRate: Int?
  let maxHeartRate: Int?
  let zoneDurations: [Int: TimeInterval]
  let packetCount: Int
  let meanMotionIntensity: Double
  let peakMotionIntensity: Double
  let confidence: Double
}

func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
  lhs >= rhs ? lhs : rhs
}
