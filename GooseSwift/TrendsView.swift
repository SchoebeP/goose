import SwiftUI

enum TrendPeriod: String, CaseIterable, Identifiable {
  case week = "W"
  case month = "M"
  case sixMonth = "6M"

  var id: String { rawValue }

  /// How many trailing points to show for this period.
  var pointCount: Int {
    switch self {
    case .week: 7
    case .month: 30
    case .sixMonth: 180
    }
  }
}

struct TrendsView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
  @State private var period: TrendPeriod = .week
  @StateObject private var sleepFeed = SleepNightsFeed()
  private let sleepRefresh = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        Picker("Period", selection: $period) {
          ForEach(TrendPeriod.allCases) { p in
            Text(p.rawValue).tag(p)
          }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 2)

        // Resting HR and Resting HRV — the genuinely-populated source.
        ForEach(recoveryTrendCards) { snapshot in
          TrendCard(snapshot: snapshot, period: period)
        }

        // Steps/day — no multi-day source exists (steps are not backfillable),
        // so this is an honest empty state, never fabricated.
        TrendEmptyCard(
          title: "Steps / day",
          systemImage: "shoeprints.fill",
          accent: GooseTheme.Accent.activity,
          message: "Daily step history isn't available yet — steps are counted live from the band and aren't backfilled."
        )

        // Sleep (our estimate) — VPS-computed nights when available, otherwise
        // the local trend, otherwise the honest empty state.
        if !sleepFeed.nights.isEmpty {
          SleepNightsTrendCard(nights: sleepFeed.nights, period: period)
        } else if let sleep = sleepTrendCard {
          TrendCard(snapshot: sleep, period: period, ours: true)
        } else {
          TrendEmptyCard(
            title: "Sleep (our estimate)",
            systemImage: "bed.double.fill",
            accent: GooseTheme.Accent.sleep,
            message: "Not enough sleep history yet. This is our own estimate, not WHOOP's."
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Trends")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      model.recordUIAction("page.opened", detail: "Trends")
      healthStore.loadBridgeCatalogsIfNeeded()
      sleepFeed.refresh()
    }
    .onReceive(sleepRefresh) { _ in sleepFeed.refresh() }
  }

  /// Resting HR + Resting HRV rows from the recovery trend set, filtered to ones
  /// that actually have data.
  private var recoveryTrendCards: [HealthMetricSnapshot] {
    let wanted: Set<String> = ["recovery-rhr-trend", "recovery-hrv-trend"]
    return healthStore.trendRows(for: .recovery)
      .filter { wanted.contains($0.id) && $0.source.kind != .unavailable && $0.trend.hasData }
  }

  private var sleepTrendCard: HealthMetricSnapshot? {
    healthStore.trendRows(for: .sleep)
      .first { $0.id == "sleep-score-trend" && $0.source.kind != .unavailable && $0.trend.hasData }
  }
}

struct TrendCard: View {
  let snapshot: HealthMetricSnapshot
  let period: TrendPeriod
  var ours: Bool = false

  private var points: [Double] {
    let all = snapshot.trend.points.map(\.value)
    return Array(all.suffix(period.pointCount))
  }

  private var average: Double? {
    guard !points.isEmpty else { return nil }
    return points.reduce(0, +) / Double(points.count)
  }

  /// Delta of recent-half mean vs older-half mean (nil if not enough points).
  private var delta: Double? {
    guard points.count >= 4 else { return nil }
    let mid = points.count / 2
    let older = points.prefix(mid)
    let recent = points.suffix(points.count - mid)
    guard !older.isEmpty, !recent.isEmpty else { return nil }
    let o = older.reduce(0, +) / Double(older.count)
    let r = recent.reduce(0, +) / Double(recent.count)
    return r - o
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        GooseMetricLabel(systemImage: snapshot.systemImage, title: snapshot.title, accent: snapshot.tint)
        Spacer()
        if let delta {
          let up = delta >= 0
          HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(String(format: "%+.0f", delta))
              .monospacedDigit()
          }
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(average.map { String(format: "%.0f", $0) } ?? snapshot.value)
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .monospacedDigit()
        if !snapshot.unit.isEmpty {
          Text(snapshot.unit).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
      }

      HealthSparkline(points: points, tint: snapshot.tint)
        .frame(height: 64)

      Text(captionText)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .gooseCard()
  }

  private var captionText: String {
    let base = "Avg over last \(points.count) · \(snapshot.freshness)"
    return ours ? base + " · our own estimate" : base
  }
}

// MARK: - Sleep nights (computed on the VPS from overnight vitals; ours, not WHOOP's)

/// One detected sleep night, as served by GET /whoop/ingest/sleep/nights.
struct SleepNight: Decodable, Identifiable {
  let date: String        // e.g. "2026-06-07" (the morning the night ends on)
  let start_utc: String   // ISO-8601, e.g. "2026-06-06T22:41:00Z"
  let end_utc: String
  let duration_min: Double
  let avg_hr: Double?
  let avg_resp_rpm: Double?
  let quality: String?    // estimator version tag, e.g. "ours-v1"
  var id: String { date }
}

