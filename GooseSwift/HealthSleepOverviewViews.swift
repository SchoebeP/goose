import Darwin
import Foundation
import SwiftUI
import UIKit

/// Sleep detail — Radiograph restyle. A ledger of the primary sleep window:
/// quality reading up top, bed/asleep durations, schedule actions, band sync
/// status, timeline, and trends. Presented sheets (insights, alarm settings,
/// sleep-needed calculator, the primary-sleep detail, and the per-metric
/// trend chart) are unchanged and keep their existing styling — restyling
/// those is out of this pass's scope.
struct SleepV2OverviewPage: View {
  @EnvironmentObject private var router: AppRouter
  @ObservedObject var store: HealthDataStore
  @ObservedObject var ble: GooseBLEClient
  @Binding var selectedDate: Date
  @Environment(\.colorScheme) private var colorScheme
  // Observed (not just referenced) so the Trends section re-renders the
  // instant ServerMetricsFeed's longer-window fetch resolves, instead of
  // waiting on unrelated state to redraw this view.
  @ObservedObject private var metricsFeed = ServerMetricsFeed.shared
  @State private var showingInsightsSheet = false
  @State private var showingAlarmSheet = false
  @State private var showingSleepNeededSheet = false
  @State private var showingDatePicker = false
  @State private var selectedTrend: HealthMetricSnapshot?
  @State private var selectedPrimarySleep: PrimarySleepDetail?
  @State private var autoBandSyncRequested = false

  private var autoBandSleepSyncEnabled: Bool {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-auto-band-sleep-sync")
      || processInfo.environment["GOOSE_AUTO_BAND_SLEEP_SYNC"] == "1"
  }

