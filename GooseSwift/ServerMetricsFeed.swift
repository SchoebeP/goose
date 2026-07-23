import Foundation

/// Server-computed sleep window inside one metrics day
/// (`GET /whoop/ingest/metrics/daily`). Every field is optional — the server
/// includes only what it has real data for.
struct ServerMetricsSleep: Decodable, Equatable {
  let startUTC: String?
  let endUTC: String?
  let durationMin: Double?
  let avgHR: Double?

  enum CodingKeys: String, CodingKey {
    case startUTC = "start_utc"
    case endUTC = "end_utc"
    case durationMin = "duration_min"
    case avgHR = "avg_hr"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    startUTC = try? container.decodeIfPresent(String.self, forKey: .startUTC)
    endUTC = try? container.decodeIfPresent(String.self, forKey: .endUTC)
    durationMin = try? container.decodeIfPresent(Double.self, forKey: .durationMin)
    avgHR = try? container.decodeIfPresent(Double.self, forKey: .avgHR)
  }

  var start: Date? { startUTC.flatMap(ServerMetricsDay.parseUTC) }
  var end: Date? { endUTC.flatMap(ServerMetricsDay.parseUTC) }
}

/// Server skin temperature for one day (`skin_temp` in
/// `GET /whoop/ingest/metrics/daily`): `{value, unit, calibrated}`. When
/// `calibrated` is false the value is in RAW sensor units, not °C — it must
/// never be displayed as a temperature.
struct ServerMetricsSkinTemp: Decodable, Equatable {
  let value: Double?
  let unit: String?
  let calibrated: Bool?

  enum CodingKeys: String, CodingKey {
    case value
    case unit
    case calibrated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = try? container.decodeIfPresent(Double.self, forKey: .value)
    unit = try? container.decodeIfPresent(String.self, forKey: .unit)
    calibrated = try? container.decodeIfPresent(Bool.self, forKey: .calibrated)
  }

  /// True only when the server explicitly marked this value calibrated (°C).
  var isCalibratedCelsius: Bool {
    calibrated == true && value != nil
  }
}

/// Baevsky stress index + band. All server-computed; absent when no data.
struct ServerMetricsStress: Decodable, Equatable {
  let stressIndex: Double?
  let band: String?
  enum CodingKeys: String, CodingKey { case stressIndex = "stress_index", band }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    stressIndex = try? c.decodeIfPresent(Double.self, forKey: .stressIndex)
    band = try? c.decodeIfPresent(String.self, forKey: .band)
  }
}

/// Frequency-domain HRV (LF/HF autonomic balance).
struct ServerMetricsHRVFreq: Decodable, Equatable {
  let lfHfRatio: Double?
  enum CodingKeys: String, CodingKey { case lfHfRatio = "lf_hf_ratio" }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    lfHfRatio = try? c.decodeIfPresent(Double.self, forKey: .lfHfRatio)
  }
}

/// Relative SpO2 desaturation screen — events per hour, never an absolute %.
struct ServerMetricsODI: Decodable, Equatable {
  let eventsPerHour: Double?
  let burdenPct: Double?
  enum CodingKeys: String, CodingKey {
    case eventsPerHour = "odi_events_per_hour", burdenPct = "burden_pct"
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    eventsPerHour = try? c.decodeIfPresent(Double.self, forKey: .eventsPerHour)
    burdenPct = try? c.decodeIfPresent(Double.self, forKey: .burdenPct)
  }
}

/// Sleep staging + AASM accounting. Any field may be absent (honest omission).
struct ServerMetricsSleepStages: Decodable, Equatable {
  let tibMin: Double?
  let tstMin: Double?
  let remPct: Double?
  let deepPct: Double?
  let lightPct: Double?
  let wasoMin: Double?
  let efficiencyPct: Double?
  enum CodingKeys: String, CodingKey {
    case tibMin = "tib_min", tstMin = "tst_min", remPct = "rem_pct"
    case deepPct = "deep_pct", lightPct = "light_pct"
    case wasoMin = "waso_min", efficiencyPct = "efficiency_pct"
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    tibMin = try? c.decodeIfPresent(Double.self, forKey: .tibMin)
    tstMin = try? c.decodeIfPresent(Double.self, forKey: .tstMin)
    remPct = try? c.decodeIfPresent(Double.self, forKey: .remPct)
    deepPct = try? c.decodeIfPresent(Double.self, forKey: .deepPct)
    lightPct = try? c.decodeIfPresent(Double.self, forKey: .lightPct)
    wasoMin = try? c.decodeIfPresent(Double.self, forKey: .wasoMin)
    efficiencyPct = try? c.decodeIfPresent(Double.self, forKey: .efficiencyPct)
  }
}

