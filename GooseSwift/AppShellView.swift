import SwiftUI

struct AppShellView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @StateObject private var healthStore = HealthDataStore()
  @State private var homeHealthPath: [HealthRoute] = []
  @State private var homeSelectedDate = Date()
  @State private var trendsPath: [HealthRoute] = []

  var body: some View {
    TabView(selection: tabSelection) {
      ForEach(GooseAppTab.allCases) { tab in
        tabNavigationStack(for: tab)
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
  }

  private var tabSelection: Binding<GooseAppTab> {
    Binding {
      router.selectedTab
    } set: { newTab in
      if newTab == router.selectedTab {
        router.reselect(newTab)
        return
      }
      router.selectedTab = newTab
      model.recordUIAction("tab.selected", detail: newTab.title)
    }
  }

  @ViewBuilder
  private func tabNavigationStack(for tab: GooseAppTab) -> some View {
    if tab == .home {
      NavigationStack(path: $homeHealthPath) {
        tabContent(for: tab)
          .navigationDestination(for: HealthRoute.self) { route in
            HealthRouteDestinationView(route: route, store: healthStore, selectedDate: $homeSelectedDate)
          }
      }
    } else if tab == .trends {
      NavigationStack(path: $trendsPath) {
        tabContent(for: tab)
          .navigationDestination(for: HealthRoute.self) { route in
            HealthRouteDestinationView(route: route, store: healthStore, selectedDate: $homeSelectedDate)
          }
      }
    } else if tab == .health {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab)
      }
    } else if tab == .more {
      NavigationStack(path: $router.morePath) {
        tabContent(for: tab)
      }
    } else {
      NavigationStack {
        tabContent(for: tab)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: GooseAppTab) -> some View {
    switch tab {
    case .home:
      HomeDashboardView(
        healthStore: healthStore,
        selectedDate: $homeSelectedDate,
        openHealthRoute: openHomeHealthRoute
      )
    case .trends:
      TrendsPlaceholderView()
    case .health:
      HealthView(store: healthStore)
    case .available:
      AvailableMetricsView()
    case .cloudOnly:
      CloudOnlyMetricsView()
    case .coach:
      CoachView(healthStore: healthStore)
    case .more:
      MoreView(healthStore: healthStore)
    }
  }

  private func openHomeHealthRoute(_ route: HealthRoute) {
    homeHealthPath = [route]
  }
}

enum GooseAppTab: String, CaseIterable, Identifiable {
  case home
  case trends
  case health
  case available
  case cloudOnly
  case coach
  case more

  // 4.0-focused, noise-trimmed UI: only Home (all the real decoded data + live
  // pulse) and More (connect / capture / debug). Available is folded into Home;
  // Cloud (WHOOP's proprietary cloud metrics we can't get), Health (cloud
  // dashboards) and Coach are hidden — their views still exist, just untabbed.
  static var allCases: [GooseAppTab] { [.home, .trends, .more] }

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Today"
    case .trends: "Trends"
    case .health: "Health"
    case .available: "Available"
    case .cloudOnly: "Cloud"
    case .coach: "Coach"
    case .more: "More"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "heart.fill"
    case .trends: "chart.line.uptrend.xyaxis"
    case .health: "heart.text.square"
    case .available: "waveform.path.ecg"
    case .cloudOnly: "cloud"
    case .coach: "sparkles"
    case .more: "ellipsis.circle"
    }
  }

}

// MARK: - Available vs Cloud-only tabs (WHOOP 4.0 data split for RE work)

/// Data we DO decode locally from the WHOOP 4.0 over BLE.
struct AvailableMetricsView: View {
  @EnvironmentObject private var model: GooseAppModel
  // Observe the BLE client DIRECTLY so live values (battery, HR, HRV) refresh —
  // observing `model` alone misses updates to the nested observable `ble`.
  var body: some View { AvailableMetricsContent(ble: model.ble) }
}

private struct AvailableMetricsContent: View {
  @ObservedObject var ble: GooseBLEClient

