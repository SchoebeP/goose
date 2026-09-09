import CoreLocation
import MapKit
import SwiftUI
import UIKit

final class ActivitySessionModel: ObservableObject {
  @Published private(set) var selectedActivity: ActivityKind = .run
  @Published private(set) var isActive = false
  @Published private(set) var isPaused = false
  @Published private(set) var startedAt: Date?
  @Published private(set) var endedAt: Date?
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var averageHeartRate: Int?
  @Published private(set) var maxHeartRate: Int?
  @Published private(set) var zoneDurations: [Int: TimeInterval] = [:]

  private var lastTick: Date?
  private var heartRateWeightedTotal: Double = 0
  private var heartRateMeasuredSeconds: TimeInterval = 0
  private var timer: Timer?
  private var heartRateProvider: (() -> Int?)?
  private var recoveryContextProvider: (() -> ActivityRecoveryContext?)?
  private var lastRecoverySnapshotWrittenAt = Date.distantPast
  private static let recoverySnapshotInterval: TimeInterval = 5

  static var recoverySnapshotURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("active-workout-recovery.json")
  }

  /// Reads and removes the crash-recovery snapshot left behind when the app
  /// died mid-workout. The file is deleted before decoding so a corrupt
  /// snapshot can never crash-loop the launch path.
  static func consumeRecoverySnapshot() -> ActiveWorkoutRecoverySnapshot? {
    let url = recoverySnapshotURL
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    try? FileManager.default.removeItem(at: url)
    return try? JSONDecoder().decode(ActiveWorkoutRecoverySnapshot.self, from: data)
  }

  func attachRecoveryContextProvider(_ provider: @escaping () -> ActivityRecoveryContext?) {
    recoveryContextProvider = provider
    lastRecoverySnapshotWrittenAt = .distantPast
  }

  deinit {
    timer?.invalidate()
  }

  var statusText: String {
    if isActive && isPaused {
      return "Paused"
    }
    if isActive {
      return "Recording"
    }
    if endedAt != nil {
      return "Ended"
    }
    return "Ready"
  }

  func select(_ activity: ActivityKind) {
    guard !isActive else {
      return
    }
    selectedActivity = activity
    resetMetrics(keepingSelection: true)
  }

  func start(now: Date = Date(), heartRateProvider: @escaping () -> Int?) {
    resetMetrics(keepingSelection: true)
    self.heartRateProvider = heartRateProvider
    isActive = true
    isPaused = false
    startedAt = now
    endedAt = nil
    lastTick = now
    scheduleTimer()
  }

  func resume(now: Date = Date(), heartRateProvider: @escaping () -> Int?) {
    guard isActive, isPaused else {
      return
    }
    self.heartRateProvider = heartRateProvider
    isPaused = false
    lastTick = now
    scheduleTimer()
  }

  func pause(now: Date = Date(), heartRate: Int?) {
    guard isActive, !isPaused else {
      return
    }
    tick(now: now, heartRate: heartRate)
    isPaused = true
    lastTick = nil
    timer?.invalidate()
    timer = nil
    writeRecoverySnapshot(now: now)
  }

  func end(now: Date = Date(), heartRate: Int?) {
    guard isActive else {
      return
    }
    tick(now: now, heartRate: heartRate)
    isActive = false
    isPaused = false
    endedAt = now
    lastTick = nil
    timer?.invalidate()
    timer = nil
    heartRateProvider = nil
    clearRecoverySnapshot()
  }

  func tick(now: Date, heartRate: Int?) {
    guard isActive, !isPaused else {
      return
    }
    let previousTick = lastTick ?? now
    let delta = max(0, now.timeIntervalSince(previousTick))
    elapsed += delta
    lastTick = now
    writeRecoverySnapshotIfDue(now: now)

    guard delta > 0, let heartRate else {
      return
    }
    // Clamp HR attribution so a background-suspension gap is never credited
    // to one stale sample (elapsed above keeps the full wall-clock delta).
    let hrDelta = min(delta, 15)
    let zoneID = HeartRateZone.zoneID(for: heartRate)
    zoneDurations[zoneID, default: 0] += hrDelta
    heartRateWeightedTotal += Double(heartRate) * hrDelta
    heartRateMeasuredSeconds += hrDelta
    averageHeartRate = Int((heartRateWeightedTotal / max(heartRateMeasuredSeconds, 1)).rounded())
    maxHeartRate = max(maxHeartRate ?? heartRate, heartRate)
  }

  private func scheduleTimer() {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self else {
        return
      }
      self.tick(now: Date(), heartRate: self.heartRateProvider?())
    }
    newTimer.tolerance = 0.002
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }

  private func writeRecoverySnapshotIfDue(now: Date) {
    guard now.timeIntervalSince(lastRecoverySnapshotWrittenAt) >= Self.recoverySnapshotInterval else {
      return
    }
    writeRecoverySnapshot(now: now)
  }

  private func writeRecoverySnapshot(now: Date) {
    guard isActive, let startedAt, let context = recoveryContextProvider?() else {
      return
    }
    let snapshot = ActiveWorkoutRecoverySnapshot(
      activitySessionID: context.activitySessionID,
      captureSessionID: context.captureSessionID,
      ownsCaptureSession: context.ownsCaptureSession,
      source: context.source,
      detectionMethod: context.detectionMethod,
      syncStatus: context.syncStatus,
      importedFrameCount: context.importedFrameCount,
      lastImportedFrameAt: context.lastImportedFrameAt,
      activityRawValue: selectedActivity.rawValue,
      startedAt: startedAt,
      elapsed: elapsed,
      averageHeartRate: averageHeartRate,
      maxHeartRate: maxHeartRate,
      zoneDurations: zoneDurations,
      distanceMeters: context.distanceMeters,
      elevationGainMeters: context.elevationGainMeters,
      routePointCount: context.routePointCount,
      lastUpdatedAt: now
    )
    guard let data = try? JSONEncoder().encode(snapshot) else {
      return
    }
    try? data.write(to: Self.recoverySnapshotURL, options: .atomic)
    lastRecoverySnapshotWrittenAt = now
  }

  private func clearRecoverySnapshot() {
    recoveryContextProvider = nil
    lastRecoverySnapshotWrittenAt = .distantPast
    try? FileManager.default.removeItem(at: Self.recoverySnapshotURL)
  }

  private func resetMetrics(keepingSelection: Bool) {
    timer?.invalidate()
    timer = nil
    if !keepingSelection {
      selectedActivity = .run
    }
    elapsed = 0
    averageHeartRate = nil
    maxHeartRate = nil
    zoneDurations = [:]
    heartRateWeightedTotal = 0
    heartRateMeasuredSeconds = 0
    lastTick = nil
    startedAt = nil
    endedAt = nil
    isActive = false
    isPaused = false
    heartRateProvider = nil
    clearRecoverySnapshot()
  }
}

