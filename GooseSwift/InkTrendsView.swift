import SwiftUI

/// "Trends" — Radiograph redesign. Long-window readings drawn as ink lines,
/// one full-bleed chart section per metric.
struct InkTrendsView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
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

  private var trendSections: some View {
    let rows = healthStore.trendRows(for: .recovery) + healthStore.trendRows(for: .sleep)
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
      Text("Not enough nights yet")
        .font(InkTheme.sectionTitle)
        .foregroundStyle(InkTheme.ink)
        .padding(.top, 14)
      Text("Trends draw from nightly readings. Wear the band overnight and sync — lines appear after a few days.")
        .font(InkTheme.body)
        .foregroundStyle(InkTheme.graphite)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct InkTrendSection: View {
  let snapshot: HealthMetricSnapshot
  let period: TrendPeriod

  private var values: [Double] {
    Array(snapshot.trend.points.map(\.value).suffix(period.pointCount))
  }

  private var latestText: String {
    guard let last = values.last else { return "--" }
    return last == last.rounded() ? String(Int(last)) : String(format: "%.1f", last)
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
        Text(snapshot.trend.rangeLabel).inkEyebrow()
      }

      InkSparkline(values: values, height: 72, showsNowDot: true)

      if !snapshot.trend.summary.isEmpty {
        Text(snapshot.trend.summary)
          .font(InkTheme.footnote)
          .foregroundStyle(InkTheme.graphite)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 18)
  }
}
