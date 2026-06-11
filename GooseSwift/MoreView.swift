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
        MoreBandCard(ble: model.ble)
      }
      .gdaCardListRow()

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

      Section {
        MorePrivacyCard()
      }
      .gdaCardListRow()

      Section {
        MoreLocalFootnote()
      }
      .gdaCardListRow()
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

// MARK: - Direction A "Quiet Companion" PMore cards

/// Top band card (PMore): 46pt rounded icon well, name, connection status, and
/// a right-aligned battery readout with charging state. Pure display, derived
/// live from the BLE client.
private struct MoreBandCard: View {
  @ObservedObject var ble: GooseBLEClient

  private var isConnected: Bool {
    ble.connectionState == "ready" || ble.connectionState == "connected"
  }

  private var connectionText: String {
    isConnected ? "Connected · in range" : "Out of range"
  }

  private var batteryText: String {
    if let pct = ble.batteryLevelPercent { return "\(pct)%" }
    return "—"
  }

  private var chargingText: String {
    (ble.batteryIsCharging ?? false) ? "charging" : "not charging"
  }

  var body: some View {
    HStack(spacing: 14) {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(GDA.surface3)
        .frame(width: 46, height: 46)
        .overlay(
          Image(systemName: "sensor.tag.radiowaves.forward.fill")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(GDA.text2)
        )
      VStack(alignment: .leading, spacing: 2) {
        Text("WHOOP 4.0 band")
          .font(.system(size: 17, weight: .bold, design: .rounded))
          .foregroundStyle(GDA.text)
        Text(connectionText)
          .font(.system(size: 13))
          .foregroundStyle(GDA.text2)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(batteryText)
          .font(GDA.num(22))
          .foregroundStyle(GDA.text)
        Text(chargingText)
          .font(.system(size: 11.5))
          .foregroundStyle(GDA.text3)
      }
    }
    .gdaCard()
    .onAppear { ble.refreshBatteryLevel() }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("WHOOP 4.0 band, \(connectionText), battery \(batteryText), \(chargingText)")
  }
}

/// Privacy card (PMore): lock icon + verbatim local-first statement.
private struct MorePrivacyCard: View {
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "lock.fill")
        .font(.system(size: 20))
        .foregroundStyle(GDA.activity)
      (
        Text("Local-first.").foregroundColor(GDA.text)
          + Text(" Your data moves between this phone and your own server — nowhere else. No analytics, no third parties, no WHOOP cloud. Every number here is computed by Goose.")
            .foregroundColor(GDA.text2)
      )
      .font(.system(size: 13))
      .lineSpacing(3)
      .fixedSize(horizontal: false, vertical: true)
    }
    .gdaCard()
    .accessibilityElement(children: .combine)
  }
}

/// Centered version footnote (PMore).
private struct MoreLocalFootnote: View {
  var body: some View {
    Text("Goose 0.4 · not a medical device · raw signals & rough estimates only")
      .font(.system(size: 12.5))
      .foregroundStyle(GDA.text3)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
  }
}

private extension View {
  /// Renders a `Section`'s row as a borderless card on the grouped-list
  /// background, so Direction A cards sit cleanly among the existing rows.
  func gdaCardListRow() -> some View {
    listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
  }
}
