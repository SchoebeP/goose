import SwiftUI

/// SyncSection — UI-only section for the historical (type-47) backfill.
///
/// The BLE engine already exists and is field-proven (beginHistoricalSync in
/// GooseBLEClient+HistoricalCommands.swift); this file only renders its
/// @Published state (isHistoricalSyncing / historicalSyncStatus /
/// historicalPacketCount / lastHistoricalSyncCompletedAt) and triggers it.
/// French labels, honest "--" when no data yet, dark design.

// MARK: - Relative FR formatting ("il y a 5 min / 2 h / 3 j")

enum SimpleRelativeTimeFormatter {

  /// "il y a X" with coarse units — min under an hour, h under a day, j beyond.
  /// Returns "--" when the date is nil (never synced).
  static func text(since date: Date?, now: Date = Date()) -> String {
    guard let date else { return "--" }
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "il y a moins d'une min" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "il y a \(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return "il y a \(hours) h" }
    return "il y a \(hours / 24) j"
  }
}

// MARK: - "Sync historique" section (used inside SimpleDeviceSheet)

struct SyncSection: View {
  @EnvironmentObject private var model: GooseAppModel

  /// Auto-sync only fires when the last sync is older than 12 h.
  static let autoSyncThreshold: TimeInterval = 12 * 3600

  /// True when the last completed sync is older than the 12 h threshold
  /// (or never happened). Drives the orange hint on the home screen too.
  static func isStale(_ completedAt: Date?, now: Date = Date()) -> Bool {
    guard let completedAt else { return true }
    return now.timeIntervalSince(completedAt) > autoSyncThreshold
  }

  var body: some View {
    Section("Sync historique") {
      // Last sync + packet count, live. On a GEN4 band (WHOOP 4.0) the fd4b
      // engine is unreachable — show the 4.0 backfill's own state instead,
      // so the section reflects reality instead of a permanent "jamais".
      let gen4 = model.ble.isGen4Band
      HStack {
        Text("Dernière sync")
        Spacer()
        Text(SimpleRelativeTimeFormatter.text(
          since: gen4 ? model.ble.lastGen4BackfillCompletedAt
                      : model.ble.lastHistoricalSyncCompletedAt))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityIdentifier("sync.last")

      if gen4 {
        // GEN4 live/idle state from the 4.0 backfill engine. The band never
        // announces its buffered total, so there is no real % — the bar shows
        // elapsed time against the bounded pull window, plus bytes + rate.
        if model.ble.isGen4Backfilling {
          Gen4BackfillProgressView()
            .accessibilityIdentifier("sync.live")
        } else if model.ble.gen4BackfillPacketCount > 0 {
          HStack {
            Text("Paquets")
            Spacer()
            Text("\(model.ble.gen4BackfillPacketCount)")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .accessibilityIdentifier("sync.packets")
        }
        SyncJournalView()
      } else if model.ble.isHistoricalSyncing {
        // Live state while syncing: spinner + engine status + packet count.
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
              .font(.footnote)
              .foregroundStyle(.secondary)
            if model.ble.historicalPacketCount > 0 {
              Text("\(model.ble.historicalPacketCount) paquets reçus")
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
          }
        }
        .accessibilityIdentifier("sync.live")
      } else if model.ble.historicalPacketCount > 0 {
        HStack {
          Text("Paquets")
          Spacer()
          Text("\(model.ble.historicalPacketCount)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityIdentifier("sync.packets")
      }

      Button {
        // UI-only trigger. GEN4 band → the 4.0 backfill engine (the V5
        // beginHistoricalSync would refuse a 61080002 characteristic).
        // V5 band → the fd4b engine. Both guard themselves against re-entry.
        if gen4 {
          model.ble.beginGen4HistoricalBackfill()
        } else {
          model.ble.beginHistoricalSync(trigger: "simple_ui_manual", automatic: false)
        }
      } label: {
        Text("Synchroniser maintenant")
      }
      .disabled(gen4 ? model.ble.isGen4Backfilling : model.ble.isHistoricalSyncing)
      .accessibilityIdentifier("sync.now")

      if gen4 {
        Button {
          // LOT 1 BIS (Zulusierra MITM): replay the official app's full
          // handshake — HELLO, clock, feature-flag read loop, config —
          // THEN ask history with 0x16 only. Journal tells the story live.
          model.ble.runOfficialHandshake()
        } label: {
          Text("Tester le handshake officiel")
        }
        .disabled(model.ble.isGen4Backfilling)
        .accessibilityIdentifier("sync.official-handshake")
      }
    }
  }

  private var statusLine: String {
    let status = model.ble.historicalSyncStatus
    switch status {
    case "syncing": return "Synchronisation en cours…"
    case "waiting": return "En attente de la réponse du bracelet…"
    case "failed": return "Échec de la dernière tentative"
    default: return status
    }
  }
}

// MARK: - GEN4 backfill progress (time-based bar + bytes + rate + ETA)

/// The band never discloses how much history it holds, so a true % is
/// impossible. The pull is bounded by a fixed window (90 s), so progress =
/// elapsed/window; ETA = time left in the window. Bytes and rate come from the
/// type-47 frames actually received — that's the honest throughput signal.
/// The human-readable protocol journal PERSISTS after the run (kept on the
/// BLE client, not reset by finishGen4BackfillIfRunning) so the user can read
/// what happened — including the total data received per type.
struct Gen4BackfillProgressView: View {
  @EnvironmentObject private var model: GooseAppModel
  private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Backfill 4.0 en cours…")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer()
        Text(etaText)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      ProgressView(value: progressFraction)
        .progressViewStyle(.linear)
      HStack {
        Text("\(model.ble.gen4BackfillPacketCount) paquets")
        Spacer()
        Text(bytesLine)
      }
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.tertiary)
    }
    .onReceive(tick) { _ in now = Date() }
  }

  @State private var now = Date()

  private var elapsed: TimeInterval {
    guard let start = model.ble.gen4BackfillStartedAt else { return 0 }
    return now.timeIntervalSince(start)
  }

  private var progressFraction: Double {
    min(1, max(0.02, elapsed / GooseBLEClient.gen4BackfillWindow))
  }

  private var etaText: String {
    let remaining = max(0, GooseBLEClient.gen4BackfillWindow - elapsed)
    return remaining < 1 ? "presque fini" : "≈ \(Int(remaining.rounded())) s restantes"
  }

  /// "12.4 Ko reçus · 8.1 Ko/s" — total wire bytes plus average rate over the
  /// run (average is stabler than an instantaneous delta for BLE bursts).
  private var bytesLine: String {
    let bytes = model.ble.gen4BackfillBytes
    let seconds = max(0.5, elapsed)
    let rate = Double(bytes) / seconds
    let total = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    let perSec = ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .binary)
    return "\(total) reçus · \(perSec)/s"
  }
}

// MARK: - Persistent human-readable journal (Journal de synchronisation)

/// A persistent log of what the band said during the last sync — survives the
/// end of the backfill (lives on GooseBLEClient, reset only on the NEXT sync).
/// Every line is plain French, no hex, no jargon.
struct SyncJournalView: View {
  @EnvironmentObject private var model: GooseAppModel

  var body: some View {
    Section("Journal de synchronisation") {
      if model.ble.gen4SyncJournal.isEmpty {
        Text("Aucune synchronisation enregistrée")
          .font(.footnote)
          .foregroundStyle(.tertiary)
      } else {
        ForEach(Array(model.ble.gen4SyncJournal.suffix(14).enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
  }
}
