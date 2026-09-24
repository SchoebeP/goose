import Foundation

enum CoachStreamState: Equatable {
  case idle
  case streaming
  case failed(String)

  var isStreaming: Bool {
    if case .streaming = self {
      return true
    }
    return false
  }
}

struct CoachToolEvent: Identifiable, Equatable, Codable {
  let id: String
  var name: String
  var status: String
  var arguments: String
  var resultSummary: String?
}

struct CoachChatMessage: Identifiable, Equatable, Codable {
  enum Role: Equatable, Codable {
    case user
    case assistant
  }

  let id: UUID
  let role: Role
  var text: String
  var toolEvents: [CoachToolEvent]
  var isStreaming: Bool
  var isCancelled: Bool
  let createdAt: Date

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    toolEvents: [CoachToolEvent] = [],
    isStreaming: Bool = false,
    isCancelled: Bool = false,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.toolEvents = toolEvents
    self.isStreaming = isStreaming
    self.isCancelled = isCancelled
    self.createdAt = createdAt
  }
}

enum CoachModelPreset: String, CaseIterable, Identifiable {
  case gpt55Low
  case gpt55Medium
  case gpt55High

  var id: String { rawValue }

  static let defaultValue: CoachModelPreset = .gpt55Medium

  var title: String {
    switch self {
    case .gpt55Low:
      return "GPT-5.5 Low"
    case .gpt55Medium:
      return "GPT-5.5 Medium"
    case .gpt55High:
      return "GPT-5.5 High"
    }
  }

  var modelID: String {
    "gpt-5.5"
  }

  var effort: String {
    switch self {
    case .gpt55Low:
      return "low"
    case .gpt55Medium:
      return "medium"
    case .gpt55High:
      return "high"
    }
  }
}

enum CoachConversationStore {
  private static let legacyDefaultsKey = "goose.coach.conversation.v1"
  private static let maxPersistedMessages = 80

  static func load() -> [CoachChatMessage] {
    migrateLegacyDefaultsIfNeeded()
    guard let data = try? Data(contentsOf: fileURL()) else {
      return []
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([CoachChatMessage].self, from: data)) ?? []
  }

  static func save(_ messages: [CoachChatMessage]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let persisted = Array(messages.suffix(maxPersistedMessages))
    guard let data = try? encoder.encode(persisted) else {
      return
    }
    write(data)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    try? FileManager.default.removeItem(at: fileURL())
  }

  private static func fileURL() -> URL {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let directory = baseDirectory.appendingPathComponent("GooseSwift", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("coach-conversation.json")
  }

  private static func write(_ data: Data) {
    var url = fileURL()
    // Transcript carries biometric tool output: keep it encrypted at rest and
    // out of device backups (Keychain tokens are similarly device-only).
    guard (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil else {
      return
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }

  private static func migrateLegacyDefaultsIfNeeded() {
    guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey) else {
      return
    }
    if !FileManager.default.fileExists(atPath: fileURL().path) {
      write(data)
    }
    UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
  }
}
