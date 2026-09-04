import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepV2SectionHeader<Trailing: View>: View {
  let title: String
  let palette: SleepV2Palette
  let trailing: Trailing

  init(
    title: String,
    palette: SleepV2Palette,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.palette = palette
    self.trailing = trailing()
  }

  init(title: String, palette: SleepV2Palette) where Trailing == EmptyView {
    self.title = title
    self.palette = palette
    self.trailing = EmptyView()
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.title2.weight(.semibold))
        .foregroundStyle(palette.text)
      Spacer()
      trailing
    }
    .padding(.top, 22)
    .padding(.bottom, 4)
  }
}

struct SleepV2TimelineRow: View {
  let palette: SleepV2Palette
  let session: PrimarySleepDetail?
  let action: () -> Void

	  var body: some View {
	    Button(action: action) {
	      VStack(alignment: .leading, spacing: 16) {
	        HStack(alignment: .top, spacing: 12) {
	          Image(systemName: "moon.stars.fill")
	            .font(.title3.weight(.semibold))
	            .foregroundStyle(palette.accent)
	            .frame(width: 42, height: 42)
	            .background(palette.accent.opacity(0.12), in: Circle())

	          VStack(alignment: .leading, spacing: 4) {
	            Text("Primary sleep")
	              .font(.headline.weight(.semibold))
	              .foregroundStyle(palette.text)
	            Text(subtitle)
	              .font(.subheadline.weight(.medium))
	              .foregroundStyle(palette.mutedText)
	              .lineLimit(1)
	              .minimumScaleFactor(0.72)
	          }

	          Spacer(minLength: 8)

	          if let session {
	            Text(session.scoreDisplayText)
	              .font(.headline.weight(.semibold))
	              .fontDesign(.rounded)
	              .foregroundStyle(palette.text)
	              .padding(.horizontal, 10)
	              .padding(.vertical, 6)
	              .background(palette.surfaceElevated.opacity(0.65), in: Capsule())
	          } else {
	            Image(systemName: "chevron.right")
	              .font(.headline.weight(.semibold))
	              .foregroundStyle(palette.mutedText)
	          }
	        }

	        if let session {
	          HStack(spacing: 10) {
	            SleepV2TimelineMetric(label: "Asleep", value: session.durationText, palette: palette)
	            SleepV2TimelineMetric(label: "In bed", value: session.timeInBedText, palette: palette)
	            SleepV2TimelineMetric(label: "Wake", value: session.endLabel, palette: palette)
	          }
	          SleepV2StageStrip(stages: session.stages, height: 14)
	        }
	      }
	      .padding(18)
	      .background(
	        RoundedRectangle(cornerRadius: 28, style: .continuous)
	          .fill(palette.surface)
	          .shadow(color: palette.shadow.opacity(0.40), radius: 11, x: 0, y: 5)
	      )
	      .overlay(
	        RoundedRectangle(cornerRadius: 28, style: .continuous)
	          .stroke(palette.separator.opacity(0.70), lineWidth: 1)
	      )
	    }
	    .buttonStyle(.plain)
  }

  private var subtitle: String {
    guard let session else {
      return "Add a sleep row"
    }
	    return "\(session.dateLabel) at \(session.startLabel)"
	  }
	}

struct SleepV2TimelineMetric: View {
  let label: String
  let value: String
  let palette: SleepV2Palette

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.secondaryText)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(palette.surfaceElevated.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct SleepV2StageStrip: View {
  let stages: [HealthSleepStageSegment]
  var height: CGFloat = 18

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 3) {
        ForEach(stages) { stage in
          RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Self.stageColor(stage.stage))
            .frame(width: segmentWidth(stage, totalWidth: proxy.size.width))
        }
      }
    }
    .frame(height: height)
  }

  private func segmentWidth(_ stage: HealthSleepStageSegment, totalWidth: CGFloat) -> CGFloat {
    let totalMinutes = max(stages.map(\.durationMinutes).reduce(0, +), 1)
    let spacing = CGFloat(max(stages.count - 1, 0)) * 3
    return max(8, (totalWidth - spacing) * CGFloat(stage.durationMinutes / totalMinutes))
  }

  static func stageColor(_ stage: String) -> Color {
    switch stage.lowercased() {
    case "awake": return Color(red: 1.0, green: 0.61, blue: 0.25)
    case "rem": return Color(red: 0.70, green: 0.45, blue: 1.0)
    case "deep": return Color(red: 0.24, green: 0.48, blue: 1.0)
    default: return Color(red: 0.39, green: 0.54, blue: 1.0)
    }
  }
}

