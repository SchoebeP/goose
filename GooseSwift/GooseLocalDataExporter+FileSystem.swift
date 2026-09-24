import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

extension GooseLocalDataExporter {
  static func validateSQLiteDatabase(
    path: String,
    included: Bool,
    exists: inout Bool,
    openable: inout Bool,
    storageCheckPassed: inout Bool,
    issues: inout [String]
  ) {
    exists = FileManager.default.fileExists(atPath: path)
    guard exists else {
      issues.append("missing goose.sqlite")
      return
    }
    if !included {
      issues.append("goose.sqlite was not included in export")
    }

    do {
      let report = try GooseRustBridge().request(
        method: "storage.check",
        args: [
          "database_path": path,
          "self_test": false,
        ]
      )
      openable = true
      storageCheckPassed = (report["pass"] as? Bool) ?? false
      if !storageCheckPassed {
        let storageIssues = (report["issues"] as? [Any])?.compactMap { $0 as? String } ?? []
        if storageIssues.isEmpty {
          issues.append("goose.sqlite storage check failed")
        } else {
          issues.append("goose.sqlite storage check failed: \(storageIssues.joined(separator: "; "))")
        }
      }
    } catch {
      openable = false
      storageCheckPassed = false
      issues.append("goose.sqlite could not be opened: \(errorSummary(error))")
    }
  }

  static func defaultDatabasePath() -> String {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseDirectory
      .appendingPathComponent("GooseSwift", isDirectory: true)
      .appendingPathComponent("goose.sqlite")
      .path
  }

  static func createSQLiteSnapshot(
    databasePath: String,
    outputDirectory: URL,
    createdAt: String
  ) throws -> URL {
    // The raw-export bridge snapshots via VACUUM INTO, which holds a read
    // transaction on the source, so the copy is transactionally consistent even
    // while CaptureFrameWriteQueue keeps committing to the live database.
    let bridge = GooseRustBridge()
    let report = try bridge.request(
      method: "export.raw_timeframe",
      args: [
        "database_path": databasePath,
        "output_dir": outputDirectory.path,
        "start": "1970-01-01T00:00:00Z",
        "end": createdAt,
        "include_sqlite": true,
        "data_families": ["sqlite"],
        "include_raw_bytes": true,
      ]
    )
    let snapshotURL = outputDirectory
      .appendingPathComponent("data", isDirectory: true)
      .appendingPathComponent("goose.sqlite")
    guard boolValue(report["pass"]) == true,
          FileManager.default.fileExists(atPath: snapshotURL.path) else {
      let issues = (report["issues"] as? [Any])?.compactMap { $0 as? String } ?? []
      throw GooseLocalDataExportError.sqliteSnapshotFailed(
        issues.isEmpty ? "raw export snapshot did not pass" : issues.joined(separator: "; ")
      )
    }
    // Check the snapshot itself so the exported bytes are the verified bytes.
    let check = try bridge.request(
      method: "storage.check",
      args: [
        "database_path": snapshotURL.path,
        "self_test": false,
      ]
    )
    guard boolValue(check["pass"]) == true else {
      let issues = (check["issues"] as? [Any])?.compactMap { $0 as? String } ?? []
      throw GooseLocalDataExportError.sqliteSnapshotFailed(
        issues.isEmpty
          ? "snapshot storage check failed"
          : "snapshot storage check failed: \(issues.joined(separator: "; "))"
      )
    }
    try applyExportProtection(to: snapshotURL)
    return snapshotURL
  }

  static func currentBLELogByteCount(logURLs: [URL], fileManager: FileManager) -> UInt64 {
    logURLs
      .reduce(UInt64(0)) { total, url in
        total + fileByteCount(at: url, fileManager: fileManager)
      }
  }

  static func currentBLELogContains(
    sessionID: String,
    logURLs: [URL],
    fileManager: FileManager
  ) -> Bool {
    logURLs.contains { fileContainsUTF8Needle(at: $0, needle: sessionID, fileManager: fileManager) }
  }

