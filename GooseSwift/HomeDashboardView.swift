import SwiftUI

struct HomeDashboardView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void
  @State private var showingScoreDatePicker = false
  @State private var showingCardioLoadSheet = false
  @State private var selectedHealthMonitorTrend: HealthMetricSnapshot?
  @StateObject private var stepsFeed = MinutelyStepsFeed()

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeLiveHeartRateWidget()

        HomeStatCardRow(stepsFeed: stepsFeed)

        HomeMinutelyHRSection()

        HomeMinutelyStepsSection(feed: stepsFeed)

        HomeStressEnergySection(
          stress: landingSnapshot(for: .stress),
          openStress: { openHealth(.stress) }
        )

        HomeBodySection()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .scrollClipDisabled()
    .gooseScreenBackground()
    .navigationTitle("Today")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .overlay(alignment: .top) {
      HomeTopScrollFade()
        .allowsHitTesting(false)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        ScoreDateTitleButton(
          title: homeTitle,
          subtitle: nil,
          action: { showingScoreDatePicker = true }
        )
      }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView()
        } label: {
          HomeDeviceChip()
        }
        .accessibilityLabel("Device")
        .accessibilityValue(deviceToolbarAccessibilityValue)
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Home")
    }
    .task {
      healthStore.loadBridgeCatalogsIfNeeded()
      model.refreshActivityTimeline(for: selectedDate)
      stepsFeed.refresh()
    }
    .onChange(of: selectedDate) { _, newValue in
      model.refreshActivityTimeline(for: newValue)
    }
    .sheet(isPresented: $showingScoreDatePicker) {
      ScoreDatePickerSheet(
        title: "Daily Scores",
        routes: [.sleep, .recovery, .strain],
        snapshots: scorePickerSnapshots,
        selectedDate: $selectedDate
      )
    }
    .sheet(isPresented: $showingCardioLoadSheet) {
      CardioLoadSheet(store: healthStore)
    }
    .sheet(item: $selectedHealthMonitorTrend) { snapshot in
      SleepV2BevelTrendSheet(snapshot: snapshot)
    }
  }

  private var scoreSnapshots: [HealthMetricSnapshot] {
    [
      datedHomeSnapshot(for: .sleep),
      datedHomeSnapshot(for: .recovery),
      datedHomeSnapshot(for: .strain),
    ]
  }

  private var scorePickerSnapshots: [HealthMetricSnapshot] {
    [
      homeSnapshot(for: .sleep),
      homeSnapshot(for: .recovery),
      homeSnapshot(for: .strain),
    ]
  }

  private var homeTitle: String {
    ScoreDateTimeline.dateLabel(for: selectedDate)
  }

  private var deviceToolbarTint: Color {
    deviceToolbarConnected ? .green : .red
  }

  private var deviceToolbarAccessibilityValue: String {
    deviceToolbarConnected ? "Connected" : "Disconnected"
  }

  private var deviceToolbarConnected: Bool {
    let state = model.ble.connectionState.lowercased()
    return state == "ready" || state == "connected"
  }

  private var dailyActionSummary: String {
    let inputAction = healthStore.metricInputReadinessNextActionSummary()
    if !inputAction.isEmpty {
      return inputAction
    }
    return healthStore.packetDerivedScoreNextActionSummary()
  }

  private var landingSnapshots: [HealthMetricSnapshot] {
    healthStore.landingSnapshots(
      liveHeartRateBPM: model.ble.liveHeartRateBPM,
      liveHeartRateSource: model.ble.liveHeartRateSource,
      liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt,
      stableDailyMetrics: true
    )
  }

  private func landingSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    landingSnapshots.first { $0.route == route } ?? healthStore.snapshot(for: route)
  }

  private func homeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    let snapshot = landingSnapshot(for: route)
    guard route == .strain, snapshot.unit != "%" else {
      return snapshot
    }
    let rawValue = firstNumber(in: snapshot.displayValue) ?? firstNumber(in: snapshot.value) ?? 0
    let percent = min(max(Int((rawValue / 21 * 100).rounded()), 0), 100)
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "\(percent)",
      unit: "%",
      status: snapshot.status,
      freshness: snapshot.freshness,
      provenance: snapshot.provenance,
      source: snapshot.source,
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: snapshot.trend
    )
  }

  private func datedHomeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    ScoreDateTimeline.datedSnapshot(from: homeSnapshot(for: route), date: selectedDate)
  }

  private func openHealth(_ route: HealthRoute) {
    openHealthRoute(route)
    model.recordUIAction("health.deep_link.opened", detail: route.title)
  }

  private func openHealthMonitorSnapshot(_ snapshot: HealthMetricSnapshot) {
    if snapshot.id == "resting-hr" {
      selectedHealthMonitorTrend = snapshot
    } else {
      openHealth(.healthMonitor)
    }
  }

  private func openCoach(_ prompt: String) {
    router.openCoach(prompt: prompt)
    model.recordUIAction("coach.opened", detail: "Home daily score card")
  }
}


