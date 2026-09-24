import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var status: String
    var timerStartDate: Date?
    var elapsedSeconds: TimeInterval
    var currentHeartRate: Int?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var activeCalories: Int
    var distanceMeters: Double?
    var isPaused: Bool
    var updatedAt: Date
  }

  var sessionID: String
  var activityName: String
  var activitySystemImage: String
  var activityTintHex: String
  var environmentName: String
  var usesGPS: Bool
}

/// Standalone "Live Heart Rate" Live Activity — shows the band's live BPM / HRV /
/// connection on the Lock Screen and Dynamic Island, independent of any workout.
struct LiveHeartRateActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var bpm: Int?
    var hrvRMSSD: Double?
    var source: String
    var connection: String        // BLE connectionState, e.g. "ready" / "disconnected"
    var batteryPercent: Int?
    var charging: Bool
    var updatedAt: Date

    var isConnected: Bool { connection == "ready" || connection == "connected" }
  }

  var deviceName: String
}
