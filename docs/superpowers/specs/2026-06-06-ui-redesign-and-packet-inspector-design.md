# UI Redesign + VPS Packet Inspector — Design Spec

**Date:** 2026-06-06
**Status:** Approved by user (visual companion session `.superpowers/brainstorm/10109-1780731349`)
**Mockups:** `scope.html`, `navigation.html`, `visual-style.html`, `design-overview.html`, `packet-inspector.html`, `web-inspector.html` in that session's `content/` directory.

## Summary

Two independent work streams, executed on parallel branches by background agents:

- **Branch A — `ui-redesign` (this repo, `GooseSwift/`):** full redesign of the iOS app — design system, navigation, and screens — in an **Apple Health clean** visual style with a **3-tab** structure (Today / Trends / More). UI-only: no changes to BLE, parsing, stores, or upload pipelines.
- **Branch B — `packet-inspector` (repo `~/PycharmProjects/whoop-band`, `backend/`):** a web-based **Packet Inspector** page on the VPS dashboard for analysing raw band frames from the `raw_frame` Postgres table — frame browser, annotated hex view, byte-offset-over-time plotting with auto-scan correlation ranking.

The two streams touch disjoint repos; there is no shared file, so they can run fully in parallel.

## Decisions made during brainstorming

| Question | Decision |
|---|---|
| Scope | **C** — full redesign: design system + layout + navigation |
| Navigation | **B** — 3 tabs: Today / Trends / More |
| Visual style | **B** — Apple Health clean (native iOS, soft dark cards, per-metric accent colors, SF typography) |
| Raw-data analysis UI | On the **VPS web dashboard**, not in the app |

---

## Branch A — iOS app redesign (`GooseSwift/`)

### A1. Design system (`GooseTheme.swift` expansion)

Extend `GooseTheme` into a real design system; all redesigned screens consume it:

- **Palette:** pure-black screen background (`#000` dark / system light), card background `#1C1C1E` (dark) / `.secondarySystemGroupedBackground` (light). Per-metric accent colors, Apple-Health style: heart `#FF375F`, HRV `#BF5AF2`, steps/activity `#30D158`, battery `#30D158`/`#FFD60A` (charging), sleep `#64D2FF`, range/strain `#FF9F0A`.
- **Typography:** SF (system); large title 19–34 semibold/bold for screen titles, big metric numerals `.system(size: 30–40, weight: .semibold)` + `.monospacedDigit()`, metric-label style: caption-size, accent-colored, with SF Symbol icon.
- **Cards:** corner radius 14, padding 12–16, no borders/shadows in dark mode; one shared `gooseCard()` view modifier replaces today's ad-hoc `Color.secondary.opacity(0.08)` backgrounds.
- **Charts:** thin-line sparklines and rounded bar/range marks tinted with the metric accent; shared chart primitives reused across Today and Trends.
- Both light and dark mode must look intentional (the palette above adapts via dynamic colors, as `GooseTheme` already does).

### A2. Navigation (`AppShellView.swift`, `AppRouter.swift`)

- `GooseAppTab.allCases` becomes `[.today, .trends, .more]` (rename `home` → `today` or keep the case and retitle "Today"; new `trends` case).
- Tab icons: `heart.fill` (Today), `chart.line.uptrend.xyaxis` (Trends), `ellipsis.circle` (More).
- Health/Coach/Available/Cloud views stay hidden (code remains, untabbed) — unchanged from today.
- Existing deep links (`HealthRoute` pushes from Home) keep working from Today.

### A3. Today tab (rework of `HomeDashboardView.swift` + `Home*` views)

Top to bottom:

