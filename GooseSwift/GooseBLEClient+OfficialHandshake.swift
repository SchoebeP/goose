import Foundation

/// LOT 1 BIS — "Official handshake mode" (Zulusierra MITM, 2026-09-08).
/// Replays the official WHOOP app's init sequence byte-for-byte before pulling
/// history: HELLO → clock → feature-flag read loop → config query → 0x16 history.
/// Every step is journaled (visible in Réglages ⌚ and in app_log) so we can see
/// exactly where the band starts (or refuses to) cooperate.
///
/// Wire facts from the MITM capture:
/// - Commands: type 0x23 (=35 decimal), responses 0x24 (=36), data 0x28 (=40).
/// - HELLO (0x23) carries a timestamp; response = 133B device status w/ serial.
/// - Feature flags: 0x75 query starts iteration; 0x76 = next-flag read (×13);
///   0x78 = flag set. Names observed: general_ab_test, sigproc_10_sec_dp,
///   enable_r19_v2_packets, enable_capsense_wear_detect, enable_false_step_detection,
///   wear_detect_bias.
/// - Config query 0x22 returns a 69B blob.
/// - History request = 0x16 (NOT 34!). ACK/trim = 0x17 with a per-chunk token.
/// All commands below are READ-ONLY against band config except the flag SETs,
/// which are sent in a second, separately-gated pass (we never write blind).
extension GooseBLEClient {

  struct OfficialHandshakeStep {
    let cmd: UInt8
    let payload: [UInt8]
    let label: String
    let waitAfter: TimeInterval
  }

  /// The full read-only first pass (steps 1, 2, 3, 4, 6 of the MITM table).
  /// No 0x78 flag-writes here — that's `runOfficialFlagWrites` once we've seen
  /// the read loop work on this band.
  static func officialReadHandshake() -> [OfficialHandshakeStep] {
    return [
      OfficialHandshakeStep(cmd: 35, payload: Self.helloTimestampPayload(),
                            label: "HELLO(0x23) timestamp+status", waitAfter: 0.8),
      OfficialHandshakeStep(cmd: 10, payload: Self.clockSyncPayload(), label: "CLOCK_SYNC(0x0a)", waitAfter: 0.4),
      OfficialHandshakeStep(cmd: 0x75, payload: [], label: "FEATURE_FLAG_QUERY(0x75)", waitAfter: 0.4),
      // 0x76 iteration: the app reads 13 flags; we iterate a few empty reads —
      // each should return one flag name in the response. We log what we get.
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #1", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #2", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #3", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #4", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #5", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x76, payload: [], label: "FLAG_ITER(0x76) #6", waitAfter: 0.25),
      OfficialHandshakeStep(cmd: 0x22, payload: [], label: "CONFIG_QUERY(0x22)", waitAfter: 0.6),
    ]
  }

  /// CLOCK_SYNC payload — 5 bytes: unix epoch u32 LE + commit byte 0x01.
  /// Vérifié sur le bracelet (2026-09-09): la forme 8B (OpenStrap) n'est PAS
  /// latched sur ce firmware; seule la 5B [epoch][0x01] répare la RTC.
  /// Sans RTC valide le firmware refuse d'écrire toute donnée en flash
  /// ("RTC timestamp invalid; not saving data to flash") et le buffer
  /// historique reste vide — d'où des mois de données perdues.
  static func clockSyncPayload() -> [UInt8] {
    let now = UInt32(Date().timeIntervalSince1970)
    return withUnsafeBytes(of: now.littleEndian) { Array($0) } + [0x01]
  }

  /// HELLO payload: 9 bytes — unix timestamp LE + zero padding (MITM frame:
  /// `aa 8e d4 69 a9 6d 00 00 00` little-endian seconds).
  static func helloTimestampPayload() -> [UInt8] {
    let now = UInt32(Date().timeIntervalSince1970)
    return withUnsafeBytes(of: now.littleEndian) { Array($0) } + [0, 0, 0, 0, 0]
  }

  /// Runs the official read handshake right now (bonded, "ready" state).
  /// Journals each step so the user sees the conversation live.
  func runOfficialHandshake() {
    guard connectionState == "ready" else {
      gen4Journal("❌ Impossible: le bracelet n'est pas connecté (état: \(connectionState))")
      return
    }
    gen4Journal("🤝 Handshake officiel — je me présente comme la vraie app…")
    var delay: TimeInterval = 0.2
    for step in Self.officialReadHandshake() {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.writeGen4Command(step.cmd, payload: step.payload, label: step.label)
        self?.gen4Journal("→ \(step.label)")
      }
      delay += step.waitAfter
    }
    // After the read handshake, immediately request history the official way
    // (0x16 = 22) — this is the whole point: history AFTER a proper greeting.
    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) { [weak self] in
      guard let self else { return }
      self.gen4Journal("📜 Demande d'historique (0x16, forme officielle)…")
      self.requestGen4HistoricalBackfillIfNeeded(force: true, officialOnly: true)
    }
    record(level: .warn, source: "ble.gen4", title: "official.handshake.started",
           body: "full read-only MITM sequence: hello, clock, flags x6, config, then 0x16 history")
  }

  /// Second, separately-gated pass: feature-flag WRITES (0x78). Not run by
  /// default — Pat decides from the journal whether the read loop worked.
  func runOfficialFlagWrites() {
    guard connectionState == "ready" else { return }
    gen4Journal("⚙️ Activation des feature flags (écriture)…")
    let flags = [
      "enable_r19_v2_packets",
      "enable_capsense_wear_detect",
      "enable_false_step_detection",
      "wear_detect_bias",
      "sigproc_10_sec_dp",
      "sigproc_pdaf",
      "general_ab_test",
    ]
    var delay: TimeInterval = 0.2
    for flag in flags {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        self?.writeGen4Command(0x78, payload: Array(flag.utf8) + [0],
                               label: "FLAG_SET(0x78) \(flag)")
      }
      delay += 0.3
    }
  }
}
