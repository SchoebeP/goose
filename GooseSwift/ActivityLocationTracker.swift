import CoreLocation
import MapKit
import SwiftUI
import UIKit

final class ActivityLocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published private(set) var locations: [CLLocation] = []
  @Published private(set) var routePointCount = 0
  @Published private(set) var distanceMeters: CLLocationDistance = 0
  @Published private(set) var currentPaceSecondsPerKilometer: TimeInterval?
  @Published private(set) var elevationMeters: CLLocationDistance = 0
  @Published private(set) var elevationGainMeters: CLLocationDistance = 0
  @Published private(set) var gpsStatus = "GPS idle"

  private let manager = CLLocationManager()
  private static let maximumPublishedRoutePoints = 360
  private var lastAcceptedLocation: CLLocation?
  private var recentLocations: [CLLocation] = []
  private var elevationBaselineAltitude: CLLocationDistance?
  private var wantsUpdates = false

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = 5
    manager.activityType = .fitness
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    manager.showsBackgroundLocationIndicator = true
    authorizationStatus = manager.authorizationStatus
  }

  func start(reset: Bool) {
    wantsUpdates = true
    if reset {
      resetRoute()
    }
    gpsStatus = "Starting GPS"

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
      gpsStatus = "Looking for GPS"
    case .denied, .restricted:
      gpsStatus = "Location permission needed"
    @unknown default:
      gpsStatus = "Location unavailable"
    }
    authorizationStatus = manager.authorizationStatus
  }

  func startIfAuthorized(reset: Bool) {
    if reset {
      resetRoute()
    }
    authorizationStatus = manager.authorizationStatus
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      wantsUpdates = true
      manager.startUpdatingLocation()
      gpsStatus = "Looking for GPS"
    case .notDetermined:
      wantsUpdates = false
      gpsStatus = "GPS idle"
    case .denied, .restricted:
      wantsUpdates = false
      gpsStatus = "Location permission needed"
    @unknown default:
      wantsUpdates = false
      gpsStatus = "Location unavailable"
    }
  }

  func stop() {
    wantsUpdates = false
    manager.stopUpdatingLocation()
    // Drop segment-bridging state (keep cumulative totals) so the first fix
    // after a resume starts a fresh segment instead of adding the displacement
    // covered while paused to distance/pace/elevation.
    lastAcceptedLocation = nil
    recentLocations = []
    elevationBaselineAltitude = nil
    currentPaceSecondsPerKilometer = nil
    gpsStatus = routePointCount == 0 ? "GPS idle" : "GPS paused"
  }

  func resetRoute() {
    locations = []
    routePointCount = 0
    recentLocations = []
    lastAcceptedLocation = nil
    elevationBaselineAltitude = nil
    distanceMeters = 0
    currentPaceSecondsPerKilometer = nil
    elevationMeters = 0
    elevationGainMeters = 0
  }

  func routeSegments(for activity: ActivityKind) -> [ActivityRouteSegment] {
    guard locations.count > 1 else {
      return []
    }

    var segments: [ActivityRouteSegment] = []
    for index in 1..<locations.count {
      let start = locations[index - 1]
      let end = locations[index]
      let distance = end.distance(from: start)
      let seconds = max(end.timestamp.timeIntervalSince(start.timestamp), 0)
      let secondsPerKilometer = distance > 1 && seconds > 0 ? seconds / (distance / 1000) : nil
      let zone = secondsPerKilometer.map { PaceZone.zone(secondsPerKilometer: $0, activity: activity) } ?? .unknown
      segments.append(ActivityRouteSegment(id: index, start: start.coordinate, end: end.coordinate, zone: zone))
    }
    return segments
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationStatus = manager.authorizationStatus
    guard wantsUpdates else {
      return
    }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.startUpdatingLocation()
      gpsStatus = "Looking for GPS"
    case .denied, .restricted:
      manager.stopUpdatingLocation()
      gpsStatus = "Location permission needed"
    case .notDetermined:
      gpsStatus = "Waiting for permission"
    @unknown default:
      gpsStatus = "Location unavailable"
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations newLocations: [CLLocation]) {
    for location in newLocations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 80 {
      append(location)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    gpsStatus = "GPS error: \(error.localizedDescription)"
  }

  private func append(_ location: CLLocation) {
    if let lastAcceptedLocation {
      let segmentDistance = location.distance(from: lastAcceptedLocation)
      if segmentDistance >= 1 {
        distanceMeters += segmentDistance
      }
      if lastAcceptedLocation.verticalAccuracy >= 0,
         location.verticalAccuracy >= 0,
         lastAcceptedLocation.verticalAccuracy <= 15,
         location.verticalAccuracy <= 15 {
        // Deadband against a baseline altitude: only commit climbs larger than
        // the fix's own vertical uncertainty, so per-fix GPS altitude jitter
        // can't rectify into phantom elevation gain on flat routes.
        let baseline = elevationBaselineAltitude ?? lastAcceptedLocation.altitude
        if elevationBaselineAltitude == nil {
          elevationBaselineAltitude = baseline
        }
        let threshold = max(3.0, location.verticalAccuracy)
        if location.altitude - baseline >= threshold {
          elevationGainMeters += location.altitude - baseline
          elevationBaselineAltitude = location.altitude
        } else if baseline - location.altitude >= threshold {
          // Sustained descent: rebase without subtracting (gain-only metric).
          elevationBaselineAltitude = location.altitude
        }
      }
    }

    lastAcceptedLocation = location
    routePointCount += 1
    locations.append(location)
    if locations.count > Self.maximumPublishedRoutePoints {
      locations.removeFirst(locations.count - Self.maximumPublishedRoutePoints)
    }
    recentLocations.append(location)
    if recentLocations.count > 8 {
      recentLocations.removeFirst(recentLocations.count - 8)
    }
    currentPaceSecondsPerKilometer = recentPace()
    if location.verticalAccuracy >= 0 && location.verticalAccuracy <= 80 {
      elevationMeters = location.altitude
    }
    gpsStatus = "GPS locked +/- \(Int(location.horizontalAccuracy))m"
  }

  private func recentPace() -> TimeInterval? {
    guard let first = recentLocations.first, let last = recentLocations.last, recentLocations.count > 1 else {
      return nil
    }
    let seconds = last.timestamp.timeIntervalSince(first.timestamp)
    guard seconds > 0 else {
      return nil
    }
    var distance: CLLocationDistance = 0
    for index in 1..<recentLocations.count {
      distance += recentLocations[index].distance(from: recentLocations[index - 1])
    }
    guard distance > 5 else {
      return nil
    }
    return seconds / (distance / 1000)
  }
}
