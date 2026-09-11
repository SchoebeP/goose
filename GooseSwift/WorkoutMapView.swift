import MapKit
import SwiftUI

/// Dark MapKit view showing the recorded GPS route: hairline street map in
/// dark mode, the route polyline in accent blue, green start / red current
/// dot. Used full-screen (workout) and compact (home session card).
struct WorkoutMapView: UIViewRepresentable {
  let track: [WorkoutGPSTracker.TrackPoint]
  /// compact = home mini card: no interaction, no compass, no padding.
  var interactive: Bool = true

  func makeUIView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.overrideUserInterfaceStyle = .dark
    map.showsCompass = false
    map.showsScale = false
    map.isRotateEnabled = false
    map.isPitchEnabled = false
    map.delegate = context.coordinator
    if !interactive {
      map.isScrollEnabled = false
      map.isZoomEnabled = false
      map.isUserInteractionEnabled = false
    }
    return map
  }

  func updateUIView(_ map: MKMapView, context: Context) {
    guard track.count >= 2 else { return }
    // Only rebuild when the point count actually changed (updates are frequent).
    guard map.overlays.count != trackOverlaysRebuildMarker() else { return }
    map.removeOverlays(map.overlays)
    var coords = track.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    let line = MKPolyline(coordinates: &coords, count: coords.count)
    line.title = "route"
    map.addOverlay(line)
    if let first = coords.first, let last = coords.last {
      let start = MKCircle(center: first, radius: 6)
      start.title = "start"
      let end = MKCircle(center: last, radius: 8)
      end.title = "end"
      map.addOverlay(start)
      map.addOverlay(end)
    }
    map.setVisibleMapRect(line.boundingMapRect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
  }

  private func trackOverlaysRebuildMarker() -> Int {
    // route + 2 circles = 3 overlays once the track has ≥2 points
    track.count >= 2 ? 3 : 0
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      if let line = overlay as? MKPolyline {
        let r = MKPolylineRenderer(polyline: line)
        r.strokeColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
        r.lineWidth = 5
        r.lineCap = .round
        r.lineJoin = .round
        return r
      }
      if let circle = overlay as? MKCircle {
        let r = MKCircleRenderer(circle: circle)
        r.fillColor = circle.title == "start"
          ? UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
          : UIColor(red: 1.0, green: 0.27, blue: 0.25, alpha: 1)
        return r
      }
      return MKOverlayRenderer(overlay: overlay)
    }
  }
}

private extension MKCircle {
  func then(_ apply: (MKCircle) -> Void) -> MKCircle {
    apply(self)
    return self
  }
}
