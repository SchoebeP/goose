import Foundation

@MainActor
final class AppRouter: ObservableObject {
  @Published var selectedTab: GooseAppTab = .home
  @Published var healthPath: [HealthRoute] = []
  @Published var morePath: [MoreRoute] = []
  @Published var codexAuthCallbackURL: URL?
  @Published var codexEmbeddedLoginRequestID = 0
  @Published var coachPromptDraft = ""
  @Published var coachPromptRequestID = 0
  @Published var coachScrollToBottomRequestID = 0

  func openHealth(_ route: HealthRoute?) {
    selectedTab = .health
    if let route {
      healthPath = [route]
    } else {
      healthPath = []
    }
  }

  func openCoach(prompt: String? = nil) {
    // Coach removed from the UI — navigation disabled (no-op).
    _ = prompt
  }

  func openMore(_ route: MoreRoute?) {
    selectedTab = .more
    if let route {
      morePath = [route]
    } else {
      morePath = []
    }
  }

  func reselect(_ tab: GooseAppTab) {
    switch tab {
    case .coach:
      coachScrollToBottomRequestID += 1
    default:
      break
    }
  }

  @discardableResult
  func handleDeepLink(_ url: URL) -> Bool {
    if isCodexAuthCallback(url) {
      selectedTab = .coach
      codexAuthCallbackURL = url
      return true
    }

    if url.scheme == "gooseswift", url.host == "coach" {
      selectedTab = .coach
      if url.pathComponents.dropFirst().first == "embedded-login" {
        codexEmbeddedLoginRequestID += 1
      }
      return true
    }

    if url.scheme == "gooseswift", url.host == "more" {
      let routeName = url.pathComponents.dropFirst().first ?? ""
      if routeName.isEmpty {
        openMore(nil)
        return true
      }
      guard let route = MoreRoute(rawValue: routeName) else {
        return false
      }
      openMore(route)
      return true
    }

    guard url.scheme == "gooseswift", url.host == "health" else {
      return false
    }
    let routeName = url.pathComponents.dropFirst().first ?? ""
    if routeName.isEmpty {
      openHealth(nil)
      return true
    }
    guard let route = HealthRoute(rawValue: routeName) else {
      return false
    }
    openHealth(route)
    return true
  }

  private func isCodexAuthCallback(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
      return false
    }
    return ["gooseswift", "goose"].contains(scheme) && url.host == "codex-auth"
  }
}
