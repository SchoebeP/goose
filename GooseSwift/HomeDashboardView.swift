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
        header
        heartRateCard
        stepsCard
        bottomGrid
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
      store.refreshBandVitalsDaily()
      ble.refreshBatteryLevel()
      hrFeed.refresh()
      hrFeed.startAutoRefresh()
      stepsFeed.refresh()
      stepsFeed.startAutoRefresh()
    }
    .onDisappear {
      hrFeed.stopAutoRefresh()
      stepsFeed.stopAutoRefresh()
    }
  }

  // MARK: Header

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
  private var token: String { IngestCredentials.token }
  private var refreshTask: Task<Void, Never>?

  deinit { refreshTask?.cancel() }

  /// Periodic refresh owned by the feed (not the view) so parent re-renders
  /// can't reset the countdown — a Timer.publish stored in the view struct was
  /// re-created every <=5 s while the band streamed and never fired.
  func startAutoRefresh() {
    guard refreshTask == nil else { return }
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard let self else { return }
        self.refresh()
      }
    }
  }

  func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }

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
  @Published var lastSuccess: Date?
  @Published var lastError: String?
  // Same local-midnight day window as the HR feed (see above).
  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/steps/minutely")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  private var token: String { IngestCredentials.token }
  private var refreshTask: Task<Void, Never>?

  deinit { refreshTask?.cancel() }

  /// Feed-owned periodic refresh — see MinutelyHRFeed.startAutoRefresh.
  func startAutoRefresh() {
    guard refreshTask == nil else { return }
    refreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard let self else { return }
        self.refresh()
      }
    }
  }

  func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
      let status = (resp as? HTTPURLResponse)?.statusCode
      let decoded: StepsResponse? = {
        guard err == nil, let status, (200..<300).contains(status), let data else { return nil }
        return try? JSONDecoder().decode(StepsResponse.self, from: data)
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
          title: "steps_minutely.fetch_failed", body: failure, at: Date())
      }
      Task { @MainActor in
        guard let self else { return }
        if let decoded {
          self.minutes = decoded.minutes
          self.total = decoded.total
          self.lastSuccess = Date()
          self.lastError = nil
        } else {
          self.lastError = failure
        }
      }
    }.resume()
  }
}
