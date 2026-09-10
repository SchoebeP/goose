import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepTimelineSection: View {
  let session: PrimarySleepDetail?
  let onAddSleep: () -> Void
  let onSelectPrimarySleep: (PrimarySleepDetail) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        HealthSectionTitle("Sleep Timeline")
        Spacer()
        Button {
          onAddSleep()
        } label: {
          Label("Add Sleep", systemImage: "plus.circle")
        }
        .font(.subheadline.weight(.semibold))
      }

      if let session {
        Button {
          onSelectPrimarySleep(session)
        } label: {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("Primary Sleep")
                  .font(.headline)
                Text("\(session.dateLabel) | \(session.startLabel) - \(session.endLabel)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 3) {
                Text(session.scoreDisplayText)
                  .font(.title3.bold())
                Text(session.durationText)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            SleepStageTimeline(stages: session.stages)
            Text(session.source.label)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          .padding(14)
          .healthCardSurface()
        }
        .buttonStyle(.plain)
      } else {
        ContentUnavailableView("No Sleep Timeline", systemImage: "bed.double", description: Text("Add Sleep creates the first local sleep row once manual entry is available."))
          .frame(maxWidth: .infinity)
          .padding(14)
          .healthCardSurface()
      }
    }
  }
}

struct SleepStageTimeline: View {
  let stages: [HealthSleepStageSegment]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 2) {
          ForEach(stages) { stage in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(stageColor(stage.stage))
              .frame(width: segmentWidth(stage, totalWidth: proxy.size.width))
              .overlay {
                Text(stage.durationText)
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(.white)
                  .lineLimit(1)
                  .minimumScaleFactor(0.6)
              }
          }
        }
      }
      .frame(height: 30)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
        ForEach(stages) { stage in
          HStack(spacing: 8) {
            Circle()
              .fill(stageColor(stage.stage))
              .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
              Text(stage.displayStage)
                .font(.caption.weight(.semibold))
              Text("\(stage.durationText) | \(stage.startLabel)-\(stage.endLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private func segmentWidth(_ stage: HealthSleepStageSegment, totalWidth: CGFloat) -> CGFloat {
    let totalMinutes = max(stages.map(\.durationMinutes).reduce(0, +), 1)
    return max(32, totalWidth * CGFloat(stage.durationMinutes / totalMinutes))
  }

  private func stageColor(_ stage: String) -> Color {
    switch stage.lowercased() {
    case "awake": return .orange
    case "rem": return .purple
    case "deep": return .blue
    default: return .indigo
    }
  }
}

struct PrimarySleepDetailSheet: View {
  let sleep: PrimarySleepDetail
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = SleepV2Palette(colorScheme: colorScheme)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 5) {
                Text("Primary Sleep")
                  .font(.title2.weight(.semibold))
                  .foregroundStyle(palette.text)
                Text("\(sleep.dateLabel)  \(sleep.startLabel)-\(sleep.endLabel)")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(palette.secondaryText)
              }
              Spacer()
              Text(sleep.scoreDisplayText)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(palette.surfaceElevated.opacity(0.65), in: Capsule())
            }

            HStack(spacing: 10) {
              SleepV2SleepDetailStat(palette: palette, label: "Asleep", value: sleep.durationText, systemImage: "moon.zzz.fill")
              SleepV2SleepDetailStat(palette: palette, label: "In bed", value: sleep.timeInBedText, systemImage: "bed.double.fill")
              SleepV2SleepDetailStat(palette: palette, label: "Quality", value: sleep.qualityText, systemImage: "sparkles")
            }
          }
          .padding(20)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator.opacity(0.70), lineWidth: 1))

          VStack(alignment: .leading, spacing: 16) {
            Text("Stages")
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.text)
            SleepV2StageStrip(stages: sleep.stages, height: 20)
            VStack(spacing: 10) {
              ForEach(sleep.stages) { stage in
                SleepV2SleepStageRow(stage: stage, palette: palette)
              }
            }
          }
          .padding(20)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator.opacity(0.70), lineWidth: 1))

          VStack(alignment: .leading, spacing: 8) {
            Label("Data source", systemImage: "doc.text.magnifyingglass")
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.text)
            Text(sleep.source.label)
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(20)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(18)
      }
      .background(palette.background)
      .navigationTitle("Primary Sleep")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

struct SleepV2SleepDetailStat: View {
  let palette: SleepV2Palette
  let label: String
  let value: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.accent)
        .frame(width: 28, height: 28)
        .background(palette.accent.opacity(0.12), in: Circle())
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.secondaryText)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.64)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(palette.surfaceElevated.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct SleepV2SleepStageRow: View {
  let stage: HealthSleepStageSegment
  let palette: SleepV2Palette

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(SleepV2StageStrip.stageColor(stage.stage))
        .frame(width: 12, height: 12)
      VStack(alignment: .leading, spacing: 3) {
        Text(stage.displayStage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.text)
        Text("\(stage.startLabel)-\(stage.endLabel)")
          .font(.caption.weight(.medium))
          .foregroundStyle(palette.secondaryText)
      }
      Spacer()
      Text(stage.durationText)
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
    }
    .padding(12)
    .background(palette.surfaceElevated.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}


struct HealthSectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(InkTheme.sectionTitle)
      .foregroundStyle(InkTheme.ink)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension View {
  func healthCardSurface() -> some View {
    background(InkTheme.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(InkTheme.hairline)
      }
  }
}
