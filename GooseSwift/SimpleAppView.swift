import SwiftUI
import UserNotifications

/// SimpleAppView — the whole app on ONE screen (branch `simple`).
///
/// Design: exactly the owner's four metrics (FC, pas, sommeil, température
/// cutanée), everything read from the VPS (single source of truth), French
/// labels, honest "--" when no data. The BLE engine (GooseBLEClient) is kept
/// as-is — it's field-proven; only the UI is rebuilt from scratch.

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

struct SimpleDailyDay: Decodable {
  let date: String
  let steps: Int?
  let skin_temp: SkinTemp?
  struct SkinTemp: Decodable {
    let deviation_c: Double?
  }
}

@MainActor
final class SimpleVPSFeed: ObservableObject {
  @Published var hrMinutes: [SimpleHRMinute] = []
  @Published var hrLoaded = false
  @Published var steps: [SimpleStepMinute] = []
  @Published var stepsTotal: Int?
  @Published var nights: [SimpleSleepNight] = []
  @Published var lastTempDeviation: Double?
  @Published var lastSync: Date?

  private let base = "https://latenightgames.fr/whoop/ingest"
  private let token = Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""
  private let tz = TimeZone.current.identifier

  func refreshAll() {
    get("/hr/minutely?tz=\(tz)") { [weak self] (r: HRPayload?) in
      self?.hrMinutes = r?.minutes ?? []
      self?.hrLoaded = true
    }
    get("/steps/minutely?tz=\(tz)") { [weak self] (r: StepsPayload?) in
      self?.steps = r?.minutes ?? []
      self?.stepsTotal = r?.total
    }
    get("/sleep/nights?days=7&tz=\(tz)") { [weak self] (r: NightsPayload?) in
      self?.nights = r?.nights ?? []
    }
    get("/metrics/daily?days=7&tz=\(tz)") { [weak self] (r: DailyPayload?) in
      self?.lastTempDeviation = r?.days.last { $0.skin_temp?.deviation_c != nil }?.skin_temp?.deviation_c
    }
    Task { @MainActor in self?.lastSync = Date() }
  }

  private struct HRPayload: Decodable { let minutes: [SimpleHRMinute] }
  private struct StepsPayload: Decodable { let minutes: [SimpleStepMinute]; let total: Int }
  private struct NightsPayload: Decodable { let nights: [SimpleSleepNight] }
  private struct DailyPayload: Decodable { let days: [SimpleDailyDay] }

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
  @State private var showDevice = false
  @State private var sleepSheet = false
  @State private var tempSheet = false
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          statusBar
          hrHero
          HStack(spacing: 12) { stepsCard; sleepCard }
          tempCard
        }
        .padding(16)
      }
      .background(Color.black.ignoresSafeArea())
      .navigationTitle("Goose")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showDevice = true } label: {
            Image(systemName: "applewatch")
          }
        }
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      feed.refreshAll()
      Task {
        try? await UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .badge, .sound])
      }
    }
    .onReceive(refresh) { _ in feed.refreshAll() }
    .sheet(isPresented: $showDevice) { SimpleDeviceSheet() }
    .sheet(isPresented: $sleepSheet) { SimpleNightsSheet(nights: feed.nights) }
    .sheet(isPresented: $tempSheet) { SimpleTempSheet(deviation: feed.lastTempDeviation) }
  }

  // MARK: status

  private var connected: Bool {
    let s = model.ble.connectionState.lowercased()
    return s == "ready" || s == "connected"
  }

  private var statusBar: some View {
    HStack(spacing: 10) {
      Circle().fill(connected ? Color.green : Color.red).frame(width: 8, height: 8)
      Text(connected ? "Bracelet connecté" : "Bracelet déconnecté")
        .font(.subheadline.weight(.semibold))
      Spacer()
      if let pct = model.ble.batteryLevelPercent {
        Label("\(pct)%", systemImage: model.ble.batteryIsCharging == true ? "bolt.fill" : "battery.100")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(model.ble.batteryIsCharging == true ? .yellow : .secondary)
      }
    }
    .padding(.horizontal, 4)
  }

  // MARK: HR hero (live BLE value, range from server)

  private var hrHero: some View {
    NavigationLink {
      HRDayDetailView(minutes: feed.hrMinutes.map {
        HRMinute(minute: $0.minute, bpm: $0.bpm, lo: $0.lo, hi: $0.hi, n: $0.n)
      })
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        Label("Fréquence cardiaque", systemImage: "heart.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.red)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(model.ble.liveHeartRateBPM.map(String.init) ?? "—")
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text("bpm").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
          if feed.hrMinutes.count > 1 {
            VStack(alignment: .trailing, spacing: 2) {
              Text("moy \(avgHR) · \(loHR)–\(hiHR)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Text("aujourd'hui").font(.caption2).foregroundStyle(.tertiary)
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

  // MARK: temp

  private var tempCard: some View {
    Button { tempSheet = true } label: {
      HStack {
        smallCard(icon: "thermometer.medium", tint: .orange, title: "Température cutanée",
                  value: tempText, unit: tempText == "--" ? "" : "°C")
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
    }
    .buttonStyle(.plain)
  }

  private var tempText: String {
    guard let d = feed.lastTempDeviation else { return "--" }
    return String(format: "%+.1f", d)
  }

  private func smallCard(icon: String, tint: Color, title: String, value: String, unit: String) -> some View {
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
          Button("Reconnecter") { model.ble.reconnectRemembered() }
          Button("Oublier ce bracelet", role: .destructive) { model.ble.forgetRememberedDevice() }
        }
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

private struct SimpleNightsSheet: View {
  let nights: [SimpleSleepNight]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if nights.isEmpty {
          Text("Pas encore de nuit enregistrée.")
            .foregroundStyle(.secondary)
        }
        ForEach(nights.reversed()) { n in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(nightLabel(n.date)).font(.headline)
              if let hr = n.avg_hr {
                Text("FC moyenne \(Int(hr)) bpm").font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            if let d = n.duration_min {
              Text(String(format: "%dh%02d", d / 60, d % 60))
                .font(.title3.bold().monospacedDigit())
            } else {
              Text("--").foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Sommeil — 7 nuits")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
    }
    .preferredColorScheme(.dark)
  }

  private func nightLabel(_ iso: String) -> String {
    String(iso.prefix(10)).split(separator: "-").suffix(2).joined(separator: "/")
  }
}

// MARK: - Temp sheet

private struct SimpleTempSheet: View {
  let deviation: Double?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let d = deviation {
            Text(String(format: "%+.1f °C", d))
              .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Écart vs ta baseline des 14 dernières nuits (notre calcul, pas celui de WHOOP).")
              .font(.footnote).foregroundStyle(.secondary)
          } else {
            Text("Pas encore assez de nuits pour calculer un écart.")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Température")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
    }
    .preferredColorScheme(.dark)
  }
}
