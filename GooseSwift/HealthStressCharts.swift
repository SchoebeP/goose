import Darwin
import Foundation
import SwiftUI
import UIKit

struct EnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(InkTheme.wash)
          .overlay {
            Text("No energy or stress data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(InkTheme.wash)
          ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            if point.isSleepWindow {
              Rectangle()
                .fill(InkTheme.graphite.opacity(0.08))
                .frame(width: max(proxy.size.width / CGFloat(points.count), 28), height: proxy.size.height - 28)
                .position(x: xPosition(index: index, width: proxy.size.width), y: (proxy.size.height - 28) / 2)
            }
            Capsule()
              .fill(point.stress > 55 ? InkTheme.ink.opacity(0.55) : InkTheme.graphite.opacity(0.40))
              .frame(width: 6, height: max(8, CGFloat(point.usage)))
              .position(x: xPosition(index: index, width: proxy.size.width), y: proxy.size.height - 24 - CGFloat(point.usage) / 2)
            if point.isChargeEvent {
              Circle()
                .fill(InkTheme.ink)
                .frame(width: 8, height: 8)
                .position(x: xPosition(index: index, width: proxy.size.width), y: proxy.size.height - 20)
            }
          }
          energyPath(in: proxy.size)
            .stroke(InkTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          stressPath(in: proxy.size)
            .stroke(InkTheme.graphite, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
          if let selectedPoint,
             let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
            let x = xPosition(index: selectedIndex, width: proxy.size.width)
            Rectangle()
              .fill(InkTheme.ink.opacity(0.18))
              .frame(width: 1, height: proxy.size.height - 28)
              .position(x: x, y: (proxy.size.height - 28) / 2)
            Text("Energy \(Int(selectedPoint.energy)) | Stress \(Int(selectedPoint.stress))")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(InkTheme.ink)
              .padding(.horizontal, 7)
              .padding(.vertical, 4)
              .background(.thinMaterial, in: Capsule())
              .position(x: min(max(x, 74), proxy.size.width - 74), y: 18)
          }
          HStack {
            ForEach(points) { point in
              Text(point.timeLabel)
                .font(.caption2)
                .foregroundStyle(InkTheme.graphite)
                .frame(maxWidth: .infinity)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 2)
          VStack(alignment: .trailing) {
            Text("100%")
            Spacer()
            Text("50%")
            Spacer()
            Text("0%")
          }
          .font(.caption2)
          .foregroundStyle(InkTheme.graphite)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 28, alignment: .trailing)
          .padding(.top, 8)
        }
      }
    }
  }

  private func energyPath(in size: CGSize) -> Path {
    Path { path in
      for (index, point) in points.enumerated() {
        let cgPoint = CGPoint(x: xPosition(index: index, width: size.width), y: yPosition(value: point.energy, height: size.height))
        if index == 0 {
          path.move(to: cgPoint)
        } else {
          path.addLine(to: cgPoint)
        }
      }
    }
  }

  private func stressPath(in size: CGSize) -> Path {
    Path { path in
      for (index, point) in points.enumerated() {
        let cgPoint = CGPoint(x: xPosition(index: index, width: size.width), y: yPosition(value: point.stress, height: size.height))
        if index == 0 {
          path.move(to: cgPoint)
        } else {
          path.addLine(to: cgPoint)
        }
      }
    }
  }

  private func xPosition(index: Int, width: CGFloat) -> CGFloat {
    let left: CGFloat = 16
    let right: CGFloat = 38
    let usableWidth = max(width - left - right, 1)
    return left + usableWidth * CGFloat(index) / CGFloat(max(points.count - 1, 1))
  }

  private func yPosition(value: Double, height: CGFloat) -> CGFloat {
    let top: CGFloat = 20
    let bottom: CGFloat = 34
    let usableHeight = max(height - top - bottom, 1)
    return top + usableHeight * CGFloat(1 - min(max(value / 100, 0), 1))
  }
}

struct StressDailyChart: View {
  let summary: StressAlgorithmSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle("Today's Stress")
      StressTimelineChart(windows: summary.windows)
        .frame(height: 132)
      Text(summary.hasData ? timelineSummary : "Stress needs local heart-rate samples from today.")
        .font(.caption)
        .foregroundStyle(InkTheme.graphite)
    }
    .padding(14)
    .healthCardSurface()
  }

  private var timelineSummary: String {
    let score = summary.score.flatMap { HealthDataStore.numberText($0, fractionDigits: 0) } ?? "--"
    return "\(summary.sampleCount) HR samples | avg stress \(score) | avg HR \(averageHeartRateText)"
  }

  private var averageHeartRateText: String {
    guard let averageHeartRate = summary.averageHeartRate,
          let text = HealthDataStore.numberText(averageHeartRate, fractionDigits: 0) else {
      return "-- bpm"
    }
    return "\(text) bpm"
  }
}

