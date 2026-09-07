import SwiftUI

/// Full-screen workout recording: big live timer, live HR with z1–z5 zone bar,
/// running avg/min/max, Pause + red Stop. HR comes live from the BLE client;
/// samples are compiled by SimpleWorkoutSession (1/sec, paused excluded).
struct WorkoutRecordView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var session: SimpleWorkoutSession
  @Environment(\.dismiss) private var dismiss
  private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  /// HRmax default 190 — configurable via UserDefaults "hrMax".
  private var hrMax: Int {
    UserDefaults.standard.object(forKey: "hrMax") as? Int ?? 190
  }

  private var liveBPM: Int? {
    guard let bpm = model.ble.liveHeartRateBPM,
          let at = model.ble.liveHeartRateUpdatedAt,
          Date().timeIntervalSince(at) < 15 else { return nil }
    return bpm
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          timerCard
          hrCard
          statsRow
          controls
        }
        .padding(16)
      }
      .background(Color.black.ignoresSafeArea())
      .navigationTitle(session.workoutType?.displayName ?? "Séance")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Réduire") { dismiss() }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  // MARK: timer

  private var timerCard: some View {
    VStack(spacing: 4) {
      Text(timeString(session.durationSeconds))
        .font(.system(size: 58, weight: .bold, design: .rounded))
        .monospacedDigit()
      Text(session.isPaused ? "en pause" : "en cours · \(startTimeLabel)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }

  private var startTimeLabel: String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return "début \(f.string(from: Date().addingTimeInterval(-Double(session.durationSeconds))))"
  }

  // MARK: live HR

  private var hrCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("FC maintenant", systemImage: "heart.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.red)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(liveBPM.map(String.init) ?? "—")
          .font(.system(size: 62, weight: .bold, design: .rounded))
          .monospacedDigit()
        Text("bpm").font(.subheadline).foregroundStyle(.secondary)
        Spacer()
        Text("zone \(zoneName)")
          .font(.headline)
          .foregroundStyle(zoneColor)
      }
      zoneBar
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }

  private var zoneBar: some View {
    GeometryReader { proxy in
      let zones: [(Double, Color)] = [
        (0.6, .green), (0.7, .yellow), (0.8, .orange), (0.9, Color(red: 1, green: 0.35, blue: 0.2)), (1.01, .red)
      ]
      ZStack(alignment: .leading) {
        HStack(spacing: 3) {
          ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
            Capsule().fill(z.1.opacity(0.85)).frame(height: 8)
          }
        }
        if let bpm = liveBPM {
          let frac = min(max(Double(bpm) / Double(hrMax), 0), 1)
          Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .offset(x: proxy.size.width * frac - 7)
        }
      }
    }
    .frame(height: 16)
  }

  private var zoneName: String {
    guard let bpm = liveBPM else { return "—" }
    let f = Double(bpm) / Double(hrMax)
    switch f {
    case ..<0.6: return "z1"
    case ..<0.7: return "z2"
    case ..<0.8: return "z3"
    case ..<0.9: return "z4"
    default: return "z5"
    }
  }

  private var zoneColor: Color {
    switch zoneName {
    case "z1": return .green
    case "z2": return .yellow
    case "z3": return .orange
    case "z4": return Color(red: 1, green: 0.35, blue: 0.2)
    default: return .red
    }
  }

  // MARK: stats + controls

  private var statsRow: some View {
    HStack(spacing: 10) {
      statBox("Moy", session.avgBPM.map(String.init) ?? "—")
      statBox("Max", session.maxBPM.map(String.init) ?? "—")
      statBox("Min", session.minBPM.map(String.init) ?? "—")
    }
  }

  private func statBox(_ label: String, _ value: String) -> some View {
    VStack(spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.title2.bold().monospacedDigit())
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
  }

  private var controls: some View {
    VStack(spacing: 8) {
      Button {
        if session.isPaused { session.resume() } else { session.pause() }
      } label: {
        Text(session.isPaused ? "Reprendre" : "Pause")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemBackground)))
      }
      .buttonStyle(.plain)

      Button {
        session.stop()
        dismiss()
      } label: {
        Label("Arrêter", systemImage: "stop.fill")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(RoundedRectangle(cornerRadius: 14).fill(.red))
      }
      .buttonStyle(.plain)
    }
  }

  private func timeString(_ s: Int) -> String {
    String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
  }
}
