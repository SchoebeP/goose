import Foundation
import SwiftUI

// MARK: - Snapshot

/// A point-in-time view of a running band history sync, derived from the unix
/// timestamps embedded in the band's buffered history records (type-47, u32 LE
/// at payload offset 7). Every number here is our own estimate of *transfer*
/// progress — how much of the band's buffered time window has been drained —
/// not a WHOOP metric and not a health signal.
struct GooseHistorySyncProgressSnapshot: Equatable {
  let startedAt: Date
  let updatedAt: Date
  let packetCount: Int
  let pageCount: Int
  let oldestRecordDate: Date?
  let newestRecordDate: Date?
  /// Fraction (0...1) of the band's buffered time window already drained:
  /// (newestReached − oldestSeen) / (now − oldestSeen). nil until record
  /// timestamps have been decoded this sync.
  let fractionComplete: Double?
  /// Seconds of historical time covered per wall-clock second, over the
  /// rolling rate window. > 1 means the sync is catching up to "now".
  let coverageRatePerWallSecond: Double?
  /// Estimated wall-clock seconds until the sync catches up to "now".
  /// nil while there is not yet enough data to estimate.
  let etaSeconds: TimeInterval?
  /// Average packets per wall-clock second since the sync started.
  let packetsPerSecond: Double?
  /// Average pages (HistoryEnd boundaries) per wall-clock second since the sync started.
  let pagesPerSecond: Double?

  var percentText: String? {
    fractionComplete.map { "\(Int(($0 * 100).rounded()))%" }
  }

  var etaText: String {
    guard let etaSeconds else {
      return "estimating…"
    }
    return "~\(Self.durationText(etaSeconds)) left"
  }

  var positionText: String? {
    newestRecordDate.map { $0.formatted(date: .abbreviated, time: .shortened) }
  }

  /// One-line summary for the floating toast, e.g.
  /// "43% · ~2h 10m left · at Jun 4, 18:32".
  var summaryLine: String {
    var parts: [String] = []
    if let percentText {
      parts.append(percentText)
    }
    parts.append(etaText)
    if let positionText {
      parts.append("at \(positionText)")
    }
    return parts.joined(separator: " · ")
  }

  static func durationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
      return "\(minutes)m"
    }
    return "<1m"
  }
}

// MARK: - Estimator (pure logic; no device or BLE dependency)

/// Tracks honest progress of a band history sync. "Honest" means: percent is
/// the share of the band's buffered TIME window (oldest record seen → now)
/// already covered, and the ETA comes from the measured rate at which the
/// newest-reached record timestamp advances per wall-clock second.
struct HistorySyncProgressEstimator {
  /// Rolling window the coverage rate is measured over.
  static let rateWindow: TimeInterval = 90
  /// Minimum observed wall-clock span before an ETA is published.
  static let minimumRateSpan: TimeInterval = 60
  /// Plausibility floor for record epochs (2020-01-01T00:00:00Z) — rejects
  /// zeroed or garbage timestamp bytes so they cannot poison min/max.
  static let minimumPlausibleEpoch: TimeInterval = 1_577_836_800
  /// Records may not be stamped later than now + this slack.
  static let epochFutureSlack: TimeInterval = 86_400
  /// Floor for the ETA denominator (rate − 1) so a near-realtime rate cannot
  /// blow the estimate up to absurd values.
  static let etaRateFloor: Double = 0.05

  private(set) var startedAt: Date?
  private(set) var pageCount = 0
  private(set) var oldestRecordEpoch: TimeInterval?
  private(set) var newestRecordEpoch: TimeInterval?
  private var rateSamples: [(wallClock: Date, newestEpoch: TimeInterval)] = []

  mutating func begin(at date: Date) {
    reset()
    startedAt = date
  }

  mutating func reset() {
    startedAt = nil
    pageCount = 0
    oldestRecordEpoch = nil
    newestRecordEpoch = nil
    rateSamples.removeAll(keepingCapacity: true)
  }