  static func includedBLELogURLs(
    pathSet: Set<String>,
    documentsDirectory: URL,
    fileManager: FileManager
  ) -> [URL] {
    var urls: [URL] = []
    if pathSet.contains("Application Support/GooseSwift/goose-ble.log"),
       let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      urls.append(
        appSupport
          .appendingPathComponent("GooseSwift", isDirectory: true)
          .appendingPathComponent("goose-ble.log")
      )
    }
    if pathSet.contains("Documents/GooseSwift/goose-ble-live.log") {
      urls.append(
        documentsDirectory
          .appendingPathComponent("GooseSwift", isDirectory: true)
          .appendingPathComponent("goose-ble-live.log")
      )
    }
    return urls
  }

  static func fileByteCount(at url: URL, fileManager: FileManager) -> UInt64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else {
      return 0
    }
    return size.uint64Value
  }

  static func fileContainsUTF8Needle(at url: URL, needle: String, fileManager: FileManager) -> Bool {
    guard let needleData = needle.data(using: .utf8), !needleData.isEmpty else {
      return false
    }
    guard fileManager.fileExists(atPath: url.path),
          let handle = try? FileHandle(forReadingFrom: url) else {
      return false
    }
    defer {
      try? handle.close()
    }

    let chunkSize = 64 * 1024
    let carryLimit = max(needleData.count - 1, 0)
    var carry = Data()
    while true {
      let chunk: Data?
      do {
        chunk = try handle.read(upToCount: chunkSize)
      } catch {
        return false
      }
      guard let chunk, !chunk.isEmpty else {
        return false
      }

      var searchWindow = Data()
      if !carry.isEmpty {
        searchWindow.append(carry)
      }
      searchWindow.append(chunk)
      if searchWindow.range(of: needleData) != nil {
        return true
      }
      carry = carryLimit > 0 ? Data(searchWindow.suffix(carryLimit)) : Data()
    }
  }

  static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    if let value = value as? String {
      return Int(value)
    }
    return nil
  }

  static func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    if let value = value as? String {
      switch value.lowercased() {
      case "true", "1", "yes":
        return true
      case "false", "0", "no":
        return false
      default:
        return nil
      }
    }
    return nil
  }

  static func errorSummary(_ error: Error) -> String {
    if case let GooseRustBridgeError.methodFailed(message) = error {
      return message
    }
    return String(describing: error)
  }

  static func enumerateJSONLines(at url: URL, body: ([String: Any]?) -> Void) -> String? {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      return "could not open \(url.lastPathComponent): \(errorSummary(error))"
    }

    var buffer = Data()
    do {
      while true {
        let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
        if chunk.isEmpty {
          break
        }
        buffer.append(chunk)
        while let newlineIndex = buffer.firstIndex(of: 0x0a) {
          let line = buffer.subdata(in: 0..<newlineIndex)
          buffer.removeSubrange(0...newlineIndex)
          parseJSONLine(line, body: body)
        }
      }
    } catch {
      try? handle.close()
      return "could not read \(url.lastPathComponent): \(errorSummary(error))"
    }
    do {
      try handle.close()
    } catch {
      return "could not close \(url.lastPathComponent): \(errorSummary(error))"
    }
    if !buffer.isEmpty {
      parseJSONLine(buffer, body: body)
    }
    return nil
  }

  static func parseJSONLine(_ line: Data, body: ([String: Any]?) -> Void) {
    guard !line.isEmpty else {
      return
    }
    body((try? JSONSerialization.jsonObject(with: line)) as? [String: Any])
  }

  static func exportRoots(fileManager: FileManager, documentsDirectory: URL) -> [(label: String, url: URL)] {
    var roots: [(String, URL)] = []
    if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      roots.append(("Application Support/GooseSwift", appSupport.appendingPathComponent("GooseSwift", isDirectory: true)))
    }
    roots.append(("Documents/GooseSwift", documentsDirectory.appendingPathComponent("GooseSwift", isDirectory: true)))
    if let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
      roots.append(("Library/Preferences", library.appendingPathComponent("Preferences", isDirectory: true)))
    }
    return roots
  }

  static func filesUnder(
    _ root: URL,
    label: String,
    outputDirectory: URL,
    requiredOvernightSessionID: String?,
    fileManager: FileManager
  ) -> [(url: URL, relativePath: String)] {
    var files: [(URL, String)] = []
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
      return files
    }

    if !isDirectory.boolValue {
      let relativePath = root.lastPathComponent
      if shouldIncludeFile(
        label: label,
        relativePath: relativePath,
        requiredOvernightSessionID: requiredOvernightSessionID
      ) {
        files.append((root, "\(label)/\(relativePath)"))
      }
      return files
    }

    let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: resourceKeys) else {
      return files
    }

    for case let url as URL in enumerator {
      if isUnder(url, directory: outputDirectory) {
        enumerator.skipDescendants()
        continue
      }
      guard (try? url.resourceValues(forKeys: Set(resourceKeys)).isRegularFile) == true else {
        continue
      }
      let relativePath = relativePath(for: url, under: root)
      if !shouldIncludeFile(
        label: label,
        relativePath: relativePath,
        requiredOvernightSessionID: requiredOvernightSessionID
      ) {
        continue
      }
      files.append((url, "\(label)/\(relativePath)"))
    }
    return files.sorted(by: { lhs, rhs in
      lhs.1 < rhs.1
    })
  }

  static func shouldIncludeFile(
    label: String,
    relativePath: String,
    requiredOvernightSessionID: String?
  ) -> Bool {
    guard let requiredOvernightSessionID else {
      return true
    }

    switch label {
    case "Application Support/GooseSwift":
      return relativePath == "goose.sqlite"
        || relativePath == "goose.sqlite-wal"
        || relativePath == "goose.sqlite-shm"
        || relativePath == "goose.sqlite-journal"
        || relativePath == "goose-ble.log"
        || relativePath.hasPrefix("goose-ble.")
    case "Documents/GooseSwift":
      return relativePath == "goose-ble-live.log"
        || relativePath.hasPrefix("OvernightGuard/\(requiredOvernightSessionID)/")
    case "Library/Preferences":
      return true
    default:
      return false
    }
  }

  static func isLiveSQLiteSidecarPath(_ relativePath: String) -> Bool {
    relativePath == "Application Support/GooseSwift/goose.sqlite-wal"
      || relativePath == "Application Support/GooseSwift/goose.sqlite-shm"
      || relativePath == "Application Support/GooseSwift/goose.sqlite-journal"
  }

  static func relativePath(for url: URL, under root: URL) -> String {
    let rootPath = normalizedPath(root)
    let path = normalizedPath(url)
    guard path.hasPrefix(rootPath + "/") else {
      return url.lastPathComponent
    }
    return String(path.dropFirst(rootPath.count + 1))
  }

  static func isUnder(_ url: URL, directory: URL) -> Bool {
    let path = normalizedPath(url)
    let directoryPath = normalizedPath(directory)
    return path == directoryPath || path.hasPrefix(directoryPath + "/")
  }

  static func normalizedPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  static func writeJSONObject(_ object: [String: Any], to handle: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try handle.write(contentsOf: data)
  }

  static func writeJSONObjectFields(_ object: [String: Any], to handle: FileHandle) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard data.count >= 2, data.first == 123, data.last == 125 else {
      try writeJSONObject(object, to: handle)
      return
    }
    try handle.write(contentsOf: Data(data.dropFirst().dropLast()))
  }

  static func writeString(_ string: String, to handle: FileHandle) throws {
    try handle.write(contentsOf: Data(string.utf8))
  }

  static func synchronizeAndClose(_ handle: FileHandle) throws {
    var fileError: Error?
    do {
      try handle.synchronize()
    } catch {
      fileError = error
    }
    do {
      try handle.close()
    } catch {
      if fileError == nil {
        fileError = error
      }
    }
    if let fileError {
      throw fileError
    }
  }

  static func applyExportProtection(to url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: exportProtection],
      ofItemAtPath: url.path
    )
  }

  static func writeFileRecord(
    source: String,
    relativePath: String,
    inputHandle: FileHandle,
    to outputHandle: FileHandle
  ) throws -> FileContentDigest {
    defer {
      try? inputHandle.close()
    }

    try writeString("{", to: outputHandle)
    try writeJSONObjectFields([
      "source": source,
      "relative_path": relativePath,
    ], to: outputHandle)
    try writeString(",\"base64\":\"", to: outputHandle)
    let digest = try writeBase64Contents(from: inputHandle, to: outputHandle)
    try writeString("\",\"byte_count\":\(digest.byteCount),\"sha256\":\"\(digest.sha256)\"}", to: outputHandle)
    return digest
  }

  static func writeBase64Contents(from inputHandle: FileHandle, to outputHandle: FileHandle) throws -> FileContentDigest {
    var byteCount: UInt64 = 0
    var carry = Data()
    var hasher = SHA256()
    let chunkSize = 192 * 1024

    while true {
      let chunk = try inputHandle.read(upToCount: chunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }

      byteCount += UInt64(chunk.count)
      hasher.update(data: chunk)
      var pending = carry
      pending.append(chunk)
      let encodableCount = pending.count - (pending.count % 3)
      if encodableCount > 0 {
        let encoded = Data(pending.prefix(encodableCount)).base64EncodedData()
        try outputHandle.write(contentsOf: encoded)
      }
      if encodableCount < pending.count {
        carry = Data(pending.suffix(pending.count - encodableCount))
      } else {
        carry.removeAll(keepingCapacity: true)
      }
    }

    if !carry.isEmpty {
      try outputHandle.write(contentsOf: carry.base64EncodedData())
    }
    return FileContentDigest(byteCount: byteCount, sha256: hexString(for: hasher.finalize()))
  }

  static func fileDigest(at url: URL) throws -> FileContentDigest {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }

    var byteCount: UInt64 = 0
    var hasher = SHA256()
    while true {
      let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
      if chunk.isEmpty {
        break
      }
      byteCount += UInt64(chunk.count)
      hasher.update(data: chunk)
    }
    return FileContentDigest(byteCount: byteCount, sha256: hexString(for: hasher.finalize()))
  }

  static func hexString<D: Sequence>(for digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
