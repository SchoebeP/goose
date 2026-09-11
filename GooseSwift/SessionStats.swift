import Foundation

/// Session-derived numbers shared by the home session card and the full
/// workout screen: time-in-zone, kcal estimate, live curve points.
enum SessionStats {
  /// Seconds spent in each zone (z1..z5) across the session samples.
  /// Zone edges are fractions of hrMax: 0.5 / 0.6 / 0.7 / 0.8 / 0.9.
  /// Samples below 50 % of hrMax count as z1 (warm-up is real work too).
  static func zoneSeconds(samples: [SimpleHRSample], hrMax: Int) -> [Int] {
    guard hrMax > 0 else { return [0, 0, 0, 0, 0] }
    let iso = ISO8601DateFormatter()
    let parsed: [(Date, Int)] = samples.compactMap { s in
      guard let d = iso.date(from: s.ts) else { return nil }
      return (d, s.bpm)
    }
    guard parsed.count >= 2 else { return [0, 0, 0, 0, 0] }
    var out = [0, 0, 0, 0, 0]
    for (a, b) in zip(parsed, parsed.dropFirst()) {
      let dt = b.0.timeIntervalSince(a.0)
      guard dt > 0, dt < 30 else { continue }   // gaps (pause) don't count
      out[zoneIndex(bpm: a.1, hrMax: hrMax)] += Int(dt)
    }
    return out
  }

  static func zoneIndex(bpm: Int, hrMax: Int) -> Int {
    let f = Double(bpm) / Double(hrMax)
    switch f {
    case ..<0.6: return 0
    case ..<0.7: return 1
    case ..<0.8: return 2
    case ..<0.9: return 3
    default: return 4
    }
  }

  /// kcal estimate — same linear HR model as the VPS webhook (~7.5 kcal/min
  /// at 150 bpm). Honest: always labelled "est." in the UI.
  static func kcal(avgBPM: Int?, seconds: Int) -> Int {
    let avg = Double(avgBPM ?? 0)
    guard avg > 0, seconds > 0 else { return 0 }
    let perMin = max(0.0733 * avg - 3.5, 0)
    return Int((perMin * Double(seconds) / 60).rounded())
  }

  /// The last `window` seconds of HR, as normalized 0…1 points for a curve.
  static func curveValues(samples: [SimpleHRSample], window: TimeInterval = 300) -> [Double] {
    let iso = ISO8601DateFormatter()
    let now = Date()
    let pts: [(Date, Int)] = samples.compactMap { s in
      guard let d = iso.date(from: s.ts) else { return nil }
      return (d, s.bpm)
    }.filter { now.timeIntervalSince($0.0) <= window }
    guard pts.count >= 2 else { return [] }
    let lo = pts.map(\.1).min()!
    let hi = max(pts.map(\.1).max()!, lo + 1)
    return pts.map { Double($0.1 - lo) / Double(hi - lo) }
  }

  static func hms(_ s: Int) -> String {
    String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
  }

  static func ms(_ s: Int) -> String {
    String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
  }
}
