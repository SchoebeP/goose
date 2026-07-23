import Foundation

/// Single source of truth for the VPS ingest token.
/// Resolution order: `whoopIngestToken` in UserDefaults (settable without a
/// rebuild, e.g. after rotating the token server-side) -> compiled-in fallback.
/// The fallback value is ALREADY public in this repo's git history (leak noted
/// 2026-06-10) and must be deleted once the server token is rotated — that
/// rotation is a release gate for this branch.
enum IngestCredentials {
  /// Rotation override: Documents/ingest-token.txt, pushed onto the device
  /// over USB/Wi-Fi (devicectl) — survives relaunches, never touches the repo.
  private static let fileToken: String? = {
    guard let documents = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let value = try? String(contentsOf: documents.appendingPathComponent("ingest-token.txt"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (value?.isEmpty == false) ? value : nil
  }()

  static var token: String {
    if let override = UserDefaults.standard.string(forKey: "whoopIngestToken"),
       !override.isEmpty {
      // Persist launch-argument overrides (-whoopIngestToken X) so background
      // relaunches — which carry no launch arguments — keep the rotated token.
      if UserDefaults.standard.persistentDomain(
        forName: Bundle.main.bundleIdentifier ?? "")?["whoopIngestToken"] as? String != override {
        UserDefaults.standard.set(override, forKey: "whoopIngestToken")
      }
      return override
    }
    if let fileToken { return fileToken }
    // No compiled-in token: the old value was rotated dead on 2026-07-23 after
    // leaking in public git history. Without an override the feeds simply
    // stay silent rather than shipping a secret in source.
    return ""
  }
}
