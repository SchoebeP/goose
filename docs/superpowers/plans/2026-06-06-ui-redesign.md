# iOS UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the GooseSwift iOS app into an Apple-Health-clean 3-tab structure (Today / Trends / More) with a shared design system, restyled cards, and a new Trends tab. UI-only: no edits to BLE, parsing, store write-paths, upload pipelines, or `Info.plist`.

**Architecture:** SwiftUI app. `RootView` → `AppShellView` (TabView over `GooseAppTab.allCases`) → per-tab `NavigationStack`s. Live data is read off `GooseAppModel.ble` (a `GooseBLEClient` `ObservableObject`) and `HealthDataStore` (snapshots/trends). Minutely HR/steps are fetched from the VPS via `MinutelyHRFeed` / `MinutelyStepsFeed`. A `GooseTheme` enum + `View` extensions centralize palette/cards.

**Tech Stack:** Swift / SwiftUI, Xcode 26.5, iOS 26 deployment target, iPhone 17 Pro simulator. Build invokes an embedded Rust core via `Scripts/build_ios_rust.sh` (so `cargo` must be on `PATH`).

---

## Verified environment facts (read before starting)

- **Bundle id is `com.pschoebela.goosewhoop`** (verified in `GooseSwift.xcodeproj/project.pbxproj`). Always use `com.pschoebela.goosewhoop` for `simctl launch`.
- **Onboarding gate:** `RootView` reads `@AppStorage(OnboardingStorage.onboardingComplete)` where the key string is `"goose.swift.onboardingComplete"`, backed by `UserDefaults.standard`. The app shows a 6-step onboarding on first run unless this is `true`.
  - **Bypass mechanism (use in EVERY screenshot step):** pass it as a launch argument, which populates the volatile `NSArgumentDomain` that `UserDefaults.standard` reads first:
    `xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1`
  - **Fallback** if onboarding still appears (run AFTER install, BEFORE launch):
    `xcrun simctl spawn "iPhone 17 Pro" defaults write com.pschoebela.goosewhoop goose.swift.onboardingComplete -bool true`
- **No physical band is connected to the simulator.** Live HR / HRV / battery / connection will be `nil` / `"disconnected"`. The hero card BPM shows `—`, the device chip shows a red dot. This is EXPECTED. Verification steps check layout, card styling, labels, and empty states — NEVER live biometric numbers.
- **`GooseBLEClient` published properties** (all on `model.ble`): `connectionState: String` (e.g. `"disconnected"`), `liveHeartRateBPM: Int?`, `liveHeartRateSource: String`, `liveHeartRateUpdatedAt: Date?`, `liveHRVRMSSD: Double?`, `batteryLevelPercent: Int?`, `batteryIsCharging: Bool?`.
- **Hard constraints (CLAUDE.md + spec A6):** never edit `GooseBLEClient*`, `*Parsing*`, store write paths, upload/ingest, or `Info.plist`. All our computed metrics (HRV, steps, sleep estimate) must be labelled as OURS — never as WHOOP's. No recovery-% or 0–21 strain claims introduced. Non-medical copy only. Light AND dark mode must both look intentional.
- **Git:** repo is on `main`. Task 0 creates the working branch; never push.

---

## Task 0 — Create the working branch

**Files:** none (git only)

- [ ] Create and switch to the redesign branch:
```bash
git -C /Users/schoebela/PycharmProjects/goose checkout -b ui-redesign
```
- [ ] Confirm you are on `ui-redesign`:
```bash
git -C /Users/schoebela/PycharmProjects/goose branch --show-current
```
- [ ] Commit nothing yet (no changes). Proceed to Task 1.

---

## CHECKPOINT 1 — Design system + navigation

