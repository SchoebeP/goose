import Foundation
import Combine

/// Single source of truth for the Dev/Clean split.
///
/// "Clean" (Release) is what a stranger installs: zero debug/diagnostic
/// surfaces, zero raw-data dumps, zero experimental toggles. "Dev" (Debug)
/// keeps the full toolbox (Packet Inspector links, raw frame/hex dumps,
/// protocol commands, capture/export tooling, algorithm calibration, etc).
///
/// HOW TO GATE A DEV-ONLY SURFACE (for this track and anything added later,
/// e.g. the UI-cleanup pass that follows this one):
///
///  1. Screens, NavigationLink rows/destinations, deep-link handlers, or any
///     other "registration" of dev-only functionality: wrap the call site in
///     `#if DEBUG ... #endif`. This is the strong guarantee — the Release
///     build never compiles or links that code, so it is not merely hidden,
///     it does not exist in the Clean binary and cannot be turned on there.
///
///  2. Inside a `#if DEBUG` block (or a shared data path that already only
///     matters in Debug), additionally check `DeveloperSettings.shared.isEnabled`
///     when you want the surface to be toggle-able within a Debug build too
///     (e.g. to preview what Clean looks like, or take a clean screenshot,
///     without doing a full Release build). Example:
///
///       #if DEBUG
///       if DeveloperSettings.shared.isEnabled {
///         NavigationLink(value: MoreRoute.debug) { ... }
///       }
///       #endif
///
///     For a data-level filter shared by both configurations (e.g. trimming
///     dev-only entries out of a list that both Debug and Release render),
///     it is fine to check `DeveloperSettings.shared.isEnabled` directly
///     without `#if DEBUG`: it is a hardcoded, non-toggleable `false` in
///     Release (see below), so the effect is identical to compiling it out.
///
///  3. Never gate the ONE navigation entry point back to the toggle itself
///     (see `MoreDeveloperView`) behind `isEnabled` — only behind `#if DEBUG`.
///     Otherwise turning dev tools off would strand the developer with no
///     way back to turn them on again.
///
/// Release builds ship no toggle UI (it is itself `#if DEBUG`-only) and
/// `isEnabled` is a hardcoded `let false` there — not `@Published`, not
/// backed by UserDefaults — so dev tooling cannot be switched on in a Clean
/// build by any means, including a shared UserDefaults suite carrying over
/// a `true` from a Debug install.
@MainActor
final class DeveloperSettings: ObservableObject {
  static let shared = DeveloperSettings()

#if DEBUG
  private static let storageKey = "goose.swift.developer.toolsEnabled"

  /// Debug builds default to dev tools visible; the toggle persists across launches.
  @Published var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Self.storageKey)
    }
  }

  private init() {
    if UserDefaults.standard.object(forKey: Self.storageKey) != nil {
      isEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
    } else {
      isEnabled = true
    }
  }
#else
  /// Always false: Release ships no toggle UI and no stored override can
  /// flip this — dev tooling is physically unavailable in a Clean build.
  let isEnabled = false

  private init() {}
#endif
}
