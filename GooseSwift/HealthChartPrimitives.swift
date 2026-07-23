import Darwin
import Foundation
import SwiftUI
import UIKit

struct HealthSummaryPill: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(InkTheme.graphite)
      Text(value)
        .font(.caption.weight(.bold))
        .foregroundStyle(InkTheme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(InkTheme.wash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct HealthSourceBadge: View {
  let source: HealthDataSource

  var body: some View {
    Text(source.kind.rawValue)
      .font(.caption2.weight(.bold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(color.opacity(0.12), in: Capsule())
  }

  private var color: Color {
    switch source.kind {
    case .bridge: InkTheme.ink
    case .local: InkTheme.ink
    case .live: InkTheme.arterial
    case .unavailable: InkTheme.graphite
    }
  }
}

struct LegacyCardioWeeklyLoadChart: View {
  let days: [CardioLoadDay]

  var body: some View {
    if days.isEmpty {
      ContentUnavailableView("No Weekly Load", systemImage: "heart.circle", description: Text("Cardio Load needs HR and activity data."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      HStack(alignment: .bottom, spacing: 10) {
        ForEach(days) { day in
          VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(color(for: day.status))
              .frame(height: max(12, 120 * day.percent))
              .overlay(alignment: .top) {
                Text("\(Int(day.load))")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(InkTheme.film)
                  .padding(.top, 4)
              }
            Text(day.dateLabel)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
  }

  private func color(for status: String) -> Color {
    // Radiograph: charts are ink-monochrome; status is carried by the label.
    _ = status
    return InkTheme.ink
  }
}

struct LegacyEnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    if points.isEmpty {
      ContentUnavailableView("No Energy Data", systemImage: "bolt.circle", description: Text("Energy Bank needs stress, sleep, and activity inputs."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        GeometryReader { proxy in
          ZStack {
            chartPath(values: points.map(\.energy), size: proxy.size)
              .stroke(InkTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            chartPath(values: points.map(\.stress), size: proxy.size)
              .stroke(InkTheme.graphite, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let selectedPoint, let index = points.firstIndex(where: { $0.id == selectedPoint.id }) {
              let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
              Rectangle()
                .fill(InkTheme.ink.opacity(0.16))
                .frame(width: 2)
                .position(x: x, y: proxy.size.height / 2)
            }
          }
        }

        HStack(spacing: 16) {
          Label("Energy", systemImage: "bolt.fill")
            .foregroundStyle(InkTheme.ink)
          Label("Stress", systemImage: "waveform.path.ecg")
            .foregroundStyle(InkTheme.graphite)
        }
        .font(.caption.weight(.semibold))
      }
      .padding(.vertical, 8)
    }
  }

  private func chartPath(values: [Double], size: CGSize) -> Path {
    Path { path in
      guard !values.isEmpty else {
        return
      }
      for (index, value) in values.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
        let normalized = min(max(value / 100, 0), 1)
        let y = size.height - size.height * CGFloat(normalized)
        if index == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
    }
  }
}

struct CompactEnergyAndStressChart: View {
  let points: [EnergyStressPoint]
  let selectedPoint: EnergyStressPoint?

  var body: some View {
    if points.isEmpty {
      ContentUnavailableView("No Energy Data", systemImage: "battery.0percent", description: Text("Energy Bank needs stress, sleep, and activity data."))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        GeometryReader { proxy in
          ZStack(alignment: .bottomLeading) {
            chartLine(points.map(\.energy), in: proxy.size)
              .stroke(InkTheme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            chartLine(points.map(\.stress), in: proxy.size)
              .stroke(InkTheme.graphite, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ForEach(points) { point in
              Circle()
                .fill(point.id == selectedPoint?.id ? InkTheme.ink : InkTheme.graphite.opacity(0.45))
                .frame(width: point.id == selectedPoint?.id ? 9 : 6, height: point.id == selectedPoint?.id ? 9 : 6)
                .position(position(for: point.energy, index: index(of: point), size: proxy.size))
            }
          }
        }
        .frame(height: 126)

        HStack(spacing: 12) {
          ChartLegend(color: InkTheme.ink, label: "Energy")
          ChartLegend(color: InkTheme.graphite, label: "Stress")
          Spacer()
          if let selectedPoint {
            Text(selectedPoint.timeLabel)
              .font(.caption.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
        }
      }
      .padding(.top, 8)
    }
  }

  private func chartLine(_ values: [Double], in size: CGSize) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = position(for: value, index: index, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func position(for value: Double, index: Int, size: CGSize) -> CGPoint {
    let x = size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
    let y = size.height - size.height * CGFloat(min(max(value / 100, 0), 1))
    return CGPoint(x: x, y: y)
  }

  private func index(of point: EnergyStressPoint) -> Int {
    points.firstIndex(where: { $0.id == point.id }) ?? 0
  }
}

struct ChartLegend: View {
  let color: Color
  let label: String

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(InkTheme.graphite)
    }
  }
}

struct HealthSparkline: View {
  let points: [Double]
  let tint: Color

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(InkTheme.wash)
          .overlay {
            Text("No data")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
      } else {
        Path { path in
          let minimum = points.min() ?? 0
          let maximum = points.max() ?? 1
          let span = max(maximum - minimum, 1)
          for (index, point) in points.enumerated() {
            let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
            let normalized = (point - minimum) / span
            let y = proxy.size.height - proxy.size.height * CGFloat(normalized)
            if index == 0 {
              path.move(to: CGPoint(x: x, y: y))
            } else {
              path.addLine(to: CGPoint(x: x, y: y))
            }
          }
        }
        // Radiograph: sparklines are always ink, regardless of the caller-supplied tint.
        .stroke(InkTheme.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
      }
    }
  }
}

struct CardioWeeklyLoadChart: View {
  let days: [CardioLoadDay]

  var body: some View {
    GeometryReader { proxy in
      if days.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(InkTheme.wash)
          .overlay {
            Text("No weekly load data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(InkTheme.graphite)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(InkTheme.wash)
          rangeBand(in: proxy.size)
          chartPath(in: proxy.size)
            .stroke(InkTheme.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
          ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
            let point = chartPoint(index: index, load: day.load, size: proxy.size)
            Circle()
              // Arterial marks "today" — the newest point only.
              .fill(index == days.count - 1 ? InkTheme.arterial : InkTheme.film)
              .stroke(index == days.count - 1 ? InkTheme.arterial : InkTheme.ink, lineWidth: 1.5)
              .frame(width: index == days.count - 1 ? 10 : 7, height: index == days.count - 1 ? 10 : 7)
              .position(point)
            Text(day.dateLabel)
              .font(.caption2)
              .foregroundStyle(InkTheme.graphite)
              .position(x: point.x, y: proxy.size.height - 12)
          }
          VStack(alignment: .trailing, spacing: 0) {
            Text("60")
            Spacer()
            Text("30")
            Spacer()
            Text("0")
          }
          .font(.caption2)
          .foregroundStyle(InkTheme.graphite)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 24, alignment: .trailing)
          .padding(.top, 8)
          if let last = days.last {
            Text("\(Int(last.load)) load | \(last.status)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(InkTheme.ink)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(.thinMaterial, in: Capsule())
              .position(x: min(proxy.size.width - 72, chartPoint(index: days.count - 1, load: last.load, size: proxy.size).x), y: 18)
          }
        }
      }
    }
  }

  private func rangeBand(in size: CGSize) -> some View {
    let top = yPosition(load: 45, height: size.height)
    let bottom = yPosition(load: 30, height: size.height)
    return Rectangle()
      .fill(InkTheme.graphite.opacity(0.08))
      .frame(width: size.width, height: max(bottom - top, 1))
      .position(x: size.width / 2, y: (top + bottom) / 2)
  }

  private func chartPath(in size: CGSize) -> Path {
    Path { path in
      for (index, day) in days.enumerated() {
        let point = chartPoint(index: index, load: day.load, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func chartPoint(index: Int, load: Double, size: CGSize) -> CGPoint {
    let left: CGFloat = 16
    let right: CGFloat = 34
    let usableWidth = max(size.width - left - right, 1)
    let x = left + usableWidth * CGFloat(index) / CGFloat(max(days.count - 1, 1))
    return CGPoint(x: x, y: yPosition(load: load, height: size.height))
  }

  private func yPosition(load: Double, height: CGFloat) -> CGFloat {
    let top: CGFloat = 18
    let bottom: CGFloat = 34
    let usableHeight = max(height - top - bottom, 1)
    let normalized = min(max(load / 60.0, 0), 1)
    return top + usableHeight * CGFloat(1 - normalized)
  }
}

