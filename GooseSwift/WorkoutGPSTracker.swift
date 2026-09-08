import CoreLocation
import Foundation
import SwiftUI

/// LOT 2: GPS tracker for runs. WhenInUse only; filters bad fixes (<50 m
/// accuracy); exposes cumulative distance (km) and a smoothed pace text.
/// Permission denied / off → `authorized` stays false, the UI hides the
/// distance/pace cards and the workout still records (HR-only, honest).
final class WorkoutGPSTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
  static let shared = WorkoutGPSTracker()

  @Published var authorized = false
  @Published var started = false
  @Published var distanceKm: Double? = nil
  @Published var paceText: String? = nil

  private let manager = CLLocationManager()
  private var lastFix: CLLocation? = nil
  /// pace smoothing: distance/time over a sliding 30 s window.
  private var windowDistance: CLLocationDistance = 0
  private var windowStart: Date? = nil

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
    lastFix = nil
    windowDistance = 0
    windowStart = nil
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
        }
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

  /// min:sec per km from a speed. Too-slow/negative speeds → "—" (honest).
  static func paceString(mps: Double) -> String? {
    guard mps > 0.3 else { return nil }
    let secPerKm = Int(1000 / mps)
    return String(format: "%d:%02d /km", secPerKm / 60, secPerKm % 60)
  }
}
