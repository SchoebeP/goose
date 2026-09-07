import Foundation
import Combine
import SwiftUI

public enum SimpleWorkoutType: String, Codable, CaseIterable, Identifiable {
  case run = "run"
  case gym = "gym"
  case bike = "bike"
  case swim = "swim"
  case other = "other"

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .run: return "Course"
    case .gym: return "Muscu"
    case .bike: return "Vélo"
    case .swim: return "Natation"
    case .other: return "Autre"
    }
  }

  public var iconName: String {
    switch self {
    case .run: return "figure.run"
    case .gym: return "dumbbell.fill"
    case .bike: return "figure.outdoor.cycle"
    case .swim: return "figure.pool.swim"
    case .other: return "ellipsis.circle.fill"
    }
  }
}

public struct SimpleHRSample: Codable, Identifiable {
  public var id: String { ts }
  public let ts: String
  public let bpm: Int

  public init(ts: String, bpm: Int) {
    self.ts = ts
    self.bpm = bpm
  }
}

public struct SimpleWorkoutRecord: Codable, Identifiable {
  public var id: String { id_str }
  public let id_str: String
  public let type: String
  public let started_at: String
  public let ended_at: String
  public let duration_s: Int
  public let avg_bpm: Int
  public let min_bpm: Int
  public let max_bpm: Int
  public let samples: [SimpleHRSample]
  public let steps: Int?

  enum CodingKeys: String, CodingKey {
    case id_str = "id"
    case type
    case started_at
    case ended_at
    case duration_s
    case avg_bpm
    case min_bpm
    case max_bpm
    case samples
    case steps
  }
}

@MainActor
public final class SimpleWorkoutSession: ObservableObject {
  @Published public private(set) var isActive: Bool = false
  @Published public private(set) var isPaused: Bool = false
  @Published public private(set) var workoutType: SimpleWorkoutType? = nil
  @Published public private(set) var durationSeconds: Int = 0
  @Published public private(set) var samples: [SimpleHRSample] = []
  @Published public private(set) var avgBPM: Int? = nil
  @Published public private(set) var minBPM: Int? = nil
  @Published public private(set) var maxBPM: Int? = nil

  private var startDate: Date? = nil
  private var lastPauseDate: Date? = nil
  private var lastSampleDate: Date = .distantPast

  private var timer: AnyCancellable? = nil
  private let isoFormatter = ISO8601DateFormatter()

  private let token: String = {
    Bundle.main.object(forInfoDictionaryKey: "WHOOP_INGEST_TOKEN") as? String ?? ""
  }()

  public init() {}

  public func start(type: SimpleWorkoutType) {
    self.workoutType = type
    self.isActive = true
    self.isPaused = false
    self.durationSeconds = 0
    self.samples = []
    self.avgBPM = nil
    self.minBPM = nil
    self.maxBPM = nil
    let now = Date()
    self.startDate = now
    self.lastSampleDate = .distantPast

    startTimer()
  }

  public func pause() {
    guard isActive, !isPaused else { return }
    isPaused = true
    lastPauseDate = Date()
    timer?.cancel()
    timer = nil
  }

  public func resume() {
    guard isActive, isPaused else { return }
    lastPauseDate = nil
    isPaused = false
    startTimer()
  }

  public func stop(stepsCount: Int? = nil) {
    guard isActive else { return }
    timer?.cancel()
    timer = nil

    let endDate = Date()
    let startIso = isoFormatter.string(from: startDate ?? endDate)
    let endIso = isoFormatter.string(from: endDate)
    let dur = durationSeconds
    let typeStr = workoutType?.rawValue ?? "other"

    let finalAvg = avgBPM ?? 0
    let finalMin = minBPM ?? 0
    let finalMax = maxBPM ?? 0
    let finalSamples = samples

    let record = SimpleWorkoutRecord(
      id_str: UUID().uuidString,
      type: typeStr,
      started_at: startIso,
      ended_at: endIso,
      duration_s: dur,
      avg_bpm: finalAvg,
      min_bpm: finalMin,
      max_bpm: finalMax,
      samples: finalSamples,
      steps: stepsCount
    )

    // Local JSON save in Application Support/GooseSwift/workouts
    saveLocally(record: record)

    // VPS upload
    uploadToVPS(record: record)

    // Reset session state
    self.isActive = false
    self.isPaused = false
    self.workoutType = nil
    self.durationSeconds = 0
    self.startDate = nil
    self.lastPauseDate = nil
  }

  public func ingestHeartRate(bpm: Int, at date: Date = Date()) {
    guard isActive, !isPaused else { return }
    guard bpm > 0 && bpm < 250 else { return }

    // Throttle: Max 1 HR sample per second
    guard date.timeIntervalSince(lastSampleDate) >= 0.98 else { return }
    lastSampleDate = date

    let sample = SimpleHRSample(ts: isoFormatter.string(from: date), bpm: bpm)
    samples.append(sample)

    let allBPMs = samples.map(\.bpm)
    minBPM = allBPMs.min()
    maxBPM = allBPMs.max()
    let sum = allBPMs.reduce(0, +)
    avgBPM = Int((Double(sum) / Double(allBPMs.count)).rounded())
  }

  private func startTimer() {
    timer?.cancel()
    timer = Timer.publish(every: 1.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        guard let self = self, self.isActive, !self.isPaused else { return }
        self.durationSeconds += 1
      }
  }

  private func saveLocally(record: SimpleWorkoutRecord) {
    do {
      let fm = FileManager.default
      let baseDir = try fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ).appendingPathComponent("GooseSwift/workouts", isDirectory: true)

      try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
      let fileURL = baseDir.appendingPathComponent("\(record.id_str).json")
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      let data = try encoder.encode(record)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("[WorkoutSession] Failed to save locally: \(error)")
    }
  }

  private func uploadToVPS(record: SimpleWorkoutRecord) {
    guard let url = URL(string: "https://latenightgames.fr/whoop/ingest/workouts") else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")

    do {
      let bodyData = try JSONEncoder().encode(record)
      req.httpBody = bodyData

      URLSession.shared.dataTask(with: req) { _, response, error in
        if let error = error {
          print("[WorkoutSession] VPS ingest error: \(error)")
        } else if let httpResp = response as? HTTPURLResponse {
          print("[WorkoutSession] VPS ingest response code: \(httpResp.statusCode)")
        }
      }.resume()
    } catch {
      print("[WorkoutSession] Failed to encode JSON for VPS upload: \(error)")
    }
  }
}
