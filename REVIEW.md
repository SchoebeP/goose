# Project Review — goose (2026-08-24)

**Branch:** `review-fixes-20260824` · **Base:** `main` @ `610aea6`
**Scope:** entire repo — Swift app (`GooseSwift/`), Rust core (`Rust/core`), build/deploy scripts, docs, git hygiene.
**Method:** 3 independent deep-review passes (repo/Rust/build, BLE protocol core, coach/security/data layer) → **adversarial challenger pass** attacking every finding against the actual code → only surviving findings fixed → verification builds.

**Verification:**
- `cargo test` (Rust/core): **all suites pass, exit 0**
- `xcodebuild -scheme GooseSwift -destination 'generic/platform=iOS Simulator'`: **BUILD SUCCEEDED**, 0 errors (includes the Rust-core build phase)

---

## Summary

| | Count |
|---|---|
| Findings raised by reviewers | 27 |
| Confirmed after challenge | 22 |
| Corrected by challenge (fix amended) | 2 |
| Refuted as non-issue | 1 |
| **Fixed on this branch** | **15** |
| Deferred / manual (prepared, need device or server) | 7 |

---

## Issues fixed

| # | Sev | Issue | Before | After | Expected impact |
|---|-----|-------|--------|-------|-----------------|
| 1 | **Critical** | Compromised VPS ingest token still compiled into every build (`GooseBLETypes.swift`). The removal commit (`d345280`) existed but was never merged to main; repo is public with 3 extra forks. Token is sole auth on public biometric read/write endpoints. | `private static let fallbackToken = "c006…f25b"` shipped in source of every build; anyone with the public repo could read/inject your health data. | Token resolves **UserDefaults → `Documents/ingest-token.txt` → empty** (fail-closed; feeds stay silent rather than ship a secret). Ported from d345280 incl. launch-arg persistence. | No secret in source or binaries. Ends forged-write/full-history-read exposure once the server-side rotation is confirmed (see manual list). |
| 2 | High | The audit doc itself republished the full 48-hex token 3× (`docs/audit-2026-06-10.md`). | Full token in a tracked doc of a public repo. | Masked: `c00678…[REDACTED]`. | Token no longer re-leaks from docs (history still needs the rewrite decision). |
| 3 | High | App-side GEN4 frame reassembly had **no CRC gate**: a payload byte `0xAA` with plausible length bytes pinned the scanner and swallowed real frames into 64 KB chimera frames that flowed unvalidated to capture DB + VPS (GEN4 bypasses the Rust parser). | `gooseFrames` trusted any `0xAA` + declared-length ≤64 KB. | GEN4 headers now validated via `crc8Gen4([len_lo,len_hi]) == crc8_byte` before trusting (same gate as cloud reassembler), plus 16 KB poison-trim resync. | No more chimera frames / dropped-frame windows during PPG-heavy streams; capture DB and VPS receive only CRC-plausible frames. |
| 4 | Medium | Reassembly buffers survived disconnects — a stranded partial frame absorbed the next connection's bytes (cloud path had this fix; app path didn't). | `frameReassemblyBuffers` never cleared on link loss. | Cleared on every non-ready connection state change, dispatched onto the serial ingest queue (thread-safe). | One corrupted frame + byte-scan per flappy reconnect eliminated. |
| 5 | Medium | Rust FFI: release profile had `panic = "abort"` and no `catch_unwind` — any library panic (46–60 unwrap/expect sites) killed the whole iOS app. | Panic → app abort. | `[profile.release] panic = "unwind"` + `catch_unwind(AssertUnwindSafe)` around bridge dispatch returning `{"ok":false,"code":"panic"}` JSON. Toolchain pinned via `rust-toolchain.toml`. | Bridge fault degrades to an error the app already handles (`methodFailed`) instead of crashing mid-capture/overnight. *Note: the original proposed fix (catch_unwind alone) would have done nothing under abort — caught by the challenger.* |
| 6 | Medium | R21 IMU history channels decoded **unsigned** in Swift while the Rust decoder reads the identical offsets signed (`read_i16_le`) — negatives wrapped to ~65 000, corrupting min/mean/rms diagnostics. | `intFromUInt16` for sample channels @20/220/…/1032. | New `intFromInt16` used for the channel loop (counts stay unsigned); comment ties it to the Rust decoder. | Trustworthy IMU diagnostics; decoders agree. Final confirmation on one live k21 frame recommended (manual list). |
| 7 | Medium | Fabricated calibration results shown as real output ("ready \| 4 train / 2 holdout \| improved", "71.5 raw -> 74.2 / 100") behind a Calibrate button whose handler only flips a bool. | Hardcoded fake numbers presented as computed evidence. | Honest placeholders ("Holdout not computed" / "Not computed" / next action names the missing bridge). | No invented measurements — matches the project's provenance discipline. Real engine exists (`Rust/core/src/calibration.rs`); wiring it is future work. |
| 8 | Medium | Coach prompt told the LLM to "Preserve WHOOP's 0-21 strain semantics" — violating the hard constraint that derived scores are never WHOOP's numbers. | Prompt instructed model to adopt proprietary semantics. | "This is Goose's own packet-derived estimate — never present it as WHOOP's proprietary Strain score." | Coach replies can't misattribute our estimate as WHOOP's. |
| 9 | Medium | Raw band frame bytes (`body_hex=`, up to 48 B, potentially PPG) left the device inside coach tool output posted to chatgpt.com. | Shared signal-point store fed debug UI *and* tool JSON verbatim. | `CoachLocalToolContext.deviceSignal` strips `body_hex=` / `raw={…}` segments; local debug UI untouched. | Only bounded summaries leave the device, matching sign-in disclosure. |
| 10 | Low→Med | Cloud forwarding defaulted ON with no disclosure in the shipped tree (text existed only in an unmerged worktree copy). | Users/you had no visible indication raw frames stream to latenightgames.fr. | Privacy screen gains a **Network Sync** section: working toggle (`whoopCloudForwarding`, default stays ON to protect nightly sync) + full disclosure text. | Informed consent + one-tap local-only mode. Default flip to OFF deferred as an explicit release decision. |
| 11 | Low | Assistant markdown rendered with `.full` syntax — model-controllable replies could embed remote images (tracking pixels) fetched on render. | `interpretedSyntax: .full`. | `.inlineOnlyPreservingWhitespace` (per-line rendering means no visual loss). | Injected reply can't beacon the network. |
| 12 | Low | Passive-activity average HR divided weighted total by `max(measuredSeconds, 1)` — sub-second early windows produced absurd averages (~10 bpm). | `100 bpm × 0.1 s ÷ max(0.1,1)` ≈ 10 bpm stored on the session. | Divide by real measured time, guarded by existing `delta > 0`; stays nil until first real interval. | Correct session averages; also cleans values reaching coach tool JSON. |
| 13 | Low | Live-HR summary always labelled "trusted", ignoring the `waiting` source state the very next row handles. | `"… | trusted | …"` unconditional. | Trust derived from source (`unproven` while waiting). | Provenance labels honest everywhere, including LLM-visible summaries. |
| 14 | Low | Overnight SQLite mirror queue: failed flush requeued rows but never rescheduled — backlog stalled until next enqueue. | Silent stall on flush error. | Retry with capped backoff (`flushDelay × min(failures, 30)`), counter resets on success. | Mirror keeps pace with the JSONL spool overnight; bounded retry churn. |
| 15 | Hygiene | Repo hygiene/docs drift: `.claude/` untracked-unignored (footgun on a public repo); unpinned Rust toolchain; GOAL.md described a nonexistent Python project with "(none yet)" progress; README promised a TestFlight beta dated June 2026; no CI; CHANGELOG claimed the token fix that hadn't landed. | Stale/misleading docs; accidental-commit risk. | `.claude/` ignored; `rust-toolchain.toml` pins 1.96.0; GOAL.md gets a dated STATUS CORRECTION banner; README date line made truthful; minimal CI added (cargo test); CHANGELOG gains an accurate 0.3.1 entry. | Future agent sessions stop running phantom pytest/ruff workflows; toolchain/unwind semantics pinned; CI guards the Rust core. |

