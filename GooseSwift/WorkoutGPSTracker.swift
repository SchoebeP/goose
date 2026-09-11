import CoreLocation
import Foundation
import SwiftUI

/// GPS tracker for outdoor workouts (run/bike). WhenInUse only; filters bad
/// fixes (<50 m accuracy); exposes the recorded track (for the map), the
/// cumulative distance (km), a smoothed pace text, per-km splits and the
/// elevation gain (D+).
/// Permission denied / off → `authorized` stays false, the UI hides the
/// map/distance cards and the workout still records (HR-only, honest).
final class WorkoutGPSTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = WorkoutGPSTracker()

  /// One recorded point of the route (for the map polyline).
  struct TrackPoint {
    let latitude: Double
    let longitude: Double
  }

  /// One completed kilometre: split time (s) and climbed metres.
  struct Split: Identifiable {
    let km: Int
    let seconds: Int
    let gainM: Double
    var id: Int { km }
  }

  @Published var authorized = false
  @Published var started = false
  @Published var distanceKm: Double? = nil
  @Published var paceText: String? = nil
  /// The route so far (map polyline). Bounded: one point per ~5 m of movement.
  @Published private(set) var track: [TrackPoint] = []
  /// Completed kilometre splits, in order.
  @Published private(set) var splits: [Split] = []
  /// Total climbed metres (D+), from filtered fixes.
  @Published private(set) var elevationGainM: Double = 0

  private let manager = CLLocationManager()
  private var lastFix: CLLocation? = nil
  /// pace smoothing: distance/time over a sliding 30 s window.
  private var windowDistance: CLLocationDistance = 0
  private var windowStart: Date? = nil
  /// split bookkeeping
  private var lastSplitKm: Int = 0
  private var lastSplitTime: Date? = nil
  private var splitGain: Double = 0
  /// last trusted altitude for gain bookkeeping
  private var lastAltitude: CLLocationDistance? = nil

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.activityType = .fitness
  }

  func start() {
    let status = manager.authorizationStatus
    if status == .denied || status == .restricted {
      authorized = false
      return
    }
    if status == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else {
      authorized = true
    }
    distanceKm = nil
    paceText = nil
    track = []
    splits = []
    elevationGainM = 0
    lastFix = nil
    lastAltitude = nil
    windowDistance = 0
    windowStart = nil
    lastSplitKm = 0
    lastSplitTime = nil
    splitGain = 0
    manager.startUpdatingLocation()
    started = true
  }

  func stop() {
    manager.stopUpdatingLocation()
    started = false
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    if authorized && started { manager.startUpdatingLocation() }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for loc in locations {
      guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 else { continue }
      if let prev = lastFix {
        let d = loc.distance(from: prev)
        // ignore GPS jitter (<1 m between fixes)
        if d >= 1 {
          windowDistance += d
          distanceKm = (distanceKm ?? 0) + d / 1000.0
          recordAltitudeAndSplit(loc: loc)
          // route point: keep at most one per ~5 m to bound memory on long runs
          if d >= 5 {
            track.append(TrackPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
          }
        }
      } else {
        // first trusted fix — seed the track
        track.append(TrackPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude))
      }
      lastFix = loc
      // smoothed instant pace over the last ~30 s of movement
      if let start = windowStart {
        let secs = loc.timestamp.timeIntervalSince(start)
        if secs >= 30 {
          let mps = windowDistance / secs
          paceText = Self.paceString(mps: mps)
          windowDistance = 0
          windowStart = loc.timestamp
        }
      } else {
        windowStart = loc.timestamp
      }
    }
  }

  private func recordAltitudeAndSplit(loc: CLLocation) {
    // altitude gain: only climbs of ≥1 m between vertically-trusted fixes count
    if loc.verticalAccuracy > 0 {
      if let alt = lastAltitude {
        let climb = loc.altitude - alt
        if climb >= 1 {
          elevationGainM += climb
          splitGain += climb
        }
      }
      lastAltitude = loc.altitude
    }
    // km split crossing
    guard let totalKmDouble = distanceKm else { return }
    let totalKm = Int(totalKmDouble)
    if totalKm > lastSplitKm {
      let now = loc.timestamp
      if let splitStart = lastSplitTime {
        let secs = Int(now.timeIntervalSince(splitStart))
        splits.append(Split(km: totalKm, seconds: secs, gainM: splitGain))
        splitGain = 0
      }
      lastSplitTime = now
      lastSplitKm = totalKm
    }
  }

  /// min:sec per km from a speed. Too-slow/negative speeds → "—" (honest).
  static func paceString(mps: Double) -> String? {
    guard mps > 0.3 else { return nil }
    let secPerKm = Int(1000 / mps)
    return String(format: "%d:%02d /km", secPerKm / 60, secPerKm % 60)
  }

  /// "m'ss"" split pace from seconds per km.
  static func splitPaceString(seconds: Int) -> String {
    String(format: "%d'%02d\"", seconds / 60, seconds % 60)
  }
}
