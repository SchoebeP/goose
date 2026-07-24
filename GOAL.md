# GOAL.md — roadmap & progress

## North star
A local-first WHOOP 4.0 companion: read my band's data over BLE, store it on my own machine, and view it in my own web dashboard — reachable over Tailscale, with nothing touching WHOOP's app or cloud.

## Non-goals (explicitly out of scope)
- Reproducing WHOOP's exact **Recovery %**, **Strain (0–21)**, or **sleep stages** — proprietary, not attempted.
- WHOOP Coach / AI insights, journal-behaviour correlations, community comparisons.
- Cloud sync, account features, OTA firmware updates, multi-user.
- Long-term cloud archive — we only ever have the band's finite onboard buffer.

## Target layout
```
whoop-local/
├── collector/        # BLE connect, decode, write to DB; history backfill
├── storage/          # SQLite schema + data access
├── api/              # FastAPI read endpoints
├── web/              # dashboard (static HTML/JS + charts)
├── tests/            # unit tests (decode logic, schema, api)
├── .env.example
├── requirements.txt
└── CLAUDE.md / GOAL.md / README.md
```

## Phases
Work top to bottom. Tick a box only when its acceptance criteria are met (see CLAUDE.md "Definition of done").

### Phase 0 — Scaffold
- [ ] Create the directory layout above with package `__init__.py` files.
- [ ] `requirements.txt` and `.env.example` (device id, db path, scan timeout).
- [ ] `.gitignore` covering `.env`, `*.db`, `data/`, `.venv`, `__pycache__`.
- [ ] A `pytest` harness that runs green with one trivial test.
- **Acceptance:** `pip install -r requirements.txt` and `pytest -q` both succeed on a clean checkout.

### Phase 1 — Connect + decode core vitals + persist
- [ ] `collector` scans for a device whose name starts with `WHOOP`, connects, subscribes to data char `61080004-...`.
- [ ] Verify the 96-byte packet's trailing CRC-32 before trusting a packet; drop bad ones.
- [ ] Decode **heart rate** and **R-R intervals**; write timestamped rows to SQLite.
- [ ] Unit test the decoder against **captured real packet bytes** (provided by the user — see Human-in-the-loop).
- **Acceptance:** live HR logged to DB matches the value shown by the whoomp web tool for the same band; decoder unit test passes on captured bytes.

### Phase 2 — Extended sensors
- [ ] Decode and store **SpO2**, **skin temperature**, **accelerometer**.
- [ ] Document each decoded byte offset in `collector/PROTOCOL.md` (our own notes, from our own captures).
- **Acceptance:** values move sensibly with reality (accel changes on movement; temp ~skin range; SpO2 ~90s when worn) and are unit-tested on captured bytes.

