import SwiftUI

/// Trends (PTrends) — Direction A "Quiet Companion".
/// W/M/6M segmented control over our own overnight vitals: Overnight HRV +
/// Resting HR full band-trend cards, a provisional Wrist-temp half tile,
/// Sleep bars, and an honest Steps-per-day gap chart (steps never backfill).
struct TrendsView: View {
  @ObservedObject var healthStore: HealthDataStore
  @State private var period: TrendPeriod = .week
  @StateObject private var sleepFeed = SleepNightsFeed()
  @StateObject private var serverFeed = TrendsServerFeed()
  private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header

        // Morning report header — our own read of last night, never WHOOP's.
        LastNightReportCard(report: serverFeed.lastNight)

        recoverySection
        sleepSection
        activitySection
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Trends")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      model.recordUIAction("page.opened", detail: "Trends")
      healthStore.loadBridgeCatalogsIfNeeded()
      sleepFeed.refresh()
      serverFeed.refresh(period: period)
    }
    .onChange(of: period) { _, newPeriod in
      serverFeed.refresh(period: newPeriod)
    }
    .onReceive(refreshTimer) { _ in
      sleepFeed.refresh()
      serverFeed.refresh(period: period)
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var recoverySection: some View {
    let signals = serverFeed.trends?.signals
    TrendSectionHeader(title: "Recovery", systemImage: "heart.fill", accent: GooseTheme.Accent.heart)

    BandedTrendCard(
      title: "HRV",
      systemImage: "waveform.path.ecg",
      accent: GooseTheme.Accent.hrv,
      signal: signals?["hrv_rmssd"],
      decimals: 0
    )
    BandedTrendCard(
      title: "Resting HR",
      systemImage: "heart.fill",
      accent: GooseTheme.Accent.heart,
      signal: signals?["resting_hr"],
      decimals: 0
    )
    BandedTrendCard(
      title: "Respiratory",
      systemImage: "wind",
      accent: GooseTheme.Accent.respiratory,
      signal: signals?["respiratory_rpm"],
      decimals: 1
    )
    BandedTrendCard(
      title: "Skin Temp",
      systemImage: "thermometer.medium",
      accent: GooseTheme.Accent.range,
      signal: signals?["skin_temp_c"],
      decimals: 1
    )

    // SpO2 — we never invent a number without a calibrated oximeter source.
    SpO2ReservedCard()
  }

  @ViewBuilder
  private var sleepSection: some View {
    TrendSectionHeader(title: "Sleep", systemImage: "bed.double.fill", accent: GooseTheme.Accent.sleep)
    if !sleepFeed.nights.isEmpty {
      SleepNightsTrendCard(nights: sleepFeed.nights, period: period)
    } else {
      TrendEmptyCard(
        title: "Sleep (our estimate)",
        systemImage: "bed.double.fill",
        accent: GooseTheme.Accent.sleep,
        message: "Not enough sleep history yet. This is our own estimate, not WHOOP's."
      )
    }
  }

  @ViewBuilder
  private var activitySection: some View {
    let stepsSignal = serverFeed.trends?.signals["steps_per_day"]
    TrendSectionHeader(title: "Activity", systemImage: "figure.walk", accent: GooseTheme.Accent.activity)

    if let stepsSignal, !stepsSignal.validPoints.isEmpty {
      BandedTrendCard(
        title: "Steps / day",
        systemImage: "shoeprints.fill",
        accent: GooseTheme.Accent.activity,
        signal: stepsSignal,
        decimals: 0,
        asBars: true
      )
    } else {
      // Steps are counted live and aren't backfilled — honest empty state, never fabricated.
      TrendEmptyCard(
        title: "Steps / day",
        systemImage: "shoeprints.fill",
        accent: GooseTheme.Accent.activity,
        message: "Daily step history isn't available yet — steps are counted live from the band and aren't backfilled."
      )
    }

    // Stress stays iOS-local (computed on-device from HR), never fetched from the server.
    if let stress = stressTrendCard {
      TrendCard(snapshot: stress, period: period, ours: true)
    } else {
      TrendEmptyCard(
        title: "Stress (our estimate)",
        systemImage: "waveform.path.ecg",
        accent: .yellow,
        message: "Not enough local HR data yet to estimate stress. This is our own computation, not WHOOP's."
      )
    }
  }

  /// On-device stress trend (from the existing local stress snapshot path), or
  /// nil when there isn't enough local HR data to compute it.
  private var stressTrendCard: HealthMetricSnapshot? {
    healthStore.trendRows(for: .stress)
      .first { $0.id == "stress-score-trend" && $0.source.kind != .unavailable && $0.trend.hasData }
  }
}

