import SwiftUI

// MARK: - Decodable Data Models

struct SimpleWorkoutSample: Decodable, Identifiable {
  let ts: String
  let bpm: Int
  var id: String { ts }
}

struct SimpleWorkout: Decodable, Identifiable {
  let id: String
  let type: String
  let started_at: String
  let ended_at: String?
  let duration_s: Int
  let avg_bpm: Int?
  let min_bpm: Int?
  let max_bpm: Int?
  let samples: [SimpleWorkoutSample]?
}

private struct WorkoutsPayload: Decodable {
  let workouts: [SimpleWorkout]
}

// MARK: - VPS Client Feed

@MainActor
final class SimpleWorkoutsFeed: ObservableObject {
  @Published var workouts: [SimpleWorkout] = []
  @Published var loaded = false
  @Published var errorText: String? = nil

  private let base = "https://latenightgames.fr/whoop/ingest"
  private let token = Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""

  func refresh(days: Int = 30) {
    var components = URLComponents(string: "\(base)/workouts")!
    components.queryItems = [
      URLQueryItem(name: "days", value: String(days))
    ]
    guard let url = components.url else { return }

    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")

    URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
      Task { @MainActor in
        self?.loaded = true
        guard let data = data, error == nil,
              let payload = try? JSONDecoder().decode(WorkoutsPayload.self, from: data) else {
          self?.errorText = "Sync impossible pour l'instant"
          self?.workouts = []
          return
        }
        self?.errorText = nil
        self?.workouts = payload.workouts
      }
    }.resume()
  }
}

// MARK: - Date / Label Formatters & Helpers

enum WorkoutTypeFormatter {
  static func iconName(for type: String) -> String {
    let lower = type.lowercased()
    if lower.contains("run") || lower.contains("course") {
      return "figure.run"
    } else if lower.contains("muscu") || lower.contains("strength") || lower.contains("dumbbell") {
      return "dumbbell"
    } else {
      return "figure.mixed.cardio"
    }
  }

  static func displayName(for type: String) -> String {
    let lower = type.lowercased()
    if lower.contains("run") || lower.contains("course") {
      return "Course"
    } else if lower.contains("muscu") || lower.contains("strength") || lower.contains("dumbbell") {
      return "Muscu"
    } else {
      return type.capitalized
    }
  }

  static func durationText(_ seconds: Int) -> String {
    let m = seconds / 60
    let h = m / 60
    let remM = m % 60
    if h > 0 {
      return "\(h) h \(remM) min"
    } else if m > 0 {
      return "\(m) min"
    } else {
      return "\(seconds) s"
    }
  }

  static func relativeTimeText(from isoDateString: String) -> String {
    guard let date = parseISODate(isoDateString) else { return "" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.locale = Locale(identifier: "fr_FR")
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  static func startDateTimeText(_ isoDateString: String) -> String {
    guard let date = parseISODate(isoDateString) else { return isoDateString }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.dateFormat = "E d MMM 'à' HH:mm"
    return formatter.string(from: date).capitalized
  }

  static func parseISODate(_ string: String) -> Date? {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: string) {
      return date
    }
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: string) {
      return date
    }
    // Fallback for "yyyy-MM-dd'T'HH:mm:ss" without offset
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    df.locale = Locale(identifier: "en_US_POSIX")
    return df.date(from: string)
  }
}

// MARK: - Main History View

struct WorkoutHistoryView: View {
  @StateObject private var feed = SimpleWorkoutsFeed()