struct StressBreakdownRows: View {
  let summary: StressAlgorithmSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        HealthSectionTitle("Stress Breakdown")
        if summary.hasData {
          Text("Duration: \(HealthDataStore.minutesText(totalDurationMinutes))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(InkTheme.graphite)
        }
      }
      // Monochrome intensity ramp: High = full ink, Med/Low fade out.
      BreakdownRow(label: "High", value: percentText(summary.high.percent), tint: InkTheme.ink, width: summary.high.percent)
      BreakdownRow(label: "Med", value: percentText(summary.medium.percent), tint: InkTheme.ink.opacity(0.55), width: summary.medium.percent)
      BreakdownRow(label: "Low", value: percentText(summary.low.percent), tint: InkTheme.ink.opacity(0.30), width: summary.low.percent)
    }
    .padding(14)
    .healthCardSurface()
  }

  private var totalDurationMinutes: Double {
    summary.high.durationMinutes + summary.medium.durationMinutes + summary.low.durationMinutes
  }

  private func percentText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

struct StressTimelineChart: View {
  let windows: [StressWindowPoint]

  var body: some View {
    GeometryReader { proxy in
      if windows.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(InkTheme.wash)
          .overlay {
            Text("No stress timeline")
              .font(.caption.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(InkTheme.wash)
          ForEach([25, 50, 75, 100], id: \.self) { value in
            let y = yPosition(value: Double(value), height: proxy.size.height)
            Path { path in
              path.move(to: CGPoint(x: 8, y: y))
              path.addLine(to: CGPoint(x: proxy.size.width - 30, y: y))
            }
            .stroke(InkTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
          }
          ForEach(Array(0..<max(windows.count - 1, 0)), id: \.self) { index in
            Path { path in
              path.move(to: chartPoint(index: index, size: proxy.size))
              path.addLine(to: chartPoint(index: index + 1, size: proxy.size))
            }
            .stroke(
              color(for: (windows[index].stress + windows[index + 1].stress) / 2),
              style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
          }
          ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
            if window.isSleepWindow {
              Rectangle()
                .fill(InkTheme.graphite.opacity(0.08))
                .frame(width: max(proxy.size.width / CGFloat(max(windows.count, 1)), 10), height: proxy.size.height - 24)
                .position(x: chartPoint(index: index, size: proxy.size).x, y: (proxy.size.height - 24) / 2)
            }
          }
          if let last = windows.last,
             let lastIndex = windows.indices.last {
            Circle()
              .fill(color(for: last.stress))
              .frame(width: 8, height: 8)
              .position(chartPoint(index: lastIndex, size: proxy.size))
          }
          VStack(alignment: .trailing) {
            Text("100")
            Spacer()
            Text("50")
            Spacer()
            Text("0")
          }
          .font(.caption2)
          .foregroundStyle(InkTheme.graphite)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 22, alignment: .trailing)
          .padding(.top, 6)
        }
      }
    }
  }

  private func chartPoint(index: Int, size: CGSize) -> CGPoint {
    let window = windows[index]
    return CGPoint(
      x: xPosition(index: index, width: size.width),
      y: yPosition(value: window.stress, height: size.height)
    )
  }

  private func xPosition(index: Int, width: CGFloat) -> CGFloat {
    let left: CGFloat = 12
    let right: CGFloat = 34
    let usableWidth = max(width - left - right, 1)
    return left + usableWidth * CGFloat(index) / CGFloat(max(windows.count - 1, 1))
  }

  private func yPosition(value: Double, height: CGFloat) -> CGFloat {
    let top: CGFloat = 10
    let bottom: CGFloat = 22
    let usableHeight = max(height - top - bottom, 1)
    return top + usableHeight * CGFloat(1 - min(max(value / 100, 0), 1))
  }

  private func color(for stress: Double) -> Color {
    // Radiograph: the stress trace is ink-monochrome; intensity fades with level.
    if stress >= 66 {
      return InkTheme.ink
    }
    if stress >= 33 {
      return InkTheme.ink.opacity(0.62)
    }
    return InkTheme.ink.opacity(0.34)
  }
}

struct HeartRateZonesSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HealthSectionTitle("Heart Rate Zones")
      BreakdownRow(label: "Zone 5", value: "0 min", tint: InkTheme.ink, width: 0)
      BreakdownRow(label: "Zone 4", value: "0 min", tint: InkTheme.ink.opacity(0.75), width: 0)
      BreakdownRow(label: "Zone 3", value: "0 min", tint: InkTheme.ink.opacity(0.50), width: 0)
      BreakdownRow(label: "Zone 2", value: "0 min", tint: InkTheme.ink.opacity(0.30), width: 0)
    }
    .padding(14)
    .healthCardSurface()
  }
}

struct BreakdownRow: View {
  let label: String
  let value: String
  let tint: Color
  let width: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(InkTheme.ink)
        .frame(width: 74, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(InkTheme.hairline)
          Capsule()
            .fill(tint)
            .frame(width: proxy.size.width * min(max(width, 0), 1))
        }
      }
      .frame(height: 8)
      Text(value)
        .font(.caption.weight(.semibold))
        .foregroundStyle(InkTheme.graphite)
        .frame(width: 54, alignment: .trailing)
    }
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
  /// Radiograph: flat wash surface with a hairline rule; the per-metric tint is ignored.
  func healthDashboardSurface(tint: Color, tintOpacity: Double = 0.06) -> some View {
    background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(InkTheme.wash)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(InkTheme.hairline)
    }
  }

  func healthCardSurface() -> some View {
    background(InkTheme.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(InkTheme.hairline)
      }
  }
}
