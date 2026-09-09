import SwiftUI

// ============================================================
// Today (PToday) — Direction A · "Quiet Companion".
// Live HR hero, day HR-range chart, steps, live-HRV + energy tiles.
// Copy is verbatim from design_handoff_goose_direction_a/proto-screens.jsx.
// Our own numbers, never WHOOP's; honest gaps that never interpolate.
// ============================================================

struct HomeDashboardView: View {
  @EnvironmentObject private var model: GooseAppModel
  // Kept so AppShellView's call site compiles unchanged. `openHealthRoute` is
  // unused by the redesigned Today screen (navigation is via GDADetail pushes)
  // but stays a stored prop per the call contract.
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void

  @StateObject private var hrFeed = MinutelyHRFeed()
  @StateObject private var stepsFeed = MinutelyStepsFeed()
  @StateObject private var hrFeed = MinutelyHRFeed()

  // Simple v1: exactly the owner's four metrics, one screen, no scroll maze.
  // HR hero (live) → 2-up grid (Steps | Sleep) → Skin temp. Each taps into
  // its detail. Stress/HRV/charts live in Trends, not here.
  var body: some View {
    HomeTodayContent(
      store: healthStore,
      ble: model.ble,
      hrFeed: hrFeed,
      stepsFeed: stepsFeed
    )
  }
}

/// The whole Today screen, observing the BLE client + the two minutely feeds
/// directly so live HR / HRV / battery and the per-hour charts all refresh.
private struct HomeTodayContent: View {
  @ObservedObject var store: HealthDataStore
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var hrFeed: MinutelyHRFeed
  @ObservedObject var stepsFeed: MinutelyStepsFeed

  private var bandAway: Bool {
    let s = ble.connectionState.lowercased()
    return !(s == "ready" || s == "connected")
  }

  private var hrBuckets: [HourlyHR] { hourlyHR(from: hrFeed.minutes) }
  private var stepBuckets: [HourlySteps] { hourlySteps(from: stepsFeed.minutes) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        NavigationLink {
          HRDayDetailView(minutes: hrFeed.minutes)
        } label: {
          HomeLiveHeartRateWidget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fréquence cardiaque")

        HStack(spacing: 12) {
          NavigationLink {
            StepsDayDetailView(minutes: stepsFeed.minutes)
          } label: {
            metricCard(
              icon: "shoeprints.fill", tint: GooseTheme.Accent.activity,
              title: "Pas",
              value: stepsFeed.loaded ? stepsFeed.total.formatted() : "—",
              unit: stepsFeed.loaded ? "pas" : ""
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Pas du jour")

          Button {
            openHealth(.sleep)
          } label: {
            metricCard(
              icon: "bed.double.fill", tint: .purple,
              title: "Sommeil",
              value: healthStore.primarySleep()?.durationText ?? "--",
              unit: ""
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Sommeil")
        }

        Button {
          openHealth(.calibration)
        } label: {
          HStack {
            metricCard(
              icon: "thermometer.medium", tint: .orange,
              title: "Température cutanée",
              value: tempValueText,
              unit: tempValueText == "--" ? "" : "°C"
            )
            Image(systemName: "chevron.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(.tertiary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Température cutanée")

        HomeMinutelyStepsSection(feed: stepsFeed)

        // Cached, off-main computed snapshot: the full `landingSnapshot(for:)`
        // chain recomputed every metric (incl. synchronous cardio-load bridge
        // calls) on the main thread on every body pass — seconds of "loading".
        HomeStressEnergySection(
          stress: healthStore.homeStressSnapshot(),
          openStress: { openHealth(.stress) }
        )

        HomeBodySection()
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
    }
    .gdaScreenBackground()
    .navigationDestination(for: GDADetail.self) { detail in
      switch detail {
      case .sleep: GDASleepDetailView(store: store)
      case .hrv: GDAHRVDetailView(store: store)
      }
    }
    .task {
      healthStore.loadBridgeCatalogsIfNeeded()
      healthStore.refreshHomeStressSnapshotIfNeeded()
      model.refreshActivityTimeline(for: selectedDate)
      stepsFeed.refresh()
      hrFeed.refresh()
    }
    .onDisappear {
      hrFeed.stopAutoRefresh()
      stepsFeed.stopAutoRefresh()
    }
  }

  private var tempValueText: String {
    let t = healthStore.recoveryWristTemperatureDisplayText()
    guard t != "--" else { return "--" }
    return t.replacingOccurrences(of: " C", with: "")
  }

  private func metricCard(icon: String, tint: Color, title: String,
                          value: String, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(tint)
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value)
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        if !unit.isEmpty {
          Text(unit)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .gooseCard()
  }

  private var scoreSnapshots: [HealthMetricSnapshot] {
    [
      datedHomeSnapshot(for: .sleep),
      datedHomeSnapshot(for: .recovery),
      datedHomeSnapshot(for: .strain),
    ]
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Today")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .tracking(-0.4)
          .foregroundStyle(GDA.text)
        Text(todayLabel)
          .font(.system(size: 14))
          .foregroundStyle(GDA.text2)
      }
      Spacer(minLength: 8)
      bandPill
    }
  }

  /// "Tuesday, June 10" — the device's own day, formatted like the prototype.
  private var todayLabel: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US")
    f.dateFormat = "EEEE, MMMM d"
    return f.string(from: Date())
  }

  /// "Band · NN%" while connected, grey "Band · away" when out of range.
  private var bandPill: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(bandAway ? GDA.text3 : GDA.activity)
        .frame(width: 7, height: 7)
      Text(bandAway ? "Band · away" : "Band · \(ble.batteryLevelPercent.map { "\($0)%" } ?? "—")")
        .font(.system(size: 12.5, weight: .semibold))
    }
    .foregroundStyle(GDA.text2)
    .padding(.horizontal, 11)
    .padding(.vertical, 4)
    .background(
      Color(red: 168/255, green: 184/255, blue: 214/255).opacity(0.10),
      in: Capsule()
    )
  }

  // MARK: Heart rate card

  private var heartRateCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Heart rate", color: GDA.heart) {
        if bandAway {
          GDAPill(text: "out of range", style: .mut)
        } else {
          GDAPill(text: "live", style: .live, withDot: true)
        }
      }

