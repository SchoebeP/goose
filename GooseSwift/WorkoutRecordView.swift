import SwiftUI

/// Full-screen workout recording: big live timer, live HR with z1–z5 zone bar,
/// running avg/min/max, Pause + red Stop. HR comes live from the BLE client;
/// samples are compiled by SimpleWorkoutSession (1/sec, paused excluded).
///
/// LOT 1 (animations): FC card expands on appear, heart pulses at the real
/// bpm rate, zone halo tints the screen, zone cursor already slides (kept).
/// LOT 2 (data): live 5-min HR curve, kcal estimate, GPS distance/pace for runs.
struct WorkoutRecordView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var session: SimpleWorkoutSession
  @Environment(\.dismiss) private var dismiss
  private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  /// LOT 1: card-expansion spring state.
  @State private var expanded = false
  /// LOT 1: heart pulse phase driver.
  @State private var heartBeat = false
  /// LOT 2: GPS tracker (only started for runs).
  @ObservedObject private var gps = WorkoutGPSTracker.shared

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

  private var isRun: Bool { session.workoutType == .run }

  /// LOT 2: kcal estimate (linear HR model, same constant as the VPS webhook —
  /// ~7.5 kcal/min at 150 bpm). Honest: labelled "est.".
  private var kcalEstimate: Int {
    let avg = Double(session.avgBPM ?? liveBPM ?? 0)
    guard avg > 0 else { return 0 }
    let perMin = max(0.0733 * avg - 3.5, 0)
    return Int((perMin * Double(session.durationSeconds) / 60).rounded())
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          heroCard          // timer + big HR + zone bar
          if isRun { mapCard }
          statsGrid
          if isRun { splitsCard }
          controls
        }
        .padding(16)
      }
      .background(zoneHalo.ignoresSafeArea())
      .background(Color.black.ignoresSafeArea())
      .navigationTitle(session.workoutType?.displayName ?? "Séance")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Réduire") {
            gps.stop()
            dismiss()
          }
        }
      }
      .onAppear {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { expanded = true }
      }
      .onReceive(ticker) { _ in
        // LOT 1: drive the heart pulse once per live beat interval.
        if let bpm = liveBPM, bpm > 30 {
          let interval = 60.0 / Double(bpm)
          if Date().timeIntervalSince(lastPulseAt) >= interval {
            lastPulseAt = Date()
            heartBeat.toggle()
          }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  /// LOT 1: last time the heart pulsed (to pace it at the real bpm).
  @State private var lastPulseAt: Date = .distantPast

  /// LOT 1: subtle radial tint behind everything, colored by current zone.
  private var zoneHalo: some View {
    ZStack {
      Color.black
      RadialGradient(
        colors: [zoneColor.opacity(0.12), .clear],
        center: .top, startRadius: 40, endRadius: 480)
        .animation(.easeInOut(duration: 0.6), value: zoneName)
    }
  }

  // MARK: hero (LOT UI v3 — timer + FC fusionnés en une carte)

  /// LOT UI v3: ONE hero card — workout type + big pulsing heart + giant bpm
  /// as the visual anchor, timer + zone inline, zone bar and live curve below.
  private var heroCard: some View {
    VStack(spacing: 14) {
      // header row: workout type + start time
      HStack {
        Label(session.workoutType?.displayName ?? "Séance",
              systemImage: session.workoutType == .run ? "figure.run" :
                           session.workoutType == .gym ? "dumbbell.fill" : "figure.mix")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text(session.isPaused ? "en pause" : startTimeLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      // the anchor: pulsing heart + giant bpm + zone, one line
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "heart.fill")
          .foregroundStyle(.red)
          .font(.system(size: 40))
          .scaleEffect(heartBeat && liveBPM != nil ? 1.15 : 1.0)
          .animation(.easeInOut(duration: pulseHalfSeconds), value: heartBeat)
        Text(liveBPM.map(String.init) ?? "—")
          .font(.system(size: 88, weight: .bold, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(.easeOut(duration: 0.3), value: liveBPM)
        VStack(alignment: .leading, spacing: 2) {
          Text("bpm").font(.subheadline).foregroundStyle(.secondary)
          Text("zone \(zoneName)")
            .font(.headline)
            .foregroundStyle(zoneColor)
            .animation(.easeInOut(duration: 0.4), value: zoneName)
        }
        Spacer()
        // timer, compact, right-aligned
        VStack(alignment: .trailing, spacing: 2) {
          Text(timeString(session.durationSeconds))
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text("durée").font(.caption2).foregroundStyle(.secondary)
        }
      }
      zoneBar
      liveCurve
    }
    .padding(18)
    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
    .scaleEffect(expanded ? 1.0 : 0.92)
    .opacity(expanded ? 1.0 : 0.6)
  }

  private var startTimeLabel: String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return "début \(f.string(from: Date().addingTimeInterval(-Double(session.durationSeconds))))"
  }

  /// LOT 1: half a heartbeat, in seconds (drives the pulse animation curve).
  private var pulseHalfSeconds: Double {
    guard let bpm = liveBPM, bpm > 30 else { return 0.4 }
    return min(max(30.0 / Double(bpm), 0.18), 0.6)
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
            .shadow(color: zoneColor, radius: 6)
            .offset(x: proxy.size.width * frac - 7)
            .animation(.easeOut(duration: 0.4), value: frac)
        }
      }
    }
    .frame(height: 16)
  }

  /// LOT 2: the last 5 minutes of HR, drawn as a red curve with a soft fill.
  private var liveCurve: some View {
    Group {
      if session.samples.count >= 2 {
        Canvas { ctx, size in
          let window: TimeInterval = 300   // 5 min
          let iso = ISO8601DateFormatter()
          let now = Date()
          let parsed: [(Date, Int)] = session.samples.compactMap { s in
            guard let d = iso.date(from: s.ts) else { return nil }
            return (d, s.bpm)
          }
          let pts = parsed.filter { now.timeIntervalSince($0.0) <= window }
          guard pts.count >= 2 else { return }
          let lo = pts.map(\.1).min()!
          let hi = max(pts.map(\.1).max()!, lo + 1)
          let t0 = pts[0].0
          let span = max(now.timeIntervalSince(t0), 1)
          func pt(_ p: (Date, Int)) -> CGPoint {
            let x = size.width * (now.timeIntervalSince(p.0) / span)
            let y = size.height * (1 - (Double(p.1) - Double(lo)) / Double(hi - lo))
            return CGPoint(x: size.width - x, y: y)
          }
          var path = Path()
          path.move(to: pt(pts[0]))
          for s in pts.dropFirst() { path.addLine(to: pt(s)) }
          ctx.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          var fill = path
          fill.addLine(to: CGPoint(x: size.width, y: size.height))
          fill.addLine(to: CGPoint(x: size.width - size.width, y: size.height))
          fill.closeSubpath()
          ctx.fill(fill, with: .linearGradient(
            Gradient(colors: [.red.opacity(0.28), .clear]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
        }
        .frame(height: 54)
      } else {
        Text("la courbe apparaît après quelques secondes…")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Dark GPS map card: route polyline + distance/pace row (runs only).
  @ViewBuilder private var mapCard: some View {
    if gps.authorized && gps.started {
      VStack(alignment: .leading, spacing: 8) {
        Text("CARTE · GPS")
          .font(.system(size: 11, weight: .semibold))
          .tracking(1)
          .foregroundStyle(.secondary)
        WorkoutMapView(track: gps.track)
          .frame(height: 210)
          .clipShape(RoundedRectangle(cornerRadius: 12))
        HStack(spacing: 24) {
          Text(gps.distanceKm.map { String(format: "%.1f km", $0) } ?? "—")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
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
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
  }

  /// Stats grid — run: kcal / km / allure / FC moy. Indoor: kcal / FC moy /
  /// FC max / durée. Only numbers we truly have.
  private var statsGrid: some View {
    HStack(spacing: 10) {
      if isRun {
        statBox("kcal (est.)", "\(kcalEstimate)")
        statBox("Distance", gps.distanceKm.map { String(format: "%.1f km", $0) } ?? "—")
        statBox("Allure", gps.paceText ?? "—")
        statBox("FC moy", session.avgBPM.map(String.init) ?? "—")
      } else {
        statBox("kcal (est.)", "\(kcalEstimate)")
        statBox("FC moy", session.avgBPM.map(String.init) ?? "—")
        statBox("FC max", session.maxBPM.map(String.init) ?? "—")
        statBox("Durée", timeString(session.durationSeconds))
      }
    }
  }

  /// Per-kilometre splits with climb, from the GPS trace (runs only).
  @ViewBuilder private var splitsCard: some View {
    if !gps.splits.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("SPLITS")
          .font(.system(size: 11, weight: .semibold))
          .tracking(1)
          .foregroundStyle(.secondary)
        ForEach(gps.splits) { split in
          let isCurrent = split.km == gps.splits.last?.km
          HStack {
            Text("KM \(split.km)")
              .font(.subheadline.weight(isCurrent ? .bold : .regular))
              .foregroundStyle(isCurrent ? .blue : .primary)
            Spacer()
            Text(WorkoutGPSTracker.splitPaceString(seconds: split.seconds))
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(isCurrent ? .blue : .primary)
            Text(String(format: "%+.0f m", split.gainM))
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(width: 52, alignment: .trailing)
          }
        }
      }
      .padding(14)
      .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
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

  private var controls: some View {
    HStack(spacing: 14) {
      Button {
        session.isPaused ? session.resume() : session.pause()
      } label: {
        Label(session.isPaused ? "Reprendre" : "Pause",
              systemImage: session.isPaused ? "play.fill" : "pause.fill")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
      }
      Button {
        gps.stop()
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
    }
  }

  private func statBox(_ label: String, _ value: String) -> some View {
    VStack(spacing: 3) {
      Text(value).font(.headline).monospacedDigit()
      Text(label).font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
  }

  private func timeString(_ s: Int) -> String {
    String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
  }
}
