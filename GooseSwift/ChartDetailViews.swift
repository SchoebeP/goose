
/// Hour key extracted from a minute string like "2026-06-05T14:32" -> "14"
/// (defensive: works for "14:32" too). Returns "" if unparseable.
func hourKey(from minute: String) -> String {
  let afterT = minute.split(separator: "T").last.map(String.init) ?? minute
  let hour = afterT.split(separator: ":").first.map(String.init) ?? ""
  return hour
}

struct HRMinute: Decodable, Identifiable {
  let minute: String
  let bpm: Int
  let lo: Int
  let hi: Int
  let n: Int
  var id: String { minute }
}

struct StepMinute: Decodable, Identifiable {
  let minute: String
  let steps: Int
  var id: String { minute }
}
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
    let accent = InkTheme.arterial
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if buckets.isEmpty {
          Text("No heart-rate data for today yet.")
            .font(InkTheme.footnote)
            .foregroundStyle(InkTheme.graphite)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
          let idx = min(max(selected, 0), buckets.count - 1)
          let sel = buckets[idx]

          // Header panel for the selected hour.
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Button {
                if idx > 0 { selected = idx - 1 }
              } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
              }
              .disabled(idx <= 0)

              Spacer()
              Text(hourRangeLabel(sel.hour))
                .font(InkTheme.mono(15, weight: .semibold))
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

            HStack(spacing: 26) {
              hrStat("Avg", "\(sel.avg)", accent)
              hrStat("Low", "\(sel.lo)", InkTheme.graphite)
              hrStat("High", "\(sel.hi)", InkTheme.graphite)
            }
            Text("\(sel.minuteCount) min recorded · bpm · computed on our server")
              .font(InkTheme.footnote)
              .foregroundStyle(InkTheme.graphite)
          }
          .padding(.vertical, 16)

          InkRule()

          SelectableRangeChart(
            buckets: buckets,
            selectedHour: sel.hour,
            accent: accent,
            onSelect: { hour in
              if let i = buckets.firstIndex(where: { $0.hour == hour }) { selected = i }
            }
          )
          .frame(height: 220)
          .padding(.vertical, 16)

          InkRule()

          // Per-hour list.
          VStack(alignment: .leading, spacing: 0) {
            ForEach(buckets) { b in
              Button {
                if let i = buckets.firstIndex(where: { $0.hour == b.hour }) { selected = i }
              } label: {
                HStack {
                  Text(hourRangeLabel(b.hour))
                    .font(InkTheme.mono(13, weight: b.hour == sel.hour ? .bold : .regular))
                    .foregroundStyle(b.hour == sel.hour ? accent : InkTheme.ink)
                  Spacer()
                  Text("avg \(b.avg) · \(b.lo)–\(b.hi) bpm")
                    .font(InkTheme.mono(13))
                    .foregroundStyle(InkTheme.graphite)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              InkRule()
            }
          }
        }
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.vertical, 18)
    }
    .inkScreen()
    .navigationTitle("Heart Rate · Today")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func hrStat(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).inkEyebrow()
      Text(value)
        .font(InkTheme.displayNumeral(28))
        .foregroundStyle(color)
        .monospacedDigit()
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
    let accent = InkTheme.ink
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if buckets.isEmpty {
          Text("No steps for today yet.")
            .font(InkTheme.footnote)
            .foregroundStyle(InkTheme.graphite)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
          let idx = min(max(selected, 0), buckets.count - 1)
          let sel = buckets[idx]

          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Button {
                if idx > 0 { selected = idx - 1 }
              } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
              }
              .disabled(idx <= 0)

              Spacer()
              Text(hourRangeLabel(sel.hour))
                .font(InkTheme.mono(15, weight: .semibold))
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

            HStack(alignment: .firstTextBaseline, spacing: 5) {
              Text("\(sel.total)")
                .font(InkTheme.displayNumeral(34))
                .monospacedDigit()
                .foregroundStyle(accent)
              Text("steps")
                .font(InkTheme.mono(12))
                .foregroundStyle(InkTheme.graphite)
            }
            Text("Most active minute: \(sel.busiestMinuteLabel) (\(sel.busiestMinuteSteps) steps) · our own count")
              .font(InkTheme.footnote)
              .foregroundStyle(InkTheme.graphite)
          }
          .padding(.vertical, 16)

          InkRule()

          SelectableStepsChart(
            buckets: buckets,
            selectedHour: sel.hour,
            accent: accent,
            onSelect: { hour in
              if let i = buckets.firstIndex(where: { $0.hour == hour }) { selected = i }
            }
          )
          .frame(height: 220)
          .padding(.vertical, 16)

          InkRule()

          VStack(alignment: .leading, spacing: 0) {
            ForEach(buckets) { b in
              Button {
                if let i = buckets.firstIndex(where: { $0.hour == b.hour }) { selected = i }
              } label: {
                HStack {
                  Text(hourRangeLabel(b.hour))
                    .font(InkTheme.mono(13, weight: b.hour == sel.hour ? .bold : .regular))
                    .foregroundStyle(b.hour == sel.hour ? accent : InkTheme.ink)
                  Spacer()
                  Text("\(b.total) steps")
                    .font(InkTheme.mono(13))
                    .foregroundStyle(InkTheme.graphite)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              InkRule()
            }
          }
        }
      }
      .padding(.horizontal, InkTheme.screenMargin)
      .padding(.vertical, 18)
    }
    .inkScreen()
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

