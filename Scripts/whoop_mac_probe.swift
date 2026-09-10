import CoreBluetooth
import Foundation

let logPath = "/tmp/whoop-probe-app.log"
func log(_ s: Any) {
  let line = String(describing: s) + "\n"
  FileHandle.standardError.write(line.data(using: .utf8)!)
  if let h = FileHandle(forWritingAtPath: logPath) {
    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
  }
}

// Mac-side WHOOP probe: scan → connect → dump GATT → GET_HELLO_HARVARD (0x23)
// handshake → TOGGLE_REALTIME_HR. Framing is byte-identical to the app's
// GooseBLEClient+Parsing.buildGen4CommandFrame. The band requires an encrypted
// (bonded) link for command writes: when the first write fails with
// "Encryption is insufficient", keep retrying — each retry re-asks macOS to
// pair (click PAIR in the system dialog).
// Run: swift scripts/whoop_mac_probe.swift   (or compile with swiftc -O)

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var central: CBCentralManager!
  var target: CBPeripheral?
  var commandChar: CBCharacteristic?
  var seq: UInt8 = 4
  let scanSeconds: TimeInterval = 25
  var pairAttempts = 0
  var helloSent = false
  var hrToggled = false
  var helloPayload: [UInt8] = {
    var ts = [UInt8]()
    var t = UInt64(Date().timeIntervalSince1970)
    for _ in 0..<8 { ts.append(UInt8(t & 0xff)); t >>= 8 }
    return ts + [0x00]
  }()

  func run() {
    try? "=== probe start \(Date()) ===\n".write(toFile: logPath, atomically: true, encoding: .utf8)
    central = CBCentralManager(delegate: self, queue: nil)
    log("probe: starting (Bluetooth will power on shortly)…")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { exit(0) }
    RunLoop.main.run()
  }

  // MARK: CRCs (identical to the app's)

  func crc8(_ bytes: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0
    for byte in bytes {
      crc ^= byte
      for _ in 0..<8 { crc = (crc & 0x80 != 0) ? (crc << 1) ^ 0x07 : crc << 1 }
    }
    return crc
  }

  func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc = UInt32(0xffffffff)
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc & 1 == 1) ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
    }
    return ~crc
  }

  func frame(seq: UInt8, command: UInt8, payload: [UInt8]) -> Data {
    var body = [UInt8(35), seq, command]   // packet type 0x23 (command)
    body += payload
    let crc = crc32(body)
    let len = UInt16(body.count + 4)
    var f: [UInt8] = [0xaa, UInt8(len & 0xff), UInt8((len >> 8) & 0xff), crc8([UInt8(len & 0xff), UInt8((len >> 8) & 0xff)])]
    f += body
    f += [UInt8(crc & 0xff), UInt8((crc >> 8) & 0xff), UInt8((crc >> 16) & 0xff), UInt8((crc >> 24) & 0xff)]
    return Data(f)
  }

  // MARK: Central delegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central.state == .poweredOn else {
      log("probe: bluetooth not on (raw=\(central.state.rawValue))"); return
    }
    log("probe: scanning \(Int(scanSeconds))s for WHOOP…")
    central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    DispatchQueue.main.asyncAfter(deadline: .now() + scanSeconds) {
      central.stopScan()
      if self.target == nil {
        log("probe: scan window over — no WHOOP seen. Charger-cycle the band and retry.")
      }
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                      advertisementData: [String: Any], rssi RSSI: NSNumber) {
    let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
    let interesting = name.uppercased().contains("WHOOP")
      || services.contains { $0.lowercased().hasPrefix("6108") || $0.lowercased().hasPrefix("fd4b") }
    guard interesting, target == nil else { return }
    log(String(format: "probe: FOUND %@ [%@] rssi=%d services=%@", name, peripheral.identifier.uuidString, RSSI.intValue, services))
    target = peripheral
    peripheral.delegate = self
    central.stopScan()
    central.connect(peripheral, options: nil)
    log("probe: connecting…")
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    log("probe: CONNECTED to \(peripheral.name ?? "?") — discovering services…")
    helloSent = false
    hrToggled = false
    peripheral.discoverServices(nil)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    log("probe: CONNECT FAILED: \(error?.localizedDescription ?? "no error") — retrying in 3s")
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      guard let self, let p = self.target else { return }
      self.central.connect(p, options: nil)
    }
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    log("probe: DISCONNECTED: \(error?.localizedDescription ?? "clean") — reconnecting in 2s (pairing often drops the link once)")
    // Pairing frequently kicks the link; reconnect re-attaches it encrypted.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, let p = self.target else { return }
      self.central.connect(p, options: nil)
    }
  }

  // MARK: Peripheral delegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    for s in peripheral.services ?? [] {
      log("probe: service \(s.uuid.uuidString)")
      peripheral.discoverCharacteristics(nil, for: s)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    for c in service.characteristics ?? [] {
      log("probe:   char \(c.uuid.uuidString) props=\(c.properties)")
      let u = c.uuid.uuidString.lowercased()
      if u.hasPrefix("61080002") || u.hasPrefix("fd4b0002") {
        commandChar = c
      }
      if c.properties.contains(.notify) || c.properties.contains(.indicate) {
        peripheral.setNotifyValue(true, for: c)
      }
    }
    if commandChar != nil, !helloSent {
      helloSent = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.sendHello()
      }
    }
  }

  func sendHello() {
    guard let p = target, let ch = commandChar else { return }
    let f = frame(seq: seq, command: 35, payload: helloPayload)
    log("probe: → GET_HELLO_HARVARD \(f.map { String(format: "%02x", $0) }.joined())")
    p.writeValue(f, for: ch, type: .withResponse)
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    log("probe: write \(error == nil ? "ok" : "ERROR \(error!.localizedDescription)") for \(characteristic.uuid.uuidString)")
    guard characteristic === commandChar else { return }
    if error == nil {
      if hrToggled { return }
      hrToggled = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        guard let ch = self.commandChar else { return }
        self.seq &+= 1
        let f = self.frame(seq: self.seq, command: 0x03, payload: [0x01])
        log("probe: → TOGGLE_REALTIME_HR(on) \(f.map { String(format: "%02x", $0) }.joined())")
        peripheral.writeValue(f, for: ch, type: .withResponse)
      }
    } else if (error!.localizedDescription as NSString).contains("Encryption") || (error!.localizedDescription as NSString).contains("Authentication") {
      pairAttempts += 1
      if pairAttempts <= 12 {
        log("probe: encrypted write refused (attempt \(pairAttempts)) — CLICK PAIR ON THE SYSTEM DIALOG if one shows; retrying in 5s…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
          guard let self, let ch = self.commandChar, let p = self.target else { return }
          let f = self.frame(seq: self.seq, command: 35, payload: self.helloPayload)
          p.writeValue(f, for: ch, type: .withResponse)
        }
      } else {
        log("probe: pairing never completed — giving up on encrypted writes.")
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    let d = characteristic.value ?? Data()
    let hex = d.map { String(format: "%02x", $0) }.joined()
    let u = characteristic.uuid.uuidString.lowercased()
    var tag = u.hasSuffix("0003") ? "RESP" : (u.hasSuffix("0004") ? "EVENT" : (u.hasSuffix("0005") ? "DATA" : String(u.suffix(4))))
    if d.count > 7, d[d.startIndex] == 0xaa {
      let bytes = [UInt8](d)
      let t = bytes[4], sub = bytes[6]
      tag = "\(tag) type=0x\(String(t, radix: 16)) sub=0x\(String(sub, radix: 16))"
      // commandResponse (type 0x24=36) for cmd 35 = HELLO answer
      if t == 36, sub == 35 {
        let ascii = String(bytes: bytes[10...].prefix(60), encoding: .ascii) ?? ""
        log("probe: ★ HELLO_HARVARD ANSWER (\(d.count) bytes) — serial/fw: \(ascii.replacingOccurrences(of: "\0", with: ""))")
      }
    }
    log("probe: ← \(tag) \(hex.prefix(120))\(hex.count > 120 ? "…" : "")")
  }
}

Probe().run()