private struct SleepNightsResponse: Decodable {
  let nights: [SleepNight]
  let count: Int
}

/// Fetches the VPS-computed sleep nights (same token-only read path as MinutelyHRFeed).
/// Any failure — offline, 404 while the endpoint isn't deployed yet, bad JSON —
/// just leaves `nights` empty so the UI falls back to its designed empty state.
@MainActor
final class SleepNightsFeed: ObservableObject {
  @Published var nights: [SleepNight] = []
  private let url = URL(string: "https://latenightgames.fr/whoop/ingest/sleep/nights")!
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
      guard let data,
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let r = try? JSONDecoder().decode(SleepNightsResponse.self, from: data)
      else { return }
      Task { @MainActor in self?.nights = r.nights.sorted { $0.date < $1.date } }
    }.resume()
  }
}

/// "451" minutes -> "7h 31m"
private func sleepDurationText(_ minutes: Double) -> String {
  let total = Int(minutes.rounded())
  return "\(total / 60)h \(String(format: "%02d", total % 60))m"
}

/// "2026-06-07" -> "Jun 7" (falls back to the raw string).
private func sleepNightLabel(_ date: String) -> String {
  let parts = date.split(separator: "-")
  guard parts.count == 3, let m = Int(parts[1]), (1...12).contains(m), let d = Int(parts[2]) else { return date }
  let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return "\(months[m - 1]) \(d)"
}

/// Real sleep card: average nightly duration + one bar per detected night
/// for the selected period. All numbers are our own estimate, never WHOOP's.
struct SleepNightsTrendCard: View {
  let nights: [SleepNight]
  let period: TrendPeriod
  @State private var selectedIndex: Int?

  private var shown: [SleepNight] {
    Array(nights.suffix(period.pointCount))
  }

  private var avgMinutes: Double? {
    guard !shown.isEmpty else { return nil }
    return shown.map(\.duration_min).reduce(0, +) / Double(shown.count)
  }

  private var selected: SleepNight? {
    guard let i = selectedIndex, shown.indices.contains(i) else { return nil }
    return shown[i]
  }

  var body: some View {
    let rows = shown
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        GooseMetricLabel(systemImage: "bed.double.fill", title: "Sleep (our estimate)", accent: GooseTheme.Accent.sleep)
        Spacer()
        if let night = selected {
          Text("\(sleepNightLabel(night.date)) · \(sleepDurationText(night.duration_min))")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(GooseTheme.Accent.sleep)
        } else {
          Text("\(rows.count) night\(rows.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let avg = avgMinutes {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(sleepDurationText(avg))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text("avg").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
        }
      }

      SleepNightsBarChart(nights: rows, selectedIndex: $selectedIndex)
        .frame(height: 110)

      Text("our own estimate from overnight vitals — not WHOOP's")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .gooseCard()
    .onChange(of: period) { _, _ in selectedIndex = nil }
  }
}

/// One rounded bar per night (sleep accent), like the steps chart.
/// Tap a bar to highlight that night; tap again (or elsewhere) to clear.
private struct SleepNightsBarChart: View {
  let nights: [SleepNight]
  @Binding var selectedIndex: Int?

  var body: some View {
    Canvas { ctx, size in
      guard !nights.isEmpty else { return }
      let mx = nights.map(\.duration_min).max() ?? 1
      let slot = size.width / CGFloat(nights.count)
      let bw = max(2, min(slot * 0.78, 22))
      for (i, n) in nights.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let h = CGFloat(n.duration_min / max(mx, 1)) * (size.height - 4)
        let rect = CGRect(x: x - bw / 2, y: size.height - h, width: bw, height: max(1.5, h))
        let dim = selectedIndex != nil && selectedIndex != i
        ctx.fill(
          Path(roundedRect: rect, cornerRadius: max(1, bw / 2)),
          with: .color(GooseTheme.Accent.sleep.opacity(dim ? 0.35 : 1))
        )
      }
    }
    .contentShape(Rectangle())
    .gesture(
      SpatialTapGesture().onEnded { value in
        guard !nights.isEmpty else { return }
        let slot = max(geometryWidth / CGFloat(nights.count), 1)
        let i = min(max(Int(value.location.x / slot), 0), nights.count - 1)
        selectedIndex = (selectedIndex == i) ? nil : i
      }
    )
    .background(WidthReader(width: $measuredWidth))
  }

  @State private var measuredWidth: CGFloat = 0
  private var geometryWidth: CGFloat { measuredWidth > 0 ? measuredWidth : 1 }
}

/// Reads the rendered width of whatever it's backgrounded onto.
private struct WidthReader: View {
  @Binding var width: CGFloat
  var body: some View {
    GeometryReader { geo in
      Color.clear
        .onAppear { width = geo.size.width }
        .onChange(of: geo.size.width) { _, w in width = w }
    }
  }
}

struct TrendEmptyCard: View {
  let title: String
  let systemImage: String
  let accent: Color
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GooseMetricLabel(systemImage: systemImage, title: title, accent: accent)
      HStack(spacing: 10) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.title3)
          .foregroundStyle(.tertiary)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .gooseCard()
  }
}