/// One server-computed local day of daily metrics from the VPS
/// (`GET /whoop/ingest/metrics/daily?days=7&tz=...`). The server windows days
/// in the timezone we pass, so `date` is the local calendar day (yyyy-MM-dd).
/// ALL metric fields are optional: an absent field means the server has no
/// real data for it — callers must fall back to their honest empty state,
/// never invent a value.
struct ServerMetricsDay: Decodable, Identifiable, Equatable {
  let date: String
  let sleep: ServerMetricsSleep?
  /// Overnight heart-rate dip, percent (e.g. 18.5).
  let hrDipPct: Double?
  /// Overnight HRV (RMSSD), milliseconds.
  let hrvRMSSDMs: Double?
  /// Resting heart rate, bpm.
  let rhrBPM: Double?
  /// Respiratory rate, breaths per minute.
  let respRPM: Double?
  /// Nightly skin temperature (`{value, unit, calibrated}`); the value is
  /// only °C when `calibrated == true`, otherwise raw sensor units.
  let skinTemp: ServerMetricsSkinTemp?
  /// Strain on the server's 0–21 scale.
  let strain: Double?
  /// Recovery, percent 0–100.
  let recoveryPct: Double?
  /// Stress: Baevsky index + band ("low"/"normal"/"elevated"/"high").
  let stress: ServerMetricsStress?
  /// Frequency-domain HRV (LF/HF).
  let hrvFreq: ServerMetricsHRVFreq?
  /// Relative SpO2 desaturation screen (events/hour) — never an absolute %.
  let spo2ODI: ServerMetricsODI?
  /// Sleep staging + AASM accounting (REM/deep/light, time-in-bed, efficiency).
  let sleepStages: ServerMetricsSleepStages?

  var id: String { date }

  enum CodingKeys: String, CodingKey {
    case date
    case sleep
    case hrDipPct = "hr_dip_pct"
    case hrvRMSSDMs = "hrv_rmssd_ms"
    case rhrBPM = "rhr_bpm"
    case respRPM = "resp_rpm"
    case skinTemp = "skin_temp"
    case strain
    case recoveryPct = "recovery_pct"
    case stress
    case hrvFreq = "hrv_freq"
    case spo2ODI = "spo2_odi"
    case sleepStages = "sleep_stages"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // `date` is the only required key — a day we can't place on the calendar
    // is unusable. Everything else tolerates absent, null, or wrong-typed
    // values by collapsing to nil.
    date = try container.decode(String.self, forKey: .date)
    sleep = try? container.decodeIfPresent(ServerMetricsSleep.self, forKey: .sleep)
    hrDipPct = try? container.decodeIfPresent(Double.self, forKey: .hrDipPct)
    hrvRMSSDMs = try? container.decodeIfPresent(Double.self, forKey: .hrvRMSSDMs)
    rhrBPM = try? container.decodeIfPresent(Double.self, forKey: .rhrBPM)
    respRPM = try? container.decodeIfPresent(Double.self, forKey: .respRPM)
    skinTemp = try? container.decodeIfPresent(ServerMetricsSkinTemp.self, forKey: .skinTemp)
    strain = try? container.decodeIfPresent(Double.self, forKey: .strain)
    recoveryPct = try? container.decodeIfPresent(Double.self, forKey: .recoveryPct)
    stress = try? container.decodeIfPresent(ServerMetricsStress.self, forKey: .stress)
    hrvFreq = try? container.decodeIfPresent(ServerMetricsHRVFreq.self, forKey: .hrvFreq)
    spo2ODI = try? container.decodeIfPresent(ServerMetricsODI.self, forKey: .spo2ODI)
    sleepStages = try? container.decodeIfPresent(ServerMetricsSleepStages.self, forKey: .sleepStages)
  }