/// Live heart rate widget for Home (replaces the Cardio Load widget).
/// Observes the BLE client directly so the BPM/HRV refresh live.
struct HomeLiveHeartRateWidget: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { HomeLiveHeartRateContent(ble: model.ble) }
}

/// The data we actually decode from the 4.0 (the old "Available" tab, folded
/// onto Home). HR / HRV / battery already show in the live widget above; this
/// adds connection + the other decoded channels.
struct HomeDecodedBandSection: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { HomeDecodedBandContent(ble: model.ble) }
}

private struct HomeDecodedBandContent: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Decoded from your band")
        .font(.headline)
      decodedRow("antenna.radiowaves.left.and.right", .blue, "Connection", ble.connectionState.capitalized)
      decodedRow("move.3d", .orange, "Accelerometer", "validated · 1g")
      decodedRow("bell.fill", .gray, "Device events", "wrist · charging · battery")
      Text("Heart rate, HRV and battery are shown above. Sleep, recovery and strain are WHOOP-cloud only and intentionally absent.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .onAppear { ble.refreshBatteryLevel() }
  }

  @ViewBuilder
  private func decodedRow(_ icon: String, _ tint: Color, _ title: String, _ value: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .frame(width: 26)
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .fontWeight(.semibold)
    }
  }
}

/// Small capsule in the Today header: connection dot + battery % + charging bolt.
struct HomeDeviceChip: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { HomeDeviceChipContent(ble: model.ble) }
}

private struct HomeDeviceChipContent: View {
  @ObservedObject var ble: GooseBLEClient

  private var connected: Bool {
    let s = ble.connectionState.lowercased()
    return s == "ready" || s == "connected"
  }
  private var charging: Bool { ble.batteryIsCharging == true }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(connected ? GooseTheme.Accent.activity : Color.red)
        .frame(width: 7, height: 7)
      Text(ble.batteryLevelPercent.map { "\($0)%" } ?? "—")
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
      if charging {
        Image(systemName: "bolt.fill")
          .font(.caption2.weight(.bold))
          .foregroundStyle(GooseTheme.Accent.charging)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(GooseTheme.cardBackground, in: Capsule(style: .continuous))
    .onAppear { ble.refreshBatteryLevel() }
  }
}

private struct HomeLiveHeartRateContent: View {
  @ObservedObject var ble: GooseBLEClient

  private var isLive: Bool {
    guard ble.liveHeartRateBPM != nil, let at = ble.liveHeartRateUpdatedAt else { return false }
    return Date().timeIntervalSince(at) < 15
  }

