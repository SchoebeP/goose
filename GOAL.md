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
- (none yet)
