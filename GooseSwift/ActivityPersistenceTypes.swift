import Foundation
import UIKit

struct ActiveActivityPersistence {
  let activitySessionID: String
  let captureSessionID: String
  let startedAt: Date
  let source: String
  let detectionMethod: String
  let syncStatus: String
  var importedFrameCount: Int
  var lastImportedFrameAt: Date?
  var movementPacketCount = 0
  var meanMotionIntensity = 0.0
  var peakMotionIntensity = 0.0
  var averageHeartRate: Int?
  var maxHeartRate: Int?
  var zoneDurations: [Int: TimeInterval] = [:]

  private var lastMovementSampleAt: Date?
  private var lastHeartRate: Int?
  private var heartRateWeightedTotal = 0.0
  private var heartRateMeasuredSeconds: TimeInterval = 0
  private var motionIntensityTotal = 0.0

  init(
    activitySessionID: String,
    captureSessionID: String,
    startedAt: Date,
    source: String,
    detectionMethod: String,
    syncStatus: String,
    importedFrameCount: Int
  ) {
    self.activitySessionID = activitySessionID
    self.captureSessionID = captureSessionID
    self.startedAt = startedAt
    self.source = source
    self.detectionMethod = detectionMethod
    self.syncStatus = syncStatus
    self.importedFrameCount = importedFrameCount
  }

  mutating func recordImportedFrames(_ count: Int, at date: Date) {
    importedFrameCount += count
    lastImportedFrameAt = lastImportedFrameAt.map { maxDate($0, date) } ?? date
  }

  mutating func ingest(_ sample: MovementPacketSample) {
    let previousSampleAt = lastMovementSampleAt ?? startedAt
    let delta = min(max(sample.capturedAt.timeIntervalSince(previousSampleAt), 0), 15)
    lastMovementSampleAt = sample.capturedAt
    movementPacketCount += 1
    motionIntensityTotal += sample.motionIntensity
    meanMotionIntensity = motionIntensityTotal / Double(max(movementPacketCount, 1))
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
    averageHeartRate = Int((heartRateWeightedTotal / max(heartRateMeasuredSeconds, 1)).rounded())
  }

  func sensorMetricSnapshot(endedAt: Date) -> ActivitySensorMetricSnapshot {
    var finalZoneDurations = zoneDurations
    var finalHeartRateWeightedTotal = heartRateWeightedTotal
    var finalHeartRateMeasuredSeconds = heartRateMeasuredSeconds

    if let lastMovementSampleAt, let lastHeartRate {
      let tail = min(max(endedAt.timeIntervalSince(lastMovementSampleAt), 0), 15)
      if tail > 0 {
        let zoneID = HeartRateZone.zoneID(for: lastHeartRate)
        finalZoneDurations[zoneID, default: 0] += tail
        finalHeartRateWeightedTotal += Double(lastHeartRate) * tail
        finalHeartRateMeasuredSeconds += tail
      }
    }

    let finalAverageHeartRate = finalHeartRateMeasuredSeconds > 0
      ? Int((finalHeartRateWeightedTotal / finalHeartRateMeasuredSeconds).rounded())
      : averageHeartRate

    return ActivitySensorMetricSnapshot(
      averageHeartRate: finalAverageHeartRate,
      maxHeartRate: maxHeartRate,
      zoneDurations: finalZoneDurations,
      movementPacketCount: movementPacketCount,
      meanMotionIntensity: meanMotionIntensity,
      peakMotionIntensity: peakMotionIntensity,
      hasHeartRate: finalHeartRateMeasuredSeconds > 0
    )
  }
}

struct ActivitySensorMetricSnapshot {
  let averageHeartRate: Int?
  let maxHeartRate: Int?
  let zoneDurations: [Int: TimeInterval]
  let movementPacketCount: Int
  let meanMotionIntensity: Double
  let peakMotionIntensity: Double
  let hasHeartRate: Bool
}

struct ActivityRecoveryContext {
  let activitySessionID: String
  let captureSessionID: String
  let ownsCaptureSession: Bool
  let source: String
  let detectionMethod: String
  let syncStatus: String
  let importedFrameCount: Int
  let lastImportedFrameAt: Date?
  let distanceMeters: Double
  let elevationGainMeters: Double
  let routePointCount: Int
}

struct ActiveWorkoutRecoverySnapshot: Codable {
  let activitySessionID: String
  let captureSessionID: String
  let ownsCaptureSession: Bool
  let source: String
  let detectionMethod: String
  let syncStatus: String
  let importedFrameCount: Int
  let lastImportedFrameAt: Date?
  let activityRawValue: String
  let startedAt: Date
  let elapsed: TimeInterval
  let averageHeartRate: Int?
  let maxHeartRate: Int?
  let zoneDurations: [Int: TimeInterval]
  let distanceMeters: Double
  let elevationGainMeters: Double
  let routePointCount: Int
  let lastUpdatedAt: Date
}

struct ActivityTimelineRefreshResult {
  let items: [ActivityTimelineItem]
  let status: String
}

struct ActivityTimelineItem: Identifiable, Equatable {
  let id: String
  let startedAt: Date
  let title: String
  let activityType: String
  let syncStatus: String
  let durationSeconds: TimeInterval
  let distanceMeters: Double?
  let averageHeartRate: Int?
}

