import Darwin
import Foundation
import SwiftUI
import UIKit

enum SleepV2PaletteTheme {
  case sleep
  case recovery
  case strain
  case stress
}

struct SleepV2Palette {
  let background: Color
  let surface: Color
  let surfaceElevated: Color
  let surfaceHeader: Color
  let text: Color
  let secondaryText: Color
  let mutedText: Color
  let separator: Color
  let accent: Color
  let accentAlt: Color
  let success: Color
  let shadow: Color
  let light: Bool

  init(colorScheme: ColorScheme, theme: SleepV2PaletteTheme = .sleep) {
    light = colorScheme == .light

    switch (theme, light) {
    case (.sleep, true):
      background = Color(UIColor.systemGroupedBackground)
      surface = .white
      surfaceElevated = Color(red: 0.93, green: 0.95, blue: 1.0)
      surfaceHeader = Color(red: 0.89, green: 0.91, blue: 0.99)
      text = Color(UIColor.label)
      secondaryText = Color(red: 0.40, green: 0.42, blue: 0.47)
      mutedText = Color(red: 0.54, green: 0.56, blue: 0.64)
      separator = Color.black.opacity(0.12)
      accent = Color(red: 0.48, green: 0.49, blue: 1.0)
      accentAlt = Color(red: 0.73, green: 0.83, blue: 1.0)
      success = Color(red: 0.20, green: 0.78, blue: 0.47)
      shadow = Color.black.opacity(0.12)
    case (.sleep, false):
      background = Color(red: 0.07, green: 0.08, blue: 0.13)
      surface = Color(red: 0.13, green: 0.15, blue: 0.24)
      surfaceElevated = Color(red: 0.15, green: 0.17, blue: 0.28)
      surfaceHeader = Color(red: 0.19, green: 0.22, blue: 0.33)
      text = .white
      secondaryText = Color(red: 0.69, green: 0.71, blue: 0.77)
      mutedText = Color(red: 0.45, green: 0.47, blue: 0.55)
      separator = Color.white.opacity(0.08)
      accent = Color(red: 0.46, green: 0.44, blue: 1.0)
      accentAlt = Color(red: 0.65, green: 0.76, blue: 1.0)
      success = Color(red: 0.38, green: 0.86, blue: 0.53)
      shadow = Color.black.opacity(0.36)
    case (.recovery, true):
      background = Color(red: 0.94, green: 0.97, blue: 0.94)
      surface = .white
      surfaceElevated = Color(red: 0.91, green: 0.96, blue: 0.92)
      surfaceHeader = Color(red: 0.86, green: 0.94, blue: 0.88)
      text = Color(UIColor.label)
      secondaryText = Color(red: 0.35, green: 0.43, blue: 0.36)
      mutedText = Color(red: 0.50, green: 0.60, blue: 0.52)
      separator = Color.black.opacity(0.11)
      accent = Color(red: 0.19, green: 0.72, blue: 0.35)
      accentAlt = Color(red: 0.58, green: 0.91, blue: 0.62)
      success = Color(red: 0.20, green: 0.78, blue: 0.47)
      shadow = Color.black.opacity(0.10)
    case (.recovery, false):
      background = Color(red: 0.05, green: 0.09, blue: 0.07)
      surface = Color(red: 0.10, green: 0.16, blue: 0.13)
      surfaceElevated = Color(red: 0.13, green: 0.20, blue: 0.16)
      surfaceHeader = Color(red: 0.16, green: 0.24, blue: 0.18)
      text = .white
      secondaryText = Color(red: 0.70, green: 0.77, blue: 0.70)
      mutedText = Color(red: 0.50, green: 0.58, blue: 0.52)
      separator = Color.white.opacity(0.09)
      accent = Color(red: 0.40, green: 0.90, blue: 0.52)
      accentAlt = Color(red: 0.64, green: 0.96, blue: 0.62)
      success = Color(red: 0.42, green: 0.88, blue: 0.55)
      shadow = Color.black.opacity(0.34)
    case (.stress, true):
      background = Color(UIColor.systemGroupedBackground)
      surface = .white
      surfaceElevated = Color(red: 0.94, green: 0.96, blue: 0.96)
      surfaceHeader = Color(red: 0.90, green: 0.93, blue: 0.94)
      text = Color(UIColor.label)
      secondaryText = Color(red: 0.40, green: 0.43, blue: 0.45)
      mutedText = Color(red: 0.55, green: 0.58, blue: 0.61)
      separator = Color.black.opacity(0.12)
      accent = Color(red: 0.33, green: 0.72, blue: 0.70)
      accentAlt = Color(red: 0.96, green: 0.72, blue: 0.22)
      success = Color(red: 0.24, green: 0.70, blue: 0.42)
      shadow = Color.black.opacity(0.12)
    case (.stress, false):
      background = Color(red: 0.08, green: 0.085, blue: 0.095)
      surface = Color(red: 0.16, green: 0.17, blue: 0.20)
      surfaceElevated = Color(red: 0.19, green: 0.20, blue: 0.24)
      surfaceHeader = Color(red: 0.22, green: 0.23, blue: 0.28)
      text = .white
      secondaryText = Color(red: 0.72, green: 0.75, blue: 0.76)
      mutedText = Color(red: 0.52, green: 0.55, blue: 0.58)
      separator = Color.white.opacity(0.10)
      accent = Color(red: 0.47, green: 0.82, blue: 0.80)
      accentAlt = Color(red: 1.0, green: 0.82, blue: 0.25)
      success = Color(red: 0.48, green: 0.84, blue: 0.54)
      shadow = Color.black.opacity(0.34)
    case (.strain, true):
      background = Color(red: 0.95, green: 0.955, blue: 0.935)
      surface = .white
      surfaceElevated = Color(red: 0.95, green: 0.94, blue: 0.90)
      surfaceHeader = Color(red: 0.93, green: 0.91, blue: 0.86)
      text = Color(UIColor.label)
      secondaryText = Color(red: 0.41, green: 0.40, blue: 0.36)
      mutedText = Color(red: 0.58, green: 0.56, blue: 0.50)
      separator = Color.black.opacity(0.11)
      accent = Color(red: 0.88, green: 0.34, blue: 0.12)
      accentAlt = Color(red: 0.97, green: 0.64, blue: 0.24)
      success = Color(red: 0.25, green: 0.66, blue: 0.38)
      shadow = Color.black.opacity(0.10)
    case (.strain, false):
      background = Color(red: 0.08, green: 0.085, blue: 0.075)
      surface = Color(red: 0.14, green: 0.135, blue: 0.115)
      surfaceElevated = Color(red: 0.18, green: 0.17, blue: 0.14)
      surfaceHeader = Color(red: 0.22, green: 0.20, blue: 0.16)
      text = .white
      secondaryText = Color(red: 0.74, green: 0.72, blue: 0.66)
      mutedText = Color(red: 0.52, green: 0.50, blue: 0.45)
      separator = Color.white.opacity(0.09)
      accent = Color(red: 1.0, green: 0.45, blue: 0.18)
      accentAlt = Color(red: 1.0, green: 0.70, blue: 0.32)
      success = Color(red: 0.42, green: 0.80, blue: 0.46)
      shadow = Color.black.opacity(0.34)
    }
  }
}

