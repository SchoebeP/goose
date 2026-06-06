import SwiftUI

// MARK: - Shared helpers

/// "11:00 – 12:00" style label for an integer hour (wraps at 24).
private func hourRangeLabel(_ hour: Int) -> String {
  String(format: "%02d:00 – %02d:00", hour, (hour + 1) % 24)
}

/// Format a minute string like "2026-06-05T14:32" or "14:32" into "14:32".
private func minuteClockLabel(from minute: String) -> String {
  let afterT = minute.split(separator: "T").last.map(String.init) ?? minute
  // Keep HH:MM only (drop any trailing seconds / zone).
  let parts = afterT.split(separator: ":")
  guard parts.count >= 2 else { return afterT }
  return "\(parts[0]):\(parts[1])"
}

// MARK: - Heart Rate · Today drill-down

/// One hour's worth of HR, aggregated from the per-minute feed.
private struct HRHourBucket: Identifiable {
  let hour: Int
  let avg: Int
  let lo: Int
  let hi: Int
  let minuteCount: Int
  var id: Int { hour }
}

/// Full-screen drill-down for the HR Range card: a larger selectable hourly
/// range chart, a per-hour header panel, chevron stepping, and a per-hour list.
struct HRDayDetailView: View {
  let minutes: [HRMinute]
  @State private var selected: Int = 0

  private var buckets: [HRHourBucket] {
    var byHour: [String: [HRMinute]] = [:]
    for m in minutes {
      byHour[hourKey(from: m.minute), default: []].append(m)
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { key, rows in
        let avg = rows.isEmpty
          ? 0
          : Int((Double(rows.map(\.bpm).reduce(0, +)) / Double(rows.count)).rounded())
        return HRHourBucket(
          hour: Int(key) ?? 0,
          avg: avg,
          lo: rows.map(\.lo).min() ?? 0,
          hi: rows.map(\.hi).max() ?? 0,
          minuteCount: rows.count
        )
      }
  }

  var body: some View {
    let buckets = self.buckets
    let accent = GooseTheme.Accent.range
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if buckets.isEmpty {
          Text("No heart-rate data for today yet.")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
          let idx = min(max(selected, 0), buckets.count - 1)
          let sel = buckets[idx]

          // Header panel for the selected hour.
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Button {
                if idx > 0 { selected = idx - 1 }
              } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
              }
              .disabled(idx <= 0)

              Spacer()
              Text(hourRangeLabel(sel.hour))
                .font(.headline.weight(.semibold))
                .foregroundStyle(accent)
              Spacer()

              Button {
                if idx < buckets.count - 1 { selected = idx + 1 }
              } label: {
                Image(systemName: "chevron.right").font(.headline.weight(.bold))
              }
              .disabled(idx >= buckets.count - 1)
            }
            .tint(accent)

            HStack(spacing: 22) {
              hrStat("Avg", "\(sel.avg)", accent)
              hrStat("Low", "\(sel.lo)", .secondary)
              hrStat("High", "\(sel.hi)", .secondary)
            }
            Text("\(sel.minuteCount) min recorded · bpm · computed on our server")
              .font(.caption).foregroundStyle(.secondary)
          }
          .gooseCard()

          SelectableRangeChart(
            buckets: buckets,
            selectedHour: sel.hour,
            accent: accent,
            onSelect: { hour in
              if let i = buckets.firstIndex(where: { $0.hour == hour }) { selected = i }
            }
          )
          .frame(height: 260)
          .gooseCard()

          // Per-hour list.
          VStack(alignment: .leading, spacing: 0) {
            ForEach(buckets) { b in
              Button {
                if let i = buckets.firstIndex(where: { $0.hour == b.hour }) { selected = i }
              } label: {
                HStack {
                  Text(hourRangeLabel(b.hour))
                    .font(.subheadline.weight(b.hour == sel.hour ? .bold : .regular))
                    .foregroundStyle(b.hour == sel.hour ? accent : Color.primary)
                  Spacer()
                  Text("avg \(b.avg) · \(b.lo)–\(b.hi) bpm")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
              }
              .buttonStyle(.plain)
              if b.hour != buckets.last?.hour {
                Divider().overlay(Color.primary.opacity(0.06))
              }
            }
          }
          .gooseCard()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Heart Rate · Today")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func hrStat(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(color)
    }
  }
}

/// Selectable floating range bars (lo→hi) on one shared vertical scale.
private struct SelectableRangeChart: View {
  let buckets: [HRHourBucket]
  let selectedHour: Int
  let accent: Color
  let onSelect: (Int) -> Void