  /// True when this day is the given local calendar day.
  func isForLocalDay(_ day: Date, calendar: Calendar = .current) -> Bool {
    date == Self.dayKey(for: day, calendar: calendar)
  }

  /// Wake time (sleep end) as a short local time, e.g. "07:12".
  var wakeLocalTimeText: String? {
    guard let end = sleep?.end else { return nil }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: end)
  }

  /// "HR dip 18%" — only when the server reported a dip.
  var hrDipText: String? {
    hrDipPct.map { "HR dip \(Int($0.rounded()))%" }
  }

  static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  static func parseUTC(_ text: String) -> Date? {
    if let date = isoFormatter.date(from: text) {
      return date
    }
    return isoFractionalFormatter.date(from: text)
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let isoFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

/// Skips array elements that fail to decode instead of failing the whole
/// payload — one malformed day must not hide the rest.
private struct LossyDayArray: Decodable {
  let days: [ServerMetricsDay]

  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var decoded: [ServerMetricsDay] = []
    while !container.isAtEnd {
      if let day = try? container.decode(ServerMetricsDay.self) {
        decoded.append(day)
      } else {
        // Consume the undecodable element so the container advances.
        _ = try? container.decode(DiscardedElement.self)
      }
    }
    days = decoded
  }

  private struct DiscardedElement: Decodable {}
}

private struct ServerMetricsDailyResponse: Decodable {
  let days: [ServerMetricsDay]

  init(from decoder: Decoder) throws {
    // Accept either {"days": [...], ...} or a bare top-level [...] — the
    // endpoint is being built in parallel; unknown sibling keys are ignored.
    if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
       let wrapped = try? keyed.decode(LossyDayArray.self, forKey: .days) {
      days = wrapped.days
      return
    }
    days = (try? LossyDayArray(from: decoder).days) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case days
  }
}

/// Server-computed daily metrics (sleep, HRV, RHR, respiration, strain,
/// recovery) fetched from the VPS. Same token-only read path as
/// ServerSleepFeed; tz = our local zone so the server windows days around OUR
/// midnight. Fields the server omits stay nil — never substitute values.
@MainActor
final class ServerMetricsFeed: ObservableObject {
  static let shared = ServerMetricsFeed()

  @Published var days: [ServerMetricsDay] = []
  @Published var latestDay: ServerMetricsDay?

  /// False until the first fetch has completed (success, empty, or failure).
  /// While false a server-backed field is still genuinely awaiting its first
  /// response and callers may show a loading state instead of "No data".
  @Published private(set) var hasLoadedOnce = false
  /// True while a fetch is in flight.
  @Published private(set) var isLoading = false

  private let url: URL = {
    var components = URLComponents(string: "https://latenightgames.fr/whoop/ingest/metrics/daily")!
    components.queryItems = [
      URLQueryItem(name: "days", value: "7"),
      URLQueryItem(name: "tz", value: TimeZone.current.identifier),
    ]
    return components.url!
  }()
  private var token: String { IngestCredentials.token }
  private var lastRequestedAt: Date?

  /// The server's day for the given local calendar day (default: today).
  func day(forLocalDay date: Date = Date(), calendar: Calendar = .current) -> ServerMetricsDay? {
    days.first { $0.isForLocalDay(date, calendar: calendar) }
  }

  /// Today's metrics day, if the server has computed it.
  var today: ServerMetricsDay? {
    day(forLocalDay: Date())
  }

  func refresh() {
    lastRequestedAt = Date()
    isLoading = true
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.setValue(token, forHTTPHeaderField: "X-Ingest-Token")
    URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
      var sorted: [ServerMetricsDay]?
      if let data,
         (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) != false,
         let r = try? JSONDecoder().decode(ServerMetricsDailyResponse.self, from: data) {
        sorted = r.days.sorted { $0.date > $1.date }
      }
      Task { @MainActor in
        guard let self else { return }
        // Only replace data on a successful decode; always finish the load
        // state so the first completion (success/empty/failure) ends loading.
        if let sorted {
          self.days = sorted
          self.latestDay = sorted.first
        }
        self.isLoading = false
        self.hasLoadedOnce = true
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
