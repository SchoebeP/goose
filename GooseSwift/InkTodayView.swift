import SwiftUI

/// "Today" — Radiograph redesign. A ledger of the body's current readings:
/// live vitals up top under the pulse spine, then the day's derived metrics.
struct InkTodayView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void
  @StateObject private var stepsFeed = MinutelyStepsFeed()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        InkTodayHeader()
        InkLiveHero(ble: model.ble)
          .padding(.top, 10)

        InkRule()
          .padding(.top, InkTheme.sectionSpacing)

        InkMinutelyHRSection()
        InkRule()
        InkMinutelyStepsSection(feed: stepsFeed)
        InkRule()

        snapshotRows
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.bottom, 34)
    }
    .inkScreen()
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      model.recordUIAction("page.opened", detail: "Today (ink)")
      healthStore.loadBridgeCatalogsIfNeeded()
    }
  }

  private var snapshotRows: some View {
    let snapshots = healthStore.landingSnapshots(
      liveHeartRateBPM: model.ble.liveHeartRateBPM,
      liveHeartRateSource: model.ble.liveHeartRateSource,
      liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt
    )
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(snapshots) { snapshot in
        Button {
          openHealthRoute(snapshot.route)
        } label: {
          InkSnapshotRow(snapshot: snapshot)
        }
        .buttonStyle(.plain)
        InkRule()
      }
    }
  }
}

private struct InkTodayHeader: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .inkEyebrow()
      Text("Today")
        .font(InkTheme.screenTitle)
        .foregroundStyle(InkTheme.ink)
    }
    .padding(.top, 12)
  }
}

/// Live hero: pulse spine + the three live readings. Observes the BLE client
/// directly so values never go stale.
private struct InkLiveHero: View {
  @ObservedObject var ble: GooseBLEClient

  private var isLive: Bool {
    guard let updatedAt = ble.liveHeartRateUpdatedAt else { return false }
    return Date().timeIntervalSince(updatedAt) < 25
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      PulseSpine(bpm: ble.liveHeartRateBPM, isLive: isLive)

      VitalReading(
        eyebrow: "Heart rate",
        value: ble.liveHeartRateBPM.map(String.init) ?? "--",
        unit: "bpm",
        numeralSize: 64,
        live: isLive
      )

      HStack(alignment: .top, spacing: 24) {
        VitalReading(
          eyebrow: "Resting",
          value: ble.restingHeartRateEstimateBPM.map { String(Int($0.rounded())) } ?? "--",
          unit: "bpm",
          numeralSize: 34
        )
        VitalReading(
          eyebrow: "HRV",
          value: ble.liveHRVRMSSD.map { String(Int($0.rounded())) } ?? "--",
          unit: "ms",
          numeralSize: 34
        )
        VitalReading(
          eyebrow: ble.batteryIsCharging == true ? "Battery · charging" : "Battery",
          value: ble.batteryLevelPercent.map(String.init) ?? "--",
          unit: "%",
          numeralSize: 34
        )
      }

      bandLine
    }
  }

  private var bandLine: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(isLive ? InkTheme.arterial : InkTheme.hairline)
        .frame(width: 5, height: 5)
      Text(bandStatusText)
        .font(InkTheme.footnote)
        .foregroundStyle(InkTheme.graphite)
    }
    .accessibilityElement(children: .combine)
  }

  private var bandStatusText: String {
    if isLive {
      var text = "\(ble.activeDeviceName) — live"
      if let onWrist = ble.isOnWrist {
        text += onWrist ? " · on wrist" : " · off wrist"
      }
      if let lastSync = ble.lastSyncAt {
        text += " · synced \(lastSync.formatted(.relative(presentation: .named)))"
      }
      return text
    }
    if ble.connectionState.lowercased().contains("connect")
      && !ble.connectionState.lowercased().contains("dis") {
      return "\(ble.activeDeviceName) — connected, waiting for signal"
    }
    return "Bring the band in range to go live"
  }
}

/// Today's heart rate per hour — VPS recap, drawn as ink range bars.
/// Tap-through to the minute-level day detail (regression fix vs old Home).
private struct InkMinutelyHRSection: View {
  @StateObject private var feed = MinutelyHRFeed()
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  private var hourlyBuckets: [HRMinute] {
    var byHour: [String: [HRMinute]] = [:]
    for minute in feed.minutes {
      byHour[hourKey(from: minute.minute), default: []].append(minute)
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { hour, rows in
        HRMinute(
          minute: hour,
          bpm: rows.last?.bpm ?? 0,
          lo: rows.map(\.lo).min() ?? 0,
          hi: rows.map(\.hi).max() ?? 0,
          n: rows.reduce(0) { $0 + $1.n }
        )
      }
  }

  var body: some View {
    let buckets = hourlyBuckets
    NavigationLink {
      HRDayDetailView(minutes: feed.minutes)
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Heart rate · today").inkEyebrow()
          Spacer()
          if let last = buckets.last, last.hi > 0 {
            Text("\(Int(last.lo))–\(Int(last.hi)) bpm")
              .font(InkTheme.mono(11))
              .foregroundStyle(InkTheme.graphite)
          }
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(InkTheme.hairline)
        }
        if buckets.isEmpty {
          Text("No readings yet today")
            .font(InkTheme.footnote)
            .foregroundStyle(InkTheme.graphite)
        } else {
          InkRangeBars(
            buckets: buckets.map { .init(low: Double($0.lo), high: Double($0.hi)) },
            emphasizeLast: true
          )
        }
      }
      .padding(.vertical, 15)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }
}

/// Today's steps per hour — our own accelerometer-derived count.
private struct InkMinutelyStepsSection: View {
  @ObservedObject var feed: MinutelyStepsFeed
  private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

  private var hourlyTotals: [Double] {
    var byHour: [String: Int] = [:]
    for minute in feed.minutes {
      byHour[hourKey(from: minute.minute), default: 0] += minute.steps
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { Double($0.value) }
  }

  var body: some View {
    NavigationLink {
      StepsDayDetailView(minutes: feed.minutes)
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Steps · today").inkEyebrow()
          Spacer()
          Text("\(feed.total)")
            .font(InkTheme.mono(11))
            .foregroundStyle(InkTheme.graphite)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(InkTheme.hairline)
        }
        if hourlyTotals.isEmpty {
          Text("Steps accrue while the band is worn and connected")
            .font(InkTheme.footnote)
            .foregroundStyle(InkTheme.graphite)
        } else {
          InkBars(values: hourlyTotals)
        }
      }
      .padding(.vertical, 15)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onAppear { feed.refresh() }
    .onReceive(refresh) { _ in feed.refresh() }
  }
}

private struct InkSnapshotRow: View {
  let snapshot: HealthMetricSnapshot

  private var trendValues: [Double] {
    snapshot.trend.points.map(\.value)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text(snapshot.title).inkEyebrow()
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(snapshot.value)
            .font(InkTheme.displayNumeral(27))
            .foregroundStyle(InkTheme.ink)
            .monospacedDigit()
          if !snapshot.unit.isEmpty {
            Text(snapshot.unit)
              .font(InkTheme.mono(11))
              .foregroundStyle(InkTheme.graphite)
          }
        }
        if !snapshot.status.isEmpty {
          Text(snapshot.status)
            .font(InkTheme.footnote)
            .foregroundStyle(InkTheme.graphite)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 10)
      if trendValues.count > 1 {
        InkSparkline(values: trendValues, height: 34)
          .frame(width: 92)
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(InkTheme.hairline)
    }
    .padding(.vertical, 15)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
