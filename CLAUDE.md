# CLAUDE.md — whoop-local

> Read this fully at the start of every session. Then read `GOAL.md` for the current roadmap and progress.

## What this project is
A **local-first** companion for a **WHOOP 4.0** band. It reads biometric data directly off the band over Bluetooth LE, stores it on hardware the owner controls, and serves it to a self-hosted web dashboard. **No WHOOP app, no WHOOP cloud, no data leaving the user's machines.**

## Hard constraints (never violate)
- **Local only.** Data never leaves the user's own machines. No third-party cloud, telemetry, or analytics. Remote access is via the user's existing Tailscale network only — never expose ports to the public internet.
- **No WHOOP dependency.** Do not call WHOOP servers or require the WHOOP app to be installed/running.
- **We compute our own metrics; we do not claim to reproduce WHOOP's.** Recovery %, the exact 0–21 Strain, and WHOOP's sleep stages are proprietary and out of scope. Anything derived (HRV/RHR/stress/sleep-detection/strain-like) is *our own* computation, clearly labelled as such — never presented as "WHOOP's number."
- **Respect upstream licenses.** This project's code is original. You may study reference projects, but do NOT copy code from any repo without a license that permits it. `b-nnett/goose` has **no license** (all rights reserved) — do not copy from it. Before porting algorithms from `bWanShiTong/openwhoop`, `christianmeurer/whoop-reader`, or `johnmiddleton12/my-whoop`, check and honour their licenses and add attribution.
- **Health copy is careful and non-medical.** No diagnoses, no medical claims. These are raw signals and rough estimates.

## Architecture
```
band ──BLE──> collector (Python/bleak) ──> SQLite ──> FastAPI (read API) ──> web dashboard
                                                                              (served over Tailscale)
```
- **collector/** — connects to the band, subscribes to the data characteristic, decodes packets, writes time-series rows to SQLite. Also handles on-demand history backfill.
- **storage/** — SQLite schema + thin data-access layer. One file DB; trivial to back up.
- **api/** — FastAPI app exposing read endpoints over the stored data.
- **web/** — the dashboard (clean, dark, chart-first). Plain HTML+JS+a charting lib is fine; no heavyweight framework needed.

## Tech stack & conventions
- Python 3.11+. Type hints everywhere. Small, typed models over raw dicts/strings.
- BLE: `bleak` (cross-platform). API: `fastapi` + `uvicorn`. DB: stdlib `sqlite3` (add `sqlmodel` only if it clearly helps). Signal/HRV math (later phases): `numpy`/`scipy`.
- Lint/format with `ruff`. Keep functions small and testable. Pure decode logic must be unit-testable without a real device (feed it captured packet bytes).
- Config via a gitignored `.env` (copy from `.env.example`). Never commit device IDs, secrets, or `.db`/data files.

## Hardware reality (design around this)
- **One connection at a time.** A BLE peripheral talks to one central. While our collector is connected, the WHOOP app cannot be — which is fine, we're appless — but it also means the collector must be the sole owner of the link.
- **Range.** The collector must be physically near the band (~10 m). A stationary collector only captures when the user is in range, so the design is: **live-stream when near + periodic history backfill** of whatever the band buffered while away.
- **Finite onboard buffer.** The band stores only a limited window between syncs (the real archive lives in WHOOP's cloud, which we don't use). Sync often enough (e.g. nightly) that data doesn't roll off the end. Test empirically how far back a history pull reaches.

## Protocol facts (community-reverse-engineered; verify against the live device)
- Custom GATT service `61080001-8d6d-82b8-614a-1c8cb0f8dcc6`; command/response/event/data/diagnostic characteristics under the `6108000x-...` range. Data notifications arrive on `61080004-8d6d-82b8-614a-1c8cb0f8dcc6`.
- Real-time packets are **96 bytes**; the **last 4 bytes are a CRC-32** over the preceding 92.
- Decoded fields available: **heart rate, R-R intervals, SpO2, skin temperature, accelerometer**. Bytes ~20–91 are only partially decoded across projects (likely gyro / respiration / raw PPG waveform) — treat deeper channels as unverified until confirmed on this device.
- These are facts to *verify*, not gospel. Firmware differs; always confirm decode against real captured bytes.

## Run & test commands
- Set up: `python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`
- Collector: `python -m collector` (reads `.env` for device id / db path)
- API: `uvicorn api.main:app --host 0.0.0.0 --port 8000`
- Tests: `pytest -q`
- Lint: `ruff check .`
> If any of these don't exist yet, the current phase in `GOAL.md` is to create them. Keep this section accurate as the project grows.

## Definition of done (every increment)
1. Code written to conventions, with a unit test where logic is device-independent.
2. Tests pass (`pytest -q`) and `ruff check .` is clean.
3. The relevant checkbox in `GOAL.md` is ticked and a dated line is added to its Progress log.
4. A single focused git commit (do **not** push automatically).

## Human-in-the-loop (you cannot do these alone)
- Anything that needs the **physical band** — confirming live values, capturing real packets, validating a decode, measuring buffer depth — you must hand back to the user with exact step-by-step instructions. **Never fabricate or hard-code "sample" sensor values to make a test pass.**
- Never delete the database or captured data. Never push, deploy, or run destructive shell commands without explicit confirmation.