enum SleepV2Numbers {
  static func firstInt(in text: String) -> Int? {
    let pattern = #"[-+]?\d+"#
    guard let range = text.range(of: pattern, options: .regularExpression) else {
      return nil
    }
    return Int(text[range])
  }
}

struct SleepV2ScrollOffsetPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct SleepV2ScrollOffsetProbe: View {
  static let coordinateSpaceName = "sleep-v2-scroll"

  var body: some View {
    GeometryReader { proxy in
      Color.clear
        .preference(
          key: SleepV2ScrollOffsetPreferenceKey.self,
          value: proxy.frame(in: .named(Self.coordinateSpaceName)).minY
        )
    }
    .frame(height: 0)
  }
}

struct SleepV2Hero: View {
  let palette: SleepV2Palette
  let title: String
  let dateLabel: String
  let score: Int?
  var gaugeLabel: String = "Quality"
  let onDateTap: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 32)

      SleepV2ScoreGauge(palette: palette, score: score, label: gaugeLabel)
        .frame(width: 188, height: 188)

      Button(action: onDateTap) {
        HStack(spacing: 6) {
          Text(dateLabel)
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
      }
      .buttonStyle(.plain)
      .padding(.top, 16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

struct SleepV2ScenicBackground: View {
  let palette: SleepV2Palette

  var body: some View {
    ZStack {
      LinearGradient(
        colors: palette.light
          ? [Color(red: 0.87, green: 0.91, blue: 0.98), Color(red: 0.78, green: 0.84, blue: 0.94), palette.background]
          : [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.12, green: 0.15, blue: 0.25), palette.background],
        startPoint: .top,
        endPoint: .bottom
      )

      Canvas { context, size in
        for index in 0..<34 {
          let x = CGFloat((index * 73 + 31) % max(1, Int(size.width)))
          let y = CGFloat(34 + ((index * 41) % max(1, Int(size.height * 0.42))))
          let radius = index % 9 == 0 ? CGFloat(1.2) : CGFloat(0.65)
          context.fill(
            Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(palette.light ? 0.18 : 0.24))
          )
        }
      }

      VStack {
        Spacer()
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.clear, palette.background.opacity(0.72), palette.background],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(height: 150)
      }
    }
  }
}

