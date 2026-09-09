import Darwin
import Foundation
import SwiftUI
import UIKit

/// Plain-value result of the heavy stress math so it can be computed off the
/// main actor (the math only touches the thread-safe `HeartRateSeriesStore`
/// output); the summary/snapshot wrapping happens back on main.
struct StressHRComputation {
  let windows: [StressWindowPoint]
  let score: Double
  let averageHeartRate: Double
  let restingHeartRate: Double
  let highMinutes: Double
  let mediumMinutes: Double
  let lowMinutes: Double
  let totalMinutes: Double
  let confidence: Double
  let sampleCount: Int
  let lastSampleAt: Date?
}

extension HealthDataStore {
  func stressAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> StressAlgorithmSummary {
    guard !previewMissingData else {
      return emptyStressSummary(
        status: "No data",
        freshness: "Missing",
        source: .unavailable("preview missing stress data")
      )
    }

    let samples = heartRateSeriesStore.samples(forDayContaining: date, calendar: calendar)
    guard samples.count >= 6 else {
      return emptyStressSummary(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress requires at least six heart-rate samples today")
      )
    }

    let liveRestingFallbackBPM = allowLiveFallbacks
      ? Self.liveHRDerivedRestingHeartRateSample()?.bpm
      : nil
    guard let computation = Self.stressComputation(
      samples: samples,
      store: heartRateSeriesStore,
      liveRestingFallbackBPM: liveRestingFallbackBPM,
      for: date,
      calendar: calendar
    ) else {
      return emptyStressSummary(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress buckets could not be computed")
      )
    }

    return stressSummary(from: computation)
  }

