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

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeLiveHeartRateWidget()

        HomeMinutelyHRSection()

        HomeMinutelyStepsSection()

        HomeStressEnergySection(
          stress: landingSnapshot(for: .stress),
          openStress: { openHealth(.stress) }
        )

        HomeDecodedBandSection()

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
          Image(systemName: "applewatch")
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(deviceToolbarTint)
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
          .foregroundStyle(isLive ? .red : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text("Live heart rate")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(ble.liveHeartRateBPM.map(String.init) ?? "—")
              .font(.system(size: 40, weight: .bold, design: .rounded))
              .monospacedDigit()
            Text("bpm")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        if let hrv = ble.liveHRVRMSSD {
          VStack(alignment: .trailing, spacing: 2) {
            Text("HRV")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", hrv))
              .font(.headline)
              .monospacedDigit()
          }
        }
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
              .foregroundStyle(.yellow)
              .contentTransition(.symbolEffect(.replace))
          }
          Image(systemName: "bolt.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.yellow)
            .symbolEffect(.pulse, options: .repeating)
        } else {
          Image(systemName: "battery.100")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.green)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(charging ? "Charging" : "Battery")
            .font(.subheadline.weight(charging ? .semibold : .regular))
            .foregroundStyle(charging ? .yellow : .secondary)
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
          .foregroundStyle(charging ? .yellow : .primary)
      }
      .animation(.easeInOut(duration: 0.3), value: charging)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
  private let url = URL(string: "https://latenightgames.fr/whoop/ingest/hr/minutely")!
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

/// Today's heart rate, minute by minute — the VPS-computed recap, fetched + displayed.
struct HomeMinutelyHRSection: View {
  @StateObject private var feed = MinutelyHRFeed()
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Today · minute by minute").font(.headline)
        Spacer()
        if !feed.minutes.isEmpty {
          Text("\(feed.minutes.count) min").font(.caption).foregroundStyle(.secondary)
        }
      }
      if feed.minutes.count > 1 {
        MinutelyHRChart(minutes: feed.minutes).frame(height: 150)
        if let last = feed.minutes.last {
          Text("Latest \(last.bpm) bpm · range \(last.lo)–\(last.hi) bpm · computed on the server")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Text("Waiting for today's data…")
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }
}

/// Candlestick chart: each minute is a candle. Wick = that minute's low→high HR
/// range; body = the move from the previous minute's avg to this minute's avg —
/// green when HR rose, red when it fell.
private struct MinutelyHRChart: View {
  let minutes: [HRMinute]
  var body: some View {
    Canvas { ctx, size in
      guard minutes.count > 1 else { return }
      let lo = Double((minutes.map { $0.lo }.min() ?? 40) - 3)
      let hi = Double((minutes.map { $0.hi }.max() ?? 120) + 3)
      let rng = max(hi - lo, 1)
      func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / rng) }
      let slot = size.width / CGFloat(minutes.count)
      let bodyW = max(1.5, min(slot * 0.62, 9))
      for (i, m) in minutes.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let open = Double(i == 0 ? m.bpm : minutes[i - 1].bpm)
        let close = Double(m.bpm)
        let color: Color = close >= open ? .green : .red
        // wick — intra-minute low/high
        var wick = Path()
        wick.move(to: CGPoint(x: x, y: y(Double(m.hi))))
        wick.addLine(to: CGPoint(x: x, y: y(Double(m.lo))))
        ctx.stroke(wick, with: .color(color.opacity(0.65)), lineWidth: 1)
        // body — open(prev avg) to close(this avg)
        let top = min(y(open), y(close))
        let bot = max(y(open), y(close))
        let rect = CGRect(x: x - bodyW / 2, y: top, width: bodyW, height: max(1.5, bot - top))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
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
  private let url = URL(string: "https://latenightgames.fr/whoop/ingest/steps/minutely")!
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
  @StateObject private var feed = MinutelyStepsFeed()
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Steps today").font(.headline)
        Spacer()
        Text("\(feed.total)").font(.headline.weight(.bold)).foregroundStyle(.green)
      }
      if feed.minutes.count > 1 {
        StepsBarChart(minutes: feed.minutes).frame(height: 120)
        Text("Counted from the accelerometer while worn — our own number, not WHOOP's.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Walk around with the band connected to see steps…")
          .font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }
}

/// Per-minute step bars (consecutive active minutes; green).
private struct StepsBarChart: View {
  let minutes: [StepMinute]
  var body: some View {
    Canvas { ctx, size in
      guard !minutes.isEmpty else { return }
      let mx = Double(minutes.map { $0.steps }.max() ?? 1)
      let slot = size.width / CGFloat(minutes.count)
      let bw = max(1.5, min(slot * 0.7, 10))
      for (i, m) in minutes.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let h = CGFloat(Double(m.steps) / max(mx, 1)) * (size.height - 4)
        let rect = CGRect(x: x - bw / 2, y: size.height - h, width: bw, height: max(1.5, h))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.green))
      }
    }
  }
}
