import SwiftUI

/// Trends (PTrends) — Direction A "Quiet Companion".
/// W/M/6M segmented control over our own overnight vitals: Overnight HRV +
/// Resting HR full band-trend cards, a provisional Wrist-temp half tile,
/// Sleep bars, and an honest Steps-per-day gap chart (steps never backfill).
struct TrendsView: View {
  @ObservedObject var healthStore: HealthDataStore
  @State private var period: String = "W"

  /// The screen is wired to the verified store under the `store` alias used
  /// across the redesign; the init/stored prop stays `healthStore`.
  private var store: HealthDataStore { healthStore }

  // Honest defaults so charts never crash on an empty fetch.
  private let hrvBandDefault = VitalBand(lo: 60, hi: 85, mean: 72)
  private let rhrBandDefault = VitalBand(lo: 51, hi: 67, mean: 59)
  private let tempBandDefault = VitalBand(lo: 33.5, hi: 34.0, mean: 33.7)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        periodPicker

        hrvCard
        rhrCard

        tempRow
        Text("* provisional — coarse skin-temp calibration")
          .font(.system(size: 11.5))
          .foregroundStyle(GDA.text3)
          .padding(.top, -6)

        sleepCard
        stepsCard
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
    }
    .gdaScreenBackground()
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(for: GDADetail.self) { detail in
      switch detail {
      case .sleep: GDASleepDetailView(store: store)
      case .hrv: GDAHRVDetailView(store: store)
      }
    }
    .task {
      store.refreshTrends(period: period)
      store.refreshSleepNights()
    }
  }

  // MARK: - Header

  private var header: some View {
    Text("Trends")
      .font(.system(size: 28, weight: .bold, design: .rounded))
      .foregroundStyle(GDA.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)
  }

  // MARK: - Period segmented control

  private var periodPicker: some View {
    Picker("Period", selection: $period) {
      Text("W").tag("W")
      Text("M").tag("M")
      Text("6M").tag("6M")
    }
    .pickerStyle(.segmented)
    .onChange(of: period) { _, newValue in
      store.refreshTrends(period: newValue)
    }
    .padding(.bottom, 2)
  }

  // MARK: - Overnight HRV (full card)

  private var hrvCard: some View {
    let series = store.vitalSeries["hrv"] ?? []
    let band = store.vitalBands["hrv"] ?? hrvBandDefault
    let latest = series.last?.value
    return VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Overnight HRV", color: GDA.hrv) {
        GDADelta(value: -0.7, unit: "ms", good: true)
      }
      heroNumber(latest, unit: "ms", decimals: 1)
      BandTrendChart(series: series, band: band, color: GDA.hrv, fractionDigits: 1)
    }
    .gdaCard()
  }

  // MARK: - Resting HR (full card)

  private var rhrCard: some View {
    let series = store.vitalSeries["rhr"] ?? []
    let band = store.vitalBands["rhr"] ?? rhrBandDefault
    let latest = series.last?.value
    return VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Resting HR", color: GDA.heart) {
        GDADelta(value: 3, unit: "bpm", good: false)
      }
      heroNumber(latest, unit: "bpm", decimals: 0)
      BandTrendChart(series: series, band: band, color: GDA.heart, fractionDigits: 0)
    }
    .gdaCard()
  }

  // MARK: - Wrist temp* half tile (Respiratory dropped entirely)

  private var tempRow: some View {
    let series = store.vitalSeries["temp"] ?? []
    let band = store.vitalBands["temp"] ?? tempBandDefault
    let latest = series.last?.value
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 7) {
        GDACardTitle("Wrist temp *", color: GDA.temp)
        heroNumber(latest, unit: "°C", decimals: 1, size: 24)
        BandTrendChart(series: series, band: band, color: GDA.temp, height: 64, fractionDigits: 1)
      }
      .gdaCard()
      .frame(maxWidth: .infinity)

      // Single half tile per spec (Respiratory dropped) — empty trailing column
      // keeps the temp tile at half width, matching the prototype grid.
      Color.clear
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Sleep (our estimate)

  private var sleepCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Sleep", color: GDA.sleep)
      SleepBarsChart(nights: store.sleepNights)
    }
    .gdaCard()
  }

  // MARK: - Steps per day (honest gap — never backfills)

  private var stepsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Steps per day", color: GDA.activity)
      DailyBarsChart(points: stepsPlaceholderPoints)
      GDAGapNote(text: "Only days the band streamed — step history can't backfill")
    }
    .gdaCard()
  }

  /// No multi-day step series exists (raw 100 Hz accel isn't buffered, so steps
  /// can never backfill). Build an honest 7-day placeholder of all-gap bars from
  /// the recent sleep-night dates; falls back to plain weekday labels so the
  /// chart is always non-empty and never crashes.
  private var stepsPlaceholderPoints: [VitalPoint] {
    let labels: [String]
    let recent = store.sleepNights.suffix(7).map(\.date)
    if recent.count == 7 {
      labels = recent.map { d in
        let parts = d.split(separator: "-")
        return parts.count >= 3 ? "\(parts[1])/\(parts[2])" : d
      }
    } else {
      let fmt = DateFormatter()
      fmt.dateFormat = "M/d"
      let cal = Calendar.current
      labels = (0..<7).reversed().compactMap { back in
        cal.date(byAdding: .day, value: -back, to: Date()).map { fmt.string(from: $0) }
      }
    }
    // value < 0 renders as a hatched gap (honest "no step history" placeholder).
    return labels.map { VitalPoint(label: $0, value: -1) }
  }

  // MARK: - Shared hero numeral

  @ViewBuilder
  private func heroNumber(_ value: Double?, unit: String, decimals: Int, size: CGFloat = 28) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(value.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—")
        .font(GDA.num(size))
        .foregroundStyle(value == nil ? GDA.text3 : GDA.text)
      Text(unit)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(GDA.text2)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}
