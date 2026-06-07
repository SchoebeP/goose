import SwiftUI
import UIKit

enum GooseTheme {
  static let deviceBackground = Color(red: 0.06, green: 0.09, blue: 0.11)

  static let appBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  })

  static let plainBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemBackground
  })

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
    static let respiratory = Color(red: 0.251, green: 0.784, blue: 0.878) // #40C8E0
  }

  /// Card fill: #1C1C1E in dark, .secondarySystemGroupedBackground in light.
  static let cardBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
      : .secondarySystemGroupedBackground
  })

  static let cardCornerRadius: CGFloat = 14
  static let cardPadding: CGFloat = 16

  static func configureAppearance() {
    UIWindow.appearance().backgroundColor = appBackgroundUIColor
    UITableView.appearance().backgroundColor = appBackgroundUIColor
    UICollectionView.appearance().backgroundColor = appBackgroundUIColor

    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithTransparentBackground()
    navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    navigationAppearance.backgroundColor = navigationBarBackgroundUIColor
    navigationAppearance.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = navigationAppearance
    UINavigationBar.appearance().compactAppearance = navigationAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = appBackgroundUIColor
    tabAppearance.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  private static let deviceBackgroundUIColor = UIColor(
    red: 0.06,
    green: 0.09,
    blue: 0.11,
    alpha: 1
  )

  private static let appBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  }

  private static let navigationBarBackgroundUIColor = UIColor { traits in
    let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.46
    return appBackgroundUIColor.resolvedColor(with: traits).withAlphaComponent(alpha)
  }
}

extension View {
  func gooseScreenBackground() -> some View {
    background(GooseTheme.appBackground.ignoresSafeArea())
  }

  func goosePlainBackground() -> some View {
    background(GooseTheme.plainBackground.ignoresSafeArea())
  }

  func gooseListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(GooseTheme.appBackground.ignoresSafeArea())
  }

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
}

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