// MARK: - Section header (GooseMetricLabel small-caps style)

private struct TrendSectionHeader: View {
  let title: String
  let systemImage: String
  let accent: Color

  var body: some View {
    GooseMetricLabel(systemImage: systemImage, title: title, accent: accent)
      .textCase(.uppercase)
      .padding(.top, 6)
      .padding(.leading, 2)
  }
}

// MARK: - Server trends feed (token-only read path, same as MinutelyHRFeed)

/// Decodes a JSON number that may arrive as Double, Int, or a numeric string.
/// The server mixes int/float across fields, so every numeric goes through this.
private struct FlexDouble: Decodable {
  let value: Double?
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      value = nil
    } else if let d = try? c.decode(Double.self) {
      value = d
    } else if let i = try? c.decode(Int.self) {
      value = Double(i)
    } else if let s = try? c.decode(String.self) {
      value = Double(s)
    } else {
      value = nil
    }
  }
}

/// One point in a signal's time series. `value` is dropped if null/unparseable.
struct TrendSeriesPoint: Decodable {
  let date: String
  let value: Double?

  enum CodingKeys: String, CodingKey { case date, value }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    date = (try? c.decode(String.self, forKey: .date)) ?? ""
    value = (try? c.decode(FlexDouble.self, forKey: .value))?.value
  }
}

/// A signal's personal "usual range" band. Every bound is lenient + nullable.
struct TrendBand: Decodable {
  let lo: Double?
  let hi: Double?
  let mean: Double?

  enum CodingKeys: String, CodingKey { case lo, hi, mean }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    lo = (try? c.decode(FlexDouble.self, forKey: .lo))?.value
    hi = (try? c.decode(FlexDouble.self, forKey: .hi))?.value
    mean = (try? c.decode(FlexDouble.self, forKey: .mean))?.value
  }
}

/// One signal in /trends: a unit, a series, an optional usual-range band, and
/// the latest value + delta-vs-previous (all numerics lenient/nullable).
struct TrendSignal: Decodable {
  let unit: String
  let series: [TrendSeriesPoint]
  let band: TrendBand?
  let latest: Double?
  let delta_vs_prev: Double?
  let calibrated: Bool?

  enum CodingKeys: String, CodingKey {
    case unit, series, band, latest, delta_vs_prev, calibrated
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
    series = (try? c.decode([TrendSeriesPoint].self, forKey: .series)) ?? []
    band = try? c.decodeIfPresent(TrendBand.self, forKey: .band)
    latest = (try? c.decode(FlexDouble.self, forKey: .latest))?.value
    delta_vs_prev = (try? c.decode(FlexDouble.self, forKey: .delta_vs_prev))?.value
    calibrated = try? c.decodeIfPresent(Bool.self, forKey: .calibrated)
  }

  /// Non-null series values, chronological as the server returned them.
  var validPoints: [Double] {
    series.compactMap(\.value)
  }

  /// Skin temp specifically: raw counts (no °C) until a calibration lands.
  var isRawUncalibrated: Bool {
    calibrated == false || unit.lowercased() == "raw"
  }
}

struct TrendsResponse: Decodable {
  let period: String?
  let period_days: Int?
  let tz: String?
  let signals: [String: TrendSignal]

