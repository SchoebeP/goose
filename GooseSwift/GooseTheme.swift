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

// ============================================================
// Direction A — "Quiet Companion" redesign design system.
// Tokens from design_handoff_goose_direction_a/goose.css.
// Dark, calm, chart-first. Namespaced GDA to coexist with the
// legacy GooseTheme during the migration.
// ============================================================

/// One metric's personal "usual range" learned from recent history.
struct VitalBand: Equatable {
  let lo: Double
  let hi: Double
  let mean: Double
}

enum GDA {
  // surfaces
  static let bg = Color(hex6: 0x0B0E13)
  static let surface = Color(hex6: 0x131823)
  static let surface2 = Color(hex6: 0x1A2130)
  static let surface3 = Color(hex6: 0x222A3C)
  static let line = Color(red: 168/255, green: 184/255, blue: 214/255).opacity(0.10)
  static let lineStrong = Color(red: 168/255, green: 184/255, blue: 214/255).opacity(0.18)
  // text
  static let text = Color(hex6: 0xE9EDF5)
  static let text2 = Color(hex6: 0xA7B0C0)
  static let text3 = Color(hex6: 0x6F7889)
  // per-metric accents
  static let heart = Color(hex6: 0xFF8177)
  static let hrv = Color(hex6: 0xB9A3FF)
  static let activity = Color(hex6: 0x8BD9A9)
  static let sleep = Color(hex6: 0x86B9FF)
  static let range = Color(hex6: 0xFFB876)
  static let charge = Color(hex6: 0xFFD479)
  static let resp = Color(hex6: 0x74D6CF)
  static let temp = Color(hex6: 0xFFA98F)

  static let cardRadius: CGFloat = 20

  /// Display numerals — SF Pro Rounded bold w/ monospaced digits (fallback for
  /// Schibsted Grotesk). `size` matches the CSS px scale.
  static func num(_ size: CGFloat) -> Font {
    .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
  }

  static func caps(_ size: CGFloat = 13) -> Font {
    .system(size: size, weight: .semibold, design: .rounded)
  }

  enum PillStyle { case ok, warn, mut, live }

  /// Where a value sits relative to its personal usual band → status copy + pill.
  static func bandStatus(_ value: Double?, _ band: VitalBand?) -> (text: String, style: PillStyle) {
    guard let value, let band, band.hi > band.lo else { return ("—", .mut) }
    let span = band.hi - band.lo
    if value > band.hi + span * 0.05 { return ("above usual", .warn) }
    if value < band.lo - span * 0.05 { return ("below usual", .warn) }
    if value >= band.lo + span * 0.66 { return ("top of usual", .ok) }
    if value <= band.lo + span * 0.33 { return ("low of usual", .ok) }
    return ("usual", .ok)
  }
}

extension Color {
  init(hex6: UInt32) {
    self.init(
      red: Double((hex6 >> 16) & 0xFF) / 255,
      green: Double((hex6 >> 8) & 0xFF) / 255,
      blue: Double(hex6 & 0xFF) / 255
    )
  }
}

extension View {
  /// Direction A card: surface fill + 1px hairline, radius 20, no shadow.
  func gdaCard(padding: CGFloat = 16, vPadding: CGFloat = 18) -> some View {
    self
      .padding(.horizontal, padding)
      .padding(.vertical, vPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(GDA.surface, in: RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous)
          .strokeBorder(GDA.line, lineWidth: 1)
      )
  }

  func gdaScreenBackground() -> some View {
    background(GDA.bg.ignoresSafeArea())
  }
}

// MARK: - Shared primitives (match goose-ui.jsx)

struct GDACardTitle: View {
  var color: Color? = nil
  let title: String
  var trailing: AnyView? = nil

  init(_ title: String, color: Color? = nil, @ViewBuilder trailing: () -> some View) {
    self.title = title
    self.color = color
    self.trailing = AnyView(trailing())
  }
  init(_ title: String, color: Color? = nil) {
    self.title = title
    self.color = color
    self.trailing = nil
  }

  var body: some View {
    HStack(spacing: 8) {
      if let color {
        Circle().fill(color).frame(width: 8, height: 8)
      }
      Text(title.uppercased())
        .font(GDA.caps())
        .tracking(0.7)
        .foregroundStyle(GDA.text2)
        .lineLimit(1)
      Spacer(minLength: 6)
      if let trailing { trailing }
    }
  }
}