// ============================================================
// Direction A — "Quiet Companion" pushed DETAIL screens.
// DSleep + DHrv from proto-screens.jsx, built on the GDA design
// system. Reached via NavigationLink(value: GDADetail.…) and a
// .navigationDestination(for: GDADetail.self) on each tab screen.
// ============================================================

/// Routes for the two pushed detail screens (referenced by Today/Morning).
enum GDADetail: Hashable {
  case sleep
  case hrv
}

/// "Sleep" / "HRV" detail header: 28pt display title + 14pt muted subtitle.
/// Mirrors the proto's `HeaderA` so the detail screens read like the tabs.
private struct GDADetailHeader: View {
  let title: String
  var sub: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .tracking(-0.4)
        .foregroundStyle(GDA.text)
      if let sub {
        Text(sub)
          .font(.system(size: 14))
          .foregroundStyle(GDA.text2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Caption row matching the proto's `g-ours` honest-provenance line.
private struct GDAOurs: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 12.5))
      .foregroundStyle(GDA.text3)
      .lineSpacing(2)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Sleep detail (DSleep)

/// Pushed "Sleep" detail: last night's duration, the week's bars, and a
/// per-night list. Our own movement+HR detection — no sleep stages.
struct GDASleepDetailView: View {
  @ObservedObject var store: HealthDataStore

  /// "Night of <latest date>" subtitle from the most recent sleep night.
  private var nightSub: String {
    if let last = store.sleepNights.last {
      return "Night of \(last.date)"
    }
    return "Night of —"
  }

  /// "Xh Ym" for the most recent night's minutes (— when no data yet).
  private var lastNightDuration: (hours: Int, minutes: Int)? {
    guard let mins = store.sleepNights.last?.minutes else { return nil }
    return (mins / 60, mins % 60)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GDADetailHeader(title: "Sleep", sub: nightSub)

        // Last night — big duration, in-bed + average pills, honest caption.
        VStack(alignment: .leading, spacing: 12) {
          GDACardTitle("Last night", color: GDA.sleep)
          if let d = lastNightDuration {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
              Text("\(d.hours)")
                .font(GDA.num(52))
                .foregroundStyle(GDA.text)
              Text("h ")
                .font(GDA.num(26))
                .foregroundStyle(GDA.text2)
              Text("\(d.minutes)")
                .font(GDA.num(52))
                .foregroundStyle(GDA.text)
              Text("m")
                .font(GDA.num(26))
                .foregroundStyle(GDA.text2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          } else {
            Text("—")
              .font(GDA.num(52))
              .foregroundStyle(GDA.text3)
          }
          HStack(spacing: 8) {
            GDAPill(text: "in bed ~23:10 – 06:40", style: .mut)
            GDAPill(text: "near your average", style: .ok)
          }
          GDAOurs("Our own detection from movement + heart rate. We don't show sleep stages — the band doesn't give us enough to do them honestly.")
        }
        .gdaCard()

        // This week — sleep bars (taller variant).
        VStack(alignment: .leading, spacing: 12) {
          GDACardTitle("This week", color: GDA.sleep)
          SleepBarsChart(nights: store.sleepNights, height: 120)
        }
        .gdaCard()

        // Nights — full list, newest first.
        VStack(alignment: .leading, spacing: 12) {
          GDACardTitle("Nights")
          VStack(spacing: 0) {
            ForEach(Array(store.sleepNights.reversed())) { night in
              HStack {
                Text(night.date)
                  .font(.system(size: 14))
                  .foregroundStyle(GDA.text2)
                Spacer(minLength: 8)
                Text(sleepHMShort(night.minutes))
                  .font(GDA.num(17))
                  .foregroundStyle(GDA.text)
              }
              .padding(.vertical, 9)
              if night.id != store.sleepNights.first?.id {
                Rectangle().fill(GDA.line).frame(height: 1)
              }
            }
          }
        }
        .gdaCard()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gdaScreenBackground()
    .navigationTitle("Morning")
    .navigationBarTitleDisplayMode(.inline)
    .task { store.refreshSleepNights() }
  }

  /// "Xh Ym" for a minute count.
  private func sleepHMShort(_ minutes: Int) -> String {
    "\(minutes / 60)h \(minutes % 60)m"
  }
}

// MARK: - HRV detail (DHrv)

/// Pushed "HRV" detail: separates the trustworthy overnight rMSSD from the
/// noisy live one, with a lock note that this is our own number, never WHOOP's.
struct GDAHRVDetailView: View {
  @EnvironmentObject var model: GooseAppModel
  @ObservedObject var store: HealthDataStore