1. **Header:** "Today" + date; trailing **device chip** (small capsule: connection dot + battery % + charging bolt) replacing the toolbar watch icon — tap opens `DeviceView`.
2. **Heart-rate hero card:** "Heart Rate" label (heart accent), big live BPM + "LIVE" badge when fresh (<15 s), recent sparkline underneath (reuse the live HR data already on `GooseBLEClient`).
3. **Stat card row:** HRV (rMSSD, "ours" provenance caption) and Steps (from accel, "ours" caption) — data already available (`liveHRVRMSSD`, `MinutelyStepsFeed.total`).
4. **HR range card:** today's per-minute lo→hi as rounded **range bars** (replaces the candlestick chart; same `MinutelyHRFeed` data) with min–max summary caption.
5. **Steps chart card:** per-minute bars, restyled (same `MinutelyStepsFeed` data).
6. The current "Decoded from your band" card is **dropped** from Today (its content moves to the More tab's band section). The existing stress/energy section **stays**, restyled into the new card system — no new data work, reskin only.

### A4. Trends tab (new `TrendsView.swift` + small subviews)

- Segmented period switcher: **W / M / 6M**.
- Trend cards, each with average value, delta arrow vs previous period, and a line/bar chart:
  - **Resting HR** and **HRV** — from existing `HealthDataStore` trend/recovery data (`HealthDataStore+Trends.swift`, daily metric snapshots).
  - **Steps/day** — daily totals; if no daily-aggregate source exists yet, derive client-side from the existing minutely steps endpoint for the displayed window, else show an honest empty state.
  - **Sleep (our estimate)** — reuse the existing SleepV2 data the app already computes; clearly labelled as our own estimate.
- **Rule: charts only render for data that actually exists.** Missing data ⇒ designed empty state ("not enough history yet"), never fabricated values.

### A5. More tab (`MoreView.swift` regroup + restyle)

- Regrouped sections in the new card style: **Device** (status, battery, connection), **Band** (the decoded-channels summary that used to sit on Home), **Capture & Sync**, **Debug**, **Profile/Info**.
- A link row "Packet Inspector → on your dashboard" pointing at the VPS inspector URL (display-only convenience; the inspector itself is Branch B).
- All existing functionality is preserved — this is reorganisation + reskin, no removed tools.

### A6. Hard constraints (from CLAUDE.md — apply everywhere)

- Our computed metrics are labelled as **ours** (HRV, steps, sleep estimate); never presented as WHOOP's numbers. No recovery %/0–21 strain claims.
- Non-medical copy only.
- **UI-only branch:** no edits to `GooseBLEClient*`, parsing, stores' write paths, upload/ingest pipelines, or `Info.plist` capabilities.

### A7. Verification (agents cannot see rendered SwiftUI)

- Every increment must compile: `xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'generic/platform=iOS' build` (or the project's known build invocation).
- **User checkpoints are part of the definition of done:** after (1) design system + navigation, (2) Today, (3) Trends, (4) More, the user builds and eyeballs on a device/simulator before the next stage proceeds. Agent "done" claims without a user-verified build do not count.

---

## Branch B — VPS Packet Inspector (`whoop-band/backend/`)

### B1. What it is

A new dashboard page `GET /inspector` (HTML, served by the existing FastAPI app like `dashboard.html`), three panes, reading `raw_frame` (`received_at`, `packet_type`, `packet_name`, `seq`, `crc_ok`, `frame_hex`):

1. **Frame browser (left):** newest-first list with packet type/sub-type chips (40, 43.0, 43.41, 47, 52, …), time-range picker (defaults to last 24 h), pause/live toggle (poll every few seconds), unknown types visually flagged. Pagination/lazy-load; never ship the whole table.
2. **Hex view (middle):** selected frame as a hex grid; byte ranges color-coded from the **decode-coverage registry** (header, decoded fields, CRC, unknown). Click a byte (or drag a 2–4-byte range) → interpretation panel: u8, i16/u16 LE, u32 LE, float, and the registry's label if known.
3. **Offset plot (right):** for a chosen (packet type, offset, interpretation): value-over-time chart for the selected window, optional overlay of a known signal (HR from `hr_sample`, accel magnitude from `imu_sample`) with a Pearson r readout, and **CSV export** of the plotted series.

### B2. Decode-coverage registry

A static, code-reviewed Python module (e.g. `backend/api/decode_registry.py`) describing, per packet type/sub-type: name, decode status (`decoded`/`partial`/`unknown`), and labelled byte ranges (e.g. type 40: header 0–6, HR @7, R-R @8–11, CRC last 4). Sources: the parsing logic in `GooseSwift/GooseBLEClient+Parsing.swift` and the field-verified facts in this repo's CLAUDE.md. The registry drives both the hex-view coloring and a **coverage summary strip** on the page (per-type ✓/◐/✗ + % bytes decoded). Sub-type for type 43 is extracted from the frame bytes server-side.

### B3. API endpoints (FastAPI, same auth pattern as existing endpoints)

- `GET /api/frames?type=&since=&until=&limit=&before_id=` — frame list (id, time, type, name, seq, crc_ok, length).
- `GET /api/frames/{id}` — full `frame_hex` + registry annotations.
- `GET /api/frames/offset-series?type=&offset=&interp=&since=&until=` — decoded series + optional `overlay=hr|accel` aligned series; also `&format=csv`.
- `GET /api/frames/auto-scan?type=&since=&until=` — server sweep of every offset × {u8, i16LE, u16LE} correlated against HR / accel / time-of-day; returns top-N ranked hits. Bounded window (e.g. max 6 h of frames) so it can't melt the VPS.
- `GET /api/decode-coverage` — the registry as JSON.

### B4. Implementation conventions

- Python 3.11+, type hints, small testable functions; hex/interpretation/correlation logic is pure and unit-tested (`pytest`), `ruff` clean — per this project's conventions, which the whoop-band repo shares.
- Front end: plain HTML + JS + the chart approach already used by `dashboard.html` (no framework), dark GitHub-ish palette per the approved mockup.
- Access stays Tailscale-only with the existing token/auth pattern; **no new public exposure**.
- Deploy follows the repo's existing path (push → GitHub Actions multi-arch → Portainer); deploy only with explicit user confirmation.

### B5. Verification

- Unit tests for: hex parsing/annotation, interpretation decoding, series extraction, correlation math (captured real `frame_hex` rows as fixtures — never fabricated sensor values).
- User checkpoint: open `/inspector` against the live VPS and confirm frames render before the branch is called done.

---

## Execution plan

1. Branch A agent works in a git worktree `ui-redesign` of this repo; Branch B agent works in a worktree of `~/PycharmProjects/whoop-band`.
2. Each branch follows its repo's definition of done (tests, lint, focused commits; **no auto-push, no deploy without confirmation**).
3. User review checkpoints as defined in A7/B5; final integration (merge/PR) is decided by the user per branch.

## Out of scope

- Reviving the Health / Coach / Available / Cloud tabs.
- New metric computation (recovery scores, respiration, type-52 decoding) — the inspector is the *tool* for that future work, not the work itself.
- Any change to BLE/ingest pipelines or data schemas other than read-only queries over `raw_frame`.