  var body: some View {
    // Constructed only to satisfy the still-old-styled presented sheets
    // below (insights / sleep-needed calculator) — this page's own body no
    // longer reads any palette colors.
    let palette = SleepV2Palette(colorScheme: colorScheme)

    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        dateRow

        VitalReading(eyebrow: "Sleep quality", value: sleepScore.map(String.init) ?? "--", unit: "%", numeralSize: 60)
          .padding(.top, 14)

        InkRule()
          .padding(.top, InkTheme.sectionSpacing)

        HStack(alignment: .top, spacing: 28) {
          VitalReading(eyebrow: "Time in bed", value: primarySleep?.timeInBedText ?? "No data", numeralSize: 26)
          VitalReading(eyebrow: "Time asleep", value: primarySleep?.durationText ?? "No data", numeralSize: 26)
        }
        .padding(.vertical, 20)

        InkRule()

        // SleepV2CoachingCard renders EmptyView — coach was removed from
        // this UI upstream. Kept as-is (zero visual footprint) rather than
        // deleting, so this restyle touches presentation only.
        SleepV2CoachingCard(palette: palette, tip: coachTip) {
          router.openCoach(prompt: coachTip.prompt)
        }

        InkDisclosureRow(label: "View insights") { showingInsightsSheet = true }
        InkRule()
        InkDisclosureRow(label: "Wake alarm", value: ble.alarmDisplaySummary) { showingAlarmSheet = true }
        InkRule()
        // "Sleep needed" has no real backing data anywhere in the app yet
        // (the generic health-family fallback is equally honest about this:
        // "No target sleep input") — show that instead of the old card's
        // hardcoded "7h 39m".
        InkDisclosureRow(label: "Sleep needed", value: "No target sleep input") { showingSleepNeededSheet = true }
        InkRule()

        bandSyncSection
        InkRule()

        InkSectionHeader(title: "Timeline")
          .padding(.top, InkTheme.sectionSpacing)
        timelineRow
        InkRule()

        InkSectionHeader(title: "Trends")
          .padding(.top, InkTheme.sectionSpacing)
        trendsSection
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.bottom, 34)
    }
    .inkScreen()
    .navigationTitle("Sleep")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showingAlarmSheet = true
        } label: {
          Image(systemName: "alarm")
        }
        .foregroundStyle(InkTheme.ink)
        .accessibilityLabel("Sleep alarm settings")
      }
    }
    .onAppear {
      store.loadBridgeCatalogsIfNeeded()
      startBandSleepSyncIfReady()
    }
    .onChange(of: ble.canSyncHistorical) { _, _ in
      startBandSleepSyncIfReady()
    }
    .onChange(of: ble.historicalSyncStatus) { _, newValue in
      if newValue == "synced" {
        store.refreshSleepAfterBandSync(packetCount: ble.historicalPacketCount)
      } else if newValue == "failed" {
        store.markBandSleepSyncFailed(ble.historicalSyncStatus)
      }
    }
    .sheet(isPresented: $showingDatePicker) {
      ScoreDatePickerSheet(
        title: "Sleep",
        routes: [.sleep],
        snapshots: [store.snapshot(for: .sleep)],
        selectedDate: $selectedDate
      )
    }
    .sheet(isPresented: $showingAlarmSheet) {
      SleepV2AlarmSheet(ble: ble)
    }
    .sheet(isPresented: $showingSleepNeededSheet) {
      SleepV2SleepNeededSheet(palette: palette)
    }
    .sheet(isPresented: $showingInsightsSheet) {
      SleepV2InsightsSheet(palette: palette)
    }
    .sheet(item: $selectedTrend) { snapshot in
      SleepV2BevelTrendSheet(snapshot: snapshot)
    }
    .sheet(item: $selectedPrimarySleep) { sleep in
      PrimarySleepDetailSheet(sleep: sleep)
    }
  }

  private var dateRow: some View {
    Button {
      showingDatePicker = true
    } label: {
      HStack(spacing: 6) {
        Text(dateLabel).inkEyebrow()
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(InkTheme.graphite)
      }
    }
    .buttonStyle(.plain)
    .padding(.top, 12)
  }

  private var bandSyncSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      InkLedgerRow(label: "Band history", value: ble.historicalSyncStatus)
      InkLedgerRow(label: "Packets", value: packetText)
      InkLedgerRow(label: "Sleep score", value: store.bandSleepImportStatus)
      HStack(spacing: 22) {
        InkActionLink(title: "Sync from band", enabled: ble.canSyncHistorical) {
          startBandSleepSync(automatic: false)
        }
        InkActionLink(title: "Refresh score") {
          store.refreshSleepAfterBandSync(packetCount: ble.historicalPacketCount)
        }
      }
      .padding(.top, 8)
      .padding(.bottom, 12)
    }
  }

  private var packetText: String {
    ble.historicalPacketCount == 1 ? "1 packet" : "\(ble.historicalPacketCount) packets"
  }

  @ViewBuilder
  private var timelineRow: some View {
    if let primarySleep {
      Button {
        selectedPrimarySleep = primarySleep
      } label: {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline) {
            Text("Primary sleep").inkEyebrow()
            Spacer()
            Text(primarySleep.scoreDisplayText)
              .font(InkTheme.mono(12, weight: .semibold))
              .foregroundStyle(InkTheme.graphite)
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(InkTheme.hairline)
          }
          Text(
            "\(primarySleep.dateLabel) at \(primarySleep.startLabel) · "
              + "asleep \(primarySleep.durationText) · in bed \(primarySleep.timeInBedText) · "
              + "wake \(primarySleep.endLabel)"
          )
          .font(InkTheme.footnote)
          .foregroundStyle(InkTheme.graphite)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Text("Primary sleep").inkEyebrow()
        Text("No band sleep data")
          .font(InkTheme.footnote)
          .foregroundStyle(InkTheme.graphite)
      }
      .padding(.vertical, 15)
    }
  }

  private var sleepTrendRows: [HealthMetricSnapshot] {
    store.trendRows(for: .sleep).filter { $0.trend.hasData }
  }

  @ViewBuilder
  private var trendsSection: some View {
    if sleepTrendRows.isEmpty {
      Text("Sleep trends will appear after a few nights of band sleep data.")
        .font(InkTheme.footnote)
        .foregroundStyle(InkTheme.graphite)
        .padding(.vertical, 12)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(sleepTrendRows) { snapshot in
          InkMetricTrendRow(snapshot: snapshot) {
            selectedTrend = snapshot
          }
          InkRule()
        }
      }
    }
  }

  private var selectedSnapshot: HealthMetricSnapshot {
    ScoreDateTimeline.datedSnapshot(
      from: store.snapshot(for: .sleep),
      date: selectedDate
    )
  }

  private var primarySleep: PrimarySleepDetail? {
    store.primarySleep()
  }

  // No hardcoded fallback: when neither the selected snapshot nor
  // primarySleep has a real score, this is nil and the caller renders "--"
  // — we never fabricate a plausible-looking sleep quality number.
  private var sleepScore: Int? {
    SleepV2Numbers.firstInt(in: selectedSnapshot.value)
      ?? SleepV2Numbers.firstInt(in: primarySleep?.scoreText ?? "")
  }

  private var dateLabel: String {
    let suffix = selectedDate.formatted(.dateTime.day().month(.abbreviated))
    let prefix = ScoreDateTimeline.dateLabel(for: selectedDate)
    return "\(prefix), \(suffix)"
  }

  private var coachTip: CoachInlineTip {
    CoachTipFactory.sleepTip(healthStore: store, ble: ble)
  }

  private func startBandSleepSyncIfReady() {
    guard autoBandSleepSyncEnabled else {
      if !autoBandSyncRequested {
        autoBandSyncRequested = true
        ble.record(
          source: "health.sleep",
          title: "band_sleep_sync.auto_skipped",
          body: "autoBandSleepSync=false"
        )
      }
      return
    }
    guard !autoBandSyncRequested, ble.canSyncHistorical else {
      return
    }
    autoBandSyncRequested = true
    startBandSleepSync(automatic: true)
  }

  private func startBandSleepSync(automatic: Bool) {
    store.markBandSleepSyncRequested(
      automatic: automatic,
      canSync: ble.canSyncHistorical,
      detail: ble.historicalSyncStatus
    )
    guard ble.canSyncHistorical else {
      return
    }
    ble.syncHistoricalPackets(rangeFirst: true)
  }
}