  mutating func notePage() {
    pageCount += 1
  }

  /// Feed the unix epoch (seconds) of a decoded history record. The oldest
  /// epoch is a sticky minimum (= oldest buffered record seen this sync); the
  /// newest is a running maximum (= how far the drain has reached).
  mutating func noteRecordEpoch(_ epoch: TimeInterval, at now: Date) {
    guard epoch >= Self.minimumPlausibleEpoch,
          epoch <= now.timeIntervalSince1970 + Self.epochFutureSlack else {
      return
    }
    oldestRecordEpoch = min(oldestRecordEpoch ?? epoch, epoch)
    newestRecordEpoch = max(newestRecordEpoch ?? epoch, epoch)
  }

  /// Compute the current snapshot and record a rate sample. Call this at a
  /// throttled cadence (~1 Hz) while the sync runs.
  mutating func makeSnapshot(now: Date, packetCount: Int) -> GooseHistorySyncProgressSnapshot? {
    guard let startedAt else {
      return nil
    }

    if let newest = newestRecordEpoch {
      rateSamples.append((wallClock: now, newestEpoch: newest))
      let cutoff = now.addingTimeInterval(-Self.rateWindow)
      while rateSamples.count > 2, let first = rateSamples.first, first.wallClock < cutoff {
        rateSamples.removeFirst()
      }
    }

    let nowEpoch = now.timeIntervalSince1970

    var fraction: Double?
    if let oldest = oldestRecordEpoch, let newest = newestRecordEpoch {
      let bufferedWindow = nowEpoch - oldest
      if bufferedWindow > 0 {
        fraction = min(1, max(0, (newest - oldest) / bufferedWindow))
      }
    }

    var coverageRate: Double?
    var observedSpan: TimeInterval = 0
    if let first = rateSamples.first, let last = rateSamples.last {
      observedSpan = last.wallClock.timeIntervalSince(first.wallClock)
      if observedSpan >= 1 {
        coverageRate = (last.newestEpoch - first.newestEpoch) / observedSpan
      }
    }

    // While syncing, "now" advances too: the gap (now − newestReached) shrinks
    // at (rate − 1) historical-seconds per wall-second, so the wall-clock time
    // remaining is gap / (rate − 1) — only meaningful when rate > 1.
    var eta: TimeInterval?
    if let rate = coverageRate,
       let newest = newestRecordEpoch,
       observedSpan >= Self.minimumRateSpan,
       rate > 1 {
      let gap = max(0, nowEpoch - newest)
      eta = gap / max(rate - 1, Self.etaRateFloor)
    }

    let elapsed = now.timeIntervalSince(startedAt)
    let packetsPerSecond: Double? = elapsed >= 1 ? Double(packetCount) / elapsed : nil
    let pagesPerSecond: Double? = elapsed >= 1 ? Double(pageCount) / elapsed : nil

    return GooseHistorySyncProgressSnapshot(
      startedAt: startedAt,
      updatedAt: now,
      packetCount: packetCount,
      pageCount: pageCount,
      oldestRecordDate: oldestRecordEpoch.map { Date(timeIntervalSince1970: $0) },
      newestRecordDate: newestRecordEpoch.map { Date(timeIntervalSince1970: $0) },
      fractionComplete: fraction,
      coverageRatePerWallSecond: coverageRate,
      etaSeconds: eta,
      packetsPerSecond: packetsPerSecond,
      pagesPerSecond: pagesPerSecond
    )
  }
}

// MARK: - Toast (replaces the indeterminate spinner while a sync runs)

struct HistorySyncProgressToastView: View {
  let snapshot: GooseHistorySyncProgressSnapshot
  @Environment(\.colorScheme) private var colorScheme

