import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  nonisolated static func packetInputBridgeReports(databasePath: String) -> Result<[String: [String: Any]], Error> {
    let bridge = GooseRustBridge()
    let dailyWindow = currentDailyMetricWindow()
    let hourlyWindow = currentHourlyMetricWindow()
    let baseArgs: [String: Any] = [
      "database_path": databasePath,
      "start": "0000",
      "end": "9999",
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
    ]
    do {
      var reports: [String: [String: Any]] = [:]
      reports["readiness"] = try bridge.request(
        method: "metrics.input_readiness",
        args: [
          "database_path": databasePath,
          "start": "0000",
          "end": "9999",
          "min_owned_captures": 2,
          "require_owned_captures": false,
          "require_scores_ready": true,
        ]
      )
      reports["motion"] = try bridge.request(method: "metrics.motion_features", args: baseArgs)
      reports["step_discovery"] = try bridge.request(
        method: "metrics.step_packet_discovery",
        args: baseArgs.merging(["max_candidate_fields": 100]) { _, new in new }
      )
      reports["step_counter_ingest"] = try bridge.request(
        method: "metrics.step_counter_ingest",
        args: baseArgs.merging(["max_candidate_fields": 1_000]) { _, new in new }
      )
      reports["heart_rate"] = try bridge.request(method: "metrics.heart_rate_features", args: baseArgs)
      reports["vital_event"] = try bridge.request(method: "metrics.vital_event_features", args: baseArgs)
      reports["hrv"] = try bridge.request(
        method: "metrics.hrv_features",
        args: baseArgs.merging([
          "min_rr_intervals_to_compute": 2,
          "baseline_min_days": 3,
          "require_baseline": false,
        ]) { _, new in new }
      )
      reports["window"] = try bridge.request(method: "metrics.window_features", args: baseArgs)
      reports["resting_hr"] = try bridge.request(
        method: "metrics.resting_hr_features",
        args: baseArgs.merging([
          "baseline_min_days": 3,
          "require_baseline": false,
        ]) { _, new in new }
      )
      reports["resting_hr_rollup"] = try bridge.request(
        method: "metrics.resting_hr_daily_rollup",
        args: restingHeartRateDailyRollupArgs(databasePath: databasePath, window: dailyWindow, writeMetric: true)
      )
      reports["step_counter_rollup"] = try bridge.request(
        method: "metrics.step_counter_daily_rollup",
        args: stepCounterDailyRollupArgs(databasePath: databasePath, window: dailyWindow, writeMetric: true)
      )
      reports["step_counter_hourly_rollup"] = try bridge.request(
        method: "metrics.step_counter_hourly_rollup",
        args: stepCounterHourlyRollupArgs(databasePath: databasePath, window: hourlyWindow, writeMetric: true)
      )
      reports["activity_unavailable_status"] = try bridge.request(
        method: "metrics.activity_unavailable_daily_status",
        args: activityUnavailableDailyStatusArgs(databasePath: databasePath, window: dailyWindow, writeMetric: true)
      )
      reports["energy_rollup"] = try bridge.request(
        method: "metrics.energy_daily_rollup",
        args: energyDailyRollupArgs(
          databasePath: databasePath,
          window: dailyWindow,
          restingHeartRateRollup: reports["resting_hr_rollup"],
          writeMetric: true
        )
      )
      reports["energy_hourly_rollup"] = try bridge.request(
        method: "metrics.energy_hourly_rollup",
        args: energyHourlyRollupArgs(
          databasePath: databasePath,
          window: hourlyWindow,
          restingHeartRateRollup: reports["resting_hr_rollup"],
          writeMetric: true
        )
      )
      reports["energy_unavailable_status"] = try bridge.request(
        method: "metrics.energy_unavailable_daily_status",
        args: energyDailyRollupArgs(
          databasePath: databasePath,
          window: dailyWindow,
          restingHeartRateRollup: reports["resting_hr_rollup"],
          writeMetric: true
        )
      )
      reports["recovery_sensor_rollup"] = try bridge.request(
        method: "metrics.recovery_sensor_daily_rollup",
        args: recoveryUnavailableDailyStatusArgs(databasePath: databasePath, window: dailyWindow, writeMetric: true)
      )
      reports["recovery_unavailable_status"] = try bridge.request(
        method: "metrics.recovery_unavailable_daily_status",
        args: recoveryUnavailableDailyStatusArgs(databasePath: databasePath, window: dailyWindow, writeMetric: true)
      )
      reports["daily_activity"] = try bridge.request(
        method: "metrics.daily_activity_metrics",
        args: dailyActivityMetricListArgs(databasePath: databasePath, window: dailyWindow)
      )
      reports["hourly_activity"] = try bridge.request(
        method: "metrics.hourly_activity_metrics",
        args: hourlyActivityMetricListArgs(databasePath: databasePath, window: hourlyWindow)
      )
      reports["daily_recovery"] = try bridge.request(
        method: "metrics.daily_recovery_metrics",
        args: dailyRecoveryMetricListArgs(databasePath: databasePath, window: dailyWindow)
      )
      return .success(reports)
    } catch {
      return .failure(error)
    }
  }

  nonisolated static func restingHeartRateDailyRollupArgs(
    databasePath: String,
    window: DailyMetricWindow,
    writeMetric: Bool
  ) -> [String: Any] {
    [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "baseline_min_days": 3,
      "require_baseline": false,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func stepCounterDailyRollupArgs(
    databasePath: String,
    window: DailyMetricWindow,
    writeMetric: Bool
  ) -> [String: Any] {
    [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func recoveryUnavailableDailyStatusArgs(
    databasePath: String,
    window: DailyMetricWindow,
    writeMetric: Bool
  ) -> [String: Any] {
    [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_rr_intervals_to_compute": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func activityUnavailableDailyStatusArgs(
    databasePath: String,
    window: DailyMetricWindow,
    writeMetric: Bool
  ) -> [String: Any] {
    [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func stepCounterHourlyRollupArgs(
    databasePath: String,
    window: DailyMetricWindow,
    writeMetric: Bool
  ) -> [String: Any] {
    [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func dailyActivityMetricListArgs(databasePath: String, window: DailyMetricWindow) -> [String: Any] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let historyStart = calendar.date(byAdding: .day, value: -29, to: window.start)
      ?? window.start.addingTimeInterval(-29 * 86_400)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func hourlyActivityMetricListArgs(databasePath: String, window: DailyMetricWindow) -> [String: Any] {
    let historyStart = window.start.addingTimeInterval(-48 * 3_600)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func dailyRecoveryMetricListArgs(databasePath: String, window: DailyMetricWindow) -> [String: Any] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let historyStart = calendar.date(byAdding: .day, value: -29, to: window.start)
      ?? window.start.addingTimeInterval(-29 * 86_400)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func energyDailyRollupArgs(
    databasePath: String,
    window: DailyMetricWindow,
    restingHeartRateRollup: [String: Any]?,
    writeMetric: Bool
  ) -> [String: Any] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")

    var args: [String: Any] = [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_heart_rate_samples": 2,
      "write_metric": writeMetric,
    ]

    let profile = OnboardingProfileSnapshot()
    if profile.weightGrams > 0 {
      let weightKg = Double(profile.weightGrams) / 1000.0
      if (25.0...300.0).contains(weightKg) {
        args["profile_weight_kg"] = weightKg
      }
    }
    if let ageYears = profileAgeYears(from: profile.dateOfBirthString, calendar: calendar) {
      args["profile_age_years"] = ageYears
      args["max_hr_bpm"] = max(120.0, min(210.0, 208.0 - 0.7 * Double(ageYears)))
    }
    if let sex = normalizedProfileSex(profile.genderRaw) {
      args["profile_sex"] = sex
    }
    if let restingHeartRate = nonisolatedDoubleValue(restingHeartRateRollup?["resting_hr_bpm"]) {
      args["resting_hr_bpm"] = restingHeartRate
    }
    return args
  }

  nonisolated static func energyHourlyRollupArgs(
    databasePath: String,
    window: DailyMetricWindow,
    restingHeartRateRollup: [String: Any]?,
    writeMetric: Bool
  ) -> [String: Any] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")

    var args: [String: Any] = [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_heart_rate_samples": 2,
      "write_metric": writeMetric,
    ]

    let profile = OnboardingProfileSnapshot()
    if profile.weightGrams > 0 {
      let weightKg = Double(profile.weightGrams) / 1000.0
      if (25.0...300.0).contains(weightKg) {
        args["profile_weight_kg"] = weightKg
      }
    }
    if let ageYears = profileAgeYears(from: profile.dateOfBirthString, calendar: calendar) {
      args["profile_age_years"] = ageYears
      args["max_hr_bpm"] = max(120.0, min(210.0, 208.0 - 0.7 * Double(ageYears)))
    }
    if let sex = normalizedProfileSex(profile.genderRaw) {
      args["profile_sex"] = sex
    }
    if let restingHeartRate = nonisolatedDoubleValue(restingHeartRateRollup?["resting_hr_bpm"]) {
      args["resting_hr_bpm"] = restingHeartRate
    }
    return args
  }

  nonisolated static func currentDailyMetricWindow() -> DailyMetricWindow {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let start = calendar.startOfDay(for: Date())
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = calendar.timeZone
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    isoFormatter.formatOptions = [.withInternetDateTime]

    return DailyMetricWindow(
      dateKey: dateFormatter.string(from: start),
      timezone: calendar.timeZone.identifier,
      start: start,
      end: end,
      startISO: isoFormatter.string(from: start),
      endISO: isoFormatter.string(from: end),
      startTimeUnixMS: Int64((start.timeIntervalSince1970 * 1000).rounded()),
      endTimeUnixMS: Int64((end.timeIntervalSince1970 * 1000).rounded())
    )
  }

  nonisolated static func currentHourlyMetricWindow() -> DailyMetricWindow {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let now = Date()
    let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
    let start = calendar.date(from: components) ?? now
    let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)

    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = calendar.timeZone
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    isoFormatter.formatOptions = [.withInternetDateTime]

    return DailyMetricWindow(
      dateKey: dateFormatter.string(from: start),
      timezone: calendar.timeZone.identifier,
      start: start,
      end: end,
      startISO: isoFormatter.string(from: start),
      endISO: isoFormatter.string(from: end),
      startTimeUnixMS: Int64((start.timeIntervalSince1970 * 1000).rounded()),
      endTimeUnixMS: Int64((end.timeIntervalSince1970 * 1000).rounded())
    )
  }

  static func metricDateKey(for date: Date, calendar inputCalendar: Calendar = .current) -> String {
    var calendar = inputCalendar
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let start = calendar.startOfDay(for: date)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: start)
  }

  nonisolated static func nonisolatedDoubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return nil
  }

  nonisolated static func profileAgeYears(from dateOfBirthString: String, calendar: Calendar) -> Int? {
    guard !dateOfBirthString.isEmpty else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let dateOfBirth = formatter.date(from: dateOfBirthString) else {
      return nil
    }
    let years = calendar.dateComponents([.year], from: dateOfBirth, to: Date()).year
    guard let years, (13...120).contains(years) else {
      return nil
    }
    return years
  }

  nonisolated static func normalizedProfileSex(_ rawValue: String) -> String? {
    switch rawValue {
    case "female", "male":
      return rawValue
    default:
      return nil
    }
  }
}