---

## Challenger corrections (what the adversarial pass changed)

- **#5 (H5):** original fix was technically wrong — under `panic = "abort"`, `catch_unwind` never runs. Amended to unwind + catch.
- **GPS-jitter finding (C7):** mechanism confirmed, but the naive proposed fix (require segment distance > sum of accuracy radii) would discard legitimate walking. **Not applied** — needs amended formula + outdoor validation.
- **Date-label finding (C9):** REFUTED — keys are guaranteed `yyyy-MM-dd` upstream (`metricDateKey` uses an explicit POSIX formatter). No change made.
- **Cloud-forwarding default (C1):** flipping default OFF would silently break your nightly VPS sync — disclosure+toggle shipped instead; default flip is a deliberate decision for you.
- **Battery/event fragment decode (B3):** confirmed as first-fragment-only, but refactoring now would couple battery UI to the cloud forwarder's reassembler (breaks when forwarding is off). CLAUDE.md records these paths as live-validated. Deferred pending proof of fragmentation on iOS MTU.

## Deferred / manual (prepared, need device or server access)

| Item | Why deferred | Prepared step |
|------|--------------|---------------|
| Confirm old ingest token rejected by VPS | Needs Portainer/container access | `docker exec whoop-band-api` → check auth logs for 401s with the OLD token as `X-Ingest-Token`; then push the new token to the device via `Documents/ingest-token.txt` or `defaults write … whoopIngestToken <token>`. |
| Git history rewrite (token + forks exist) | Destructive; 3 fork copies make full purge impossible anyway | Decision only: force-push rewritten history + consider token rotation cadence. |
| B3 battery/type-36/48 fragmentation check | Needs physical band | Capture one connect session, log notification sizes for type-36/48; refactor decode onto reassembled frames only if fragments observed. |
| R21 signed-decode live confirmation | Needs physical band | Compare one k21 frame's channel min vs Rust summary in logs; expect symmetric ± values, not ~±32 000 wraps. |
| GPS distance jitter guard | Needs outdoor walk test vs known distance | Amend acceptance: reject segment when `segment < sqrt(a²+b²)` of accuracy radii AND require 2 consecutive consistent segments; validate against a measured 1 km walk. |
| Wire Rust calibration engine to Calibration screen | Feature work, not a fix | Bridge call exists in Rust (`calibration.rs`); add `calibration.run` bridge method + replace placeholders. |
| Docs trio rewrite (README vs READ-BIS.ME vs CLAUDE.md disagree on 4.0/5.0 & Python/iOS; requirements.txt vestigial; SKILL.md mandates phantom pytest/ruff) | Your instruction files; needs your intent | Keep GOAL.md banner as stopgap (done); decide whether READ-BIS.ME/requirements.txt get archived to `docs/history/` and CLAUDE.md's run/test commands updated to iOS reality. |

## Not applied (reviewer noise, judged not worth churn)
- Hardcoded `latenightgames.fr` URL consolidation (9 URLs/4 files) — mechanical refactor; runtime-configurable endpoint = scope creep.
- v5Frames/GEN4 latent length misparse in the side-effect router — benign today; touching risks V5 regressions.
- `CodexCoachSupport.swift` dead-code deletion — requires project.pbxproj surgery; flagging instead.

## Commits on this branch
1. `security:` ingest token fail-closed (+ doc redaction)
2. `ble:` reassembly CRC gate + trim + disconnect reset; signed R21 channels; mirror-queue backoff
3. `honesty:` calibration placeholders; strain prompt; markdown inline-only; body_hex strip; trusted label; avg-HR denominator; privacy toggle+disclosure
4. `rust:` panic=unwind + catch_unwind at FFI; toolchain pin
5. `docs/ci:` .gitignore, GOAL banner, README line, CHANGELOG 0.3.1, ci.yml, REVIEW.md
