import CoreBluetooth
import Foundation

func log(_ s: Any) {
  FileHandle.standardError.write((String(describing: s) + "\n").data(using: .utf8)!)
}

// Mac-side WHOOP probe: scan → connect → dump GATT → run the Zulu Sierra
// GET_HELLO_HARVARD (0x23) handshake. Uses the exact framing from the app
// (GooseBLEClient+Parsing.buildGen4CommandFrame) so results transfer 1:1.
// Run: swift scripts/whoop_mac_probe.swift

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var central: CBCentralManager!
  var target: CBPeripheral?
  var commandChar: CBCharacteristic?
  var seq: UInt8 = 4
  let scanSeconds: TimeInterval = 20

  func run() {
    central = CBCentralManager(delegate: self, queue: nil)
  log("probe: starting (Bluetooth will power on shortly)…")
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
  log("probe: bluetooth not on (\(central.state.rawValue))"); return
    }
  log("probe: scanning \(Int(scanSeconds))s for WHOOP…")
    central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    DispatchQueue.main.asyncAfter(deadline: .now() + scanSeconds) {
      central.stopScan()
      if self.target == nil {
  log("probe: scan window over — no WHOOP name seen. (Name may be withheld until bonded.)")
      }
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                      advertisementData: [String: Any], rssi RSSI: NSNumber) {
    let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
    let mfrHex = ((advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data) ?? Data()).map { String(format: "%02x", $0) }.joined()
    let interesting = name.uppercased().contains("WHOOP")
      || services.contains { $0.lowercased().hasPrefix("6108") || $0.lowercased().hasPrefix("fd4b") }
      || (mfrHex.count >= 4 && mfrHex.hasPrefix("6108"))
    if interesting {
  log(String(format: "probe: FOUND %@ [%@] rssi=%d services=%@ mfr=%@", name, peripheral.identifier.uuidString, RSSI.intValue, services, mfrHex))
      guard target == nil else { return }
      target = peripheral
      peripheral.delegate = self
      central.stopScan()
      central.connect(peripheral, options: nil)
  log("probe: connecting…")
    } else if RSSI.intValue > -55 {
  log(String(format: "probe: near device %@ rssi=%d (not WHOOP-pattern)", name.isEmpty ? "?" : name, RSSI.intValue))
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
  log("probe: CONNECTED to \(peripheral.name ?? "?") — discovering services…")
    peripheral.discoverServices(nil)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
  log("probe: CONNECT FAILED: \(error?.localizedDescription ?? "no error")")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
  log("probe: DISCONNECTED: \(error?.localizedDescription ?? "clean")")
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

  var helloSent = false

  func sendHello() {
    guard let p = target, let ch = commandChar else { return }
    // GET_HELLO_HARVARD (0x23 = 35): timestamp LE + padding, per Zulu Sierra /
    // GooseBLEClient+OfficialHandshake.
    var ts = [UInt8]()
    var t = UInt64(Date().timeIntervalSince1970)
    for _ in 0..<8 { ts.append(UInt8(t & 0xff)); t >>= 8 }
    let f = frame(seq: seq, command: 35, payload: ts + [0x00])
  log("probe: → GET_HELLO_HARVARD \(f.map { String(format: "%02x", $0) }.joined())")
    p.writeValue(f, for: ch, type: .withResponse)
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
  log("probe: write \(error == nil ? "ok" : "ERROR \(error!.localizedDescription)") for \(characteristic.uuid.uuidString)")
    if error == nil, characteristic === commandChar {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        // RT_HR_ON (0x03) — if HELLO worked, this starts the HR stream.
        guard let ch = self.commandChar else { return }
        self.seq &+= 1
        let f = self.frame(seq: self.seq, command: 0x03, payload: [0x01])
  log("probe: → TOGGLE_REALTIME_HR(on) \(f.map { String(format: "%02x", $0) }.joined())")
        peripheral.writeValue(f, for: ch, type: .withResponse)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    let d = characteristic.value ?? Data()
    let hex = d.map { String(format: "%02x", $0) }.joined()
    let u = characteristic.uuid.uuidString.lowercased()
    var tag = u.hasSuffix("0003") ? "RESP" : (u.hasSuffix("0004") ? "EVENT" : (u.hasSuffix("0005") ? "DATA" : u.suffix(4)))
    if hex.count > 16, UInt8(hex.prefix(2), radix: 16) == 0xaa {
      // Gen4 frame: type at byte 4, sub at byte 6 (payload starts after 4B header)
      let bytes = [UInt8](d)
      if bytes.count > 6 {
        let t = bytes[4], sub = bytes[6]
        tag = "\(tag) type=0x\(String(t, radix: 16)) sub=0x\(String(sub, radix: 16))"
      }
    }
  log("probe: ← \(tag) \(hex.prefix(120))\(hex.count > 120 ? "…" : "")")
  }
}

Probe().run()