  var body: some View {
    GeometryReader { geo in
      let lo = Double((buckets.map(\.lo).min() ?? 40) - 3)
      let hi = Double((buckets.map(\.hi).max() ?? 120) + 3)
      let rng = max(hi - lo, 1)
      let h = geo.size.height
      HStack(alignment: .bottom, spacing: 4) {
        ForEach(buckets) { b in
          let topFrac = 1 - (Double(b.hi) - lo) / rng     // 0 = top
          let botFrac = 1 - (Double(b.lo) - lo) / rng     // distance-from-top of lo
          let barHeight = max(4, CGFloat(botFrac - topFrac) * h)
          let bottomGap = CGFloat(1 - botFrac) * h        // empty space below lo
          ZStack(alignment: .bottom) {
            Color.clear
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(accent.opacity(b.hour == selectedHour ? 1.0 : 0.35))
              .frame(height: barHeight)
              .padding(.bottom, bottomGap)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
          .onTapGesture { onSelect(b.hour) }
        }
      }
    }
  }
}

// MARK: - Steps · Today drill-down

private struct StepsHourBucket: Identifiable {
  let hour: Int
  let total: Int
  let busiestMinuteLabel: String
  let busiestMinuteSteps: Int
  var id: Int { hour }
}

/// Full-screen drill-down for the Steps card: a larger selectable hourly bar
/// chart, a per-hour header panel, chevron stepping, and a per-hour list.
struct StepsDayDetailView: View {
  let minutes: [StepMinute]
  @State private var selected: Int = 0

  private var buckets: [StepsHourBucket] {
    var byHour: [String: [StepMinute]] = [:]
    for m in minutes {
      byHour[hourKey(from: m.minute), default: []].append(m)
    }
    return byHour
      .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
      .map { key, rows in
        let busiest = rows.max { $0.steps < $1.steps }
        return StepsHourBucket(
          hour: Int(key) ?? 0,
          total: rows.reduce(0) { $0 + $1.steps },
          busiestMinuteLabel: busiest.map { minuteClockLabel(from: $0.minute) } ?? "—",
          busiestMinuteSteps: busiest?.steps ?? 0
        )
      }
  }

  var body: some View {
    let buckets = self.buckets
    let accent = GooseTheme.Accent.activity
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if buckets.isEmpty {
          Text("No steps for today yet.")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
          let idx = min(max(selected, 0), buckets.count - 1)
          let sel = buckets[idx]

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Button {
                if idx > 0 { selected = idx - 1 }
              } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
              }
              .disabled(idx <= 0)

              Spacer()
              Text(hourRangeLabel(sel.hour))
                .font(.headline.weight(.semibold))
                .foregroundStyle(accent)
              Spacer()

              Button {
                if idx < buckets.count - 1 { selected = idx + 1 }
              } label: {
                Image(systemName: "chevron.right").font(.headline.weight(.bold))
              }
              .disabled(idx >= buckets.count - 1)
            }
            .tint(accent)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text("\(sel.total)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
              Text("steps").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Most active minute: \(sel.busiestMinuteLabel) (\(sel.busiestMinuteSteps) steps) · our own count")
              .font(.caption).foregroundStyle(.secondary)
          }
          .gooseCard()

          SelectableStepsChart(
            buckets: buckets,
            selectedHour: sel.hour,
            accent: accent,
            onSelect: { hour in
              if let i = buckets.firstIndex(where: { $0.hour == hour }) { selected = i }
            }
          )
          .frame(height: 260)
          .gooseCard()

          VStack(alignment: .leading, spacing: 0) {
            ForEach(buckets) { b in
              Button {
                if let i = buckets.firstIndex(where: { $0.hour == b.hour }) { selected = i }
              } label: {
                HStack {
                  Text(hourRangeLabel(b.hour))
                    .font(.subheadline.weight(b.hour == sel.hour ? .bold : .regular))
                    .foregroundStyle(b.hour == sel.hour ? accent : Color.primary)
                  Spacer()
                  Text("\(b.total) steps")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
              }
              .buttonStyle(.plain)
              if b.hour != buckets.last?.hour {
                Divider().overlay(Color.primary.opacity(0.06))
              }
            }
          }
          .gooseCard()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Steps · Today")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Selectable baseline step bars scaled to the busiest hour.
private struct SelectableStepsChart: View {
  let buckets: [StepsHourBucket]
  let selectedHour: Int
  let accent: Color
  let onSelect: (Int) -> Void

  var body: some View {
    GeometryReader { geo in
      let mx = Double(buckets.map(\.total).max() ?? 1)
      let h = geo.size.height
      HStack(alignment: .bottom, spacing: 4) {
        ForEach(buckets) { b in
          let barHeight = max(3, CGFloat(Double(b.total) / max(mx, 1)) * h)
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(accent.opacity(b.hour == selectedHour ? 1.0 : 0.35))
            .frame(height: barHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(b.hour) }
        }
      }
    }
  }
}