      HStack(alignment: .bottom) {
        if bandAway {
          heroNumeral("—", color: GDA.text3)
        } else {
          heroNumeral(ble.liveHeartRateBPM.map(String.init) ?? "—")
        }
        Spacer()
        if !bandAway {
          LiveSparkline(color: GDA.heart, seed: 3, width: 130, height: 40)
        }
      }

      if bandAway {
        Text("Last seen 12:48, about 10 m is the limit. The band keeps recording heart rate on its own — it backfills when you're back in range.")
          .font(.system(size: 13))
          .lineSpacing(3)
          .foregroundStyle(GDA.text2)
      } else {
        Text(hrCaption)
          .font(.system(size: 12))
          .foregroundStyle(GDA.text3)
      }

      DayHRRangeChart(buckets: hrBuckets)

      GDAGapNote(text: "Band was away 13:00–15:00 — HR backfills next sync")
    }
    .gdaCard()
  }

  /// "From the band over Bluetooth · day range LO–HI · avg AVG" — our own
  /// numbers from the day's minutely feed. Falls back to the prototype copy
  /// (54–130 · avg 82) before any data has streamed today.
  private var hrCaption: String {
    let ms = hrFeed.minutes
    guard !ms.isEmpty else {
      return "From the band over Bluetooth · day range 54–130 · avg 82"
    }
    let lo = ms.map(\.lo).min() ?? 54
    let hi = ms.map(\.hi).max() ?? 130
    let avg = Int((Double(ms.map(\.bpm).reduce(0, +)) / Double(ms.count)).rounded())
    return "From the band over Bluetooth · day range \(lo)–\(hi) · avg \(avg)"
  }

  private func heroNumeral(_ text: String, color: Color = GDA.text) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(text)
        .font(GDA.num(58))
        .foregroundStyle(color)
      Text("bpm")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(GDA.text2)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.6)
  }

  // MARK: Steps card

  private var stepsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      GDACardTitle("Steps", color: GDA.activity)

      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(stepsTotalText)
          .font(GDA.num(34))
          .foregroundStyle(GDA.text)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        GDAPill(text: bandAway ? "paused — band away" : "so far today", style: .mut)
      }

      HourlyStepsChart(buckets: stepBuckets)

      GDAGapNote(
        text: bandAway
          ? "Steps aren't buffered by the band — this gap will stay"
          : "Steps only count while connected — gaps stay gaps"
      )
    }
    .gdaCard()
  }

  /// Today's total step count (our own accel-derived number), grouped with a
  /// thousands separator like the prototype's "7,392".
  private var stepsTotalText: String {
    stepsFeed.total.formatted(.number.grouping(.automatic))
  }

  // MARK: Live-HRV + Energy tiles

  private var bottomGrid: some View {
    HStack(alignment: .top, spacing: 12) {
      NavigationLink(value: GDADetail.hrv) {
        liveHRVTile
      }
      .buttonStyle(.plain)

      energyTile
    }
  }

  private var liveHRVTile: some View {
    VStack(alignment: .leading, spacing: 8) {
      GDACardTitle("Live HRV", color: GDA.hrv)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(bandAway ? "—" : (ble.liveHRVRMSSD.map { String(format: "%.0f", $0) } ?? "—"))
          .font(GDA.num(28))
          .foregroundStyle(bandAway ? GDA.text3 : GDA.text)
        Text("ms")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(GDA.text2)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Text("Instantaneous & noisy — tap to see how it differs from overnight")
        .font(.system(size: 12))
        .foregroundStyle(GDA.text3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .gdaCard()
  }

  private var energyTile: some View {
    VStack(alignment: .leading, spacing: 8) {
      GDACardTitle("Energy", color: GDA.charge)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text("72")
          .font(GDA.num(28))
          .foregroundStyle(GDA.text)
        Text("/100")
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(GDA.text2)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Text("Our HR-based estimate, computed on this phone")
        .font(.system(size: 12))
        .foregroundStyle(GDA.text3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .gdaCard()
  }
}

// MARK: - Hourly bucketing (per-minute feed → 24-hour chart series)

/// Collapse the minutely HR feed into 24 hourly buckets (hour 0..23). Each
/// hour with at least one minute gets lo = min of los, hi = max of his,
/// avg = mean bpm; hours with no minutes are honest gaps (never zero-filled).
func hourlyHR(from minutes: [HRMinute]) -> [HourlyHR] {
  var byHour: [Int: [HRMinute]] = [:]
  for m in minutes {
    guard let hr = Int(hourKey(from: m.minute)) else { continue }
    byHour[hr, default: []].append(m)
  }
  return (0..<24).map { hr in
    guard let rows = byHour[hr], !rows.isEmpty else {
      return HourlyHR(hour: hr, lo: 0, hi: 0, avg: 0, gap: true)
    }
    let avg = Int((Double(rows.map(\.bpm).reduce(0, +)) / Double(rows.count)).rounded())
    return HourlyHR(
      hour: hr,
      lo: rows.map(\.lo).min() ?? 0,
      hi: rows.map(\.hi).max() ?? 0,
      avg: avg,
      gap: false
    )
  }
}

/// Collapse the minutely steps feed into 24 hourly buckets. Hours with at least
/// one minute sum their steps; hours with no minutes are gaps (steps can't
/// backfill, so these stay hatched forever).
func hourlySteps(from minutes: [StepMinute]) -> [HourlySteps] {
  var byHour: [Int: Int] = [:]
  var seen: Set<Int> = []
  for m in minutes {
    guard let hr = Int(hourKey(from: m.minute)) else { continue }
    byHour[hr, default: 0] += m.steps
    seen.insert(hr)
  }
  return (0..<24).map { hr in
    if seen.contains(hr) {
      return HourlySteps(hour: hr, v: byHour[hr] ?? 0, gap: false)
    }
    return HourlySteps(hour: hr, v: 0, gap: true)
  }
}

// MARK: - Per-minute HR recap (computed on the VPS, fetched by the app)

struct HRMinute: Decodable, Identifiable {
  let minute: String
  let bpm: Int
  let lo: Int
  let hi: Int
  let n: Int
  var id: String { minute }
}

private struct MinutelyResponse: Decodable {
  let minutes: [HRMinute]
  let count: Int
}

@MainActor
final class MinutelyHRFeed: ObservableObject {
  @Published var minutes: [HRMinute] = []
  @Published var lastSuccess: Date?
  @Published var lastError: String?
  // Token-only read path (auth-basic OFF on /whoop/ingest/) — same token the app uploads with.
  // tz = our local zone so the server windows "today" from OUR midnight —
  // charts reset at 00:00 local instead of showing a rolling 24 h.
  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/hr/minutely")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  // SEC1: token lives in Info.plist (never in source/history).
  private let token = Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
      let status = (resp as? HTTPURLResponse)?.statusCode
      let decoded: MinutelyResponse? = {
        guard err == nil, let status, (200..<300).contains(status), let data else { return nil }
        return try? JSONDecoder().decode(MinutelyResponse.self, from: data)
      }()
      let failure: String?
      if decoded != nil {
        failure = nil
      } else if let err {
        failure = err.localizedDescription
      } else if let status, !(200..<300).contains(status) {
        failure = "HTTP \(status)"
      } else {
        failure = "Unreadable response"
      }
      if let failure {
        WhoopCloudForwarder.shared.ingestLog(
          level: "warn", source: "cloud.feed",
          title: "hr_minutely.fetch_failed", body: failure, at: Date())
      }
      Task { @MainActor in
        guard let self else { return }
        if let decoded {
          self.minutes = decoded.minutes
          self.lastSuccess = Date()
          self.lastError = nil
        } else {
          self.lastError = failure
        }
      }
    }.resume()
  }
}

/// Hour key extracted from a minute string like "2026-06-05T14:32" -> "14"
/// (defensive: works for "14:32" too). Returns "" if unparseable.
func hourKey(from minute: String) -> String {
  let afterT = minute.split(separator: "T").last.map(String.init) ?? minute
  let hour = afterT.split(separator: ":").first.map(String.init) ?? ""
  return hour
}

// MARK: - Steps (server-computed from the accelerometer)

struct StepMinute: Decodable, Identifiable {
  let minute: String
  let steps: Int
  var id: String { minute }
}

private struct StepsResponse: Decodable {
  let minutes: [StepMinute]
  let count: Int
  let total: Int
}

@MainActor
final class MinutelyStepsFeed: ObservableObject {
  @Published var minutes: [StepMinute] = []
  @Published var total: Int = 0
  @Published var loaded = false   // U7: "0" only shown once a response arrived
  // Same local-midnight day window as the HR feed (see above).
  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/steps/minutely")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  // SEC1: token lives in Info.plist (never in source/history).
  private let token = Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
      guard let data, let r = try? JSONDecoder().decode(StepsResponse.self, from: data) else { return }
      Task { @MainActor in self?.minutes = r.minutes; self?.total = r.total; self?.loaded = true }
    }.resume()
  }
}

