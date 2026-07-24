import SwiftUI

/// "Trends" — Radiograph redesign. Long-window readings drawn as ink lines,
/// one full-bleed chart section per metric.
struct InkTrendsView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
  // Observed (not just referenced) so the screen re-renders the instant the
  // server's Trends fetch resolves, instead of sitting on the empty state
  // until something else happens to redraw this view.
  @ObservedObject private var metricsFeed = ServerMetricsFeed.shared
  @State private var period: TrendPeriod = .week

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        trendSections
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.bottom, 34)
    }
    .inkScreen()
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      model.recordUIAction("page.opened", detail: "Trends (ink)")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Long window").inkEyebrow()
      HStack(alignment: .firstTextBaseline) {
        Text("Trends")
          .font(InkTheme.screenTitle)
          .foregroundStyle(InkTheme.ink)
        Spacer()
        periodControl
      }
    }
    .padding(.top, 12)
  }

  /// Mono period switch — W / M / 6M as quiet text, active one in ink.
  private var periodControl: some View {
    HStack(spacing: 16) {
      ForEach(TrendPeriod.allCases) { candidate in
        Button {
          period = candidate
        } label: {
          Text(candidate.rawValue)
            .font(InkTheme.mono(12, weight: period == candidate ? .bold : .regular))
            .foregroundStyle(period == candidate ? InkTheme.ink : InkTheme.graphite)
            .underline(period == candidate, color: InkTheme.arterial)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(candidate.rawValue) window")
      }
    }
  }

  /// Every metric with a genuine multi-day server or local history: nightly
  /// recovery vitals (HRV, RHR, resp, temp, recovery score), sleep (duration,
  /// HR dip, and REM/deep once the backend's sleep-stage bugs are fixed),
  /// strain, and the server's Baevsky stress index. Each source function
  /// already drops metrics with no real data — nothing here is ever a
  /// permanently-dashed placeholder.
  private var trendSections: some View {
    let rows = healthStore.trendRows(for: .recovery)
      + healthStore.trendRows(for: .sleep)
      + healthStore.trendRows(for: .strain)
      + healthStore.dailyStressIndexTrendRows()
    return VStack(alignment: .leading, spacing: 0) {
      if rows.allSatisfy({ $0.trend.points.count < 2 }) {
        emptyState
      } else {
        ForEach(rows) { row in
          if row.trend.points.count > 1 {
            InkTrendSection(snapshot: row, period: period)
            InkRule()
          }
        }
      }
    }
    .padding(.top, InkTheme.sectionSpacing)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 8) {
      InkRule()
      Text(emptyStateTitle)
        .font(InkTheme.sectionTitle)
        .foregroundStyle(InkTheme.ink)
        .padding(.top, 14)
      Text(emptyStateMessage)
        .font(InkTheme.body)
        .foregroundStyle(InkTheme.graphite)
        .fixedSize(horizontal: false, vertical: true)
      if metricsFeed.hasLoadedTrendOnce, metricsFeed.lastTrendFetchFailed {
        Button {
          metricsFeed.refreshTrend()
        } label: {
          Text("Retry")
            .font(InkTheme.mono(12, weight: .bold))
            .foregroundStyle(InkTheme.ink)
            .underline(true, color: InkTheme.arterial)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
      }
    }
  }

  /// Three honest states, never conflated: still loading, loaded but the
  /// server couldn't be reached (network/decode/non-2xx — a different
  /// problem calling for a retry, not more waiting), and loaded with a real
  /// history that's just too short yet.
  private var emptyStateTitle: String {
    guard metricsFeed.hasLoadedTrendOnce else { return "Loading trends…" }
    return metricsFeed.lastTrendFetchFailed ? "Couldn't reach your server" : "Not enough history yet"
  }

  private var emptyStateMessage: String {
    guard metricsFeed.hasLoadedTrendOnce else {
      return "Fetching your history from the server…"
    }
    if metricsFeed.lastTrendFetchFailed {
      return metricsFeed.lastTrendFetchFailureReason
        ?? "The server didn't respond. Check that your VPS is reachable and try again."
    }
    return "Trends draw from server-computed nightly and daily readings. Wear the band and sync — lines appear after a few days."
  }
}

private struct InkTrendSection: View {
  let snapshot: HealthMetricSnapshot
  let period: TrendPeriod

  /// True only when every point in this trend carries a real calendar date
  /// (server-computed daily trends always do — see `serverDailyTrend`).
  /// Gates the date-window slicing and the honesty fixes below; trends
  /// without real per-point dates (e.g. packet-derived hourly buckets) keep
  /// their original point-count slice and labels untouched.
  private var hasDatedPoints: Bool {
    let points = snapshot.trend.points
    return !points.isEmpty && points.allSatisfy { $0.date != nil }
  }

  /// Points inside this period's actual calendar-day window (reusing
  /// `period.pointCount` as a day span — 7/30/180), anchored on each point's
  /// real date. This is what makes W/M/6M honest: the server caps history at
  /// 31 real days, so M and 6M now show that same true window instead of one
  /// silently padding to look longer than the other. Falls back to the
  /// previous trailing point-count slice for trends without real dates.
  private var slicedPoints: [HealthTrendPoint] {
    let points = snapshot.trend.points
    guard hasDatedPoints, let latest = points.compactMap(\.date).max() else {
      return Array(points.suffix(period.pointCount))
    }
    let calendar = Calendar.current
    let windowStart = calendar.date(
      byAdding: .day,
      value: -(period.pointCount - 1),
      to: calendar.startOfDay(for: latest)
    ) ?? latest
    return points.filter { point in
      guard let date = point.date else { return false }
      return date >= windowStart
    }
  }

  private var values: [Double] {
    slicedPoints.map(\.value)
  }

  private var latestText: String {
    guard let last = values.last else { return "--" }
    return numberText(last)
  }

  /// Min–max of the values actually drawn for this period. Recomputed from
  /// the slice (rather than the snapshot's full-series range) only for
  /// date-bounded server trends, so switching W/M/6M never leaves a range
  /// label describing a wider window than what's on screen.
  private var rangeLabel: String {
    guard hasDatedPoints, let minValue = values.min(), let maxValue = values.max() else {
      return snapshot.trend.rangeLabel
    }
    let unitSuffix = snapshot.unit.isEmpty ? "" : " \(snapshot.unit)"
    return "\(numberText(minValue)) - \(numberText(maxValue))\(unitSuffix)"
  }

  /// Point count actually on screen for this period. Only overrides the
  /// snapshot's own summary for date-bounded server trends, where
  /// `trend.summary` otherwise describes the full fetched history rather
  /// than this period's slice — e.g. never let "6M" claim more days than
  /// the server (capped at 31) actually provided.
  private var summaryText: String {
    guard hasDatedPoints else { return snapshot.trend.summary }
    let count = slicedPoints.count
    return "\(count) server-computed daily value\(count == 1 ? "" : "s")"
  }

  private func numberText(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.title).inkEyebrow()
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(latestText)
              .font(InkTheme.displayNumeral(34))
              .foregroundStyle(InkTheme.ink)
              .monospacedDigit()
            if !snapshot.unit.isEmpty {
              Text(snapshot.unit)
                .font(InkTheme.mono(11))
                .foregroundStyle(InkTheme.graphite)
            }
          }
        }
        Spacer()
        Text(rangeLabel).inkEyebrow()
      }

      InkSparkline(values: values, height: 72, showsNowDot: true)

      if !summaryText.isEmpty {
        Text(summaryText)
          .font(InkTheme.footnote)
          .foregroundStyle(InkTheme.graphite)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 18)
  }
}
