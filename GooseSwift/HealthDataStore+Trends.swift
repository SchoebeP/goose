import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  func trendRows(for route: HealthRoute) -> [HealthMetricSnapshot] {
    if previewMissingData {
      return []
    }
    switch route {
    case .sleep:
      return sleepTrendRowsForV2()
    case .recovery:
      return recoveryTrendRowsForV2()
    case .strain:
      return strainTrendRowsForV2()
    case .stress:
      return stressTrendRowsForV2()
    default:
      return []
    }
  }

  /// Sleep's own multi-day rows. Only the metrics the server actually
  /// computes per night (duration, HR dip, and — once the backend's sleep-
  /// stage bugs are fixed — REM/deep) are wired here; the rest of
  /// `Self.sleepTrendRows` (sleep score, sleep bank, wake time, ...) has no
  /// real multi-day source today and is left as the honest static "No data"
  /// placeholder, which `compactMap`'s nil naturally keeps off-screen instead
  /// of rendering a permanently empty card.
  func sleepTrendRowsForV2() -> [HealthMetricSnapshot] {
    guard !previewMissingData else {
      return []
    }
    return Self.sleepTrendRows.compactMap { snapshot in
      switch snapshot.id {
      case "time-asleep-trend":
        return serverDailyTrendRow(
          base: snapshot,
          unit: "h",
          fractionDigits: 1,
          value: { day in
            guard let minutes = day.sleep?.durationMin else {
              return nil
            }
            return minutes / 60.0
          },
          status: { _, _ in "Server-computed" }
        )
      case "hr-dip-trend":
        return serverDailyTrendRow(
          base: snapshot,
          unit: "%",
          fractionDigits: 0,
          value: { $0.hrDipPct },
          status: { _, _ in "Server-computed" }
        )
      case "rem-trend":
        return serverDailyTrendRow(
          base: snapshot,
          unit: "%",
          fractionDigits: 0,
          value: { $0.sleepStages?.remPct },
          status: { _, _ in "Server-computed" }
        )
      case "deep-trend":
        return serverDailyTrendRow(
          base: snapshot,
          unit: "%",
          fractionDigits: 0,
          value: { $0.sleepStages?.deepPct },
          status: { _, _ in "Server-computed" }
        )
      default:
        return nil
      }
    }
  }

  /// Baevsky Stress Index, server-computed per night from R-R intervals
  /// (`stress` in `/ingest/metrics/daily`) — a DIFFERENT metric from the
  /// on-device "Stress Score" % (`stressTrendRowsForV2()`), which is today's
  /// intraday timeline and stays exactly as-is for the Stress detail screen.
  /// Kept as its own standalone row (not folded into `Self.stressTrendRows`)
  /// specifically for the multi-day Trends tab.
  func dailyStressIndexTrendRows() -> [HealthMetricSnapshot] {
    guard !previewMissingData else {
      return []
    }
    let base = Self.snapshot(
      id: "stress-index-trend",
      route: .stress,
      group: .vitals,
      title: "Stress Index",
      value: "--",
      unit: "",
      status: "No data",
      freshness: "No local data",
      provenance: "server-computed stress index (self-hosted VPS /metrics/daily)",
      source: .unavailable("stress index trend not available"),
      systemImage: "waveform.path.ecg",
      tint: .yellow,
      trendValues: [],
      range: "No data"
    )
    guard let row = serverDailyTrendRow(
      base: base,
      unit: "",
      fractionDigits: 0,
      value: { $0.stress?.stressIndex },
      status: { day, _ in day.stress?.band?.capitalized ?? "Server-computed" }
    ) else {
      return []
    }
    return [row]
  }

  func recoveryTrendRowsForV2() -> [HealthMetricSnapshot] {
    guard !usesPreviewPacketData else {
      return []
    }

    return Self.recoveryTrendRows.compactMap { snapshot in
      switch snapshot.id {
      case "recovery-score-trend":
        if let server = serverDailyTrendRow(
          base: snapshot,
          unit: "%",
          fractionDigits: 0,
          value: { $0.recoveryPct },
          status: { _, v in Self.recoveryQualityLabel(score: v) }
        ) {
          return server
        }
        guard let report = packetScoreReports["recovery"],
              let score = recoveryScoreValue(),
              let scoreText = Self.numberText(score, fractionDigits: 0) else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "score_0_to_100",
          unit: "%",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: scoreText,
          unit: "%",
          status: Self.recoveryQualityLabel(score: score),
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.recovery_score_from_features",
          source: .bridge("goose.recovery.v0"),
          trend: trend
        )
      case "recovery-hrv-trend":
        if let server = serverDailyTrendRow(
          base: snapshot,
          unit: "ms",
          fractionDigits: 0,
          value: { $0.hrvRMSSDMs },
          status: { _, _ in "Server-computed" }
        ) {
          return server
        }
        if let stored = dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "hrv_rmssd_ms",
          unit: "ms",
          fractionDigits: 0,
          metricName: "HRV"
        ) {
          return stored
        }
        guard let report = packetInputReports["hrv"] else {
          return nil
        }
        guard Self.boolValue(report["pass"]) == true else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "rmssd_ms",
          unit: "ms",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData,
              let value = Self.doubleValue(Self.map(report, "score_result", "output")?["rmssd_ms"])
                ?? Self.array(report["daily"]).last.flatMap({ Self.doubleValue($0["rmssd_ms"]) }),
              let text = Self.numberText(value, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "ms",
          status: "Packet-derived",
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.hrv_features",
          source: .bridgeDeviceSensor("metrics.hrv_features"),
          trend: trend
        )
      case "recovery-rhr-trend":
        if let server = serverDailyTrendRow(
          base: snapshot,
          unit: "bpm",
          fractionDigits: 0,
          value: { $0.rhrBPM },
          status: { _, _ in "Server-computed" }
        ) {
          return server
        }
        let dailyRecoveryRHRMetrics = dailyRecoveryMetricsWithRestingHR()
        if let metric = Self.preferredDailyRecoveryMetricWithRestingHR(from: dailyRecoveryRHRMetrics),
           let value = Self.doubleValue(metric["resting_hr_bpm"]),
           let text = Self.numberText(value, fractionDigits: 0) {
          return replacingHealthMonitorSnapshot(
            snapshot,
            value: text,
            unit: "bpm",
            status: dailyRecoveryRestingHRStatus(metric),
            freshness: metric["date_key"] as? String ?? "Latest",
            provenance: "daily_recovery_metrics | \(dailyRecoveryRestingHRProvenanceSummary(metric))",
            source: dailyRecoveryRestingHRSource(metric),
            trend: Self.restingHeartRateDailyRecoveryTrend(
              base: snapshot.trend,
              metrics: dailyRecoveryRHRMetrics
            )
          )
        }
        if let rollup = packetInputReports["resting_hr_rollup"],
           Self.boolValue(rollup["pass"]) == true,
           let value = Self.doubleValue(rollup["resting_hr_bpm"]),
           let text = Self.numberText(value, fractionDigits: 0) {
          return replacingHealthMonitorSnapshot(
            snapshot,
            value: text,
            unit: "bpm",
            status: "Packet-derived",
            freshness: Self.rollupFreshnessText(in: rollup) ?? "Today",
            provenance: "metrics.resting_hr_daily_rollup",
            source: .bridgeDeviceSensor("metrics.resting_hr_daily_rollup"),
            trend: Self.restingHeartRateRollupTrend(
              base: snapshot.trend,
              report: rollup
            )
          )
        }
        guard let report = packetInputReports["resting_hr"] else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "resting_hr_bpm",
          unit: "bpm",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData,
              let value = Self.doubleValue(Self.map(report, "resting")?["resting_hr_bpm"])
                ?? Self.array(report["daily"]).last.flatMap({ Self.doubleValue($0["resting_hr_bpm"]) }),
              let text = Self.numberText(value, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "bpm",
          status: "Packet-derived",
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.resting_hr_features",
          source: .bridgeDeviceSensor("metrics.resting_hr_features"),
          trend: trend
        )
      case "recovery-rr-trend":
        if let server = serverDailyTrendRow(
          base: snapshot,
          unit: "rpm",
          fractionDigits: 1,
          value: { $0.respRPM },
          status: { _, _ in "Server-computed" }
        ) {
          return server
        }
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "respiratory_rate_rpm",
          unit: "rpm",
          fractionDigits: 1,
          metricName: "respiratory rate"
        )
      case "recovery-spo2-trend":
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "oxygen_saturation_percent",
          unit: "%",
          fractionDigits: 0,
          metricName: "oxygen saturation"
        )
      case "recovery-temp-trend":
        // Only ever chart a CALIBRATED value -- raw sensor units must never
        // be displayed as a temperature (see ServerMetricsSkinTemp).
        if let server = serverDailyTrendRow(
          base: snapshot,
          unit: "C",
          fractionDigits: 1,
          value: { day in
            guard let temp = day.skinTemp, temp.isCalibratedCelsius else {
              return nil
            }
            return temp.value
          },
          status: { _, _ in "Server-computed" }
        ) {
          return server
        }
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "skin_temperature_delta_c",
          unit: "C",
          fractionDigits: 1,
          metricName: "skin temperature delta",
          signed: true
        )
      default:
        return nil
      }
    }
  }

  func dailyRecoveryMetricSnapshot(
    base snapshot: HealthMetricSnapshot,
    valueKey: String,
    unit: String,
    fractionDigits: Int,
    metricName: String,
    signed: Bool = false
  ) -> HealthMetricSnapshot? {
    let metrics = dailyRecoveryMetricsWithValue(valueKey)
    let rows = Self.dailyRecoveryTrendRows(from: metrics, valueKey: valueKey)
    guard let metric = Self.preferredDailyRecoveryMetric(from: metrics, valueKey: valueKey) else {
      return nil
    }
    let valueText = signed
      ? Self.signedNumberText(metric[valueKey], fractionDigits: fractionDigits)
      : Self.numberText(metric[valueKey], fractionDigits: fractionDigits)
    guard let valueText else {
      return nil
    }
    let trend = Self.dailyTrend(
      id: snapshot.trend.id,
      title: snapshot.trend.title,
      rows: rows,
      valueKey: valueKey,
      unit: unit,
      fractionDigits: fractionDigits,
      resources: snapshot.trend.resources
    )
    guard trend.hasData else {
      return nil
    }
    return replacingHealthMonitorSnapshot(
      snapshot,
      value: valueText,
      unit: unit,
      status: dailyRecoveryMetricStatus(metric),
      freshness: metric["date_key"] as? String ?? "Latest",
      provenance: "daily_recovery_metrics | \(dailyRecoveryMetricProvenanceSummary(metric))",
      source: dailyRecoveryMetricSource(metric, metricName: metricName),
      trend: trend
    )
  }

  func stressTrendRowsForV2() -> [HealthMetricSnapshot] {
    let summary = stressAlgorithmSummary()
    guard summary.hasData else {
      return []
    }

    return Self.stressTrendRows.compactMap { snapshot in
      switch snapshot.id {
      case "stress-score-trend":
        guard let score = summary.score,
              let text = Self.numberText(score, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: score),
          freshness: summary.freshness,
          provenance: summary.source.detail,
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary)
        )
      case "non-activity-stress-trend":
        let wakingWindows = summary.windows.filter { !$0.isSleepWindow }
        guard !wakingWindows.isEmpty else {
          return nil
        }
        let average = wakingWindows.reduce(0.0) { $0 + $1.stress } / Double(wakingWindows.count)
        guard let text = Self.numberText(average, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: average),
          freshness: summary.freshness,
          provenance: "\(summary.source.detail) | sleep windows excluded",
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary, points: wakingWindows, title: snapshot.title)
        )
      case "sleep-stress-trend":
        let sleepWindows = summary.windows.filter(\.isSleepWindow)
        guard !sleepWindows.isEmpty else {
          return nil
        }
        let average = sleepWindows.reduce(0.0) { $0 + $1.stress } / Double(sleepWindows.count)
        guard let text = Self.numberText(average, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: average),
          freshness: summary.freshness,
          provenance: "\(summary.source.detail) | likely sleep windows",
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary, points: sleepWindows, title: snapshot.title)
        )
      default:
        return nil
      }
    }
  }

  func recoveryTrendOverviewRows() -> [HealthMetricSnapshot] {
    let bridgeRows = Dictionary(
      uniqueKeysWithValues: recoveryTrendRowsForV2().map { ($0.id, $0) }
    )
    return Self.recoveryTrendRows.map { bridgeRows[$0.id] ?? $0 }
  }
}