  private static let accent = GooseTheme.Accent.sleep

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        if snapshot.fractionComplete == nil {
          ProgressView()
            .controlSize(.small)
            .tint(Self.accent)
        } else {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Self.accent)
        }
        Text("Syncing band history")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "chevron.up")
          .font(.system(size: 11, weight: .black))
          .foregroundStyle(Self.accent)
      }

      if let fraction = snapshot.fractionComplete {
        ProgressView(value: fraction)
          .progressViewStyle(.linear)
          .tint(Self.accent)
        Text(snapshot.summaryLine)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .monospacedDigit()
      } else {
        Text("starting…")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: GooseTheme.cardCornerRadius, style: .continuous)
        .fill(toastFill)
    }
    .overlay {
      RoundedRectangle(cornerRadius: GooseTheme.cardCornerRadius, style: .continuous)
        .strokeBorder(Self.accent.opacity(0.65), lineWidth: 1.5)
    }
    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 7)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var toastFill: Color {
    colorScheme == .dark
      ? Color(red: 0.07, green: 0.16, blue: 0.25)
      : Color(red: 0.84, green: 0.91, blue: 1.0)
  }

  private var accessibilityText: String {
    snapshot.fractionComplete == nil
      ? "Syncing band history, starting"
      : "Syncing band history, \(snapshot.summaryLine)"
  }
}

// MARK: - Detail sheet (tap the toast)

struct HistorySyncProgressDetailSheet: View {
  @ObservedObject var ble: GooseBLEClient
  @Environment(\.dismiss) private var dismiss

  private static let accent = GooseTheme.Accent.sleep

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let snapshot = ble.historySyncProgressSnapshot {
            overviewCard(snapshot)
            transferCard(snapshot)
            recordWindowCard(snapshot)
          } else {
            Text("No band history sync is running right now.")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .gooseCard()
          }
          Text("Progress is estimated from the timestamps inside the band's buffered records: percent is the share of the buffered time window already transferred, and the time remaining comes from the measured catch-up rate. These are our own transfer estimates, not WHOOP figures.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
      }
      .gooseScreenBackground()
      .navigationTitle("Band History Sync")
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

  private func overviewCard(_ snapshot: GooseHistorySyncProgressSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      GooseMetricLabel(
        systemImage: "arrow.triangle.2.circlepath",
        title: "Band history",
        accent: Self.accent
      )
      if let fraction = snapshot.fractionComplete {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(snapshot.percentText ?? "—")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .monospacedDigit()
          Text(snapshot.etaText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        ProgressView(value: fraction)
          .progressViewStyle(.linear)
          .tint(Self.accent)
        if let positionText = snapshot.positionText {
          Text("Currently at \(positionText)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      } else {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
            .tint(Self.accent)
          Text("Starting — waiting for the first records…")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
    }
    .gooseCard()
  }

  private func transferCard(_ snapshot: GooseHistorySyncProgressSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Transfer")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      detailRow("Pages", "\(snapshot.pageCount)")
      detailRow("Packets", "\(snapshot.packetCount)")
      detailRow("Pages / sec", snapshot.pagesPerSecond.map { String(format: "%.2f", $0) } ?? "—")
      detailRow("Packets / sec", snapshot.packetsPerSecond.map { String(format: "%.1f", $0) } ?? "—")
      detailRow(
        "Catch-up rate",
        snapshot.coverageRatePerWallSecond.map { String(format: "%.1f× realtime", $0) } ?? "—"
      )
      detailRow("Started", snapshot.startedAt.formatted(date: .abbreviated, time: .shortened))
      detailRow(
        "Elapsed",
        GooseHistorySyncProgressSnapshot.durationText(
          snapshot.updatedAt.timeIntervalSince(snapshot.startedAt)
        )
      )
    }
    .gooseCard()
  }

  private func recordWindowCard(_ snapshot: GooseHistorySyncProgressSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Buffered records")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      detailRow(
        "Oldest record",
        snapshot.oldestRecordDate?.formatted(date: .abbreviated, time: .shortened) ?? "—"
      )
      detailRow(
        "Newest reached",
        snapshot.newestRecordDate?.formatted(date: .abbreviated, time: .shortened) ?? "—"
      )
    }
    .gooseCard()
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .fontWeight(.semibold)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
  }
}
