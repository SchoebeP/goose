import SwiftUI

// MARK: - Pulse spine (the signature element)

/// A thin cardiac ribbon that beats at the live heart rate.
/// Arterial red while live; dotted hairline with "no signal" when not.
struct PulseSpine: View {
  let bpm: Int?
  let isLive: Bool
  var height: CGFloat = 26

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if isLive, let bpm, bpm > 0 {
        liveSpine(bpm: bpm)
      } else {
        noSignal
      }
    }
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      isLive ? "Live pulse \(bpm.map(String.init) ?? "")" : "No live signal"
    )
  }

  private func liveSpine(bpm: Int) -> some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
      Canvas { canvasContext, size in
        let beatPeriod = 60.0 / Double(max(30, min(220, bpm)))
        let time = context.date.timeIntervalSinceReferenceDate
        let phase = reduceMotion ? 0.35 : (time.truncatingRemainder(dividingBy: beatPeriod)) / beatPeriod
        let path = Self.tracePath(in: size, beatPhase: phase)
        canvasContext.stroke(
          path,
          with: .color(InkTheme.arterial),
          style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        )
      }
    }
  }

  private var noSignal: some View {
    HStack(spacing: 10) {
      Line()
        .stroke(
          InkTheme.hairline,
          style: StrokeStyle(lineWidth: 1, dash: [1.5, 4])
        )
        .frame(height: 1)
      Text("no signal")
        .inkEyebrow()
        .fixedSize()
    }
  }

  /// One QRS-like complex travelling across the ribbon; amplitude follows the beat phase.
  private static func tracePath(in size: CGSize, beatPhase: Double) -> Path {
    var path = Path()
    let midY = size.height / 2
    let complexCenter = size.width * 0.5
    let complexHalfWidth = size.width * 0.09
    // Beat envelope: sharp rise right after the beat instant, decaying to rest.
    let envelope = max(0.18, 1.0 - beatPhase * 1.6)
    let spikeHeight = (size.height * 0.46) * envelope

    path.move(to: CGPoint(x: 0, y: midY))
    path.addLine(to: CGPoint(x: complexCenter - complexHalfWidth, y: midY))
    // Q dip
    path.addLine(to: CGPoint(x: complexCenter - complexHalfWidth * 0.45, y: midY + spikeHeight * 0.28))
    // R spike
    path.addLine(to: CGPoint(x: complexCenter, y: midY - spikeHeight))
    // S dip
    path.addLine(to: CGPoint(x: complexCenter + complexHalfWidth * 0.45, y: midY + spikeHeight * 0.42))
    path.addLine(to: CGPoint(x: complexCenter + complexHalfWidth, y: midY))
    path.addLine(to: CGPoint(x: size.width, y: midY))
    return path
  }

  private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: 0, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
      return path
    }
  }
}

// MARK: - Vital reading (eyebrow + serif numeral + mono unit)

struct VitalReading: View {
  let eyebrow: String
  let value: String
  var unit: String? = nil
  var numeralSize: CGFloat = 56
  var live: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 7) {
        Text(eyebrow).inkEyebrow()
        if live {
          Circle()
            .fill(InkTheme.arterial)
            .frame(width: 5, height: 5)
            .accessibilityLabel("live")
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(value)
          .font(InkTheme.displayNumeral(numeralSize))
          .foregroundStyle(live ? InkTheme.arterial : InkTheme.ink)
          .contentTransition(.numericText())
          .monospacedDigit()
        if let unit {
          Text(unit)
            .font(InkTheme.mono(numeralSize * 0.26))
            .foregroundStyle(InkTheme.graphite)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Ink sparkline (monochrome chart)

struct InkSparkline: View {
  let values: [Double]
  var height: CGFloat = 46
  var showsNowDot: Bool = false

  var body: some View {
    Canvas { context, size in
      guard values.count > 1 else { return }
      let minValue = values.min() ?? 0
      let maxValue = values.max() ?? 1
      let span = max(maxValue - minValue, 0.0001)
      let stepX = size.width / CGFloat(values.count - 1)

      func point(_ index: Int) -> CGPoint {
        let normalized = (values[index] - minValue) / span
        return CGPoint(
          x: CGFloat(index) * stepX,
          y: size.height - CGFloat(normalized) * (size.height - 6) - 3
        )
      }

      var line = Path()
      line.move(to: point(0))
      for index in 1..<values.count {
        line.addLine(to: point(index))
      }
      context.stroke(
        line,
        with: .color(InkTheme.ink),
        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
      )

      if showsNowDot {
        let last = point(values.count - 1)
        context.fill(
          Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)),
          with: .color(InkTheme.arterial)
        )
      }
    }
    .frame(height: height)
    .accessibilityHidden(true)
  }
}

// MARK: - Section scaffolding

struct InkSectionHeader: View {
  let title: String
  var detail: String? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(InkTheme.sectionTitle)
        .foregroundStyle(InkTheme.ink)
      Spacer()
      if let detail {
        Text(detail).inkEyebrow()
      }
    }
  }
}

/// Ledger row: mono label left, value right.
struct InkLedgerRow: View {
  let label: String
  let value: String
  var valueColor: Color = InkTheme.ink

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).inkEyebrow()
      Spacer(minLength: 12)
      Text(value)
        .font(.system(size: 15, weight: .medium, design: .serif))
        .foregroundStyle(valueColor)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 9)
    .accessibilityElement(children: .combine)
  }
}