struct SleepV2TrendRow: View {
  let palette: SleepV2Palette
  let snapshot: HealthMetricSnapshot
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 8) {
          Image(systemName: snapshot.systemImage)
            .font(.title3.weight(.semibold))
          Text(snapshot.title)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 8)
          Text(freshnessLabel)
            .font(.subheadline.weight(.medium))
            .fontDesign(.rounded)
            .foregroundStyle(palette.mutedText)
          Image(systemName: "chevron.right")
            .font(.headline.weight(.semibold))
            .foregroundStyle(palette.mutedText.opacity(0.70))
        }
        .foregroundStyle(titleColor)

        HStack(alignment: .bottom, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(primaryLine)
              .font(.system(size: primaryFontSize, weight: .semibold, design: .rounded))
              .foregroundStyle(palette.text)
              .lineLimit(1)
              .minimumScaleFactor(0.62)
            Text(secondaryLine)
              .font(.title3.weight(.semibold))
              .fontDesign(.rounded)
              .foregroundStyle(palette.mutedText)
              .lineLimit(1)
              .minimumScaleFactor(0.68)
          }
          .layoutPriority(1)

          Spacer(minLength: 8)

          accessory
            .frame(width: accessoryWidth, height: 76)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(palette.surface)
          .shadow(color: palette.shadow.opacity(0.40), radius: 11, x: 0, y: 5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(palette.separator.opacity(0.70), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var displayValue: String {
    snapshot.displayValue.replacingOccurrences(of: " %", with: "%")
  }

  private var primaryLine: String {
    if isSleepScore {
      if snapshot.status.localizedCaseInsensitiveContains("no data") {
        return "No data"
      }
      return snapshot.status
    }
    return displayValue
  }

  private var secondaryLine: String {
    if isSleepScore {
      guard let scoreValue else {
        return "No score"
      }
      return "\(scoreValue) points"
    }
    return snapshot.status.isEmpty ? snapshot.freshness : snapshot.status
  }

  private var primaryFontSize: CGFloat {
    displayValue.count > 10 ? 29 : 34
  }

  private var freshnessLabel: String {
    snapshot.freshness == "30d" ? "30D" : snapshot.freshness
  }

  private var isSleepScore: Bool {
    snapshot.title == "Sleep Score"
  }

  private var scoreValue: Int? {
    SleepV2Numbers.firstInt(in: snapshot.value)
      ?? SleepV2Numbers.firstInt(in: snapshot.displayValue)
  }

  private var accessoryWidth: CGFloat {
    isSleepScore ? 78 : 118
  }

  @ViewBuilder private var accessory: some View {
    if isSleepScore {
      SleepV2MiniScoreRing(
        palette: palette,
        score: scoreValue,
        tint: titleColor
      )
    } else {
      SleepV2MiniBarChart(
        palette: palette,
        points: snapshot.trend.points.map(\.value),
        tint: titleColor
      )
    }
  }

  private var lineColor: Color {
    snapshot.title == "Sleep Bank" ? Color(red: 0.36, green: 0.84, blue: 0.53) : Color(red: 0.65, green: 0.71, blue: 1.0)
  }

  private var titleColor: Color {
    if snapshot.title == "Sleep Bank" {
      return snapshot.status.localizedCaseInsensitiveContains("debt")
        ? Color(red: 0.95, green: 0.34, blue: 0.20)
        : palette.success
    }
    return lineColor
  }
}

struct SleepV2MiniScoreRing: View {
  let palette: SleepV2Palette
  let score: Int?
  let tint: Color

  var body: some View {
    ZStack {
      Circle()
        .stroke(palette.separator.opacity(0.85), lineWidth: 9)
      Circle()
        .trim(from: 0.72, to: 0.86)
        .stroke(Color(red: 0.40, green: 0.82, blue: 0.77), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Circle()
        .trim(from: 0.88, to: 0.97)
        .stroke(Color(red: 1.0, green: 0.55, blue: 0.45), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Circle()
        .trim(from: 0, to: CGFloat(min(max(score ?? 0, 0), 100)) / 100)
        .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
        .rotationEffect(.degrees(-90))
      Text(score.map(String.init) ?? "--")
        .font(.title3.weight(.bold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
    }
    .padding(5)
  }
}