  /// Current week stats: ISO Calendar (Monday to Sunday)
  private var currentWeekStats: (count: Int, totalSeconds: Int) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2 // Monday
    let now = Date()
    guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
      return (0, 0)
    }

    let thisWeekWorkouts = feed.workouts.filter { w in
      guard let date = WorkoutTypeFormatter.parseISODate(w.started_at) else { return false }
      return weekInterval.contains(date)
    }

    let totalDuration = thisWeekWorkouts.reduce(0) { $0 + $1.duration_s }
    return (thisWeekWorkouts.count, totalDuration)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let err = feed.errorText, feed.workouts.isEmpty {
          Text(err)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
        }

        if !feed.workouts.isEmpty {
          summaryHeader
        }

        if feed.workouts.isEmpty && feed.loaded {
          emptyStateView
        } else {
          workoutList
        }
      }
      .padding(16)
    }
    .background(Color.black.ignoresSafeArea())
    .navigationTitle("Historique des séances")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      feed.refresh(days: 30)
    }
  }

  // MARK: - Header Summary

  private var summaryHeader: some View {
    let stats = currentWeekStats
    return HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("CETTE SEMAINE")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
        Text("\(stats.count) séance\(stats.count > 1 ? "s" : "")")
          .font(.system(size: 24, weight: .bold, design: .rounded))
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Text("DURÉE TOTALE")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
        Text(WorkoutTypeFormatter.durationText(stats.totalSeconds))
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .monospacedDigit()
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "figure.run.circle")
        .font(.system(size: 56))
        .foregroundStyle(.secondary)
      Text("Aucune séance enregistrée")
        .font(.headline)
      Text("Lance ta première depuis l'accueil")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 260)
    .multilineTextAlignment(.center)
    .padding(24)
  }

  // MARK: - Workout List

  private var workoutList: some View {
    VStack(spacing: 12) {
      ForEach(feed.workouts) { workout in
        NavigationLink {
          WorkoutDetailView(workout: workout)
        } label: {
          workoutRow(workout)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func workoutRow(_ workout: SimpleWorkout) -> some View {
    HStack(spacing: 14) {
      Image(systemName: WorkoutTypeFormatter.iconName(for: workout.type))
        .font(.title2)
        .foregroundStyle(.red)
        .frame(width: 40, height: 40)
        .background(Circle().fill(Color.red.opacity(0.15)))

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(WorkoutTypeFormatter.displayName(for: workout.type))
            .font(.headline)
          Spacer()
          Text(WorkoutTypeFormatter.durationText(workout.duration_s))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }

        HStack {
          Text(WorkoutTypeFormatter.startDateTimeText(workout.started_at))
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          if let avg = workout.avg_bpm {
            Text("FC moy. \(avg) bpm")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
        }
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
  }
}

// MARK: - Detail View with Canvas HR Chart

struct WorkoutDetailView: View {
  let workout: SimpleWorkout

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        // Summary Header
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            Image(systemName: WorkoutTypeFormatter.iconName(for: workout.type))
              .font(.title)
              .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
              Text(WorkoutTypeFormatter.displayName(for: workout.type))
                .font(.title2.bold())
              Text(WorkoutTypeFormatter.startDateTimeText(workout.started_at))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Divider().background(Color.white.opacity(0.1))

          HStack(spacing: 20) {
            statItem(title: "DURÉE", value: WorkoutTypeFormatter.durationText(workout.duration_s))
            if let avg = workout.avg_bpm {
              statItem(title: "FC MOY", value: "\(avg) bpm")
            }
            if let maxBpm = workout.max_bpm {
              statItem(title: "FC MAX", value: "\(maxBpm) bpm")
            }
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))

        // Heart Rate Curve
        if let samples = workout.samples, !samples.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Label("Fréquence cardiaque", systemImage: "heart.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.red)

            workoutHRCanvas(samples: samples)
              .frame(height: 180)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
        } else {
          VStack(alignment: .leading, spacing: 8) {
            Label("Fréquence cardiaque", systemImage: "heart.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.red)

            Text("Aucun échantillon FC disponible pour cette séance.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
        }
      }
      .padding(16)
    }
    .background(Color.black.ignoresSafeArea())
    .navigationTitle(WorkoutTypeFormatter.displayName(for: workout.type))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func statItem(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline)
        .monospacedDigit()
    }
  }

  // MARK: - Canvas HR Chart (Minute-by-minute with gradient fill & auto Y axis)

  private func workoutHRCanvas(samples: [SimpleWorkoutSample]) -> some View {
    Canvas { context, size in
      let bpms = samples.map { Double($0.bpm) }
      guard let minBpmVal = bpms.min(), let maxBpmVal = bpms.max(), size.width > 0, size.height > 0 else { return }

      // Auto Y axis range with padding
      let yMin = max(30.0, minBpmVal - 5.0)
      let yMax = maxBpmVal + 5.0
      let yRange = max(10.0, yMax - yMin)

      let count = samples.count
      let xStep = count > 1 ? size.width / CGFloat(count - 1) : size.width

      var points: [CGPoint] = []
      for (index, sample) in samples.enumerated() {
        let x = count > 1 ? CGFloat(index) * xStep : size.width / 2.0
        let normalizedY = (Double(sample.bpm) - yMin) / yRange
        let y = size.height * (1.0 - CGFloat(normalizedY))
        points.append(CGPoint(x: x, y: y))
      }

      guard let firstPoint = points.first, let lastPoint = points.last else { return }

      // 1. Fill Path (Gradient)
      var fillPath = Path()
      fillPath.move(to: CGPoint(x: firstPoint.x, y: size.height))
      fillPath.addLine(to: firstPoint)
      for point in points.dropFirst() {
        fillPath.addLine(to: point)
      }
      fillPath.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
      fillPath.closeSubpath()

      let gradient = Gradient(colors: [
        Color.red.opacity(0.45),
        Color.red.opacity(0.05)
      ])
      context.fill(fillPath, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

      // 2. Stroke Line Path
      var strokePath = Path()
      strokePath.move(to: firstPoint)
      for point in points.dropFirst() {
        strokePath.addLine(to: point)
      }
      context.stroke(strokePath, with: .color(.red), lineWidth: 2.5)

      // 3. Y Axis Labels (Min / Max)
      let maxLabel = Text("\(Int(maxBpmVal)) bpm").font(.caption2.bold()).foregroundColor(.red)
      let minLabel = Text("\(Int(minBpmVal)) bpm").font(.caption2).foregroundColor(.secondary)

      context.draw(maxLabel, at: CGPoint(x: 35, y: max(10, points.map(\.y).min() ?? 10)))
      context.draw(minLabel, at: CGPoint(x: 35, y: min(size.height - 10, points.map(\.y).max() ?? size.height - 10)))
    }
  }
}
