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

        // Sleep (our estimate) — render only if a populated trend exists.
        if let sleep = sleepTrendCard {
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
    }
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