### Phase 3 — History backfill
- [ ] Implement the "download history" command path; parse the buffered historical packets.
- [ ] Dedupe and merge into the same SQLite tables (idempotent — re-running doesn't duplicate rows).
- [ ] Measure and record how far back a pull reaches; document the recommended sync cadence.
- **Acceptance:** running backfill twice produces no duplicate rows; gap between two live sessions is filled.

### Phase 4 — Read API
- [ ] FastAPI endpoints: live/latest sample, time-range history per metric, daily summaries.
- [ ] JSON, paginated, with sane defaults. No write endpoints.
- **Acceptance:** endpoints documented (FastAPI auto-docs) and covered by tests against a seeded test DB.

### Phase 5 — Dashboard
- [ ] Static web dashboard: live HR, and trend charts (HR, HRV, SpO2, temp) over selectable ranges.
- [ ] Clean dark theme, chart-first, readable on mobile. Empty/stale states handled gracefully.
- [ ] Confirmed reachable from another device over the user's Tailscale network.
- **Acceptance:** user can open it over Tailscale and see live + historical data.

### Phase 6 — Derived metrics (optional)
- [ ] After checking its license, port HRV / stress / sleep-detection / strain-like algorithms from `bWanShiTong/openwhoop`, computed locally. Label them clearly as our own estimates.
- **Acceptance:** each derived metric has a test and a short note on its method and limits.

### Phase 7 — Reliability / always-on
- [ ] Auto-reconnect on drop; backoff on failure.
- [ ] `systemd` unit so the collector starts on boot and restarts on crash.
- [ ] Scheduled nightly history backfill.
- **Acceptance:** collector survives a band walk-away/return and a reboot without manual intervention.

## Progress log
_(append dated entries here as work completes; newest at top)_
- 2026-07-24 — iOS app: prod UI cleanup — fixed the empty Trends tab and swept every user-visible screen for dash-forever fields. Root cause of "Trends is empty": `InkTrendsView` only ever read `.recovery`/`.sleep` trend rows, and those rows (plus `.strain`'s "Strain Score") were wired exclusively to the on-device Rust-bridge packet pipeline (`packetInputReports`/`packetScoreReports`), which only ever gets populated by Debug capture/algorithm screens — a normal user's session never runs it, so the rows were permanently empty regardless of how much real data the server had. The server's `/ingest/metrics/daily` feed (`ServerMetricsFeed`, already fully modeled as `ServerMetricsDay`) was already wired for *today's single value* in the Home ledger and Health Monitor detail vitals, but nothing fed its history into a multi-day chart. Added an independent, longer-window cache to `ServerMetricsFeed` (`trendDays`/`refreshTrendIfStale()`, capped at the server's own 31-day `METRICS_MAX_DAYS` limit so a "6M" selection honestly shows however many real days exist rather than implying six months it doesn't have) and a new `serverDailyTrendRow(...)` builder (`HealthDataStore+Vitals.swift`) mirroring the existing single-day pattern. Wired it in wherever a real per-day server field exists: recovery's HRV/RHR/resp/temp(calibrated-only)/score, sleep's time-asleep and HR-dip (plus REM/deep sleep-stage trends pre-wired for when the backend's sleep-stage bugs are fixed — self-healing, no further iOS work needed), strain's score, and a new standalone "Stress Index" row for the server's Baevsky index+band (kept separate from the existing on-device intraday "Stress Score" timeline used by the Stress detail screen, which is a different metric on a different time axis and was left untouched). `InkTrendsView` now pulls all four groups instead of two, and observes `ServerMetricsFeed` directly so the screen redraws the instant the fetch resolves instead of waiting on an unrelated re-render; added a "Loading trends…" state distinct from the honest "not enough history yet" empty state. This same fix flowed through for free to the Recovery/Sleep/Strain detail screens' own "Trends" sub-sections, which read the identical underlying functions and were equally always-empty before. Also swept More > Privacy/Support/About: these were showing raw file-system paths, internal Rust-core/schema build versions, a raw BLE handshake string, and — worst offender — a "Data Deletion" row that was a permanently disabled dead button (`deletionStatus` hardcoded to "Deletion bridge not wired", never assigned anywhere) next to a "Data Export Link" stub pointing at the already-Dev-only Raw Export feature. Dev-gated the engineering-flavored rows (export-hygiene lint, diagnostic bundle paths, Rust core/schema/raw-handshake) behind `#if DEBUG` + `DeveloperSettings.shared.isEnabled`, removed the dead export-link stub, and replaced the fake deletion button with a plain, honest statement of current reality (no in-app deletion yet; uninstalling removes the local database) — never a control that does nothing. Verified Debug and Release both still build clean with zero new warnings (`xcodebuild ... -configuration {Debug,Release} build`). Not touched (flagged for the next pass, not this mission's stated scope): the Strain detail screen's "Activities" section shows a real (non-fabricated) status message, but that message describes the local packet-score pipeline rather than actual recorded-workout state, so it can read as stale/mismatched once Strain itself is showing real server data above it; legacy dead `TrendsView.swift` (superseded by `InkTrendsView`, unreferenced by any call site, same category as the already-known-dead `MoreView.swift`/`HomeDashboardView.swift`) still defines the shared `TrendPeriod` enum `InkTrendsView` depends on, so left in place.
- 2026-07-24 — iOS app: Dev/Clean build-flavor split. Added `GooseSwift/DeveloperSettings.swift` as the single gating mechanism (documented inline) — an `ObservableObject` whose `isEnabled` toggle only exists in Debug builds (persisted, defaults true) and is a hardcoded `false` in Release with no toggle UI at all. Inventoried and gated every developer-facing surface behind `#if DEBUG` at its registration/navigation site (compiled out of Release, not just hidden — verified via `nm`/`strings` on the built Debug vs Release binaries): the More-tab Connection Lab, Capture, Local Store, Raw Export, Algorithms (operational picker), Debug (the mega diagnostics screen: parser probes, packet capture, raw research BT commands, internal QA tooling), and Developer hub screens/rows; the More-list "Packet Inspector" link to the raw VPS byte inspector; the Device screen's "Advanced" tab (firmware/Rust/raw event log/BLE action grid); the `gooseswift://debug-command/<id>?payload=<hex>` deep link that could push arbitrary raw BLE commands (now a hard no-op in Release); the Sleep Alarm sheet's "Band write diagnostics" raw-hex disclosure; and — found via a full reachability trace, not just the More tab — the live Home-tab ledger's "Packet Inputs" / "Algorithms" / "Calibration" cards (`PacketHealthView`/`AlgorithmsHealthView`/`ReferenceComparisonsView`/`CalibrationHealthView`), which were surfacing raw feature-extraction and ML-calibration internals to every user regardless of build. The one "Developer" hub entry point stays reachable in Debug regardless of the toggle, so turning dev tools off never strands you. Both Debug and Release build clean (`xcodebuild ... -configuration {Debug,Release} build`, zero warnings in touched files). Pre-existing dead code left untouched (out of scope, unreachable in both flavors already): legacy `MoreView.swift`/`HomeDashboardView.swift` (superseded by the Ink views), and everything only reachable through the untabbed `.health`/`.available`/`.cloudOnly`/`.coach` tabs.
- 2026-07-22 — Rust core: decode V24 normal-history biometric fields (R-R, PPG, gravity, skin contact, SpO2/temp/resp/signal-quality raw ADCs; reference-verified offsets, pending on-band confirmation), BATTERY_LEVEL/EXTENDED_BATTERY event fields (SoC, current, charging bit), and WRIST_ON/OFF → on-wrist state. 6 new unit tests; protocol suite green.
- (none yet)