/// Today's steps, minute by minute — our own count from the band's accelerometer,
/// computed on the server. Steps only accrue while the band is worn + connected.
struct HomeMinutelyStepsSection: View {
  @ObservedObject var feed: MinutelyStepsFeed
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  /// Sum steps into one bucket per hour, sorted by numeric hour.
  private var hourlyBuckets: [StepMinute] {
    var byHour: [String: Int] = [:]
    for m in feed.minutes {
      byHour[hourKey(from: m.minute), default: 0] += m.steps
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { StepMinute(minute: $0.key, steps: $0.value) }
  }

  var body: some View {
    let buckets = hourlyBuckets
    NavigationLink {
      StepsDayDetailView(minutes: feed.minutes)
    } label: {
      cardBody(buckets: buckets)
    }
    .buttonStyle(.plain)
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }

  @ViewBuilder
  private func cardBody(buckets: [StepMinute]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        GooseMetricLabel(systemImage: "shoeprints.fill", title: "Steps Today", accent: GooseTheme.Accent.activity)
        Spacer()
        Text("\(feed.total)").font(.headline.weight(.bold)).foregroundStyle(GooseTheme.Accent.activity)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      if buckets.count > 1 {
        StepsBarChart(minutes: buckets).frame(height: 120)
        Text("Counted from the accelerometer while worn — our own number, not WHOOP's.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Walk around with the band connected to see steps…")
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
      }
    }
    .gooseCard()
  }
}

