import SwiftUI
import UIKit

/// "Radiograph" design system — see docs/design/radiograph-design-system.md.
/// Cool film ground, ink monochrome data, serif numerals, mono eyebrows,
/// arterial red reserved exclusively for live/now.
enum InkTheme {
  // MARK: - Color tokens (light "film" / dark "negative")

  static let film = dual(light: (0.937, 0.949, 0.957), dark: (0.063, 0.075, 0.082))
  static let ink = dual(light: (0.090, 0.102, 0.118), dark: (0.910, 0.925, 0.937))
  static let graphite = dual(light: (0.369, 0.404, 0.443), dark: (0.545, 0.580, 0.620))
  static let hairline = dual(light: (0.843, 0.871, 0.890), dark: (0.137, 0.165, 0.184))
  static let arterial = dual(light: (0.761, 0.141, 0.180), dark: (0.878, 0.290, 0.322))
  static let wash = dual(light: (0.894, 0.914, 0.925), dark: (0.094, 0.114, 0.129))

  // MARK: - Type roles

  /// Oversized serif numeral for the primary reading of a section.
  static func displayNumeral(_ size: CGFloat = 56) -> Font {
    .system(size: size, weight: .medium, design: .serif)
  }

  /// Screen title, serif.
  static var screenTitle: Font {
    .system(size: 30, weight: .semibold, design: .serif)
  }

  /// Section heading, serif, quiet.
  static var sectionTitle: Font {
    .system(size: 19, weight: .semibold, design: .serif)
  }

  /// Mono eyebrow/label/unit.
  static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }

  /// Body copy.
  static var body: Font { .system(size: 15) }
  static var footnote: Font { .system(size: 13) }

  static let eyebrowTracking: CGFloat = 1.5

  // MARK: - Metrics

  static let screenMargin: CGFloat = 22
  static let sectionSpacing: CGFloat = 26
  static let hairlineWidth: CGFloat = 0.5

  static func configureAppearance() {
    let filmUIColor = dualUIColor(light: (0.937, 0.949, 0.957), dark: (0.063, 0.075, 0.082))
    let inkUIColor = dualUIColor(light: (0.090, 0.102, 0.118), dark: (0.910, 0.925, 0.937))

    UIWindow.appearance().backgroundColor = filmUIColor

    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithOpaqueBackground()
    navigationAppearance.backgroundColor = filmUIColor
    navigationAppearance.shadowColor = .clear
    let serifTitle = UIFont.systemFont(ofSize: 17, weight: .semibold)
    if let descriptor = serifTitle.fontDescriptor.withDesign(.serif) {
      navigationAppearance.titleTextAttributes = [
        .font: UIFont(descriptor: descriptor, size: 17),
        .foregroundColor: inkUIColor,
      ]
    }
    UINavigationBar.appearance().standardAppearance = navigationAppearance
    UINavigationBar.appearance().compactAppearance = navigationAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = filmUIColor
    tabAppearance.shadowColor = dualUIColor(
      light: (0.843, 0.871, 0.890),
      dark: (0.137, 0.165, 0.184)
    )
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  // MARK: - Helpers

  private static func dual(
    light: (Double, Double, Double),
    dark: (Double, Double, Double)
  ) -> Color {
    Color(uiColor: dualUIColor(light: light, dark: dark))
  }

  private static func dualUIColor(
    light: (Double, Double, Double),
    dark: (Double, Double, Double)
  ) -> UIColor {
    UIColor { traits in
      let component = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: component.0, green: component.1, blue: component.2, alpha: 1)
    }
  }
}

extension View {
  func inkScreen() -> some View {
    background(InkTheme.film.ignoresSafeArea())
  }

  /// Mono uppercase eyebrow style.
  func inkEyebrow(color: Color = InkTheme.graphite) -> some View {
    font(InkTheme.mono())
      .tracking(InkTheme.eyebrowTracking)
      .textCase(.uppercase)
      .foregroundStyle(color)
  }
}

/// 0.5pt full-bleed rule.
struct InkRule: View {
  var body: some View {
    Rectangle()
      .fill(InkTheme.hairline)
      .frame(height: InkTheme.hairlineWidth)
  }
}
