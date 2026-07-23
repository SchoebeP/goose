import Foundation

/// One server-computed sleep night from the VPS (`GET /whoop/ingest/sleep/nights`).
/// The server windows nights in the timezone we pass, so `date` is the local wake date.
struct ServerSleepNight: Decodable, Identifiable, Equatable {
  let date: String
  let startUTC: String
  let endUTC: String
  let durationMin: Double
  let avgHR: Double?
  let avgRespRPM: Double?
  let quality: String?

  var id: String { date }

  enum CodingKeys: String, CodingKey {
    case date
    case startUTC = "start_utc"
    case endUTC = "end_utc"
    case durationMin = "duration_min"
    case avgHR = "avg_hr"
    case avgRespRPM = "avg_resp_rpm"
    case quality
  }

  var start: Date? { Self.isoFormatter.date(from: startUTC) }
  var end: Date? { Self.isoFormatter.date(from: endUTC) }

  /// Duration as decimal hours, e.g. "6.0" (pairs with unit "h").
  var durationHoursText: String {
    String(format: "%.1f", durationMin / 60.0)
  }

  /// Sleep window in local time plus average HR, e.g. "01:00 - 07:00 | avg HR 54".
  var summaryText: String {
    var parts: [String] = []
    if let start, let end {
      parts.append("\(Self.localTimeText(start)) - \(Self.localTimeText(end))")
    }
    if let avgHR {
      parts.append("avg HR \(Int(avgHR.rounded()))")
    }
    return parts.isEmpty ? "Server sleep night" : parts.joined(separator: " | ")
  }

  /// True when this night's wake date is the given local calendar day.
  func isForLocalDay(_ day: Date, calendar: Calendar = .current) -> Bool {
    date == Self.dayKey(for: day, calendar: calendar)
  }

  static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static func localTimeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
  }
}

private struct ServerSleepNightsResponse: Decodable {
  let nights: [ServerSleepNight]
  let count: Int
}

/// Server-computed sleep nights, fetched from the VPS.
/// Same token-only read path as MinutelyHRFeed; tz = our local zone so the
/// server windows nights around OUR midnight.
@MainActor
final class ServerSleepFeed: ObservableObject {
  static let shared = ServerSleepFeed()

  @Published var nights: [ServerSleepNight] = []
  @Published var latestNight: ServerSleepNight?

  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/sleep/nights")!
    components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
    return components.url!
  }()
  private var token: String { IngestCredentials.token }
  private var lastRequestedAt: Date?

  /// The night that ended this morning (wake date == today local), if the server has it.
  var lastNight: ServerSleepNight? {
    nights.first { $0.isForLocalDay(Date()) }
  }

  func refresh() {
    lastRequestedAt = Date()
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
      guard let data,
            let r = try? JSONDecoder().decode(ServerSleepNightsResponse.self, from: data) else { return }
      let sorted = r.nights.sorted { $0.date > $1.date }
      Task { @MainActor in
        self?.nights = sorted
        self?.latestNight = sorted.first
      }
    }.resume()
  }

  /// Fetch at most once per `maxAge`; safe to call from snapshot builders on every render.
  func refreshIfStale(maxAge: TimeInterval = 300) {
    if let lastRequestedAt, Date().timeIntervalSince(lastRequestedAt) < maxAge {
      return
    }
    refresh()
  }
}