  enum CodingKeys: String, CodingKey { case period, period_days, tz, signals }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    period = try? c.decodeIfPresent(String.self, forKey: .period)
    period_days = try? c.decodeIfPresent(Int.self, forKey: .period_days)
    tz = try? c.decodeIfPresent(String.self, forKey: .tz)
    signals = (try? c.decode([String: TrendSignal].self, forKey: .signals)) ?? [:]
  }
}

/// One signal in /trends/last-night: just last night's value + where it sat
/// relative to the usual band.
struct LastNightSignal: Decodable {
  let value: Double?
  let unit: String?
  let in_usual_band: Bool?
  let band: TrendBand?
  let calibrated: Bool?

  enum CodingKeys: String, CodingKey {
    case value, unit, in_usual_band, band, calibrated
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    value = (try? c.decode(FlexDouble.self, forKey: .value))?.value
    unit = try? c.decodeIfPresent(String.self, forKey: .unit)
    in_usual_band = try? c.decodeIfPresent(Bool.self, forKey: .in_usual_band)
    band = try? c.decodeIfPresent(TrendBand.self, forKey: .band)
    calibrated = try? c.decodeIfPresent(Bool.self, forKey: .calibrated)
  }

  var isRawUncalibrated: Bool {
    calibrated == false || (unit?.lowercased() == "raw")
  }
}

struct LastNightResponse: Decodable {
  let date: String?
  let tz: String?
  let signals: [String: LastNightSignal]
  let all_in_band: Bool?

  enum CodingKeys: String, CodingKey { case date, tz, signals, all_in_band }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    date = try? c.decodeIfPresent(String.self, forKey: .date)
    tz = try? c.decodeIfPresent(String.self, forKey: .tz)
    signals = (try? c.decode([String: LastNightSignal].self, forKey: .signals)) ?? [:]
    all_in_band = try? c.decodeIfPresent(Bool.self, forKey: .all_in_band)
  }
}

/// Fetches /trends (for the selected period) + /trends/last-night over the same
/// token-only read path the app uploads with. Any failure — offline, 404 while
/// the endpoint isn't deployed, bad JSON — leaves the published value unchanged
/// so the UI keeps its designed empty states. Never fabricates data.
@MainActor
final class TrendsServerFeed: ObservableObject {
  @Published var trends: TrendsResponse?
  @Published var lastNight: LastNightResponse?

  private let base = "https://latenightgames.fr/whoop/ingest/trends"
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"

  func refresh(period: TrendPeriod) {
    fetchTrends(period: period)
    fetchLastNight()
  }

  private func fetchTrends(period: TrendPeriod) {
    var components = URLComponents(string: base)!
    components.queryItems = [
      URLQueryItem(name: "period", value: period.rawValue),
      URLQueryItem(name: "tz", value: TimeZone.current.identifier),
    ]
    guard let url = components.url else { return }
    request(url) { [weak self] data in
      guard let data, let r = try? JSONDecoder().decode(TrendsResponse.self, from: data) else { return }
      Task { @MainActor in self?.trends = r }
    }
  }

  private func fetchLastNight() {
    guard let url = URL(string: base + "/last-night") else { return }
    request(url) { [weak self] data in
      guard let data, let r = try? JSONDecoder().decode(LastNightResponse.self, from: data) else { return }
      Task { @MainActor in self?.lastNight = r }
    }
  }

  private func request(_ url: URL, _ completion: @escaping (Data?) -> Void) {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { data, response, _ in
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        completion(nil)
        return
      }
      completion(data)
    }.resume()
  }
}

// MARK: - Last-night morning report card

struct LastNightReportCard: View {
  let report: LastNightResponse?