struct GDAPill: View {
  let text: String
  var style: GDA.PillStyle = .mut
  var withDot: Bool = false

  private var fg: Color {
    switch style {
    case .ok: return GDA.activity
    case .warn: return GDA.range
    case .mut: return GDA.text2
    case .live: return GDA.heart
    }
  }
  private var bgFill: Color {
    switch style {
    case .ok: return GDA.activity.opacity(0.13)
    case .warn: return GDA.range.opacity(0.14)
    case .mut: return Color(red: 168/255, green: 184/255, blue: 214/255).opacity(0.10)
    case .live: return GDA.heart.opacity(0.13)
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      if withDot { Circle().fill(fg).frame(width: 7, height: 7) }
      Text(text)
        .font(.system(size: 12.5, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(fg)
    .padding(.horizontal, 11)
    .padding(.vertical, 4)
    .background(bgFill, in: Capsule())
  }
}

struct GDADelta: View {
  let value: Double
  let unit: String
  let good: Bool

  var body: some View {
    let up = value >= 0
    return HStack(spacing: 3) {
      Image(systemName: up ? "arrow.up" : "arrow.down")
        .font(.system(size: 9, weight: .bold))
      Text("\(abs(value).formatted(.number.precision(.fractionLength(0...1)))) \(unit) vs prev")
        .font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(good ? GDA.activity : GDA.range)
  }
}

struct GDAGapNote: View {
  let text: String
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "rectangle.dashed").font(.system(size: 11))
      Text(text).font(.system(size: 11.5))
    }
    .foregroundStyle(GDA.text3)
  }
}

struct GDAProvBadge: View {
  var body: some View {
    Text("PROV.")
      .font(.system(size: 11, weight: .semibold))
      .tracking(0.6)
      .foregroundStyle(GDA.text3)
      .padding(.horizontal, 6)
      .padding(.vertical, 1.5)
      .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(GDA.lineStrong, lineWidth: 1))
  }
}

/// 132×14 horizontal band gauge: full-width hairline track, a thicker tinted
/// segment for the personal usual range, and a value dot with a bg ring.
struct GDABandGauge: View {
  let value: Double?
  let band: VitalBand?
  let color: Color
  var width: CGFloat = 132
  var height: CGFloat = 14

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, midY = size.height / 2
      // domain padded around the band
      guard let band, band.hi > band.lo else {
        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: midY)); $0.addLine(to: CGPoint(x: w, y: midY)) },
                   with: .color(GDA.lineStrong), lineWidth: 3)
        return
      }
      let pad = (band.hi - band.lo) * 0.6 + 0.0001
      var lo = band.lo - pad, hi = band.hi + pad
      if let value { lo = min(lo, value); hi = max(hi, value) }
      let x = { (v: Double) in CGFloat((v - lo) / (hi - lo)) * w }
      // track
      ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: midY)); $0.addLine(to: CGPoint(x: w, y: midY)) },
                 with: .color(GDA.lineStrong), lineWidth: 3)
      // usual band segment
      ctx.stroke(Path { $0.move(to: CGPoint(x: x(band.lo), y: midY)); $0.addLine(to: CGPoint(x: x(band.hi), y: midY)) },
                 with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
      // value dot with ring
      if let value {
        let cx = x(value)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: midY - 5, width: 10, height: 10)), with: .color(GDA.surface))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.5, y: midY - 3.5, width: 7, height: 7)), with: .color(color))
      }
    }
    .frame(width: width, height: height)
  }
}

/// Morning 2×2 vital tile: dot+caps title, big value, band gauge, status pill.
struct GDAVitalTile: View {
  let label: String
  let color: Color
  let value: Double?
  let unit: String
  let band: VitalBand?
  var provisional: Bool = false
  var decimals: Int = 0

  private var valueText: String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(decimals)))
  }

  var body: some View {
    let status = GDA.bandStatus(value, band)
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text((provisional ? label + " *" : label).uppercased())
          .font(GDA.caps(12))
          .tracking(0.6)
          .foregroundStyle(GDA.text2)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(valueText)
          .font(GDA.num(30))
          .foregroundStyle(GDA.text)
        Text(unit)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(GDA.text2)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      GDABandGauge(value: value, band: band, color: color)
      GDAPill(text: status.text, style: status.style)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .gdaCard()
  }
}