  private var hrvBand: VitalBand {
    store.vitalBands["hrv"] ?? VitalBand(lo: 60, hi: 85, mean: 72)
  }

  var body: some View {
    let overnight = store.latestBandVitalDay()?.hrvRMSSDms
    let overnightStatus = GDA.bandStatus(overnight, store.vitalBands["hrv"])
    let live = model.ble.liveHRVRMSSD
    let liveStatus = GDA.bandStatus(live, store.vitalBands["hrv"])

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GDADetailHeader(title: "HRV", sub: "Two different numbers — don't mix them")

        // Card 1 — overnight rMSSD (the one to watch).
        VStack(alignment: .leading, spacing: 12) {
          GDACardTitle("Overnight HRV · rMSSD", color: GDA.hrv)
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
              Text(overnight.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(GDA.num(48))
                .foregroundStyle(overnight == nil ? GDA.text3 : GDA.text)
              Text("ms")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GDA.text2)
            }
            GDAPill(text: overnightStatus.text, style: overnightStatus.style)
          }
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          GDAOurs("One number per night, from thousands of R–R intervals while you sleep. This is the one to watch.")
          BandTrendChart(
            series: store.vitalSeries["hrv"] ?? [],
            band: hrvBand,
            color: GDA.hrv,
            height: 110,
            fractionDigits: 1
          )
          HStack {
            Text("Your usual: \(usualText(hrvBand.lo))–\(usualText(hrvBand.hi)) ms")
            Spacer(minLength: 8)
            Text("mean \(usualText(hrvBand.mean)) ms")
          }
          .font(.system(size: 12))
          .foregroundStyle(GDA.text3)
        }
        .gdaCard()

        // Card 2 — live HRV (dashed border; noisy, do not compare).
        VStack(alignment: .leading, spacing: 12) {
          GDACardTitle("Live HRV", color: GDA.hrv) {
            GDAPill(text: "live", style: .live, withDot: true)
          }
          HStack(alignment: .bottom) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
              Text(live.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                .font(GDA.num(30))
                .foregroundStyle(GDA.text2)
              Text("ms")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(GDA.text2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            LiveSparkline(color: GDA.hrv)
          }
          GDAPill(text: liveStatus.text, style: liveStatus.style)
          Text("Computed from the last few minutes of R–R intervals. It swings with every breath and posture change — interesting to watch, wrong to compare against overnight values.")
            .font(.system(size: 13))
            .foregroundStyle(GDA.text2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GDA.surface, in: RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: GDA.cardRadius, style: .continuous)
            .strokeBorder(GDA.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )

        // Card 3 — lock note: our own number, never WHOOP's.
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lock.fill")
            .font(.system(size: 16))
            .foregroundStyle(GDA.text3)
          Text("rMSSD is our own calculation, on your hardware. It is not WHOOP's recovery score, and we don't make one.")
            .font(.system(size: 13))
            .foregroundStyle(GDA.text2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gdaCard()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gdaScreenBackground()
    .navigationTitle("Back")
    .navigationBarTitleDisplayMode(.inline)
    .task { store.refreshBandVitalsDaily() }
  }

  /// One-decimal "usual range" number (band edges), trimming a trailing ".0".
  private func usualText(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0...1)))
  }

  /// "Xh Ym" formatter (kept per spec; HRV view shows it nowhere visible but
  /// the duration helper is part of the detail-screen contract).
  private func hmText(_ minutes: Int) -> String {
    "\(minutes / 60)h \(minutes % 60)m"
  }
}
