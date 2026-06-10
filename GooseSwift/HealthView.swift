import Darwin
import Foundation
import SwiftUI
import UIKit

struct HealthView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var store: HealthDataStore

  var body: some View {
    // One evaluation per render: each landingSnapshots call re-runs the full
    // stress/energy pipeline over the day's HR samples.
    let snaps = landingSnapshots
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        HealthDashboardStatusHeader(
          catalogStatus: store.catalogStatus,
          usesSampleData: store.usesSampleData
        )

        HealthActivityOverviewSection(
          steps: store.whoopStepsDisplayText(),
          activeEnergy: store.whoopActiveCaloriesDisplayText(),
          stepsFreshness: store.whoopStepsStatusText(),
          stepsSource: store.whoopStepsSource(),
          activeEnergyFreshness: store.whoopActiveCaloriesStatusText(),
          activeEnergySource: store.whoopActiveCaloriesSource(),
          heartRateValue: liveHeartRateValue,
          heartRateStatus: liveHeartRateStatus,
          heartRateSource: liveHeartRateSource
        )

        HealthVitalsPreviewSection(snapshots: vitalSnapshots)

        HealthRouteShortcutSection(
          title: "Explore Health",
          snapshots: snapshots(for: [.sleep, .recovery, .strain, .stress, .cardioLoad, .energyBank], in: snaps)
        )

        HealthRouteShortcutSection(
          title: "Data & Algorithms",
          snapshots: snapshots(for: [.packetInputs, .algorithms, .calibration], in: snaps)
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Health")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationDestination(for: HealthRoute.self) { route in
      HealthRouteContentView(route: route, store: store)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          refreshDashboard()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh Health")
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Health")
      store.loadBridgeCatalogsIfNeeded()
      store.refreshHeartRateTimeline()
    }
  }

  private var landingSnapshots: [HealthMetricSnapshot] {
    store
      .landingSnapshots(
        liveHeartRateBPM: model.ble.liveHeartRateBPM,
        liveHeartRateSource: model.ble.liveHeartRateSource,
        liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt
      )
  }

  private var vitalSnapshots: [HealthMetricSnapshot] {
    Array(store.healthMonitorSnapshots().prefix(4))
  }

  private var liveHeartRateValue: String {
    guard let bpm = model.ble.liveHeartRateBPM else {
      return "--"
    }
    return "\(bpm) bpm"
  }

  private var liveHeartRateStatus: String {
    guard model.ble.liveHeartRateBPM != nil else {
      return store.heartRateTimelineStatus
    }
    return HealthDataStore.relativeText(for: model.ble.liveHeartRateUpdatedAt) ?? "Live"
  }

  private var liveHeartRateSource: HealthDataSource {
    model.ble.liveHeartRateBPM == nil
      ? .unavailable("BLE heart-rate stream waiting")
      : .live(model.ble.liveHeartRateSource)
  }

  private func snapshots(
    for routes: [HealthRoute],
    in landingSnapshots: [HealthMetricSnapshot]
  ) -> [HealthMetricSnapshot] {
    routes.compactMap { route in
      landingSnapshots.first { $0.route == route } ?? store.snapshot(for: route)
    }
  }

  @MainActor
  private func refreshDashboard() {
    store.refreshBridgeCatalogs()
    store.refreshHeartRateTimeline()
    store.refreshPacketInputsIfNeeded()
  }
}
