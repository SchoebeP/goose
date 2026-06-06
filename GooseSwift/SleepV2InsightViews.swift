import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepV2Panel<Content: View>: View {
  let palette: SleepV2Palette
  var padding: CGFloat = 16
  var radius: CGFloat = 14
  let content: Content

  init(
    palette: SleepV2Palette,
    padding: CGFloat = 16,
    radius: CGFloat = 18,
    @ViewBuilder content: () -> Content
  ) {
    self.palette = palette
    self.padding = padding
    self.radius = radius
    self.content = content()
  }

  var body: some View {
    content
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(palette.surface)
          .shadow(color: palette.shadow.opacity(0.55), radius: 10, x: 0, y: 4)
      )
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(palette.separator, lineWidth: 1)
      )
  }
}

struct SleepV2StatCard: View {
  let palette: SleepV2Palette
  let systemImage: String
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
          .frame(width: 28, height: 28)
          .background(palette.accent.opacity(0.12), in: Circle())
        Text(label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.secondaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Spacer(minLength: 0)
      }

      Text(value)
        .font(.title3.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(palette.surface)
        .shadow(color: palette.shadow.opacity(0.60), radius: 10, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(palette.separator, lineWidth: 1)
    )
  }
}

struct SleepV2CoachingCard: View {
  let palette: SleepV2Palette
  let tip: CoachInlineTip
  let action: () -> Void

  var body: some View { EmptyView() }  // Coach removed from the UI

  private var hiddenBody: some View {
    SleepV2Panel(palette: palette, padding: 14, radius: 14) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: tip.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 30, height: 30)
            .background(palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

          VStack(alignment: .leading, spacing: 5) {
            Text(tip.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(palette.secondaryText)
            Text(tip.message)
              .font(.subheadline)
              .foregroundStyle(palette.text)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        HStack(spacing: 8) {
          Text(tip.source)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.mutedText)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Spacer(minLength: 8)
          Button(action: action) {
            Label("Ask Coach", systemImage: "bubble.left.and.bubble.right")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .tint(palette.accent)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct SleepV2ActionRow: View {
  let palette: SleepV2Palette
  let systemImage: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.headline.weight(.semibold))
        Text(title)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.mutedText)
      }
      .foregroundStyle(palette.text)
      .padding(.horizontal, 14)
      .padding(.vertical, 13)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(palette.surface)
          .shadow(color: palette.shadow.opacity(0.55), radius: 10, x: 0, y: 4)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(palette.separator, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

struct SleepV2InsightsSheet: View {
  let palette: SleepV2Palette
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        SleepV2InsightsSection(palette: palette)
          .padding(18)
      }
      .background(palette.background.ignoresSafeArea())
      .navigationTitle("Sleep Insights")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
    }
  }
}

struct SleepV2InsightsSection: View {
  let palette: SleepV2Palette

  var body: some View {
    SleepV2Panel(palette: palette, padding: 16, radius: 16) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 32, height: 32)
            .background(palette.accent.opacity(0.12), in: Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text("Sleep insights")
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.text)
            Text("Score drivers from the latest sleep window")
              .font(.footnote)
              .foregroundStyle(palette.secondaryText)
          }
        }

        HStack {
          SleepV2ImpactPill(text: "Negative", color: Color(red: 0.88, green: 0.25, blue: 0.22))
          SleepV2ImpactPill(text: "Positive", color: palette.accent)
        }

        SleepV2ImpactRow(
          palette: palette,
          systemImage: "exclamationmark.triangle.fill",
          iconColor: Color(red: 0.92, green: 0.58, blue: 0.16),
          title: "Target strain overreached",
          value: "-4%",
          strength: 0.72
        )

        Divider().background(palette.separator)

        VStack(alignment: .leading, spacing: 5) {
          Text("Low confidence")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.text)
          Text("Log more nights and tags to improve the confidence score.")
            .font(.footnote)
            .foregroundStyle(palette.secondaryText)
        }
      }
    }
  }
}

struct SleepV2ImpactPill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(color)
      .padding(.horizontal, 11)
      .padding(.vertical, 7)
      .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct SleepV2ImpactRow: View {
  let palette: SleepV2Palette
  let systemImage: String
  let iconColor: Color
  let title: String
  let value: String
  let strength: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(iconColor)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text(title)
            .font(.system(size: 15.5, weight: .bold))
            .foregroundStyle(palette.text)
          Spacer()
          Text(value)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.30))
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(palette.separator.opacity(0.8))
            Capsule()
              .fill(Color(red: 1.0, green: 0.38, blue: 0.30))
              .frame(width: proxy.size.width * min(max(strength, 0), 1))
          }
        }
        .frame(height: 6)
      }
    }
    .padding(14)
    .frame(height: 74)
    .background(palette.surfaceElevated.opacity(palette.light ? 0.72 : 0.60), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.separator, lineWidth: 1))
  }
}

