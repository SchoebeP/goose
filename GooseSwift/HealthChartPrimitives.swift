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
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.bold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    case .bridge: .green
    case .local: .teal
    case .live: .blue
    case .unavailable: .secondary
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
                  .foregroundStyle(.white)
                  .padding(.top, 4)
              }
            Text(day.dateLabel)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
  }

  private func color(for status: String) -> Color {
    switch status {
    case "Productive", "Peaking":
      return .green
    case "Maintaining":
      return .blue
    case "Detraining":
      return .orange
    case "Fatigued", "Overtraining":
      return .red
    default:
      return .pink
    }
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
              .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            chartPath(values: points.map(\.stress), size: proxy.size)
              .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let selectedPoint, let index = points.firstIndex(where: { $0.id == selectedPoint.id }) {
              let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
              Rectangle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 2)
                .position(x: x, y: proxy.size.height / 2)
            }
          }
        }

        HStack(spacing: 16) {
          Label("Energy", systemImage: "bolt.fill")
            .foregroundStyle(.teal)
          Label("Stress", systemImage: "waveform.path.ecg")
            .foregroundStyle(.orange)
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
              .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            chartLine(points.map(\.stress), in: proxy.size)
              .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            ForEach(points) { point in
              Circle()
                .fill(point.id == selectedPoint?.id ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: point.id == selectedPoint?.id ? 9 : 6, height: point.id == selectedPoint?.id ? 9 : 6)
                .position(position(for: point.energy, index: index(of: point), size: proxy.size))
            }
          }
        }
        .frame(height: 126)

        HStack(spacing: 12) {
          ChartLegend(color: .green, label: "Energy")
          ChartLegend(color: .orange, label: "Stress")
          Spacer()
          if let selectedPoint {
            Text(selectedPoint.timeLabel)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
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
          .fill(Color(.tertiarySystemFill))
          .overlay {
            Text("No data")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
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
        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
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
          .fill(Color(.tertiarySystemFill))
          .overlay {
            Text("No weekly load data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
      } else {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
          rangeBand(in: proxy.size)
          chartPath(in: proxy.size)
            .stroke(.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
            let point = chartPoint(index: index, load: day.load, size: proxy.size)
            Circle()
              .fill(index == days.count - 1 ? Color.pink : Color.white)
              .stroke(.pink, lineWidth: 2)
              .frame(width: index == days.count - 1 ? 12 : 8, height: index == days.count - 1 ? 12 : 8)
              .position(point)
            Text(day.dateLabel)
              .font(.caption2)
              .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
          .frame(width: proxy.size.width - 8, height: proxy.size.height - 24, alignment: .trailing)
          .padding(.top, 8)
          if let last = days.last {
            Text("\(Int(last.load)) load | \(last.status)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.pink)
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
      .fill(Color.green.opacity(0.12))
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


// ============================================================
// Direction A redesign charts — honest gaps (hatched) + personal bands.
// Ported from design_handoff_goose_direction_a/goose-charts.jsx.
// ============================================================

struct HourlyHR: Equatable { let hour: Int; let lo: Int; let hi: Int; let avg: Int; let gap: Bool }
struct HourlySteps: Equatable { let hour: Int; let v: Int; let gap: Bool }
struct SleepNight: Equatable, Identifiable { let date: String; let minutes: Int; var id: String { date } }
struct VitalPoint: Equatable { let label: String; let value: Double }

private func gdaHatch(_ ctx: inout GraphicsContext, in rect: CGRect, color: Color = GDA.lineStrong) {
  ctx.clip(to: Path(roundedRect: rect, cornerRadius: 3))
  var x = rect.minX - rect.height
  while x < rect.maxX {
    var p = Path()
    p.move(to: CGPoint(x: x, y: rect.maxY))
    p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
    ctx.stroke(p, with: .color(color), lineWidth: 1.2)
    x += 6
  }
}

private func gdaLabel(_ ctx: GraphicsContext, _ s: String, _ size: CGFloat, _ color: Color,
                      at p: CGPoint, anchor: UnitPoint = .leading) {
  var t = ctx
  t.draw(Text(s).font(.system(size: size)).foregroundColor(color), at: p, anchor: anchor)
}

/// Daily vitals trend vs personal usual band (shaded band, dashed mean, value line).
struct BandTrendChart: View {
  let series: [VitalPoint]
  let band: VitalBand
  let color: Color
  var height: CGFloat = 96
  var fractionDigits: Int = 0

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      let padT: CGFloat = 10, padB: CGFloat = 18, padL: CGFloat = 4, padR: CGFloat = 40
      guard !series.isEmpty else { return }
      let vals = series.map(\.value)
      let spread = (band.hi - band.lo)
      let minV = min((vals.min() ?? band.lo), band.lo) - spread * 0.35 - 0.0001
      let maxV = max((vals.max() ?? band.hi), band.hi) + spread * 0.35 + 0.0001
      let y = { (v: Double) in padT + CGFloat(1 - (v - minV) / (maxV - minV)) * (h - padT - padB) }
      let x = { (i: Int) in padL + CGFloat(i) / CGFloat(max(series.count - 1, 1)) * (w - padL - padR) }
      let fmt = { (v: Double) in v.formatted(.number.precision(.fractionLength(fractionDigits))) }

      // usual band
      let bandRect = CGRect(x: padL, y: y(band.hi), width: w - padL - padR, height: max(y(band.lo) - y(band.hi), 2))
      ctx.fill(Path(roundedRect: bandRect, cornerRadius: 3), with: .color(color.opacity(0.10)))
      // mean
      var mean = Path(); mean.move(to: CGPoint(x: padL, y: y(band.mean))); mean.addLine(to: CGPoint(x: w - padR, y: y(band.mean)))
      ctx.stroke(mean, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
      gdaLabel(ctx, fmt(band.hi), 9.5, GDA.text3, at: CGPoint(x: w - padR + 6, y: y(band.hi)))
      gdaLabel(ctx, fmt(band.lo), 9.5, GDA.text3, at: CGPoint(x: w - padR + 6, y: y(band.lo)))

      // value line
      var line = Path()
      for (i, d) in series.enumerated() {
        let pt = CGPoint(x: x(i), y: y(d.value))
        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
      }
      ctx.stroke(line, with: .color(color.opacity(0.9)),
                 style: StrokeStyle(lineWidth: series.count > 40 ? 1.4 : 2, lineCap: .round, lineJoin: .round))
      // terminal dot
      if let lastIdx = series.indices.last {
        let p = CGPoint(x: x(lastIdx), y: y(series[lastIdx].value))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(color))
      }
      // x labels first/last
      gdaLabel(ctx, series.first!.label, 9.5, GDA.text3, at: CGPoint(x: x(0), y: h - 4))
      gdaLabel(ctx, series.last!.label, 9.5, GDA.text3, at: CGPoint(x: x(series.count - 1), y: h - 4), anchor: .center)
    }
    .frame(height: height)
  }
}

/// Hourly HR lo–hi range bars (heart, 0.55), gridlines 60/90/120, hatched gaps.
struct DayHRRangeChart: View {
  let buckets: [HourlyHR]   // 24 entries, hour 0..23
  var height: CGFloat = 130

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      let padT: CGFloat = 8, padB: CGFloat = 18, padL: CGFloat = 4, padR: CGFloat = 30
      let lo = 45.0, hi = 135.0
      let y = { (v: Double) in padT + CGFloat(1 - (v - lo) / (hi - lo)) * (h - padT - padB) }
      let bw = (w - padL - padR) / 24
      let x = { (hr: Int) in padL + CGFloat(hr) * bw }
      for g in [60.0, 90.0, 120.0] {
        var gl = Path(); gl.move(to: CGPoint(x: padL, y: y(g))); gl.addLine(to: CGPoint(x: w - padR, y: y(g)))
        ctx.stroke(gl, with: .color(GDA.line), lineWidth: 1)
        gdaLabel(ctx, "\(Int(g))", 9.5, GDA.text3, at: CGPoint(x: w - padR + 5, y: y(g)))
      }
      for d in buckets {
        let rectX = x(d.hour) + 1.5
        if d.gap {
          var c = ctx
          gdaHatch(&c, in: CGRect(x: x(d.hour) + 1, y: padT, width: bw - 2, height: h - padT - padB))
        } else {
          let r = CGRect(x: rectX, y: y(Double(d.hi)), width: bw - 3, height: max(y(Double(d.lo)) - y(Double(d.hi)), 3))
          ctx.fill(Path(roundedRect: r, cornerRadius: (bw - 3) / 2), with: .color(GDA.heart.opacity(0.55)))
        }
      }
      for hr in [0, 6, 12, 18] {
        gdaLabel(ctx, hr == 0 ? "00" : "\(hr)", 9.5, GDA.text3, at: CGPoint(x: x(hr) + 2, y: h - 4))
      }
      gdaLabel(ctx, "24", 9.5, GDA.text3, at: CGPoint(x: x(24) - 2, y: h - 4), anchor: .trailing)
    }
    .frame(height: height)
  }
}

/// Hourly step bars (activity green), zero hours = 2px stub, hatched gaps.
struct HourlyStepsChart: View {
  let buckets: [HourlySteps]
  var height: CGFloat = 96

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      let padT: CGFloat = 8, padB: CGFloat = 18, padL: CGFloat = 4, padR: CGFloat = 4
      let maxV = Double(max(buckets.filter { !$0.gap }.map(\.v).max() ?? 1, 1))
      let bw = (w - padL - padR) / 24
      let x = { (hr: Int) in padL + CGFloat(hr) * bw }
      let y = { (v: Double) in padT + CGFloat(1 - v / maxV) * (h - padT - padB) }
      for d in buckets {
        if d.gap {
          var c = ctx
          gdaHatch(&c, in: CGRect(x: x(d.hour) + 1, y: padT, width: bw - 2, height: h - padT - padB))
        } else if d.v == 0 {
          ctx.fill(Path(roundedRect: CGRect(x: x(d.hour) + 1.5, y: h - padB - 2, width: bw - 3, height: 2), cornerRadius: 1),
                   with: .color(GDA.activity.opacity(0.25)))
        } else {
          let r = CGRect(x: x(d.hour) + 1.5, y: y(Double(d.v)), width: bw - 3, height: max(h - padB - y(Double(d.v)), 2))
          ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(GDA.activity.opacity(0.8)))
        }
      }
      for hr in [0, 6, 12, 18] {
        gdaLabel(ctx, hr == 0 ? "00" : "\(hr)", 9.5, GDA.text3, at: CGPoint(x: x(hr) + 2, y: h - 4))
      }
      gdaLabel(ctx, "24", 9.5, GDA.text3, at: CGPoint(x: x(24) - 2, y: h - 4), anchor: .trailing)
    }
    .frame(height: height)
  }
}

/// Per-night sleep bars vs dashed goal line; last night emphasized.
struct SleepBarsChart: View {
  let nights: [SleepNight]
  var height: CGFloat = 110
  var goalMinutes: Int = 450

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      let padT: CGFloat = 10, padB: CGFloat = 20, padL: CGFloat = 4, padR: CGFloat = 36
      guard !nights.isEmpty else { return }
      let maxV = 9.0 * 60
      let bw = (w - padL - padR) / CGFloat(nights.count)
      let x = { (i: Int) in padL + CGFloat(i) * bw }
      let y = { (v: Double) in padT + CGFloat(1 - v / maxV) * (h - padT - padB) }
      var goal = Path(); goal.move(to: CGPoint(x: padL, y: y(Double(goalMinutes)))); goal.addLine(to: CGPoint(x: w - padR, y: y(Double(goalMinutes))))
      ctx.stroke(goal, with: .color(GDA.sleep.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
      gdaLabel(ctx, "7h30", 9.5, GDA.text3, at: CGPoint(x: w - padR + 5, y: y(Double(goalMinutes))))
      for (i, n) in nights.enumerated() {
        let r = CGRect(x: x(i) + bw * 0.18, y: y(Double(n.minutes)), width: bw * 0.64, height: max(h - padB - y(Double(n.minutes)), 2))
        ctx.fill(Path(roundedRect: r, cornerRadius: min(7, bw * 0.3)),
                 with: .color(GDA.sleep.opacity(i == nights.count - 1 ? 0.95 : 0.5)))
        if nights.count <= 8 {
          let lbl = n.date.split(separator: "-").last.map(String.init) ?? n.date
          gdaLabel(ctx, lbl, 9, GDA.text3, at: CGPoint(x: x(i) + bw / 2, y: h - 6), anchor: .center)
        }
      }
    }
    .frame(height: height)
  }
}

/// Generic daily bars with honest gaps (steps per day).
struct DailyBarsChart: View {
  let points: [VitalPoint]   // value; use .value == -1 to mark a gap
  var color: Color = GDA.activity
  var height: CGFloat = 96

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      let padT: CGFloat = 8, padB: CGFloat = 18, padL: CGFloat = 4, padR: CGFloat = 4
      guard !points.isEmpty else { return }
      let maxV = max(points.filter { $0.value >= 0 }.map(\.value).max() ?? 1, 1)
      let bw = (w - padL - padR) / CGFloat(points.count)
      let x = { (i: Int) in padL + CGFloat(i) * bw }
      let y = { (v: Double) in padT + CGFloat(1 - v / maxV) * (h - padT - padB) }
      for (i, d) in points.enumerated() {
        if d.value < 0 {
          var c = ctx
          gdaHatch(&c, in: CGRect(x: x(i) + min(1, bw * 0.1), y: padT, width: max(bw - 2, 1.2), height: h - padT - padB))
        } else {
          let r = CGRect(x: x(i) + min(1.5, bw * 0.12), y: y(d.value), width: max(bw - 3, 1.2), height: max(h - padB - y(d.value), 2))
          ctx.fill(Path(roundedRect: r, cornerRadius: min(2.5, bw * 0.3)),
                   with: .color(color.opacity(i == points.count - 1 ? 0.95 : 0.65)))
        }
      }
      gdaLabel(ctx, points.first!.label, 9.5, GDA.text3, at: CGPoint(x: padL, y: h - 4))
      gdaLabel(ctx, points.last!.label, 9.5, GDA.text3, at: CGPoint(x: w - padR, y: h - 4), anchor: .trailing)
    }
    .frame(height: height)
  }
}

/// Decorative live-HR sparkline (noisy, last few minutes).
struct LiveSparkline: View {
  var color: Color = GDA.heart
  var seed: Double = 3
  var width: CGFloat = 130
  var height: CGFloat = 40

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      var p = Path()
      for i in 0..<40 {
        let fi = Double(i)
        let v = sin(fi * 0.55 + seed) * 5 + sin(fi * 1.7 + seed * 2) * 3 + sin(fi * 0.13) * 6
        let pt = CGPoint(x: CGFloat(fi / 39) * w, y: h / 2 - CGFloat(v))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
      }
      ctx.stroke(p, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
    .frame(width: width, height: height)
  }
}