  /// Heavy stress math (full-day sample bucketing into 10-minute windows plus
  /// aggregation). `nonisolated` so the Home card can run it off-main; this is
  /// the single implementation shared by the sync and async paths.
  nonisolated static func stressComputation(
    samples: [HeartRateSamplePoint],
    store: HeartRateSeriesStore,
    liveRestingFallbackBPM: Double?,
    for date: Date,
    calendar: Calendar
  ) -> StressHRComputation? {
    let restingHeartRate: Double
    if let storeEstimate = store.restingEstimate(forDayContaining: date, calendar: calendar)?.bpm {
      restingHeartRate = storeEstimate
    } else if let liveRestingFallbackBPM {
      restingHeartRate = liveRestingFallbackBPM
    } else {
      let values = samples.map(\.bpm).sorted()
      let lowCount = max(1, values.count / 4)
      restingHeartRate = Double(values.prefix(lowCount).reduce(0, +)) / Double(lowCount)
    }

    let dayStart = calendar.startOfDay(for: date)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    let bucketSeconds: TimeInterval = 10 * 60
    let grouped = Dictionary(grouping: samples) { sample in
      Int(max(sample.capturedAt.timeIntervalSince(dayStart), 0) / bucketSeconds)
    }

    // Same output as `Self.timeLabel`, hoisted out of the loop (one formatter
    // instead of one per window) and kept local so this stays nonisolated.
    let timeFormatter = DateFormatter()
    timeFormatter.timeStyle = .short
    timeFormatter.dateStyle = .none

    let windows = grouped
      .sorted { $0.key < $1.key }
      .compactMap { bucket, bucketSamples -> StressWindowPoint? in
        guard !bucketSamples.isEmpty else {
          return nil
        }
        let values = bucketSamples.map(\.bpm)
        let averageHeartRate = Double(values.reduce(0, +)) / Double(values.count)
        let minHeartRate = Double(values.min() ?? Int(averageHeartRate.rounded()))
        let maxHeartRate = Double(values.max() ?? Int(averageHeartRate.rounded()))
        let heartRatePressure = stressClamp(
          (averageHeartRate - restingHeartRate) / max(32.0, restingHeartRate * 0.62),
          min: 0,
          max: 1
        )
        let volatilityPressure = stressClamp(
          ((maxHeartRate - minHeartRate) / max(averageHeartRate, 1)) / 0.24,
          min: 0,
          max: 1
        )
        let start = dayStart.addingTimeInterval(TimeInterval(bucket) * bucketSeconds)
        let end = min(start.addingTimeInterval(bucketSeconds), dayEnd)
        // Same rule as `Self.isLikelySleepWindow`, inlined to stay nonisolated.
        let hour = calendar.component(.hour, from: start)
        let sleepWindow = hour < 7 || hour >= 23
        var stress = (heartRatePressure * 0.88 + volatilityPressure * 0.12) * 100.0
        if sleepWindow {
          stress *= 0.62
        }
        if averageHeartRate <= restingHeartRate + 4 {
          stress *= 0.65
        }
        stress = stressClamp(stress, min: 0, max: 100)

        return StressWindowPoint(
          id: "\(Int64((start.timeIntervalSince1970 * 1000).rounded()))",
          start: start,
          end: end,
          timeLabel: timeFormatter.string(from: start),
          stress: stress,
          averageHeartRate: averageHeartRate,
          sampleCount: bucketSamples.count,
          isSleepWindow: sleepWindow
        )
      }

    guard !windows.isEmpty else {
      return nil
    }

    let weightedSampleCount = max(windows.reduce(0) { $0 + $1.sampleCount }, 1)
    let score = windows.reduce(0.0) { $0 + $1.stress * Double($1.sampleCount) } / Double(weightedSampleCount)
    let averageHeartRate = windows.reduce(0.0) { $0 + $1.averageHeartRate * Double($1.sampleCount) } / Double(weightedSampleCount)
    let totalMinutes = max(windows.reduce(0.0) { $0 + $1.durationMinutes }, 1)
    let highMinutes = windows.filter { $0.stress >= 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let mediumMinutes = windows.filter { $0.stress >= 33 && $0.stress < 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let lowMinutes = max(totalMinutes - highMinutes - mediumMinutes, 0)
    let sampleConfidence = stressClamp(Double(samples.count) / 120.0, min: 0, max: 1)
    let windowConfidence = stressClamp(Double(windows.count) / 18.0, min: 0, max: 1)
    let stressConfidence = stressClamp(0.32 + sampleConfidence * 0.42 + windowConfidence * 0.18, min: 0.32, max: 0.88)

    return StressHRComputation(
      windows: windows,
      score: score,
      averageHeartRate: averageHeartRate,
      restingHeartRate: restingHeartRate,
      highMinutes: highMinutes,
      mediumMinutes: mediumMinutes,
      lowMinutes: lowMinutes,
      totalMinutes: totalMinutes,
      confidence: stressConfidence,
      sampleCount: samples.count,
      lastSampleAt: samples.last?.capturedAt
    )
  }

  /// Same behaviour as `Self.clamp`, declared nonisolated for the off-main path.
  private nonisolated static func stressClamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
    min(max(value, lowerBound), upperBound)
  }

  /// Wrap an off-main computation back into the published summary (cheap; main).
  func stressSummary(from computation: StressHRComputation) -> StressAlgorithmSummary {
    let inputSummary = [
      "hr_samples=\(computation.sampleCount)",
      "windows=\(computation.windows.count)",
      "resting_hr=\(Self.numberText(computation.restingHeartRate, fractionDigits: 0) ?? "--") bpm",
      "model=hr_elevation+hr_volatility",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(computation.confidence, fractionDigits: 2) ?? "0"

    return StressAlgorithmSummary(
      score: computation.score,
      status: Self.stressStatusLabel(score: computation.score),
      averageHeartRate: computation.averageHeartRate,
      averageHRV: nil,
      windows: computation.windows,
      high: StressZoneSummary(label: "High", percent: computation.highMinutes / computation.totalMinutes, durationMinutes: computation.highMinutes),
      medium: StressZoneSummary(label: "Med", percent: computation.mediumMinutes / computation.totalMinutes, durationMinutes: computation.mediumMinutes),
      low: StressZoneSummary(label: "Low", percent: computation.lowMinutes / computation.totalMinutes, durationMinutes: computation.lowMinutes),
      sampleCount: computation.sampleCount,
      source: .localEstimate("goose.stress.hr_proxy.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: Self.relativeText(for: computation.lastSampleAt) ?? "Today",
      confidence: computation.confidence,
      inputSummary: inputSummary
    )
  }

  func energyBankAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> EnergyBankAlgorithmSummary {
    let stress = stressAlgorithmSummary(for: date, calendar: calendar, allowLiveFallbacks: allowLiveFallbacks)
    guard stress.hasData else {
      return emptyEnergyBankSummary(
        status: "No stress data",
        freshness: stress.freshness,
        source: stress.source
      )
    }

    let recoverySeed = recoveryScoreValue()
    var energy = Self.clamp(recoverySeed ?? 55, min: 5, max: 100)
    var points: [EnergyStressPoint] = []
    var totalCharged = 0.0
    var totalDrained = 0.0
    var sleepCharge = 0.0

    for window in stress.windows.sorted(by: { $0.start < $1.start }) {
      let hours = max(window.durationMinutes / 60.0, 1.0 / 6.0)
      let delta: Double
      if window.isSleepWindow {
        let lowStressBonus = max(0, 35 - window.stress) * 0.045
        delta = (3.3 + lowStressBonus) * hours
      } else {
        let stressDrain = (0.75 + window.stress / 20.0) * hours
        let quietCharge = window.stress < 22 ? 0.55 * hours : 0
        delta = quietCharge - stressDrain
      }

      energy = Self.clamp(energy + delta, min: 0, max: 100)
      if delta >= 0 {
        totalCharged += delta
        if window.isSleepWindow {
          sleepCharge += delta
        }
      } else {
        totalDrained += abs(delta)
      }

      points.append(
        EnergyStressPoint(
          id: window.id,
          timeLabel: window.timeLabel,
          energy: energy,
          stress: window.stress,
          usage: Self.clamp(abs(delta) * 12.0, min: 4, max: 100),
          isSleepWindow: window.isSleepWindow,
          isChargeEvent: delta > 0
        )
      )
    }

    let stressConfidence = stress.confidence ?? 0.35
    let energyConfidence = Self.clamp(stressConfidence * 0.86 + (recoverySeed == nil ? 0 : 0.10), min: 0.30, max: 0.90)
    let seedText = recoverySeed.flatMap { Self.numberText($0, fractionDigits: 0) }.map { "recovery_score=\($0)" } ?? "recovery_score=default_55"
    let inputSummary = [
      "stress_windows=\(stress.windows.count)",
      "stress_confidence=\(Self.numberText(stressConfidence, fractionDigits: 2) ?? "0")",
      seedText,
      "model=stress_charge_drain",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(energyConfidence, fractionDigits: 2) ?? "0"

    return EnergyBankAlgorithmSummary(
      percent: energy,
      status: Self.energyBankStatusLabel(percent: energy),
      points: points,
      totalCharged: totalCharged,
      totalDrained: totalDrained,
      primarySleepCharge: sleepCharge,
      source: .localEstimate("goose.energy_bank.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: stress.freshness,
      confidence: energyConfidence,
      inputSummary: inputSummary
    )
  }

  func stressSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    stressSnapshot(base: snapshot, summary: stressAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks))
  }

  func stressSnapshot(base snapshot: HealthMetricSnapshot, summary: StressAlgorithmSummary) -> HealthMetricSnapshot {
    guard let score = summary.score,
          let scoreText = Self.numberText(score, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: scoreText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: Self.stressTrendModel(base: snapshot.trend, summary: summary)
    )
  }

  func energyBankSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    let summary = energyBankAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks)
    guard let percent = summary.percent,
          let percentText = Self.numberText(percent, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: percentText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: Self.energyBankTrendModel(base: snapshot.trend, summary: summary)
    )
  }

  func emptyStressSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> StressAlgorithmSummary {
    StressAlgorithmSummary(
      score: nil,
      status: status,
      averageHeartRate: nil,
      averageHRV: nil,
      windows: [],
      high: StressZoneSummary(label: "High", percent: 0, durationMinutes: 0),
      medium: StressZoneSummary(label: "Med", percent: 0, durationMinutes: 0),
      low: StressZoneSummary(label: "Low", percent: 0, durationMinutes: 0),
      sampleCount: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  func emptyEnergyBankSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> EnergyBankAlgorithmSummary {
    EnergyBankAlgorithmSummary(
      percent: nil,
      status: status,
      points: [],
      totalCharged: 0,
      totalDrained: 0,
      primarySleepCharge: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  // MARK: - Home stress card (cached snapshot, refreshed off-main)

  /// Last computed Home stress snapshot — a pure getter so rendering it costs
  /// nothing. `refreshHomeStressSnapshotIfNeeded()` keeps it fresh off-main.
  /// Before the first refresh lands it returns the base placeholder ("--").
  func homeStressSnapshot() -> HealthMetricSnapshot {
    homeStressSnapshotCache ?? homeStressBaseSnapshot
  }

  /// Recompute the Home stress snapshot off the main thread, unless a
  /// fresh-enough cache exists or a refresh is already in flight. Mirrors the
  /// packet-score off-main pattern (worker queue, publish on main, run-id guard).
  func refreshHomeStressSnapshotIfNeeded(maxAge: TimeInterval = 15) {
    guard homeStressRefreshID == nil else {
      return
    }
    if homeStressSnapshotCache != nil,
       let refreshedAt = homeStressRefreshedAt,
       Date().timeIntervalSince(refreshedAt) < maxAge {
      return
    }
    refreshHomeStressSnapshot()
  }

  func refreshHomeStressSnapshot() {
    guard !previewMissingData else {
      homeStressSnapshotCache = stressSnapshot(
        base: homeStressBaseSnapshot,
        summary: emptyStressSummary(
          status: "No data",
          freshness: "Missing",
          source: .unavailable("preview missing stress data")
        )
      )
      homeStressRefreshedAt = Date()
      return
    }

    let refreshID = UUID()
    homeStressRefreshID = refreshID
    let store = heartRateSeriesStore
    let date = Date()
    let calendar = Calendar.current

    stressSnapshotQueue.async { [weak self] in
      let samples = store.samples(forDayContaining: date, calendar: calendar)
      // Home renders stable daily metrics (`allowLiveFallbacks: false`),
      // so no live resting-HR fallback is passed to the worker.
      let computation = samples.count >= 6
        ? HealthDataStore.stressComputation(
          samples: samples,
          store: store,
          liveRestingFallbackBPM: nil,
          for: date,
          calendar: calendar
        )
        : nil
      let sampleCount = samples.count

      DispatchQueue.main.async { [weak self] in
        guard let self, self.homeStressRefreshID == refreshID else {
          return
        }
        self.homeStressRefreshID = nil
        self.homeStressRefreshedAt = Date()
        let summary: StressAlgorithmSummary
        if let computation {
          summary = self.stressSummary(from: computation)
        } else {
          summary = self.emptyStressSummary(
            status: "No HR data",
            freshness: self.heartRateTimelineStatus,
            source: .unavailable(
              sampleCount >= 6
                ? "stress buckets could not be computed"
                : "stress requires at least six heart-rate samples today"
            )
          )
        }
        self.homeStressSnapshotCache = self.stressSnapshot(base: self.homeStressBaseSnapshot, summary: summary)
      }
    }
  }

  private var homeStressBaseSnapshot: HealthMetricSnapshot {
    Self.baseLandingSnapshots.first { $0.route == .stress } ?? Self.baseLandingSnapshots[0]
  }

  func zeroStrainSnapshot(
    base snapshot: HealthMetricSnapshot,
    freshness: String,
    provenance: String,
    sourceDetail: String
  ) -> HealthMetricSnapshot {
    replacingHealthMonitorSnapshot(
      snapshot,
      value: "--",
      unit: "",
      status: "No strain data",
      freshness: freshness,
      provenance: provenance,
      source: .unavailable(sourceDetail),
      trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
    )
  }

}
