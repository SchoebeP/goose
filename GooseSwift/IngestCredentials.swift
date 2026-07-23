import Foundation

/// Single source of truth for the VPS ingest token.
/// Resolution order: `whoopIngestToken` in UserDefaults (settable without a
/// rebuild, e.g. after rotating the token server-side) -> compiled-in fallback.
/// The fallback value is ALREADY public in this repo's git history (leak noted
/// 2026-06-10) and must be deleted once the server token is rotated — that
/// rotation is a release gate for this branch.
enum IngestCredentials {
  static var token: String {
    if let override = UserDefaults.standard.string(forKey: "whoopIngestToken"),
       !override.isEmpty {
      return override
    }
    return "c0067852565b4d0d46606172de35c6ba120112c447e1f25b"
  }
}