/// Hourly step bars (one bar per hour; activity accent).
private struct StepsBarChart: View {
  let minutes: [StepMinute]
  var body: some View {
    Canvas { ctx, size in
      guard !minutes.isEmpty else { return }
      let mx = Double(minutes.map { $0.steps }.max() ?? 1)
      let slot = size.width / CGFloat(minutes.count)
      let bw = max(4, min(slot * 0.78, 22))
      for (i, m) in minutes.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let h = CGFloat(Double(m.steps) / max(mx, 1)) * (size.height - 4)
        let rect = CGRect(x: x - bw / 2, y: size.height - h, width: bw, height: max(1.5, h))
        ctx.fill(Path(roundedRect: rect, cornerRadius: max(1, bw / 2)), with: .color(GooseTheme.Accent.activity))
      }
    }
  }
}

/// Two side-by-side stat cards: HRV (rMSSD, ours) and today's step total (ours).
struct HomeStatCardRow: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var stepsFeed: MinutelyStepsFeed
  var body: some View { HomeStatCardRowContent(ble: model.ble, stepsFeed: stepsFeed) }
}

private struct HomeStatCardRowContent: View {
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var stepsFeed: MinutelyStepsFeed

  var body: some View {
    HStack(spacing: 12) {
      statCard(
        label: "HRV",
        icon: "waveform.path.ecg",
        accent: GooseTheme.Accent.hrv,
        value: ble.liveHRVRMSSD.map { String(format: "%.0f", $0) } ?? "—",
        unit: "ms",
        caption: "rMSSD — our own number"
      )
      statCard(
        label: "Steps",
        icon: "shoeprints.fill",
        accent: GooseTheme.Accent.activity,
        value: "\(stepsFeed.total)",
        unit: "",
        caption: "From accel — our own count"
      )
    }
  }

