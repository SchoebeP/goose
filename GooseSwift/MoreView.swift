import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

struct MoreView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @ObservedObject private var healthStore: HealthDataStore
  @StateObject private var store: MoreDataStore
  @AppStorage(OnboardingStorage.firstName) private var profileFirstName = ""
  @AppStorage(OnboardingStorage.unitSystem) private var profileUnitSystemRaw = "imperial"
  @AppStorage(OnboardingStorage.heightMm) private var profileHeightMm = 0
  @AppStorage(OnboardingStorage.weightGrams) private var profileWeightGrams = 0
  @AppStorage(GooseAppModel.liveHeartRateActivityDefaultsKey) private var liveHeartRateActivityEnabled = false

  @MainActor
  init(healthStore: HealthDataStore) {
    self.healthStore = healthStore
    _store = StateObject(wrappedValue: MoreDataStore())
  }

  @MainActor
  init(healthStore: HealthDataStore, store: MoreDataStore) {
    self.healthStore = healthStore
    _store = StateObject(wrappedValue: store)
  }

  var body: some View {
    List {
      Section {
        NavigationLink(value: MoreRoute.profile) {
          MoreGreetingHeader(
            firstName: profileFirstName,
            profileSummary: profileSummary
          )
        }
        .accessibilityLabel("Update profile")
      }

      Section("Device") {
        routeRows([.device, .connectionLab])
        Toggle(isOn: $liveHeartRateActivityEnabled) {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Live Heart Rate on Lock Screen")
              Text("Shows live BPM in the Dynamic Island while the band streams")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "heart.fill").foregroundStyle(.red)
          }
        }
        .onChange(of: liveHeartRateActivityEnabled) { _, _ in
          model.syncLiveHeartRateActivity()
        }
      }

      Section("Band") {
        MoreBandSummaryRow()
      }

      Section("Capture & Sync") {
        routeRows([.capture, .localStore, .healthSync, .rawExport])
      }

      Section("Debug") {
        routeRows([.algorithms, .debug, .developer])
      }

      Section("Profile & Info") {
        Link(destination: URL(string: "https://latenightgames.fr/whoop/inspector")!) {
          MorePacketInspectorRow()
        }
        routeRows([.privacy, .support, .about])
      }
    }
    .listStyle(.insetGrouped)
    .gooseListBackground()
    .navigationTitle("More")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationDestination(for: MoreRoute.self) { route in
      destination(for: route)
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "More")
      store.refreshBridgeStatus(model: model)
      store.refreshRecentCaptureSessions()
    }
  }

  private var routeStatus: MoreRouteStatus {
    store.routeStatus(ble: model.ble, model: model)
  }

  @ViewBuilder
  private func routeRows(_ routes: [MoreRoute]) -> some View {
    ForEach(routes) { route in
      NavigationLink(value: route) {
        MoreRouteRow(route: route, status: routeStatus[keyPath: route.statusKeyPath])
      }
      .accessibilityLabel(route.title)
    }
  }

  @ViewBuilder
  private func destination(for route: MoreRoute) -> some View {
    switch route {
    case .device:
      DeviceView()
    case .profile:
      MoreProfileView()
    case .connectionLab:
      ConnectionView()
    case .capture:
      MoreCaptureView(store: store)
    case .localStore:
      MoreLocalStoreView(store: store)
    case .healthSync:
      MoreHealthSyncView(store: store)
    case .rawExport:
      MoreRawExportView(store: store)
    case .algorithms:
      MoreAlgorithmsView(store: store, healthStore: healthStore) {
        router.openHealth(.algorithms)
      }
    case .debug:
      MoreDebugView(store: store)
    case .privacy:
      MorePrivacyView(store: store)
    case .support:
      MoreSupportView(store: store)
    case .about:
      MoreAboutView(store: store)
    case .developer:
      MoreDeveloperView(routes: MoreRoute.developerToolRoutes, routeStatus: routeStatus)
    }
  }

  private var profileSummary: String {
    let height = MoreProfileFormatting.heightText(millimeters: profileHeightMm, unitSystemRaw: profileUnitSystemRaw)
    let weight = MoreProfileFormatting.weightText(grams: profileWeightGrams, unitSystemRaw: profileUnitSystemRaw)
    let parts = [height, weight].filter { !$0.isEmpty }
    return parts.isEmpty ? "Update profile" : parts.joined(separator: " | ")
  }
}

/// Decoded-channels summary that used to live on the Home tab (spec A5).
struct MoreBandSummaryRow: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { MoreBandSummaryContent(ble: model.ble) }
}

private struct MoreBandSummaryContent: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      bandRow("antenna.radiowaves.left.and.right", .blue, "Connection", ble.connectionState.capitalized)
      bandRow("move.3d", GooseTheme.Accent.range, "Accelerometer", "validated · 1g")
      bandRow("bell.fill", .gray, "Device events", "wrist · charging · battery")
      Text("Heart rate, HRV and battery show on the Today tab. Sleep, recovery and strain are WHOOP-cloud only and intentionally absent — anything we derive is our own estimate.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .onAppear { ble.refreshBatteryLevel() }
  }

  private func bandRow(_ icon: String, _ tint: Color, _ title: String, _ value: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
      Text(title)
      Spacer()
      Text(value).foregroundStyle(.secondary).fontWeight(.semibold)
    }
  }
}

/// Display-only convenience link to the VPS Packet Inspector (Branch B).
struct MorePacketInspectorRow: View {
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "rectangle.and.text.magnifyingglass")
        .foregroundStyle(GooseTheme.Accent.hrv)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text("Packet Inspector")
          .foregroundStyle(.primary)
        Text("On your dashboard")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "arrow.up.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
    .accessibilityLabel("Packet Inspector on your dashboard")
  }
}