### Task 1 — Expand `GooseTheme` into a design system

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/GooseTheme.swift`

- [ ] Open `GooseTheme.swift`. Keep the existing `deviceBackground`, `appBackground`, `plainBackground`, `configureAppearance()` and the three `View` extensions EXACTLY as they are (they are referenced across the app). You are ADDING to the `GooseTheme` enum, not replacing it.

- [ ] Inside `enum GooseTheme { ... }`, directly after the existing `static let plainBackground = ...` block (before `configureAppearance()`), add the per-metric accent palette and card tokens:
```swift
  // MARK: - Apple-Health-clean design system (UI redesign)

  /// Per-metric accent colors (Apple Health style).
  enum Accent {
    static let heart = Color(red: 1.0, green: 0.216, blue: 0.373)      // #FF375F
    static let hrv = Color(red: 0.749, green: 0.353, blue: 0.949)      // #BF5AF2
    static let activity = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
    static let battery = Color(red: 0.188, green: 0.820, blue: 0.345)  // #30D158
    static let charging = Color(red: 1.0, green: 0.839, blue: 0.039)   // #FFD60A
    static let sleep = Color(red: 0.392, green: 0.824, blue: 1.0)      // #64D2FF
    static let range = Color(red: 1.0, green: 0.624, blue: 0.039)      // #FF9F0A
  }

  /// Card fill: #1C1C1E in dark, .secondarySystemGroupedBackground in light.
  static let cardBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
      : .secondarySystemGroupedBackground
  })

  static let cardCornerRadius: CGFloat = 14
  static let cardPadding: CGFloat = 16
```

- [ ] Add the shared `gooseCard()` modifier to the `extension View` block at the bottom of the file (append after `gooseListBackground()` inside the existing `extension View { ... }`):
```swift
  /// Apple-Health-clean card surface: flat fill, rounded corners, no border/shadow.
  func gooseCard(padding: CGFloat = GooseTheme.cardPadding) -> some View {
    self
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        GooseTheme.cardBackground,
        in: RoundedRectangle(cornerRadius: GooseTheme.cardCornerRadius, style: .continuous)
      )
  }
```

- [ ] After the `extension View { ... }` closing brace, add a reusable accent metric-label view used by the redesigned cards:
```swift
struct GooseMetricLabel: View {
  let systemImage: String
  let title: String
  let accent: Color

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.caption.weight(.bold))
        .foregroundStyle(accent)
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(accent)
    }
    .accessibilityElement(children: .combine)
  }
}
```

- [ ] Verify the build compiles (no UI wired to these yet — this proves the design-system code is valid Swift):
```bash
export PATH="$HOME/.cargo/bin:$PATH"   # REQUIRED: build script calls cargo
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
- [ ] Confirm the command printed `** BUILD SUCCEEDED **`. If it fails, read the error and fix the Swift before continuing.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/GooseTheme.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "Add Apple-Health-clean design system to GooseTheme

Adds per-metric accent palette, card background token, gooseCard() modifier,
and GooseMetricLabel. UI-only; no behaviour change yet.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 2 — Navigation: Today / Trends / More tabs

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/AppShellView.swift`

- [ ] In `AppShellView.swift`, in `enum GooseAppTab`, add a `trends` case. Place it after `case home`:
```swift
  case home
  case trends
  case health
  case available
  case cloudOnly
  case coach
  case more
```
(Do NOT rename `home` — `AppShellView`, `AppRouter.selectedTab = .home`, and deep links all depend on the `.home` case. We retitle it instead.)

- [ ] Update `allCases` to the new 3-tab order:
```swift
  static var allCases: [GooseAppTab] { [.home, .trends, .more] }
```

- [ ] In `var title`, retitle `home` to "Today" and add the `trends` title:
```swift
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
```

- [ ] In `var systemImage`, set the new icons (`heart.fill` Today, `chart.line.uptrend.xyaxis` Trends, `ellipsis.circle` More):
```swift
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
```

- [ ] Add a state binding for the Trends nav path. In `struct AppShellView`, after `@State private var homeSelectedDate = Date()`, add:
```swift
  @State private var trendsPath: [HealthRoute] = []
