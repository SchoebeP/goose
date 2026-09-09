import SwiftUI

/// "More" — Radiograph redesign. The instrument's control ledger: band,
/// capture, debug. Same routes and destinations as the legacy MoreView.
struct InkMoreView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @ObservedObject var healthStore: HealthDataStore
  @StateObject private var store = MoreDataStore()
#if DEBUG
  @ObservedObject private var developerSettings = DeveloperSettings.shared
#endif

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        InkBandStatus(ble: model.ble)
          .padding(.top, 14)

        routeGroup("Device", routes: deviceRoutes)
#if DEBUG
        if developerSettings.isEnabled {
          routeGroup("Capture & sync", routes: [.capture, .localStore, .healthSync, .rawExport])
          routeGroup("Debug", routes: [.algorithms, .debug, .developer])
          inspectorLink
        } else {
          // Keep exactly one way back to the toggle — never strand the
          // developer with dev tools hidden and no path to re-enable them.
          routeGroup("Debug", routes: [.developer])
        }
#endif
        routeGroup("Info", routes: [.privacy, .support, .about])
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.bottom, 34)
    }
    .inkScreen()
    .toolbar(.hidden, for: .navigationBar)
    .navigationDestination(for: MoreRoute.self) { route in
      destination(for: route)
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "More (ink)")
      store.refreshBridgeStatus(model: model)
      store.refreshRecentCaptureSessions()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Instrument").inkEyebrow()
      Text("More")
        .font(InkTheme.screenTitle)
        .foregroundStyle(InkTheme.ink)
    }
    .padding(.top, 12)
  }

  /// Connection Lab is raw BLE/diagnostic tooling — Dev only, and further
  /// gated by the developer-tools toggle so turning it off truthfully hides
  /// this row too (matching the "Show Developer Tools" help text).
  private var deviceRoutes: [MoreRoute] {
#if DEBUG
    developerSettings.isEnabled ? [.profile, .device, .connectionLab] : [.profile, .device]
#else
    [.profile, .device]
#endif
  }

  private func routeGroup(_ title: String, routes: [MoreRoute]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .inkEyebrow()
        .padding(.top, InkTheme.sectionSpacing)
        .padding(.bottom, 6)
      InkRule()
      ForEach(routes) { route in
        NavigationLink(value: route) {
          InkRouteRow(title: route.title, subtitle: route.subtitle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(route.title)
        InkRule()
      }
    }
  }

  private var inspectorLink: some View {
    VStack(alignment: .leading, spacing: 0) {
      Link(destination: URL(string: "https://latenightgames.fr/whoop/inspector")!) {
        InkRouteRow(
          title: "Packet inspector",
          subtitle: "Raw frames on the server, annotated byte by byte"
        )
      }
      .buttonStyle(.plain)
      InkRule()
    }
  }

  @ViewBuilder
  private func destination(for route: MoreRoute) -> some View {
    switch route {
    case .device:
      DeviceView()
    case .profile:
      MoreProfileView()
#if DEBUG
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
    case .developer:
      MoreDeveloperView(
        routes: MoreRoute.developerToolRoutes,
        routeStatus: store.routeStatus(ble: model.ble, model: model)
      )
#endif
    case .privacy:
      MorePrivacyView(store: store)
    case .support:
      MoreSupportView(store: store)
    case .about:
      MoreAboutView(store: store)
#if !DEBUG
    case .connectionLab, .capture, .localStore, .healthSync, .rawExport, .algorithms, .debug, .developer:
      // Compiled out of Release entirely (see the #if DEBUG block above) —
      // this only exists to keep the switch exhaustive against MoreRoute.
      // Unreachable: no row or link in a Clean build ever pushes these.
      EmptyView()
#endif
    }
  }
}

/// Band status strip — observes the BLE client directly to stay fresh.
private struct InkBandStatus: View {
  @ObservedObject var ble: GooseBLEClient

  private var isConnected: Bool {
    let state = ble.connectionState.lowercased()
    return state.contains("connect") && !state.contains("dis")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      InkLedgerRow(
        label: "Band",
        value: ble.activeDeviceName,
        valueColor: InkTheme.ink
      )
      InkRule()
      InkLedgerRow(
        label: "Link",
        value: isConnected ? "Connected" : ble.connectionState.capitalized,
        valueColor: isConnected ? InkTheme.ink : InkTheme.graphite
      )
      InkRule()
      InkLedgerRow(
        label: "Battery",
        value: batteryText,
        valueColor: InkTheme.ink
      )
      InkRule()
      InkLedgerRow(
        label: "Last sync",
        value: ble.lastSyncAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never",
        valueColor: InkTheme.graphite
      )
      InkRule()
    }
  }

  private var batteryText: String {
    guard let percent = ble.batteryLevelPercent else { return "--" }
    let charging = ble.batteryIsCharging == true ? " · charging" : ""
    return "\(percent)%\(charging)"
  }
}

private struct InkRouteRow: View {
  let title: String
  let subtitle: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .medium, design: .serif))
          .foregroundStyle(InkTheme.ink)
        Text(subtitle)
          .font(InkTheme.footnote)
          .foregroundStyle(InkTheme.graphite)
          .lineLimit(1)
      }
      Spacer(minLength: 10)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(InkTheme.hairline)
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}