  private var gradient: LinearGradient {
    LinearGradient(
      colors: [
        GooseTheme.Accent.respiratory.opacity(0.85),
        GooseTheme.Accent.hrv.opacity(0.80),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Last night — our read")
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
        Text(headerSubtitle)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.85))
      }

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
        tile("Sleep", "bed.double.fill", report?.signals["sleep_minutes"], kind: .sleep)
        tile("Resting HR", "heart.fill", report?.signals["resting_hr"], kind: .hr)
        tile("Respiratory", "wind", report?.signals["respiratory_rpm"], kind: .respiratory)
        tile("Skin Temp", "thermometer.medium", report?.signals["skin_temp_c"], kind: .skinTemp)
      }

      footer
    }
    .padding(GooseTheme.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(gradient, in: RoundedRectangle(cornerRadius: GooseTheme.cardCornerRadius, style: .continuous))
  }

  private enum TileKind { case sleep, hr, respiratory, skinTemp }

  private var headerSubtitle: String {
    if let date = report?.date, !date.isEmpty {
      return "Morning of \(sleepNightLabel(date)) · our own estimates"
    }
    return "Our own estimates, not WHOOP's"
  }

  @ViewBuilder
  private func tile(_ title: String, _ systemImage: String, _ signal: LastNightSignal?, kind: TileKind) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.caption2.weight(.bold))
        Text(title.uppercased())
          .font(.caption2.weight(.semibold))
      }
      .foregroundStyle(.white.opacity(0.85))

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(displayValue(signal, kind: kind))
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.white)
        if let glyph = statusGlyph(signal) {
          Image(systemName: glyph.name)
            .font(.caption.weight(.bold))
            .foregroundStyle(glyph.color)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func displayValue(_ signal: LastNightSignal?, kind: TileKind) -> String {
    guard let signal, let v = signal.value else { return "—" }
    switch kind {
    case .sleep:
      return sleepDurationText(v)
    case .hr:
      return String(format: "%.0f", v)
    case .respiratory:
      return String(format: "%.1f", v)
    case .skinTemp:
      return signal.isRawUncalibrated ? "raw \(Int(v.rounded()))" : String(format: "%.1f°", v)
    }
  }

  /// Subtle status vs the usual band: ✓ inside, ↑ above, ↓ below, nil if unknown.
  private func statusGlyph(_ signal: LastNightSignal?) -> (name: String, color: Color)? {
    guard let signal, let v = signal.value else { return nil }
    if signal.in_usual_band == true {
      return ("checkmark", .white)
    }
    if let hi = signal.band?.hi, v > hi {
      return ("arrow.up", .white.opacity(0.9))
    }
    if let lo = signal.band?.lo, v < lo {
      return ("arrow.down", .white.opacity(0.9))
    }
    if signal.in_usual_band == false {
      return ("exclamationmark", .white.opacity(0.9))
    }
    return nil
  }

  @ViewBuilder
  private var footer: some View {
    let present = ["sleep_minutes", "resting_hr", "respiratory_rpm", "skin_temp_c"]
      .compactMap { report?.signals[$0] }
      .filter { $0.value != nil }
    let outside = present.filter { $0.in_usual_band == false }.count

    HStack(spacing: 6) {
      if present.isEmpty {
        Image(systemName: "moon.zzz")
        Text("Waiting for last night's read…")
      } else if (report?.all_in_band == true) || outside == 0 {
        Image(systemName: "checkmark.circle.fill")
        Text(present.count == 4 ? "all four inside your usual ranges" : "all inside your usual ranges")
      } else {
        Image(systemName: "exclamationmark.triangle.fill")
        Text("\(outside) outside usual")
      }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.black.opacity(0.18), in: Capsule())
  }
}

// MARK: - Banded trend card (line/bars over a personal usual-range band)

struct BandedTrendCard: View {
  let title: String
  let systemImage: String
  let accent: Color
  let signal: TrendSignal?
  var decimals: Int = 0
  var asBars: Bool = false

