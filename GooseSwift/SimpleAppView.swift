import SwiftUI
import UserNotifications

/// SimpleAppView — the whole app on ONE screen (branch `simple`).
///
/// Design (pat, 2026-09 UI rework): ‹ Aujourd'hui › date navigator with
/// calendar, LIVE status, rattrapage banner, HR hero (session mode: expanded
/// with live curve + session stats + zones + mini map), Pas | Sommeil,
/// Cette semaine, Historique d'entraînement. French labels, honest "--".
/// The BLE engine (GooseBLEClient) is untouched — UI only.

// MARK: - VPS client (all reads token-authed, same token as upload)

struct SimpleHRMinute: Decodable, Identifiable {
  let minute: String
  let bpm: Int
  let lo: Int
  let hi: Int
  let n: Int
  var id: String { minute }
}

struct SimpleStepMinute: Decodable, Identifiable {
  let minute: String
  let steps: Int
  var id: String { minute }
}

struct SimpleSleepNight: Decodable, Identifiable {
  let date: String
  let start_utc: String
  let end_utc: String
  let duration_min: Int?
  let avg_hr: Double?
  var id: String { date }
}

struct SimpleSleepAnalysisDay: Decodable, Identifiable {
  let date: String
  let sleep_stages: Stages?
  struct Stages: Decodable {
    let tst_min: Double?
    let tib_min: Double?
    let runs: [Run]?
    let t0_epoch: Double?
    let efficiency_pct: Double?
    let light_pct: Double?
    let deep_pct: Double?
    let rem_pct: Double?
    let wake_pct: Double?
    let sol_min: Double?
    let waso_min: Double?
    let disturbances: Int?
    let rem_measured: Bool?

    struct Run: Decodable {
      let stage: String
      let sec: Double
    }
  }
  var id: String { date }
}

@MainActor
final class SimpleVPSFeed: ObservableObject {
  @Published var hrMinutes: [SimpleHRMinute] = []
  @Published var hrLoaded = false
  @Published var steps: [SimpleStepMinute] = []
  @Published var stepsTotal: Int?
  @Published var nights: [SimpleSleepNight] = []
  @Published var sleepAnalysis: [SimpleSleepAnalysisDay] = []
  @Published var workouts: [SimpleWorkout] = []
  @Published var lastSync: Date?

  private let base = "https://latenightgames.fr/whoop/ingest"
  private let token = Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""
  private let tz = TimeZone.current.identifier
  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  func refreshAll(selectedDate: Date = Date()) {
    let day = Self.dayFormatter.string(from: selectedDate)
    get("/hr/minutely?tz=\(tz)&date=\(day)") { [weak self] (r: HRPayload?) in
      self?.hrMinutes = r?.minutes ?? []
      self?.hrLoaded = true
    }
    get("/steps/minutely?tz=\(tz)&date=\(day)") { [weak self] (r: StepsPayload?) in
      self?.steps = r?.minutes ?? []
      self?.stepsTotal = r?.total
    }
    get("/sleep/nights?days=10&tz=\(tz)") { [weak self] (r: NightsPayload?) in
      self?.nights = r?.nights ?? []
    }
    get("/metrics/daily?days=10&tz=\(tz)") { [weak self] (r: DailyPayload?) in
      self?.sleepAnalysis = (r?.days ?? []).compactMap { day in
        day.sleep_stages != nil ? SimpleSleepAnalysisDay(date: day.date, sleep_stages: day.sleep_stages) : nil
      }
    }
    get("/workouts?days=30") { [weak self] (r: WorkoutsPayload?) in
      self?.workouts = r?.workouts ?? []
    }
    Task { @MainActor in self.lastSync = Date() }
  }

  private struct HRPayload: Decodable { let minutes: [SimpleHRMinute] }
  private struct StepsPayload: Decodable { let minutes: [SimpleStepMinute]; let total: Int }
  private struct NightsPayload: Decodable { let nights: [SimpleSleepNight] }
  private struct DailyPayload: Decodable {
    let days: [Day]
    struct Day: Decodable {
      let date: String
      let sleep_stages: SimpleSleepAnalysisDay.Stages?
    }
  }
  private struct WorkoutsPayload: Decodable { let workouts: [SimpleWorkout] }

  private func get<T: Decodable>(_ path: String, then: @escaping (T?) -> Void) {
    var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { data, _, _ in
      let decoded = data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
      Task { @MainActor in then(decoded) }
    }.resume()
  }
}

// MARK: - One-screen app