struct SleepV2ScoreGauge: View {
  let palette: SleepV2Palette
  let score: Int?
  let label: String

  private var progress: CGFloat {
    CGFloat(min(max(score ?? 0, 0), 100)) / 100
  }

	  var body: some View {
	    GeometryReader { proxy in
	      let side = min(proxy.size.width, proxy.size.height)
	      let lineWidth = max(13, side * 0.078)
	      let radius = side / 2 - 18
	      let end = progressPoint(side: side, radius: radius)

	      ZStack {
	        Circle()
	          .fill(palette.surface.opacity(palette.light ? 0.94 : 0.84))
	          .shadow(color: palette.shadow.opacity(0.48), radius: 18, x: 0, y: 8)
	        Circle()
	          .stroke(.white.opacity(palette.light ? 0.88 : 0.12), lineWidth: 10)
	          .padding(6)
	        Circle()
	          .inset(by: 18)
	          .stroke(palette.separator.opacity(palette.light ? 0.72 : 0.62), lineWidth: lineWidth)
	        Circle()
	          .inset(by: 18)
	          .trim(from: 0, to: progress)
	          .stroke(
	            LinearGradient(
	              colors: [palette.accentAlt, palette.accent],
	              startPoint: .topLeading,
	              endPoint: .bottomTrailing
	            ),
	            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
	          )
	          .rotationEffect(.degrees(-90))

	        Circle()
	          .fill(palette.accent)
	          .frame(width: lineWidth * 0.95, height: lineWidth * 0.95)
	          .shadow(color: palette.accent.opacity(0.32), radius: 6, x: 0, y: 2)
	          .position(end)

	        VStack(spacing: 4) {
	          HStack(alignment: .firstTextBaseline, spacing: 1) {
	            Text(score.map(String.init) ?? "--")
	              .font(.system(size: 45, weight: .semibold, design: .rounded))
	            Text("%")
	              .font(.system(size: 18, weight: .semibold, design: .rounded))
	          }
	          .foregroundStyle(palette.text)
	          Text(label)
	            .font(.footnote.weight(.semibold))
	            .foregroundStyle(palette.secondaryText)
	        }
	      }
	      .frame(width: side, height: side)
	      .frame(maxWidth: .infinity, maxHeight: .infinity)
	    }
	  }

	  private func progressPoint(side: CGFloat, radius: CGFloat) -> CGPoint {
	    let angle = Double(progress) * 2 * Double.pi - Double.pi / 2
	    let center = side / 2
	    return CGPoint(
	      x: center + CGFloat(cos(angle)) * radius,
	      y: center + CGFloat(sin(angle)) * radius
	    )
	  }
	}

