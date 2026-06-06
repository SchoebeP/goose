import SwiftUI

struct ConnectionView: View {
  @EnvironmentObject private var model: GooseAppModel

  var body: some View {
    ConnectionContentView(ble: model.ble)
      .environmentObject(model)
  }
}

private struct ConnectionContentView: View {
  @EnvironmentObject private var model: GooseAppModel
  @EnvironmentObject private var messageStore: GooseMessageStore
  @ObservedObject var ble: GooseBLEClient
  @State private var exportedLogURL: URL?
  @State private var showingExportAlert = false

  var body: some View {
    List {
      Section("Status") {
        LabeledContent("Bluetooth", value: ble.bluetoothState)
        LabeledContent("Connection", value: ble.connectionState)
        LabeledContent("Reconnect", value: ble.reconnectState)
        LabeledContent("Historical", value: historicalSyncValue)
        LabeledContent("Remembered", value: ble.rememberedDeviceDescription)
        LabeledContent("Live HR", value: liveHeartRateValue)
        LabeledContent("Rust", value: model.rustStatus)
        LabeledContent("Hello", value: model.helloSummary)
      }

      Section("Actions") {
        Button("Request Bluetooth") {
          ble.requestBluetooth()
        }
        Button(ble.isScanning ? "Stop Scan" : "Scan") {
          ble.isScanning ? ble.stopScan() : ble.startScan()
        }
        .disabled(!ble.canScan)

        Button("Connect Selected") {
          ble.connectSelected()
        }
        .disabled(!ble.canConnect)

        Button("Reconnect Remembered") {
          ble.reconnectRemembered()
        }
        .disabled(!ble.canReconnectRemembered)

        Button("Send Client Hello") {
          ble.sendClientHello()
        }
        .disabled(!ble.canSendHello)

        Button(ble.isHistoricalSyncing ? "Syncing Historical Packets" : "Request Historical Packets") {
          ble.syncHistoricalPackets()
        }
        .disabled(!ble.canSyncHistorical)

        Button("Forget Remembered Device", role: .destructive) {
          ble.forgetRememberedDevice()
        }
        .disabled(!ble.hasRememberedDevice)
      }

      Section("Discovered") {
        if ble.discoveredDevices.isEmpty {
          Text("No devices yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(ble.discoveredDevices) { device in
            Button {
              ble.select(device)
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text(device.name)
                  Text(device.id.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(device.rssi)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("Client Hello") {
        Text(GooseHello.clientHelloFrameHex)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
      }

      Section("Event Log") {
        Button("Export Event Log") {
          exportEventLog()
        }
        if let exportedLogURL {
          ShareLink("Share exported log", item: exportedLogURL)
          Text(exportedLogURL.lastPathComponent)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        ForEach(messageStore.messages) { message in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(message.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(message.level.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.level == .error ? .red : .secondary)
              Text(message.source)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(message.title)
              .font(.subheadline.weight(.semibold))
            Text(message.body)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
    }
    .gooseListBackground()
    .navigationTitle("Connect")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          exportEventLog()
          showingExportAlert = true
        } label: {
          Label("Export Log", systemImage: "square.and.arrow.up")
        }
      }
    }
    .alert("Event log exported", isPresented: $showingExportAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Saved \(messageStore.messages.count) lines. Tell Claude “exported” and it will pull the file.")
    }
  }

  private func exportEventLog() {
    let lines = messageStore.messages.map { message in
      "\(message.timestamp.ISO8601Format()) [\(message.level.rawValue)] "
        + "\(message.source) \(message.title) \(message.body)"
    }
    let text = lines.joined(separator: "\n")
    let url = URL.documentsDirectory.appendingPathComponent("goose-eventlog.txt")
    do {
      try text.write(to: url, atomically: true, encoding: .utf8)
      exportedLogURL = url
    } catch {
      exportedLogURL = nil
    }
  }

  private var liveHeartRateValue: String {
    guard let bpm = ble.liveHeartRateBPM else {
      return ble.liveHeartRateSource
    }
    if let updatedAt = ble.liveHeartRateUpdatedAt {
      return "\(bpm) bpm via \(ble.liveHeartRateSource) @ \(updatedAt.formatted(date: .omitted, time: .standard))"
    }
    return "\(bpm) bpm via \(ble.liveHeartRateSource)"
  }

  private var historicalSyncValue: String {
    let packetCount = ble.historicalPacketCount
    let packets = "\(packetCount) \(packetCount == 1 ? "packet" : "packets")"
    if ble.isHistoricalSyncing {
      return "syncing | \(packets)"
    }
    if let completedAt = ble.lastHistoricalSyncCompletedAt {
      return "\(ble.historicalSyncStatus) | \(packets) @ \(completedAt.formatted(date: .omitted, time: .standard))"
    }
    return "\(ble.historicalSyncStatus) | \(packets)"
  }
}