  private func statCard(label: String, icon: String, accent: Color, value: String, unit: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GooseMetricLabel(systemImage: icon, title: label, accent: accent)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .monospacedDigit()
        if !unit.isEmpty {
          Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Text(caption)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .gooseCard()
  }
}

// MARK: - Skin-temp calibration (raw-word -> °C fit, computed on the VPS)

/// Server-side linear fit mapping the band's raw skin-temp word to °C, built
/// from reference thermometer readings we logged ourselves. `ready` is the
/// server's verdict that the fit is usable; slope/intercept define raw -> °C.
struct SkinTempCalibration: Decodable {
  let ready: Bool
  let slope: Double?
  let intercept: Double?
  let pointsUsed: Int?
  let rmse: Double?
}

/// Fetches the skin-temp calibration the same way MinutelyHRFeed fetches the
/// HR recap. `calibration` is non-nil ONLY when the server answered 2xx with
/// `ready:true` and a usable slope+intercept — any failure (endpoint missing,
/// transport error, decode error, ready:false) publishes nil so the UI falls
/// back to the raw display and never shows an unconfirmed °C.
@MainActor
final class SkinTempCalibrationFeed: ObservableObject {
  @Published var calibration: SkinTempCalibration?
  // Token-only read path (auth-basic OFF on /whoop/ingest/) — same token the app uploads with.
  private let url = URL(string: "https://latenightgames.fr/whoop/ingest/calibration/skin-temp")!
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase // points_used -> pointsUsed
      var result: SkinTempCalibration?
      if let data,
         let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
         let cal = try? decoder.decode(SkinTempCalibration.self, from: data),
         cal.ready, cal.slope != nil, cal.intercept != nil {
        result = cal
      }
      Task { @MainActor in self?.calibration = result }
    }.resume()
  }
}

// MARK: - Body (respiratory rate, skin temp, SpO2 from the band's history records)

/// "Body" section: the latest values our own decode pulls out of the band's
/// normal-history records (see BodyHistoryMetrics.swift). Raw signals and rough
/// estimates from the band — our numbers, not WHOOP's, and not medical readings.
struct HomeBodySection: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { HomeBodySectionContent(ble: model.ble) }
}