  var body: some View {
    List {
      Section {
        WhoopMetricRow(icon: "heart.fill", tint: .red, title: "Heart rate",
                       value: ble.liveHeartRateBPM.map { "\($0) bpm" } ?? "—")
        WhoopMetricRow(icon: "waveform.path.ecg", tint: .pink, title: "HRV (RMSSD)",
                       value: ble.liveHRVRMSSD.map { String(format: "%.0f ms", $0) } ?? "—")
        WhoopMetricRow(icon: "battery.100", tint: .green, title: "Battery",
                       value: ble.batteryLevelPercent.map { "\($0)%" } ?? "—")
        WhoopMetricRow(icon: "antenna.radiowaves.left.and.right", tint: .blue, title: "Connection",
                       value: ble.connectionState.capitalized)
      } header: {
        Text("Decoded on-device from your band")
      } footer: {
        Text("Live over Bluetooth. R-R intervals feed HRV — and they're what we'll use to reverse-engineer respiratory rate.")
      }

      Section("Also captured (Mac/cloud collector)") {
        WhoopMetricRow(icon: "move.3d", tint: .orange, title: "Accelerometer", value: "validated · 1g")
        WhoopMetricRow(icon: "bell.fill", tint: .gray, title: "Device events", value: "battery · wrist · charging")
      }
    }
    .navigationTitle("Available")
    .onAppear { ble.refreshBatteryLevel() }  // re-read the band, like the Device view does
  }
}

/// Metrics WHOOP computes in its cloud — not on the band as usable values (yet).
struct CloudOnlyMetricsView: View {
  var body: some View {
    List {
      Section {
        WhoopMetricRow(icon: "lungs.fill", tint: .teal, title: "Respiratory rate",
                       value: "—", note: "Raw signal is on the wire; rate is cloud-computed. Derivable from R-R variability — next up.")
        WhoopMetricRow(icon: "drop.fill", tint: .blue, title: "Blood oxygen (SpO₂)",
                       value: "—", note: "Only raw red/IR PPG on the band. Needs PPG channel-decode + an oximeter to calibrate.")
        WhoopMetricRow(icon: "thermometer.medium", tint: .orange, title: "Skin temperature",
                       value: "—", note: "Only a raw thermistor ADC. Needs a calibration curve.")
        WhoopMetricRow(icon: "bed.double.fill", tint: .indigo, title: "Sleep stages",
                       value: "—", note: "Proprietary cloud model. We can build our own estimate (accel + HR).")
        WhoopMetricRow(icon: "heart.text.square.fill", tint: .green, title: "Recovery %",
                       value: "—", note: "Proprietary cloud score. We can compute our own from HRV / resting HR.")
        WhoopMetricRow(icon: "flame.fill", tint: .red, title: "Strain (0–21)",
                       value: "—", note: "Proprietary cloud score. We can compute our own cardio-load estimate.")
      } header: {
        Text("Not on the band — WHOOP computes these in its cloud")
      } footer: {
        Text("None of these are transmitted as finished numbers. We reverse-engineer them ourselves, clearly labelled as our own estimates — never WHOOP's.")
      }
    }
    .navigationTitle("Cloud-Only")
  }
}

private struct WhoopMetricRow: View {
  let icon: String
  let tint: Color
  let title: String
  let value: String
  var note: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .foregroundStyle(tint)
          .frame(width: 26)
        Text(title)
        Spacer()
        Text(value)
          .foregroundStyle(value == "—" ? .secondary : .primary)
          .fontWeight(.semibold)
          .monospacedDigit()
      }
      if let note {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.leading, 38)
      }
    }
    .padding(.vertical, 2)
  }
}

/// Temporary placeholder for the Trends tab; replaced by TrendsView in Task 6.
struct TrendsPlaceholderView: View {
  var body: some View {
    ContentUnavailableView(
      "Trends",
      systemImage: "chart.line.uptrend.xyaxis",
      description: Text("Coming next.")
    )
    .navigationTitle("Trends")
    .gooseScreenBackground()
  }
}