  private var points: [Double] { signal?.validPoints ?? [] }
  private var band: TrendBand? { signal?.band }
  private var rawMode: Bool { signal?.isRawUncalibrated ?? false }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        GooseMetricLabel(systemImage: systemImage, title: title, accent: accent)
        Spacer()
        deltaBadge
      }

      headline

      if points.isEmpty {
        HealthSparkline(points: [], tint: accent)
          .frame(height: 64)
      } else {
        BandedChart(points: points, band: band, accent: accent, asBars: asBars)
          .frame(height: 84)
      }

      Text(caption)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .gooseCard()
  }

  @ViewBuilder
  private var headline: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      if let latest = signal?.latest {
        if rawMode {
          Text("raw \(Int(latest.rounded()))")
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
        } else {
          Text(formatted(latest))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
          if !unitText.isEmpty {
            Text(unitText).font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } else {
        Text("—")
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private var deltaBadge: some View {
    if let delta = signal?.delta_vs_prev, !rawMode {
      let up = delta >= 0
      HStack(spacing: 3) {
        Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
        Text(String(format: "%+.\(decimals)f", delta))
          .monospacedDigit()
      }
      .font(.caption.weight(.bold))
      .foregroundStyle(accent)
    }
  }

  private var unitText: String {
    guard let unit = signal?.unit, !unit.isEmpty, unit.lowercased() != "raw" else { return "" }
    return unit
  }

  private func formatted(_ v: Double) -> String {
    String(format: "%.\(decimals)f", v)
  }

  private var caption: String {
    if points.isEmpty {
      return "Not enough data yet — this is our own computation, not WHOOP's."
    }
    if band?.lo != nil || band?.hi != nil {
      return "shaded = your usual range · our own computation"
    }
    return "building your usual range… · our own computation"
  }
}

/// Draws a signal's series as a line (or bars) over its translucent usual-range
/// band. Renders only the real points it's given — never any placeholder shape.
private struct BandedChart: View {
  let points: [Double]
  let band: TrendBand?
  let accent: Color
  var asBars: Bool = false

  var body: some View {
    Canvas { ctx, size in
      guard !points.isEmpty else { return }
      let inset: CGFloat = 6
      let h = size.height - inset * 2

      // y-range spans both the data and the band so neither is clipped.
      var minV = points.min() ?? 0
      var maxV = points.max() ?? 1
      if let lo = band?.lo { minV = min(minV, lo) }
      if let hi = band?.hi { maxV = max(maxV, hi) }
      let span = max(maxV - minV, 0.0001)
      func y(_ v: Double) -> CGFloat { inset + h - CGFloat((v - minV) / span) * h }

      // Translucent usual-range band behind everything.
      if let lo = band?.lo, let hi = band?.hi, hi >= lo {
        let top = y(hi)
        let bottom = y(lo)
        let rect = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
        ctx.fill(Path(rect), with: .color(accent.opacity(0.16)))
        if let mean = band?.mean {
          let my = y(mean)
          var line = Path()
          line.move(to: CGPoint(x: 0, y: my))
          line.addLine(to: CGPoint(x: size.width, y: my))
          ctx.stroke(line, with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
      }

      if asBars {
        let slot = size.width / CGFloat(points.count)
        let bw = max(2, min(slot * 0.78, 22))
        for (i, v) in points.enumerated() {
          let x = slot * (CGFloat(i) + 0.5)
          let top = y(v)
          let rect = CGRect(x: x - bw / 2, y: top, width: bw, height: max(1.5, size.height - inset - top))
          ctx.fill(Path(roundedRect: rect, cornerRadius: max(1, bw / 2)), with: .color(accent))
        }
      } else {
        var line = Path()
        for (i, v) in points.enumerated() {
          let x = points.count == 1
            ? size.width / 2
            : size.width * CGFloat(i) / CGFloat(points.count - 1)
          let pt = CGPoint(x: x, y: y(v))
          if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
        }
        ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

        // Emphasise the latest point.
        if let last = points.last {
          let x = size.width
          let r: CGFloat = 3.5
          ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y(last) - r, width: r * 2, height: r * 2)), with: .color(accent))
        }
      }
    }
  }
}

// MARK: - SpO2 reserved slot (no calibrated oximeter source yet)

struct SpO2ReservedCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GooseMetricLabel(systemImage: "lungs.fill", title: "SpO₂", accent: GooseTheme.Accent.respiratory)
      HStack(spacing: 10) {
        Image(systemName: "drop.degreesign")
          .font(.title3)
          .foregroundStyle(.tertiary)
        Text("needs oximeter calibration — we won't show a number we can't trust")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .gooseCard()
    .opacity(0.55)
  }
}

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