  private var charging: Bool { ble.batteryIsCharging == true }

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 16) {
        Image(systemName: "heart.fill")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(isLive ? GooseTheme.Accent.heart : Color.secondary)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            GooseMetricLabel(systemImage: "heart.fill", title: "Heart Rate", accent: GooseTheme.Accent.heart)
            if isLive {
              Text("LIVE")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(GooseTheme.Accent.heart, in: Capsule())
            }
          }
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(ble.liveHeartRateBPM.map(String.init) ?? "—")
              .font(.system(size: 64, weight: .bold, design: .rounded))
              .monospacedDigit()
              .lineLimit(1)
              .minimumScaleFactor(0.5)
            Text("bpm")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }

      Divider().overlay(Color.white.opacity(0.08))

      HStack(spacing: 10) {
        if charging {
          // animated "filling" battery (cycles 25 -> 50 -> 75 -> 100) + pulsing bolt
          TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
            let levels = ["battery.25", "battery.50", "battery.75", "battery.100"]
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % levels.count
            Image(systemName: levels[i])
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(GooseTheme.Accent.charging)
              .contentTransition(.symbolEffect(.replace))
          }
          Image(systemName: "bolt.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(GooseTheme.Accent.charging)
            .symbolEffect(.pulse, options: .repeating)
        } else {
          Image(systemName: "battery.100")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(GooseTheme.Accent.battery)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(charging ? "Charging" : "Battery")
            .font(.subheadline.weight(charging ? .semibold : .regular))
            .foregroundStyle(charging ? GooseTheme.Accent.charging : Color.secondary)
          if charging {
            Text("Plugged in — \(ble.batteryLevelPercent.map { $0 >= 95 ? "topping off" : "filling up" } ?? "on the charger")")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Text(ble.batteryLevelPercent.map { "\($0)%" } ?? "—")
          .font(.title3.bold())
          .monospacedDigit()
          .foregroundStyle(charging ? GooseTheme.Accent.charging : Color.primary)
      }
      .animation(.easeInOut(duration: 0.3), value: charging)
    }
    .gooseCard()
    .onAppear { ble.refreshBatteryLevel() }
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
  // Token-only read path (auth-basic OFF on /whoop/ingest/) — same token the app uploads with.
  // tz = our local zone so the server windows "today" from OUR midnight —
  // charts reset at 00:00 local instead of showing a rolling 24 h.
  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/hr/minutely")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
      guard let data, let r = try? JSONDecoder().decode(MinutelyResponse.self, from: data) else { return }
      Task { @MainActor in self?.minutes = r.minutes }
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

/// Today's heart rate, grouped per hour — the VPS-computed recap, fetched + displayed.
struct HomeMinutelyHRSection: View {
  @StateObject private var feed = MinutelyHRFeed()
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  /// Collapse the per-minute rows into one bucket per hour: lo = min of los,
  /// hi = max of his, bpm = last bpm in the hour. Sorted by numeric hour.
  private var hourlyBuckets: [HRMinute] {
    var byHour: [String: [HRMinute]] = [:]
    for m in feed.minutes {
      byHour[hourKey(from: m.minute), default: []].append(m)
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { hour, rows in
        HRMinute(
          minute: hour,
          bpm: rows.last?.bpm ?? 0,
          lo: rows.map(\.lo).min() ?? 0,
          hi: rows.map(\.hi).max() ?? 0,
          n: rows.reduce(0) { $0 + $1.n }
        )
      }
  }

  var body: some View {
    let buckets = hourlyBuckets
    NavigationLink {
      HRDayDetailView(minutes: feed.minutes)
    } label: {
      cardBody(buckets: buckets)
    }
    .buttonStyle(.plain)
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }

  @ViewBuilder
  private func cardBody(buckets: [HRMinute]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        GooseMetricLabel(systemImage: "heart.fill", title: "HR Range Today", accent: GooseTheme.Accent.range)
        Spacer()
        if !buckets.isEmpty {
          Text("\(buckets.count) h").font(.caption).foregroundStyle(.secondary)
        }
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      if buckets.count > 1 {
        let dayLo = feed.minutes.map(\.lo).min() ?? 0
        let dayHi = feed.minutes.map(\.hi).max() ?? 0
        let dayAvg = feed.minutes.isEmpty
          ? 0
          : Int((Double(feed.minutes.map(\.bpm).reduce(0, +)) / Double(feed.minutes.count)).rounded())
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("Avg")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GooseTheme.Accent.range)
          Text("\(dayAvg)")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(GooseTheme.Accent.range)
          Text("bpm")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        MinutelyHRChart(minutes: buckets).frame(height: 150)
        Text("Range \(dayLo)–\(dayHi) bpm · computed on our server")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Waiting for today's data…")
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
      }
    }
    .gooseCard()
  }
}

/// Hourly HR range bars: each bar spans that hour's low→high HR range,
/// rounded, in the range accent color. One bar per hour with small gaps.
private struct MinutelyHRChart: View {
  let minutes: [HRMinute]
  var body: some View {
    Canvas { ctx, size in
      guard !minutes.isEmpty else { return }
      let lo = Double((minutes.map { $0.lo }.min() ?? 40) - 3)
      let hi = Double((minutes.map { $0.hi }.max() ?? 120) + 3)
      let rng = max(hi - lo, 1)
      func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / rng) }
      let slot = size.width / CGFloat(minutes.count)
      let barW = max(4, min(slot * 0.78, 22))
      let accent = GooseTheme.Accent.range
      for (i, m) in minutes.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let top = y(Double(m.hi))
        let bot = y(Double(m.lo))
        let rect = CGRect(x: x - barW / 2, y: top, width: barW, height: max(2, bot - top))
        ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(accent))
      }
    }
  }
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
  // Same local-midnight day window as the HR feed (see above).
  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/steps/minutely")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  private let token = "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"

  func refresh() {
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
      guard let data, let r = try? JSONDecoder().decode(StepsResponse.self, from: data) else { return }
      Task { @MainActor in self?.minutes = r.minutes; self?.total = r.total }
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

  private var sample: BodyHistoryMetricsSample? { ble.latestBodyHistoryMetrics }

  /// Raw u16 / 200 -> rpm; "—" unless a history record landed in the last 24 h.
  private var respiratoryValue: String {
    guard let sample, sample.isRecent, let rpm = sample.respiratoryRateRPM else {
      return "—"
    }
    return String(format: "%.1f", rpm)
  }

  /// The raw skin-temperature word as decoded (real captures ~464–860).
  /// Never converted to °C until calibration lands.
  private var skinTempValue: String {
    guard let raw = sample?.skinTempRaw else {
      return "—"
    }
    return "raw \(raw)"
  }

  /// Red/IR optical channels carried signal within the last 24 h.
  private var spo2HasRecentSignal: Bool {
    guard let sample, sample.isRecent else {
      return false
    }
    return sample.hasSpO2Signal
  }

  var body: some View {
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
          value: skinTempValue,
          unit: "",
          caption: "calibrating — reference readings logged; °C soon"
        )
      }

      spo2Card
    }
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
