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
      // Last sync + packet count, live.
      HStack {
        Text("Dernière sync")
        Spacer()
        Text(lastSyncText)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityIdentifier("sync.last")

      if model.ble.isHistoricalSyncing {
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
        // UI-only trigger. Exact engine signature (verified in
        // GooseBLEClient+HistoricalCommands.swift): beginHistoricalSync(
        //   trigger: String, automatic: Bool, firstCommandOverride: ... = nil,
        //   rangeOnly: Bool = false, acknowledgeHistoricalDataResult: Bool = true)
        // The engine guards itself against re-entry (skips when already
        // syncing) and against a non-ready link — the UI only disables the
        // button for comfort.
        model.ble.beginHistoricalSync(trigger: "simple_ui_manual", automatic: false)
      } label: {
        Text("Synchroniser maintenant")
      }
      .disabled(model.ble.isHistoricalSyncing)
      .accessibilityIdentifier("sync.now")
    }
  }

  private var lastSyncText: String {
    SimpleRelativeTimeFormatter.text(since: model.ble.lastHistoricalSyncCompletedAt)
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