```

- [ ] In `tabNavigationStack(for:)`, add a branch for `.trends` (place it after the `.home` branch, before `.health`):
```swift
    } else if tab == .trends {
      NavigationStack(path: $trendsPath) {
        tabContent(for: tab)
          .navigationDestination(for: HealthRoute.self) { route in
            HealthRouteDestinationView(route: route, store: healthStore, selectedDate: $homeSelectedDate)
          }
      }
    } else if tab == .health {
```

- [ ] In `tabContent(for:)`, add a `.trends` case (place it after the `.home` case). `TrendsView` is created in Task 5 — to keep checkpoint 1 buildable, add a TEMPORARY placeholder for now and replace it in Task 6:
```swift
    case .home:
      HomeDashboardView(
        healthStore: healthStore,
        selectedDate: $homeSelectedDate,
        openHealthRoute: openHomeHealthRoute
      )
    case .trends:
      TrendsPlaceholderView()
```

- [ ] At the very bottom of `AppShellView.swift` (after the `WhoopMetricRow` struct), add the temporary placeholder so the build is green at checkpoint 1:
```swift
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
```

- [ ] Build:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
- [ ] Confirm `** BUILD SUCCEEDED **`.

- [ ] Install, launch with onboarding bypassed, and screenshot the tab bar (dark mode):
```bash
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl ui "iPhone 17 Pro" appearance dark
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/GooseSwift.app
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/nav-dark.png
```
- [ ] Capture light mode too:
```bash
xcrun simctl ui "iPhone 17 Pro" appearance light
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/nav-light.png
```
- [ ] Read `/tmp/nav-dark.png` and `/tmp/nav-light.png` and verify: (a) the app opened past onboarding (you see a dashboard, not the 6-step intro); (b) the bottom tab bar shows exactly three tabs — "Today" with a filled-heart icon, "Trends" with a line-chart icon, "More" with an ellipsis icon; (c) both appearances look intentional (dark = near-black background, light = grouped light background), no white-on-white or unreadable text. If onboarding still shows, run the `defaults write` fallback from the environment-facts section, relaunch, and re-screenshot.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/AppShellView.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "Navigation: Today / Trends / More 3-tab structure

Retitles Home->Today (heart.fill), adds Trends tab (chart.line.uptrend.xyaxis)
with its own NavigationStack + HealthRoute destinations, and a temporary
Trends placeholder pending the real TrendsView.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **PAUSE — user builds on device and approves before continuing.**

---

## CHECKPOINT 2 — Today tab

### Task 3 — Device chip header + restyle the heart-rate hero card

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/HomeDashboardView.swift`

- [ ] In `HomeDashboardView.swift`, replace the toolbar trailing watch icon with a device chip. In `var body`, find the `ToolbarItem(placement: .topBarTrailing)` block (the `NavigationLink { DeviceView() } label: { Image(systemName: "applewatch") ... }`) and replace the whole `ToolbarItem(placement: .topBarTrailing) { ... }` with:
```swift
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView()
        } label: {
          HomeDeviceChip()
        }
        .accessibilityLabel("Device")
        .accessibilityValue(deviceToolbarAccessibilityValue)
      }
```
(`deviceToolbarAccessibilityValue` and `deviceToolbarConnected` already exist in this file — keep them.)

- [ ] Add the `HomeDeviceChip` view. At the bottom of `HomeDashboardView.swift` (after the existing `HomeDecodedBandContent` struct), add:
```swift
/// Small capsule in the Today header: connection dot + battery % + charging bolt.
struct HomeDeviceChip: View {
  @EnvironmentObject private var model: GooseAppModel
  var body: some View { HomeDeviceChipContent(ble: model.ble) }
}

private struct HomeDeviceChipContent: View {
  @ObservedObject var ble: GooseBLEClient

  private var connected: Bool {
    let s = ble.connectionState.lowercased()
    return s == "ready" || s == "connected"
  }
  private var charging: Bool { ble.batteryIsCharging == true }

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(connected ? GooseTheme.Accent.activity : Color.red)
        .frame(width: 7, height: 7)
      Text(ble.batteryLevelPercent.map { "\($0)%" } ?? "—")
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
      if charging {
        Image(systemName: "bolt.fill")
          .font(.caption2.weight(.bold))
          .foregroundStyle(GooseTheme.Accent.charging)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(GooseTheme.cardBackground, in: Capsule(style: .continuous))
    .onAppear { ble.refreshBatteryLevel() }
  }
}
```

- [ ] Restyle the heart-rate hero card. In `private struct HomeLiveHeartRateContent`, replace the existing `VStack(alignment: .leading, spacing: 2) { Text("Live heart rate")... }` (the leading label+BPM column) with:
```swift
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            GooseMetricLabel(systemImage: "heart.fill", title: "Heart Rate", accent: GooseTheme.Accent.heart)
            if isLive {
              Text("LIVE")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(GooseTheme.Accent.heart, in: Capsule())
            }
          }
          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(ble.liveHeartRateBPM.map(String.init) ?? "—")
              .font(.system(size: 40, weight: .semibold, design: .rounded))
              .monospacedDigit()
            Text("bpm")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
```
- [ ] In the same struct, change the leading `Image(systemName: "heart.fill")` tint to use the accent: replace `.foregroundStyle(isLive ? .red : .secondary)` with `.foregroundStyle(isLive ? GooseTheme.Accent.heart : Color.secondary)`.
- [ ] Replace the card chrome at the end of `HomeLiveHeartRateContent.body`. Change the final modifiers from:
```swift
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onAppear { ble.refreshBatteryLevel() }
```
to:
```swift
    .gooseCard()
    .onAppear { ble.refreshBatteryLevel() }
```
(Keep the `Divider().overlay(...)` and battery row inside as-is. Optionally change the charging-state `.yellow` foregrounds to `GooseTheme.Accent.charging` and the discharged battery `.green` to `GooseTheme.Accent.battery` for palette consistency — do so for the `Image(systemName: "battery.100")` and the bolt.)

- [ ] Build, install, screenshot (dark):
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl ui "iPhone 17 Pro" appearance dark
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/GooseSwift.app
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/today-hero.png
```
- [ ] Read `/tmp/today-hero.png` and verify: (a) the top-right shows a small capsule chip (red dot since no band, `—%`), NOT the old watch glyph; (b) the heart-rate card has a "Heart Rate" accent label with a heart icon, a large `—` BPM numeral (no band = `—`, expected), and a flat dark card (corner radius ~14, no material blur). No "LIVE" badge appears (HR is nil). Layout is not clipped.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/HomeDashboardView.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "Today: device chip header + restyled heart-rate hero card

Replaces toolbar watch icon with a connection/battery/charging capsule chip,
and reskins the live HR card with the design system (accent label, LIVE badge,
gooseCard surface).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 4 — HRV + Steps stat row, HR range bars, restyle steps & stress, drop band card

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/HomeDashboardView.swift`

- [ ] Add an HRV + Steps stat-card row view. At the bottom of `HomeDashboardView.swift`, add:
```swift
/// Two side-by-side stat cards: HRV (rMSSD, ours) and today's step total (ours).
struct HomeStatCardRow: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var stepsFeed: MinutelyStepsFeed
  var body: some View { HomeStatCardRowContent(ble: model.ble, stepsFeed: stepsFeed) }
}

private struct HomeStatCardRowContent: View {
  @ObservedObject var ble: GooseBLEClient
  @ObservedObject var stepsFeed: MinutelyStepsFeed

  var body: some View {
    HStack(spacing: 12) {
      statCard(
        label: "HRV",
        icon: "waveform.path.ecg",
        accent: GooseTheme.Accent.hrv,
        value: ble.liveHRVRMSSD.map { String(format: "%.0f", $0) } ?? "—",
        unit: "ms",
        caption: "rMSSD — our own number"
      )
      statCard(
        label: "Steps",
        icon: "shoeprints.fill",
        accent: GooseTheme.Accent.activity,
        value: "\(stepsFeed.total)",
        unit: "",
        caption: "From accel — our own count"
      )
    }
  }

  private func statCard(label: String, icon: String, accent: Color, value: String, unit: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GooseMetricLabel(systemImage: icon, title: label, accent: accent)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(value)
          .font(.system(size: 30, weight: .semibold, design: .rounded))
          .monospacedDigit()
        if !unit.isEmpty {
          Text(unit).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Text(caption)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .gooseCard()
  }
}
```

- [ ] Replace the candlestick HR section's chart with rounded range bars. In `private struct MinutelyHRChart`, replace the entire body with:
```swift
private struct MinutelyHRChart: View {
  let minutes: [HRMinute]
  var body: some View {
    Canvas { ctx, size in
      guard !minutes.isEmpty else { return }
      let lo = Double((minutes.map { $0.lo }.min() ?? 40) - 3)
      let hi = Double((minutes.map { $0.hi }.max() ?? 120) + 3)
      let rng = max(hi - lo, 1)
      func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / rng) }
      let slot = size.width / CGFloat(minutes.count)
      let barW = max(1.5, min(slot * 0.62, 9))
      let accent = GooseTheme.Accent.range
      for (i, m) in minutes.enumerated() {
        let x = slot * (CGFloat(i) + 0.5)
        let top = y(Double(m.hi))
        let bot = y(Double(m.lo))
        let rect = CGRect(x: x - barW / 2, y: top, width: barW, height: max(2, bot - top))
        ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(accent))
      }
    }
  }
}
```

- [ ] Restyle the HR section card chrome and label. In `struct HomeMinutelyHRSection`, replace the `HStack { Text("Today · minute by minute")... }` with:
```swift
      HStack {
        GooseMetricLabel(systemImage: "heart.fill", title: "HR Range Today", accent: GooseTheme.Accent.range)
        Spacer()
        if !feed.minutes.isEmpty {
          Text("\(feed.minutes.count) min").font(.caption).foregroundStyle(.secondary)
        }
      }
```
- [ ] In the same struct, change the summary caption (the `Text("Latest \(last.bpm) bpm · range ...")`) to:
```swift
          Text("Range \(last.lo)–\(last.hi) bpm · latest \(last.bpm) · computed on our server")
            .font(.caption).foregroundStyle(.secondary)
```
- [ ] In the same struct, replace the card chrome:
  - Find:
    ```swift
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onAppear { feed.refresh() }
    ```
  - Replace with:
    ```swift
    .gooseCard()
    .onAppear { feed.refresh() }
    ```

- [ ] Restyle the steps section. In `struct HomeMinutelyStepsSection`, replace the header `HStack { Text("Steps today")...; Text("\(feed.total)")... }` with:
```swift
      HStack {
        GooseMetricLabel(systemImage: "shoeprints.fill", title: "Steps Today", accent: GooseTheme.Accent.activity)
        Spacer()
        Text("\(feed.total)").font(.headline.weight(.bold)).foregroundStyle(GooseTheme.Accent.activity)
      }
```
- [ ] In `private struct StepsBarChart`, replace `ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.green))` with `ctx.fill(Path(roundedRect: rect, cornerRadius: max(1, bw / 2)), with: .color(GooseTheme.Accent.activity))`.
- [ ] In `struct HomeMinutelyStepsSection`, replace the card chrome (the `.padding(18)` + `.frame(...)` + `.background(Color.secondary.opacity(0.08), ...)`) with `.gooseCard()` (keep `.onAppear`/`.onReceive`).

- [ ] Update `HomeDashboardView` for a shared steps feed. Add a `@StateObject` to `HomeDashboardView` after `@State private var selectedHealthMonitorTrend: HealthMetricSnapshot?`:
```swift
  @StateObject private var stepsFeed = MinutelyStepsFeed()
```
- [ ] In `HomeMinutelyStepsSection`, change `@StateObject private var feed = MinutelyStepsFeed()` to:
```swift
  @ObservedObject var feed: MinutelyStepsFeed
```
- [ ] Rewrite the `LazyVStack` contents in `HomeDashboardView.body` to (drops `HomeDecodedBandSection()` — moves to More in Task 7; do NOT delete the `HomeDecodedBandSection`/`HomeDecodedBandContent` structs):
```swift
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeLiveHeartRateWidget()

        HomeStatCardRow(stepsFeed: stepsFeed)

        HomeMinutelyHRSection()

        HomeMinutelyStepsSection(feed: stepsFeed)

        HomeStressEnergySection(
          stress: landingSnapshot(for: .stress),
          openStress: { openHealth(.stress) }
        )
      }
```
- [ ] In the existing `.task { ... }` block of `HomeDashboardView.body`, add: `stepsFeed.refresh()`.
- [ ] `HomeStressEnergySection` stays as-is inside the new layout (spec: stays, reskin only — its existing card style already reads in the new palette; if it uses `Color.secondary.opacity(0.08)` chrome, swap that for `.gooseCard()` the same way as the other sections).

- [ ] Build, install, screenshot (dark + light):
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/GooseSwift.app
xcrun simctl ui "iPhone 17 Pro" appearance dark
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/today-dark.png
xcrun simctl ui "iPhone 17 Pro" appearance light
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/today-light.png
```
- [ ] Read `/tmp/today-dark.png` and `/tmp/today-light.png` and verify: (a) order top→bottom is hero HR card, then a two-card HRV/Steps row, then "HR Range Today" card, then "Steps Today" card, then the stress card; (b) the "Decoded from your band" card is GONE from Today; (c) HRV card shows `—` ms with the caption "rMSSD — our own number"; Steps card shows a number with "our own count" caption; (d) the HR-range chart shows vertical rounded bars (or the "Waiting for today's data…" empty state) — NOT candlesticks; (e) both light and dark render cleanly with readable text and flat cards.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/HomeDashboardView.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "Today: HRV/Steps stat row, HR range bars, restyled steps; drop band card

Adds the HRV+Steps stat-card row (ours-labelled), converts the minutely HR
candlestick to rounded range bars, reskins the steps card to the design system,
shares one MinutelyStepsFeed, and removes the decoded-band card from Today
(moves to More). All metrics remain labelled as our own.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **PAUSE — user builds on device and approves before continuing.**

---

## CHECKPOINT 3 — Trends tab

### Task 5 — Trends data adapter (read-only) + trend card view

**Files:**
- Create: `/Users/schoebela/PycharmProjects/goose/GooseSwift/TrendsView.swift`

**IMPORTANT for the implementer:** the snippets below reference `healthStore.trendRows(for:)`, `HealthMetricSnapshot` fields (`.value/.unit/.freshness/.source/.systemImage/.tint/.trend`), trend row ids (`recovery-rhr-trend`, `recovery-hrv-trend`, `sleep-score-trend`), `trend.hasData`, `source.kind != .unavailable`, and a `HealthSparkline(points:tint:)` primitive. VERIFY each of these names against `HealthDataStore+Trends.swift`, `HealthModels.swift`/`HealthDataTypes.swift`, and `HealthChartPrimitives.swift` before writing the file, and adapt to the real names if they differ. Charts must only render when real data exists; otherwise show the empty cards.

- [ ] Create `TrendsView.swift`:
```swift
import SwiftUI

enum TrendPeriod: String, CaseIterable, Identifiable {
  case week = "W"
  case month = "M"
  case sixMonth = "6M"

  var id: String { rawValue }

  /// How many trailing points to show for this period.
  var pointCount: Int {
    switch self {
    case .week: 7
    case .month: 30
    case .sixMonth: 180
    }
  }
}

struct TrendsView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var healthStore: HealthDataStore
  @State private var period: TrendPeriod = .week

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        Picker("Period", selection: $period) {
          ForEach(TrendPeriod.allCases) { p in
            Text(p.rawValue).tag(p)
          }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 2)

        // Resting HR and Resting HRV — the genuinely-populated source.
        ForEach(recoveryTrendCards) { snapshot in
          TrendCard(snapshot: snapshot, period: period)
        }

        // Steps/day — no multi-day source exists (steps are not backfillable),
        // so this is an honest empty state, never fabricated.
        TrendEmptyCard(
          title: "Steps / day",
          systemImage: "shoeprints.fill",
          accent: GooseTheme.Accent.activity,
          message: "Daily step history isn't available yet — steps are counted live from the band and aren't backfilled."
        )

        // Sleep (our estimate) — render only if a populated trend exists.
        if let sleep = sleepTrendCard {
          TrendCard(snapshot: sleep, period: period, ours: true)
        } else {
          TrendEmptyCard(
            title: "Sleep (our estimate)",
            systemImage: "bed.double.fill",
            accent: GooseTheme.Accent.sleep,
            message: "Not enough sleep history yet. This is our own estimate, not WHOOP's."
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Trends")
    .navigationBarTitleDisplayMode(.large)
    .onAppear {
      model.recordUIAction("page.opened", detail: "Trends")
      healthStore.loadBridgeCatalogsIfNeeded()
    }
  }

  /// Resting HR + Resting HRV rows from the recovery trend set, filtered to ones
  /// that actually have data.
  private var recoveryTrendCards: [HealthMetricSnapshot] {
    let wanted: Set<String> = ["recovery-rhr-trend", "recovery-hrv-trend"]
    return healthStore.trendRows(for: .recovery)
      .filter { wanted.contains($0.id) && $0.source.kind != .unavailable && $0.trend.hasData }
  }

  private var sleepTrendCard: HealthMetricSnapshot? {
    healthStore.trendRows(for: .sleep)
      .first { $0.id == "sleep-score-trend" && $0.source.kind != .unavailable && $0.trend.hasData }
  }
}

struct TrendCard: View {
  let snapshot: HealthMetricSnapshot
  let period: TrendPeriod
  var ours: Bool = false

  private var points: [Double] {
    let all = snapshot.trend.points.map(\.value)
    return Array(all.suffix(period.pointCount))
  }

  private var average: Double? {
    guard !points.isEmpty else { return nil }
    return points.reduce(0, +) / Double(points.count)
  }

  /// Delta of recent-half mean vs older-half mean (nil if not enough points).
  private var delta: Double? {
    guard points.count >= 4 else { return nil }
    let mid = points.count / 2
    let older = points.prefix(mid)
    let recent = points.suffix(points.count - mid)
    guard !older.isEmpty, !recent.isEmpty else { return nil }
    let o = older.reduce(0, +) / Double(older.count)
    let r = recent.reduce(0, +) / Double(recent.count)
    return r - o
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        GooseMetricLabel(systemImage: snapshot.systemImage, title: snapshot.title, accent: snapshot.tint)
        Spacer()
        if let delta {
          let up = delta >= 0
          HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(String(format: "%+.0f", delta))
              .monospacedDigit()
          }
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(average.map { String(format: "%.0f", $0) } ?? snapshot.value)
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .monospacedDigit()
        if !snapshot.unit.isEmpty {
          Text(snapshot.unit).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
      }

      HealthSparkline(points: points, tint: snapshot.tint)
        .frame(height: 64)

      Text(captionText)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .gooseCard()
  }

  private var captionText: String {
    let base = "Avg over last \(points.count) · \(snapshot.freshness)"
    return ours ? base + " · our own estimate" : base
  }
}

struct TrendEmptyCard: View {
  let title: String
  let systemImage: String
  let accent: Color
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GooseMetricLabel(systemImage: systemImage, title: title, accent: accent)
      HStack(spacing: 10) {
        Image(systemName: "chart.line.uptrend.xyaxis")
          .font(.title3)
          .foregroundStyle(.tertiary)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .gooseCard()
  }
}
```

- [ ] Confirm the new file is picked up by the build (Xcode 26 synchronized file-system groups normally auto-include it):
```bash
grep -c "TrendsView.swift" GooseSwift.xcodeproj/project.pbxproj
```
(If this prints `0` AND the build can't find `TrendsView`, the file must be added via Xcode's file navigator — flag to the user; do not hand-edit `project.pbxproj` blindly.)

- [ ] Build (file is not yet wired into navigation — this just proves it compiles):
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```
- [ ] Confirm `** BUILD SUCCEEDED **`. If type/member names differ from the snippets (see IMPORTANT note above), adapt to the real API and rebuild until green — never stub out the data path with fake values.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/TrendsView.swift GooseSwift.xcodeproj/project.pbxproj
git -C /Users/schoebela/PycharmProjects/goose commit -m "Trends: data adapter + trend/empty cards (read-only)

Adds TrendsView with W/M/6M period switcher, TrendCard (avg + delta arrow +
sparkline) backed by healthStore.trendRows(for:), and honest empty states for
steps/day and sleep. Charts render only when trend data exists.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task 6 — Wire TrendsView into navigation

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/AppShellView.swift`

- [ ] In `AppShellView.tabContent(for:)`, replace the temporary placeholder with the real view:
```swift
    case .trends:
      TrendsView(healthStore: healthStore)
```
- [ ] Delete the temporary `TrendsPlaceholderView` struct added in Task 2 (at the bottom of `AppShellView.swift`).

- [ ] Build, install, launch, screenshot:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/GooseSwift.app
xcrun simctl ui "iPhone 17 Pro" appearance dark
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/trends-home.png
```
- [ ] Read `/tmp/trends-home.png`: the app launches to Today with the 3-tab bar intact and no crash. If UI automation is available in the environment, tap the Trends tab and screenshot it; verify the segmented W/M/6M control and the steps/day + sleep empty-state cards ("not enough history yet" / "our own estimate"). Otherwise the Trends rendering is confirmed by the user at the checkpoint pause.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/AppShellView.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "Trends: wire TrendsView into the Trends tab

Replaces the placeholder with TrendsView(healthStore:) and removes the
temporary placeholder view.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **PAUSE — user builds on device and approves before continuing.** (The user confirms the Trends tab renders the period switcher, real RHR/HRV cards when their device has history, and honest empty states for steps/sleep.)

---

## CHECKPOINT 4 — More tab

### Task 7 — Regroup More sections + Packet Inspector link row

**Files:**
- Modify: `/Users/schoebela/PycharmProjects/goose/GooseSwift/MoreView.swift`

**IMPORTANT for the implementer:** the snippet below assumes `MoreRoute` cases `device, connectionLab, capture, localStore, healthSync, rawExport, algorithms, debug, developer, privacy, support, about, profile`, a `routeRows(_:)` helper, and `MoreGreetingHeader(firstName:profileSummary:)`. VERIFY against the real `MoreView.swift` / `MoreRouteModels.swift` and adapt — the rule is: regroup into Device / Band / Capture & Sync / Debug / Profile & Info, preserve EVERY existing route exactly once, add the Band summary + Packet Inspector link. If `routeRows` doesn't exist, render each route row the same way the current file does.

- [ ] In `MoreView.body`, regroup the `List { ... }` sections to:
```swift
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
```

- [ ] Add the Band summary row and Packet Inspector link row at the bottom of `MoreView.swift` (after the closing brace of `struct MoreView`):
```swift
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
```
(`HomeDecodedBandSection`/`HomeDecodedBandContent` in `HomeDashboardView.swift` become dead code after this — leave them; deleting is out of scope for this UI-only branch.)

- [ ] Build, install, screenshot:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/GooseSwift.app
xcrun simctl ui "iPhone 17 Pro" appearance dark
xcrun simctl launch "iPhone 17 Pro" com.pschoebela.goosewhoop -goose.swift.onboardingComplete 1
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/more-dark.png
```
- [ ] Read `/tmp/more-dark.png` (launch lands on Today; confirm 3-tab bar + no crash). If UI automation is available, tap More and verify the five sections (Device / Band / Capture & Sync / Debug / Profile & Info), the Band decoded-channels rows, and the "Packet Inspector → On your dashboard" row with an up-right arrow. Otherwise the user verifies at the pause.

- [ ] Commit:
```bash
git -C /Users/schoebela/PycharmProjects/goose add GooseSwift/MoreView.swift
git -C /Users/schoebela/PycharmProjects/goose commit -m "More: regroup sections + Band summary + Packet Inspector link

Regroups into Device / Band / Capture & Sync / Debug / Profile & Info (all
existing routes preserved), moves the decoded-band summary here from Today,
and adds a display-only Packet Inspector dashboard link.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **PAUSE — user builds on device and approves before continuing.** (User confirms the More tab grouping, the Band summary rows, and the Packet Inspector link in both light and dark mode.)

---

## Self-Review checklist (run before declaring done)

- [ ] **Spec coverage:** A1 → Task 1; A2 → Task 2; A3 → Tasks 3–4; A4 → Tasks 5–6; A5 → Task 7; A6 constraints respected throughout (no BLE/parsing/Info.plist edits, ours-labelling, non-medical copy); A7 → builds + user PAUSEs per checkpoint.
- [ ] **No placeholders left:** the only intentional placeholder (`TrendsPlaceholderView`) is added in Task 2 and removed in Task 6.
- [ ] **Type consistency:** verify every referenced symbol against the real codebase before each task (notably `HealthMetricSnapshot` fields, trend row ids, `HealthSparkline`, `MoreRoute` cases) and adapt if names differ — never invent data.
- [ ] **Bundle id / onboarding bypass** used in every launch step (`com.pschoebela.goosewhoop`, `-goose.swift.onboardingComplete 1`).
- [ ] **Light + dark** captured at each visual checkpoint.
- [ ] **Git hygiene:** branch `ui-redesign`, focused commits with `Co-Authored-By`, no push.