struct SimpleAppView: View {
  @EnvironmentObject private var model: GooseAppModel
  @StateObject private var feed = SimpleVPSFeed()
  @ObservedObject private var gps = WorkoutGPSTracker.shared
  @State private var showDevice = false
  @StateObject private var workout = SimpleWorkoutSession()
  @State private var showWorkout = false
  @State private var sleepSheet = false
  @State private var showCalendar = false
  @State private var selectedDate = Date()
  /// Ticker so the relative-time labels stay fresh while the screen is open.
  @State private var relativeTimeTick = 0
  private let refresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

  private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          statusBar
          SyncBannerHost(ble: model.ble)
          if workout.isActive {
            sessionHero
            HStack(spacing: 12) { stepsCard; sleepCard }
            if isOutdoorSession { sessionMiniMapCard }
            timeInZoneCard
          } else {
            hrHero
            HStack(spacing: 12) { stepsCard; sleepCard }
            weekCard
            historyCard
          }
        }
        .padding(16)
      }
      .safeAreaInset(edge: .bottom) {
        launcherBar
      }
      .background(Color.black.ignoresSafeArea())
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) { dateNavigator }
        ToolbarItem(placement: .topBarTrailing) {
          Button { showDevice = true } label: {
            Image(systemName: "applewatch")
          }
        }
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      feed.refreshAll(selectedDate: selectedDate)
      Task {
        try? await UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .badge, .sound])
      }
      maybeAutoStartHistoricalSync(reason: "app_open")
    }
    .onReceive(refresh) { _ in
      if isToday { feed.refreshAll(selectedDate: selectedDate) }
      relativeTimeTick += 1
    }
    // Auto-sync trigger #2: every BLE transition to "ready" (a fresh link).
    .onChange(of: model.ble.connectionState) { _, newState in
      guard newState == "ready" else { return }
      maybeAutoStartHistoricalSync(reason: "reconnected")
    }
    .onReceive(model.ble.$liveHeartRateBPM) { bpm in
      if workout.isActive, let bpm {
        workout.ingestHeartRate(bpm: bpm)
      }
    }
    .onChange(of: selectedDate) { _, newDate in
      feed.refreshAll(selectedDate: newDate)
    }
    .sheet(isPresented: $showWorkout) {
      WorkoutRecordView(session: workout)
    }
    .sheet(isPresented: $showDevice) { SimpleDeviceSheet() }
    .sheet(isPresented: $sleepSheet) { SleepAnalysisSheet(days: feed.sleepAnalysis) }
    .sheet(isPresented: $showCalendar) { calendarSheet }
  }

  // MARK: auto historical sync (UI-side trigger of the existing engine)
  //
  // At app open AND on every BLE transition to "ready": if connected, no sync
  // running, and the last completed sync is stale (>12 h), start the
  // backfill. The engine re-checks everything itself; double calls are safe.
  private func maybeAutoStartHistoricalSync(reason: String) {
    guard connected else { return }
    if model.ble.isGen4Band {
      guard SyncSection.isStale(model.ble.lastGen4BackfillCompletedAt) else { return }
      model.ble.requestGen4HistoricalBackfillIfNeeded()
      return
    }
    guard !model.ble.isHistoricalSyncing else { return }
    guard SyncSection.isStale(model.ble.lastHistoricalSyncCompletedAt) else { return }
    model.ble.beginHistoricalSync(trigger: "simple_ui_\(reason)", automatic: true)
  }

  // MARK: date navigator (‹ Aujourd'hui › — tap opens the calendar)

  private var dayLabel: String {
    if Calendar.current.isDateInToday(selectedDate) { return "Aujourd'hui" }
    if Calendar.current.isDateInYesterday(selectedDate) { return "Hier" }
    return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  private var dateNavigator: some View {
    HStack(spacing: 18) {
      Button {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
      } label: {
        Image(systemName: "chevron.left")
          .font(.body.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)

      Button { showCalendar = true } label: {
        Text(dayLabel)
          .font(.headline)
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)

      Button {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
      } label: {
        Image(systemName: "chevron.right")
          .font(.body.weight(.semibold))
          .foregroundStyle(isToday ? Color.white.opacity(0.2) : Color.secondary)
      }
      .buttonStyle(.plain)
      .disabled(isToday)
    }
    .frame(maxWidth: .infinity)
  }

  private var calendarSheet: some View {
    NavigationStack {
      DatePicker(
        "Jour",
        selection: Binding(
          get: { selectedDate },
          set: {
            selectedDate = min($0, Date())
            showCalendar = false
          }),
        in: ...Date(),
        displayedComponents: .date)
        .datePickerStyle(.graphical)
        .padding()
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Aujourd'hui") { selectedDate = Date(); showCalendar = false }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("OK") { showCalendar = false }
          }
        }
        .navigationTitle("Choisir un jour")
        .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
  }

  // MARK: status (LIVE / Hors ligne)

  private var connected: Bool {
    let s = model.ble.connectionState.lowercased()
    return s == "ready" || s == "connected"
  }

  private var statusBar: some View {
    HStack(spacing: 10) {
      Circle().fill(connected ? Color.green : Color.red).frame(width: 8, height: 8)
      Text(connected ? "LIVE" : "Hors ligne")
        .font(.subheadline.weight(.bold))
        .tracking(1.2)
        .foregroundStyle(connected ? .white : .secondary)
      Spacer()
      if let pct = model.ble.batteryLevelPercent {
        Label("\(pct)%", systemImage: model.ble.batteryIsCharging == true ? "bolt.fill" : "battery.100")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(model.ble.batteryIsCharging == true ? .yellow : .secondary)
      }
    }
    .padding(.horizontal, 4)
  }


  // MARK: HR hero (idle) — live value when today, day average otherwise

  private var hrHero: some View {
    NavigationLink {
      HRDayDetailView(minutes: feed.hrMinutes.map {
        HRMinute(minute: $0.minute, bpm: $0.bpm, lo: $0.lo, hi: $0.hi, n: $0.n)
      })
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Label("Fréquence cardiaque", systemImage: "heart.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
          Spacer()
          if !isToday {
            Text(dayLabel)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(heroHRText)
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text("bpm").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
          if feed.hrMinutes.count > 1 {
            VStack(alignment: .trailing, spacing: 2) {
              Text("moy \(avgHR) · \(loHR)–\(hiHR)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Text(isToday ? "aujourd'hui" : dayLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
    .buttonStyle(.plain)
  }

  /// Live BPM when the band is streaming and we're on today; otherwise the
  /// selected day's average (honest about what the number is).
  private var heroHRText: String {
    if isToday, let bpm = model.ble.liveHeartRateBPM {
      return String(bpm)
    }
    guard avgHR > 0 else { return "—" }
    return String(avgHR)
  }

  private var avgHR: Int {
    guard !feed.hrMinutes.isEmpty else { return 0 }
    return Int((Double(feed.hrMinutes.map(\.bpm).reduce(0, +)) / Double(feed.hrMinutes.count)).rounded())
  }
  private var loHR: Int { feed.hrMinutes.map(\.lo).min() ?? 0 }
  private var hiHR: Int { feed.hrMinutes.map(\.hi).max() ?? 0 }

  // MARK: steps + sleep grid

  private var stepsCard: some View {
    NavigationLink {
      StepsDayDetailView(minutes: feed.steps.map { StepMinute(minute: $0.minute, steps: $0.steps) })
    } label: {
      smallCard(icon: "shoeprints.fill", tint: .green, title: "Pas",
                value: feed.stepsTotal.map { $0.formatted() } ?? "—",
                unit: feed.stepsTotal == nil ? "" : "pas")
    }
    .buttonStyle(.plain)
  }

  private var sleepCard: some View {
    Button { sleepSheet = true } label: {
      smallCard(icon: "bed.double.fill", tint: .purple, title: "Sommeil",
                value: lastNightDuration, unit: lastNightDuration == "--" ? "" : "")
    }
    .buttonStyle(.plain)
  }

  private var lastNightDuration: String {
    guard let n = feed.nights.last, let d = n.duration_min else { return "--" }
    return String(format: "%dh%02d", d / 60, d % 60)
  }

  // MARK: cette semaine (sleep bars of the current week + session count)

  private var weekCard: some View {
    Button { sleepSheet = true } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label("Cette semaine", systemImage: "chart.bar.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.purple)
          Spacer()
          Text("\(weekSessions.count) séances · \(SessionStats.ms(weekSessionSeconds))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        HStack(alignment: .bottom, spacing: 10) {
          ForEach(weekDays, id: \.self) { day in
            let night = nightsByDay[day]
            let minutes = night?.duration_min ?? 0
            let height = CGFloat(max(4, min(52, Double(minutes) / 600.0 * 52)))
            VStack(spacing: 4) {
              RoundedRectangle(cornerRadius: 4)
                .fill(dayIsToday(day) ? Color.blue : Color.purple.opacity(0.8))
                .frame(width: 16, height: height)
              Text(dayLetter(day))
                .font(.caption2)
                .foregroundStyle(dayIsToday(day) ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
    .buttonStyle(.plain)
  }

  private var weekDays: [Date] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    guard let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [today] }
    return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
  }

  private static let nightDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private var nightsByDay: [Date: SimpleSleepNight] {
    var out: [Date: SimpleSleepNight] = [:]
    for n in feed.nights {
      if let d = Self.nightDayFormatter.date(from: String(n.date.prefix(10))) {
        out[Calendar.current.startOfDay(for: d)] = n
      }
    }
    return out
  }

  private func dayLetter(_ day: Date) -> String {
    day.formatted(.dateTime.weekday(.narrow))
  }

  private func dayIsToday(_ day: Date) -> Bool {
    Calendar.current.isDateInToday(day)
  }

  private var weekSessions: [SimpleWorkout] {
    let cal = Calendar.current
    let days = Set(weekDays.map { cal.startOfDay(for: $0) })
    return feed.workouts.filter { w in
      guard let d = Self.workoutDate(w.started_at) else { return false }
      return days.contains(cal.startOfDay(for: d))
    }
  }

  private var weekSessionSeconds: Int {
    weekSessions.reduce(0) { $0 + $1.duration_s }
  }

  private static func workoutDate(_ iso: String) -> Date? {
    ISO8601DateFormatter().date(from: iso)
  }

  // MARK: historique d'entraînement (3 last sessions up to the selected day)

  private var historySessions: [SimpleWorkout] {
    let endOfDay = Calendar.current.startOfDay(for: selectedDate).addingTimeInterval(86_400)
    return feed.workouts
      .filter { w in Self.workoutDate(w.started_at).map { $0 < endOfDay } ?? false }
      .suffix(3)
      .reversed()
  }

  private var historyCard: some View {
    NavigationLink {
      WorkoutHistoryView()
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Label("Historique d'entraînement", systemImage: "figure.run")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.red)
          .padding(.bottom, 4)
        if historySessions.isEmpty {
          Text(isToday ? "Pas encore de séance — lance la première !" : "Pas de séance ce jour-là.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        } else {
          ForEach(Array(historySessions.enumerated()), id: \.element.id) { index, w in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(WorkoutTypeFormatter.displayName(for: workoutType(w).rawValue))
                  .font(.subheadline.weight(.medium))
                Text(workoutSubtitle(w))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            if index < historySessions.count - 1 {
              Rectangle().fill(Color(.systemGray5)).frame(height: 0.5)
            }
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
    .buttonStyle(.plain)
  }

  private func workoutType(_ w: SimpleWorkout) -> SimpleWorkoutType {
    SimpleWorkoutType(rawValue: w.type) ?? .other
  }

  private func workoutSubtitle(_ w: SimpleWorkout) -> String {
    var parts = [WorkoutTypeFormatter.relativeTimeText(from: w.started_at),
                 WorkoutTypeFormatter.durationText(w.duration_s)]
    if let bpm = w.avg_bpm { parts.append("FC moy \(bpm)") }
    return parts.joined(separator: " · ")
  }

  // MARK: session mode (workout actif — la maison devient salle de contrôle)

  private var isOutdoorSession: Bool {
    workout.workoutType == .run || workout.workoutType == .bike
  }

  private var sessionHero: some View {
    Button { showWorkout = true } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label("Fréquence cardiaque", systemImage: "heart.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
          Spacer()
          Text("SÉANCE · \(sessionBadge)")
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.blue))
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(model.ble.liveHeartRateBPM.map(String.init) ?? "—")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text("bpm").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("FC moy \(workout.avgBPM.map(String.init) ?? "—")")
            Text("FC max \(workout.maxBPM.map(String.init) ?? "—")")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        sessionCurve
          .frame(height: 54)
        sessionStatsRow
        zoneBar
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 18)
          .fill(Color(.secondarySystemBackground))
          .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue, lineWidth: 1))
      )
    }
    .buttonStyle(.plain)
  }

  private var sessionBadge: String {
    (workout.workoutType?.displayName ?? "séance").uppercased()
  }

  /// Live HR curve (last 5 minutes of samples).
  @ViewBuilder private var sessionCurve: some View {
    let values = SessionStats.curveValues(samples: workout.samples)
    if values.count >= 2 {
      GeometryReader { proxy in
        Canvas { ctx, size in
          var path = Path()
          let n = values.count
          for (i, v) in values.enumerated() {
            let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1),
                            y: size.height * (1 - CGFloat(v)))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
          }
          ctx.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
      }
    } else {
      Text("la courbe apparaît après quelques secondes…")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: 54)
    }
  }

  private var sessionStatsRow: some View {
    HStack(alignment: .top) {
      sessionStat("Durée", value: SessionStats.hms(workout.durationSeconds))
      if isOutdoorSession {
        sessionStat("Distance", value: gps.distanceKm.map { String(format: "%.1f km", $0) } ?? "—")
        sessionStat("Allure", value: gps.paceText ?? "—")
      }
      sessionStat("Kcal", value: "\(SessionStats.kcal(avgBPM: workout.avgBPM, seconds: workout.durationSeconds))")
    }
  }

  private func sessionStat(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var zoneBar: some View {
    let secs = SessionStats.zoneSeconds(samples: workout.samples, hrMax: hrMax)
    let total = max(secs.reduce(0, +), 1)
    let colors: [Color] = [.gray, .indigo, .green, .yellow, .red]
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 3) {
        ForEach(0..<5, id: \.self) { i in
          RoundedRectangle(cornerRadius: 4)
            .fill(colors[i].opacity(secs[i] > 0 ? 0.9 : 0.25))
            .frame(height: 20)
            .frame(maxWidth: .infinity)
            .overlay(Text("Z\(i + 1)").font(.system(size: 9, weight: .bold)))
        }
      }
      Text("Temps par zone · \(SessionStats.ms(workout.durationSeconds)) total")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var hrMax: Int { UserDefaults.standard.object(forKey: "hrMax") as? Int ?? 190 }

  /// Compact GPS map ("plein écran ›" opens the full session view).
  @ViewBuilder private var sessionMiniMapCard: some View {
    Button { showWorkout = true } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("CARTE · GPS")
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(.secondary)
          Spacer()
          Text("plein écran ›")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
        }
        WorkoutMapView(track: gps.track, interactive: false)
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 12))
        HStack(spacing: 24) {
          Text(gps.distanceKm.map { String(format: "%.1f km", $0) } ?? "—")
            .font(.system(size: 20, weight: .bold, design: .rounded))
          Text(gps.paceText ?? "—")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
          if gps.elevationGainM > 0 {
            Label(String(format: "+%.0f m", gps.elevationGainM), systemImage: "arrow.up.right")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
    .buttonStyle(.plain)
  }

  private var timeInZoneCard: some View {
    let secs = SessionStats.zoneSeconds(samples: workout.samples, hrMax: hrMax)
    let colors: [Color] = [.gray, .indigo, .green, .yellow, .red]
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Temps par zone")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(SessionStats.hms(workout.durationSeconds)) total")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 6) {
        ForEach(0..<5, id: \.self) { i in
          Text("Z\(i + 1) \(SessionStats.ms(secs[i]))")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(colors[i].opacity(secs[i] > 0 ? 0.9 : 0.25)))
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }

  // MARK: sticky bottom bar
  // Pendant une séance: Pause | durée+FC | Arrêter. Sinon: Course | + | Muscu.

  private var launcherBar: some View {
    Group {
      if workout.isActive {
        activeWorkoutBar
      } else {
        HStack(spacing: 0) {
          launcherButton(type: .run)
          plusButton
          launcherButton(type: .gym)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 6)
    .background(.ultraThinMaterial)
  }

  /// just Pause | Stop — two big equal buttons.
  private var activeWorkoutBar: some View {
    HStack(spacing: 12) {
      Button {
        workout.isPaused ? workout.resume() : workout.pause()
      } label: {
        Label(workout.isPaused ? "Reprendre" : "Pause",
              systemImage: workout.isPaused ? "play.fill" : "pause.fill")
          .font(.headline)
          .foregroundStyle(.orange)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
      }
      .buttonStyle(.plain)

      Button {
        gps.stop()
        workout.stop()
      } label: {
        Label("Arrêter", systemImage: "stop.fill")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(RoundedRectangle(cornerRadius: 16).fill(.red))
      }
      .buttonStyle(.plain)
    }
  }

  private func launcherButton(type: SimpleWorkoutType) -> some View {
    Button {
      if type == .run || type == .bike { gps.start() }
      workout.start(type: type)
      showWorkout = true
    } label: {
      VStack(spacing: 4) {
        Image(systemName: type.iconName)
          .font(.title3.weight(.semibold))
        Text(type.displayName)
          .font(.caption.weight(.semibold))
      }
      .foregroundStyle(.blue)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
    .disabled(workout.isActive)
  }

  private var plusButton: some View {
    Menu {
      ForEach([SimpleWorkoutType.bike, .swim, .other]) { t in
        Button {
          if t == .bike { gps.start() }
          workout.start(type: t)
          showWorkout = true
        } label: {
          Label(t.displayName, systemImage: t.iconName)
        }
      }
    } label: {
      VStack(spacing: 4) {
        Image(systemName: "plus.circle.fill")
          .font(.title3.weight(.semibold))
        Text("Plus")
          .font(.caption.weight(.semibold))
      }
      .foregroundStyle(.blue)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
    }
    .disabled(workout.isActive)
  }

  private func smallCard(icon: String, tint: Color, title: String,
                         value: String, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value)
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        if !unit.isEmpty {
          Text(unit).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }
}

// MARK: - Device sheet (connect / reconnect / forget)
// MARK: - Device sheet (connect / reconnect / forget)

private struct SimpleDeviceSheet: View {
  @EnvironmentObject private var model: GooseAppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Bracelet") {
          HStack {
            Text("État")
            Spacer()
            Text(model.ble.connectionState).foregroundStyle(.secondary)
          }
          if let pct = model.ble.batteryLevelPercent {
            HStack {
              Text("Batterie")
              Spacer()
              Text("\(pct)%").foregroundStyle(.secondary)
            }
          }
          // Only meaningful when a band is actually remembered — after
          // "Oublier" it would just spin on nothing.
          if model.ble.rememberedDeviceDescription != "none" {
            Button("Reconnecter") { model.ble.reconnectRemembered() }
          }
          Button("Oublier ce bracelet", role: .destructive) { model.ble.forgetRememberedDevice() }
        }
        // Réutilise les fonctions existantes de ConnectionView (aucune logique BLE nouvelle):
        // startScan / select / connectSelected. Auto-stop après 12 s.
        Section("Associer un bracelet") {
          Button {
            model.ble.startScan()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
              if model.ble.isScanning { model.ble.stopScan() }
            }
          } label: {
            HStack {
              if model.ble.isScanning {
                ProgressView()
                  .controlSize(.small)
                Text("Scan en cours…")
              } else {
                Text("Scanner")
              }
              Spacer()
              if model.ble.isScanning {
                Text("\(model.ble.scanNeighborCount) vu(s)")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .disabled(model.ble.isScanning)
          if model.ble.isScanning {
            Text("Recherche active (12 s max)… \(model.ble.scanNeighborCount) appareils à portée (pas encore de WHOOP)")
              .font(.footnote).foregroundStyle(.secondary)
          } else if model.ble.discoveredDevices.isEmpty && model.ble.scanNeighborCount > 0 {
            Text("Scan terminé: \(model.ble.scanNeighborCount) appareils vus, aucun WHOOP. Cycle chargeur puis re-scanne.")
              .font(.footnote).foregroundStyle(.orange)
          }
          ForEach(model.ble.discoveredDevices, id: \.id) { device in
            Button {
              model.ble.select(device)
              model.ble.connectSelected()
            } label: {
              HStack {
                Text(device.name.isEmpty ? "WHOOP" : device.name)
                Spacer()
                if model.ble.connectionState == "connecting" || model.ble.connectionState == "discovering" {
                  ProgressView().controlSize(.small)
                }
                Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        SyncSection()
        Section("À propos") {
          Text("Goose lit ton bracelet WHOOP en local et stocke tout sur ton serveur. Les métriques sont les nôtres — jamais celles de WHOOP.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Réglages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
    }
    .preferredColorScheme(.dark)
  }
}

// MARK: - Sleep sheet (7 nights)

private struct SleepAnalysisSheet: View {
  let days: [SimpleSleepAnalysisDay]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if days.isEmpty {
            Text("Pas encore assez de données — la première nuit mesurée apparaîtra ici.")
              .foregroundStyle(.secondary)
              .padding(.top, 30)
          }
          ForEach(days.reversed()) { day in
            if let st = day.sleep_stages {
              nightCard(date: day.date, st: st)
            }
          }
        }
        .padding(16)
      }
      .background(Color.black.ignoresSafeArea())
      .navigationTitle("Analyse du sommeil")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
    }
    .preferredColorScheme(.dark)
  }

  private func nightCard(date: String, st: SimpleSleepAnalysisDay.Stages) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Nuit de \(nightLabel(date))")
          .font(.subheadline.weight(.semibold))
        Spacer()
        if let eff = st.efficiency_pct {
          Text(String(format: "%.0f %%", eff))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(efficiencyColor(eff).opacity(0.25)))
            .foregroundStyle(efficiencyColor(eff))
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(tstText(st.tst_min))
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .monospacedDigit()
        Text("de sommeil").font(.subheadline).foregroundStyle(.secondary)
      }

      HStack(spacing: 2) {
        stageSeg(color: .indigo, pct: st.deep_pct)
        stageSeg(color: .blue, pct: st.rem_pct)
        stageSeg(color: Color(.systemGray3), pct: st.light_pct)
        stageSeg(color: .orange, pct: st.wake_pct)
      }
      .frame(height: 10)
      .clipShape(Capsule())

      HStack(spacing: 12) {
        legendDot(.indigo, "Profond \(pctText(st.deep_pct))")
        legendDot(.blue, "REM \(pctText(st.rem_pct))")
        legendDot(Color(.systemGray3), "Léger \(pctText(st.light_pct))")
        legendDot(.orange, "Éveil \(pctText(st.wake_pct))")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)

      if let t0 = st.t0_epoch, let runs = st.runs, !runs.isEmpty {
        SleepHypnogram(runs: runs, t0Epoch: t0)
        HStack {
          Text(clockLabel(t0))
          Spacer()
          Text(clockLabel(t0 + runs.reduce(0) { $0 + $1.sec }))
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }

      Divider()

      HStack(alignment: .top) {
        detail("Endormissement", st.sol_min.map { String(format: "%.0f min", $0) } ?? "—")
        detail("Réveils", "\(st.disturbances ?? 0)")
        detail("Éveil nocturne", st.waso_min.map { String(format: "%.0f min", $0) } ?? "—")
        detail("Au lit", st.tib_min.map { tstText($0) } ?? "—")
      }

      if st.rem_measured == false {
        Text("REM estimé sans RMSSD — moins fiable cette nuit.")
          .font(.caption2).foregroundStyle(.orange)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }

  private func stageSeg(color: Color, pct: Double?) -> some View {
    Rectangle().fill(color.opacity((pct ?? 0) > 0 ? 1 : 0.15))
      .frame(maxWidth: .infinity)
  }

  private func legendDot(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(label)
    }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func tstText(_ minutes: Double?) -> String {
    guard let m = minutes else { return "--" }
    return String(format: "%dh%02d", Int(m) / 60, Int(m) % 60)
  }

  private func pctText(_ p: Double?) -> String {
    guard let p else { return "—" }
    return String(format: "%.0f %%", p)
  }

  private func efficiencyColor(_ eff: Double) -> Color {
    eff >= 85 ? .green : eff >= 70 ? .orange : .red
  }

  private func nightLabel(_ iso: String) -> String {
    return String(iso.prefix(10)).split(separator: "-").suffix(2).joined(separator: "/")
  }

  private func clockLabel(_ epoch: Double) -> String {
    Date(timeIntervalSince1970: epoch).formatted(.dateTime.hour().minute())
  }
}

struct SyncBannerHost: View {
  @ObservedObject var ble: GooseBLEClient
  @State private var showSyncProgressDetail = false

  var body: some View {
    Group {
      if let toast = ble.syncToast {
        if toast.phase == .syncing, let progress = ble.historySyncProgressSnapshot {
          Button {
            showSyncProgressDetail = true
          } label: {
            HistorySyncProgressToastView(snapshot: progress)
          }
          .buttonStyle(.plain)
        } else {
          Button {
            if toast.phase == .failed, let failure = ble.lastSyncFailure {
              ble.syncFailureSheet = failure
            }
          } label: {
            SyncStatusToastView(toast: toast)
          }
          .buttonStyle(.plain)
          .allowsHitTesting(toast.phase == .failed)
        }
      }
    }
    .animation(.easeInOut(duration: 0.25), value: ble.syncToast?.phase)
    .sheet(item: $ble.syncFailureSheet) { failure in
      SyncFailureSheet(failure: failure)
    }
    .sheet(isPresented: $showSyncProgressDetail) {
      HistorySyncProgressDetailSheet(ble: ble)
    }
  }
}

private struct SyncFailureSheet: View {
  let failure: GooseSyncFailure
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text(failure.title)
              .font(.title2.bold())
            Text(failure.occurredAt, style: .date)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          }

          Text(failure.message)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(20)
      }
      .gooseScreenBackground()
      .navigationTitle("Sync Error")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

private struct SyncStatusToastView: View {
  let toast: GooseSyncToast
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 8) {
      SyncToastIcon(systemImage: systemImage, tint: tint, isSyncing: toast.phase == .syncing)

      Text(toast.title)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      if toast.phase == .failed {
        Image(systemName: "chevron.up")
          .font(.system(size: 12, weight: .black))
          .foregroundStyle(tint)
      }
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 8)
    .fixedSize(horizontal: true, vertical: false)
    .background {
      Capsule(style: .continuous)
        .fill(toastFill)
    }
    .overlay {
      Capsule(style: .continuous)
        .strokeBorder(tint, lineWidth: 1.5)
    }
    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var systemImage: String {
    switch toast.phase {
    case .syncing: "arrow.triangle.2.circlepath"
    case .synced: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  private var tint: Color {
    switch toast.phase {
    case .syncing: Color(red: 0.18, green: 0.48, blue: 0.95)
    case .synced: Color(red: 0.20, green: 0.68, blue: 0.27)
    case .failed: Color(red: 0.95, green: 0.23, blue: 0.18)
    }
  }

  private var toastFill: Color {
    if colorScheme == .dark {
      switch toast.phase {
      case .syncing:
        Color(red: 0.07, green: 0.16, blue: 0.25)
      case .synced:
        Color(red: 0.07, green: 0.20, blue: 0.12)
      case .failed:
        Color(red: 0.26, green: 0.10, blue: 0.09)
      }
    } else {
      switch toast.phase {
      case .syncing:
        Color(red: 0.84, green: 0.91, blue: 1.0)
      case .synced:
        Color(red: 0.86, green: 0.96, blue: 0.88)
      case .failed:
        Color(red: 1.0, green: 0.88, blue: 0.86)
      }
    }
  }

  private var accessibilityText: String {
    guard !toast.detail.isEmpty else {
      return toast.title
    }
    return "\(toast.title), \(toast.detail)"
  }
}

private struct SyncToastIcon: View {
  let systemImage: String
  let tint: Color
  let isSyncing: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if isSyncing && !reduceMotion {
      TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
        symbol(rotationDegrees: rotationDegrees(for: context.date))
      }
    } else {
      symbol(rotationDegrees: 0)
    }
  }

  private func symbol(rotationDegrees: Double) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: 14, weight: .black))
      .frame(width: 18, height: 18)
      .foregroundStyle(tint)
      .rotationEffect(.degrees(isSyncing ? rotationDegrees : 0))
      .transaction { transaction in
        transaction.disablesAnimations = true
        transaction.animation = nil
      }
  }

  private func rotationDegrees(for date: Date) -> Double {
    let duration = 0.95
    let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
    return progress * 360
  }
}

/// Hypnogramme de nuit : 4 couloirs (Profond / REM / Léger / Éveil), chaque
/// run du stager dessiné à sa hauteur sur l'axe du temps. WHOOP-style.
struct SleepHypnogram: View {
  let runs: [SimpleSleepAnalysisDay.Stages.Run]
  let t0Epoch: Double

  private struct Lane {
    let stage: String
    let color: Color
    let label: String
  }

  private var lanes: [Lane] {
    [
      Lane(stage: "deep", color: .indigo, label: "P"),
      Lane(stage: "rem", color: .blue, label: "R"),
      Lane(stage: "light", color: Color(.systemGray2), label: "L"),
      Lane(stage: "wake", color: .orange, label: "É"),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      GeometryReader { proxy in
        let total = max(runs.reduce(0) { $0 + $1.sec }, 1)
        let laneH = proxy.size.height / CGFloat(lanes.count)
        Canvas { ctx, size in
          // fond des couloirs
          for (i, lane) in lanes.enumerated() {
            let y = size.height - CGFloat(i + 1) * laneH
            ctx.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: laneH - 2)),
                     with: .color(lane.color.opacity(0.08)))
          }
          var x: CGFloat = 0
          for run in runs {
            let w = size.width * CGFloat(run.sec / total)
            if let i = lanes.firstIndex(where: { $0.stage == run.stage }) {
              let y = size.height - CGFloat(i + 1) * laneH
              ctx.fill(Path(CGRect(x: x, y: y + 1, width: max(w, 1), height: laneH - 2)),
                       with: .color(lanes[i].color))
            }
            x += w
          }
        }
      }
      .frame(height: 68)
      HStack(spacing: 10) {
        ForEach(lanes, id: \.stage) { lane in
          HStack(spacing: 3) {
            Circle().fill(lane.color).frame(width: 5, height: 5)
            Text(lane.label)
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func clockLabel(_ epoch: Double) -> String {
    Date(timeIntervalSince1970: epoch).formatted(.dateTime.hour().minute())
  }
}
