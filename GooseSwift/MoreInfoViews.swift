import Foundation
import SwiftUI

struct MorePrivacyView: View {
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section("Local Data") {
        MoreInfoRow(
          title: "Database",
          value: "Stored in this app's private container on your device",
          systemImage: "externaldrive",
          status: store.databaseExists ? .ready : .unavailable
        )
      }

      Section {
        // Real capability, stated plainly instead of a permanently disabled
        // "Data Deletion" button: there is no in-app deletion yet, and the
        // honest answer today is "uninstall the app" — never fake a control
        // that does nothing.
        MoreInfoRow(
          title: "Delete your data",
          value: "In-app deletion isn't built yet. Uninstalling removes the on-device database only — data already synced to latenightgames.fr remains there until deleted server-side.",
          systemImage: "trash",
          status: .pending
        )
      } header: {
        Text("Data deletion")
      } footer: {
        Text("No third-party cloud, telemetry, or analytics SDKs. By default, though, this build syncs your HR/R-R samples, raw BLE frames, and diagnostic logs to latenightgames.fr — the developer's own server, not necessarily yours — whether or not a sync token is configured.")
      }

#if DEBUG
      if DeveloperSettings.shared.isEnabled {
        Section("Local Data (dev)") {
          MoreInfoRow(title: "Database Path", value: store.databasePath, systemImage: "externaldrive", status: store.databaseExists ? .ready : .unavailable)
        }
        Section("Export hygiene (dev)") {
          MoreInfoRow(title: "Raw Bundle", value: store.rawBundlePath, systemImage: "folder", status: store.rawBundlePath == "No bundle" ? .pending : .ready)
          MoreInfoRow(title: "Privacy Lint", value: store.privacyLintStatus, systemImage: "hand.raised", status: .pending)
          MoreInfoRow(title: "Sanitized Privacy", value: store.sanitizedPrivacyStatus, systemImage: "sparkles.rectangle.stack", status: .pending)
          Button {
            store.validateExportArtifacts()
          } label: {
            Label("Validate Export And Lint", systemImage: "checkmark.seal")
          }
          .disabled(store.rawBundlePath == "No bundle")
        }
      }
#endif
    }
    .gooseListBackground()
    .navigationTitle("Privacy")
  }
}

struct MoreSupportView: View {
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section {
        MoreInfoRow(title: "Local File", value: store.localExportStatus, systemImage: "doc", status: store.localExportURL == nil ? .pending : .ready)
      } footer: {
        Text("Save a copy of your local data to share with yourself — e.g. for a backup, or to attach when asking for help.")
      }

      Section("Actions") {
        Button {
          store.saveLocalDataBundle()
        } label: {
          Label("Save Local Data File", systemImage: "externaldrive.badge.plus")
        }
        .disabled(store.localExportInProgress)

        if store.localExportInProgress {
          ProgressView("Saving local data file")
        }

        if let localExportURL = store.localExportURL {
          ShareLink(item: localExportURL) {
            Label("AirDrop Local Data File", systemImage: "square.and.arrow.up")
          }
        }

        if let localExportManifestURL = store.localExportManifestURL {
          ShareLink(item: localExportManifestURL) {
            Label("AirDrop Export Manifest", systemImage: "list.bullet.rectangle")
          }
        }
      }

#if DEBUG
      if DeveloperSettings.shared.isEnabled {
        Section("Diagnostic bundles (dev)") {
          MoreInfoRow(title: "Support Bundle", value: store.supportBundlePath, systemImage: "folder.badge.gearshape", status: .pending)
          MoreInfoRow(title: "Log Export", value: store.logExportStatus, systemImage: "doc.text", status: .pending)
          MoreInfoRow(title: "Latest Raw Bundle", value: store.rawBundlePath, systemImage: "shippingbox", status: store.rawBundlePath == "No bundle" ? .pending : .ready)
          MoreInfoRow(title: "Latest Zip", value: store.rawZipPath, systemImage: "doc.zipper", status: store.rawZipPath == "No zip" ? .pending : .ready)
          MoreActionRow(title: "Create Support Bundle", detail: "Pending bundle composer bridge", systemImage: "lifepreserver", status: .unavailable, disabled: true) {}
        }
      }
#endif
    }
    .gooseListBackground()
    .navigationTitle("Support")
  }
}

struct MoreAboutView: View {
  @EnvironmentObject private var model: GooseAppModel
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section("Version") {
        MoreInfoRow(title: "App Version", value: appVersion, systemImage: "app", status: .ready)
      }

#if DEBUG
      // Internal build/runtime plumbing (embedded Rust core version, DB
      // schema, raw BLE handshake) — meaningless to a stranger who installs
      // Clean; band/connection status for a prod user already lives on the
      // Device screen.
      if DeveloperSettings.shared.isEnabled {
        Section("Build (dev)") {
          MoreInfoRow(title: "Rust Core", value: store.coreVersionStatus, systemImage: "shippingbox", status: store.coreVersionStatus.hasPrefix("Rust core") ? .ready : .pending)
          MoreInfoRow(title: "Schema", value: store.schemaVersion, systemImage: "number", status: store.schemaVersion == "Unknown" ? .pending : .ready)
        }

        Section("Runtime (dev)") {
          MoreInfoRow(title: "Model", value: model.ble.activeDeviceName, systemImage: "sensor.tag.radiowaves.forward", status: model.ble.connectionState == "ready" ? .ready : .pending)
          MoreInfoRow(title: "Hello", value: model.helloSummary, systemImage: "hand.wave", status: model.helloSummary.hasPrefix("GET_HELLO") ? .ready : .pending)
        }
      }
#endif
    }
    .gooseListBackground()
    .navigationTitle("About")
    .onAppear {
      store.refreshBridgeStatus(model: model)
    }
  }

  private var appVersion: String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    return "\(short) (\(build))"
  }
}

struct MoreInfoRow: View {
  let title: String
  let value: String
  let systemImage: String
  let status: MoreStatusKind

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(status.tint)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(title)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          MoreStatusBadge(status: status)
        }
        Text(value.isEmpty ? "Unavailable" : value)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 3)
  }
}

struct MoreActionRow: View {
  let title: String
  let detail: String
  let systemImage: String
  let status: MoreStatusKind
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(status.tint)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Spacer(minLength: 8)
            MoreStatusBadge(status: status)
          }
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding(.vertical, 3)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }
}

// Only rendered by MoreDebugView's "Command Shortcuts" section — Dev only.
#if DEBUG
struct MoreCommandGroupRow: View {
  let group: MoreCommandGroup

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: group.status == .blocked ? "lock.shield" : "terminal")
        .foregroundStyle(group.status.tint)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(group.title)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          MoreStatusBadge(status: group.status)
        }
        Text(group.commands.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 3)
  }
}
#endif

extension Date {
  func moreISO8601String() -> String {
    ISO8601DateFormatter().string(from: self)
  }
}