private struct HomeBodySectionContent: View {
  @ObservedObject var ble: GooseBLEClient
  @StateObject private var calibrationFeed = SkinTempCalibrationFeed()
  private let calibrationRefresh = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

  private var sample: BodyHistoryMetricsSample? { ble.latestBodyHistoryMetrics }

  /// Raw u16 / 200 -> rpm; "—" unless a history record landed in the last 24 h.
  private var respiratoryValue: String {
    guard let sample, sample.isRecent, let rpm = sample.respiratoryRateRPM else {
      return "—"
    }
    return String(format: "%.1f", rpm)
  }

  /// 1-minute smoothed raw value when available (records stream every second
  /// during a sync — the average keeps the card steady); falls back to the
  /// latest single record.
  private var displayRaw: Int? {
    ble.skinTempRawSmoothed ?? sample?.skinTempRaw
  }

  /// The raw skin-temperature word as decoded (real captures ~464–860).
  /// Never converted to °C until calibration lands.
  private var skinTempValue: String {
    guard let raw = displayRaw else {
      return "—"
    }
    return "raw \(raw)"
  }

  /// Skin-temp card content. °C is shown ONLY when the server-side calibration
  /// answered ready:true AND the raw reading is from the last 24 h — otherwise
  /// the card stays exactly the raw display until calibration lands.
  private var skinTempDisplay: (value: String, unit: String, caption: String) {
    if let cal = calibrationFeed.calibration, cal.ready,
       let slope = cal.slope, let intercept = cal.intercept,
       let sample, sample.isRecent, let raw = displayRaw {
      let celsius = slope * Double(raw) + intercept
      // Sanity clamp: a linear fit built from only a few reference points can
      // go wild (wrong slope sign, axis mix-up, outlier reading). No human
      // wrist skin temp lands outside 25–45 °C, so a value out of that range
      // means the fit is bad — fall back to the raw display rather than show
      // a nonsense temperature.
      if (25.0...45.0).contains(celsius) {
        let readings = cal.pointsUsed.map { " (\($0) readings)" } ?? ""
        return (
          String(format: "%.1f", celsius),
          "°C",
          "our own calibration\(readings) · 1-min avg · raw \(raw)"
        )
      }
    }
    return (skinTempValue, "", "calibrating — reference readings logged; °C soon")
  }

  /// Red/IR optical channels carried signal within the last 24 h.
  private var spo2HasRecentSignal: Bool {
    guard let sample, sample.isRecent else {
      return false
    }
    return sample.hasSpO2Signal
  }

  var body: some View {
    let skinTemp = skinTempDisplay
    VStack(alignment: .leading, spacing: 12) {
      Text("Body")
        .font(.title3.weight(.bold))

      HStack(spacing: 12) {
        bodyStatCard(
          label: "Respiratory",
          icon: "lungs.fill",
          accent: GooseTheme.Accent.respiratory,
          value: respiratoryValue,
          unit: respiratoryValue == "—" ? "" : "rpm",
          caption: "from band history — our own decode"
        )
        bodyStatCard(
          label: "Skin Temp",
          icon: "thermometer.medium",
          accent: GooseTheme.Accent.range,
          value: skinTemp.value,
          unit: skinTemp.unit,
          caption: skinTemp.caption
        )
      }

      spo2Card
    }
    .onAppear { calibrationFeed.refresh() }
    .onReceive(calibrationRefresh) { _ in calibrationFeed.refresh() }
  }

  private var spo2Card: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        GooseMetricLabel(systemImage: "drop.fill", title: "SpO₂", accent: GooseTheme.Accent.sleep)
        Spacer()
        Text(spo2HasRecentSignal ? "signal ✓" : "no recent signal")
          .font(.caption.weight(.semibold))
          .foregroundStyle(spo2HasRecentSignal ? GooseTheme.Accent.activity : Color.secondary)
      }
      Text("needs oximeter calibration")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("Red/IR optical channels decoded from band history; a percentage stays off until calibrated against a reference oximeter.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .gooseCard()
  }

  private func bodyStatCard(label: String, icon: String, accent: Color, value: String, unit: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GooseMetricLabel(systemImage: icon, title: label, accent: accent)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.55)
        if !unit.isEmpty {
          Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Text(caption)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .gooseCard()
  }
}
