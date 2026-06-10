# Changelog

## 0.3.0 — 2026-06-10

Security + hardening release: a 67-finding multi-agent audit, all remediated
(64 fixed, 2 documented partials). Full detail in `docs/audit-2026-06-10.md`.

### Security & privacy
- **VPS ingest token no longer hardcoded** — resolved via `IngestCredentials`
  with a `whoopIngestToken` runtime override. **Rotate the token on the VPS**
  (the old value shipped in the public repo and is compromised).
- Coach only uploads the local health summary when the question needs it
  (`tool_choice` auto, was forced every turn); chat transcript moved from
  plaintext UserDefaults to a file with complete file protection; consent
  copy now tells the truth. Accidental 832K biometric export untracked.

### Reliability (BLE & overnight)
- Bluetooth toggle / bluetoothd reset no longer strands the app disconnected
  until relaunch — full teardown + reconnect on every power-on.
- Stale-link heal no longer tears down healthy 5.0 / standard-HR connections.
- V5 historical backfills stop being retried-then-reported-failed (type-47/52
  counter fix); preserve-unread mode can no longer trim the band's queue.
- Cloud forwarder: CRC-validated frames (verified against real captures),
  reassembly reset across connections, disk outbox for failed HR/R-R posts,
  no more double-uploads, timed tail flush for logs/frames.
- Overnight guard: final-sync wedge fixed (streams resume + retry), spool
  writes off the CoreBluetooth queue, status writes throttled.
- Workouts survive app kill/crash (5s recovery snapshots, finalized on next
  launch); pause no longer teleports distance; elevation gain uses an
  accuracy-aware deadband; summary metrics are honest (no +12s/+2kcal).

### Correctness (our own metrics)
- Sleep/recovery scored against **local midnight** (was UTC — wrong for
  Europe/Paris); HRV/RHR daily buckets use the local-day window.
- Metric windows use device sample time, not phone sync time (history
  bursts no longer collapse durations to ~0).
- Step estimator defaults to the field-verified 100 Hz accel rate.
- SQLite: transactional migrations w/ stranded-rebuild recovery, atomic
  algorithm-run inserts, busy timeout; exports snapshot via VACUUM INTO
  (no more torn copies of the live DB).

### Performance
- Stress/energy summaries memoized (~18 full 100k-sample scans per render
  → ~1 per update); score runs off the main thread; HR series persisted in
  30s batches (was a multi-MB rewrite per second); Today cards' 30s refresh
  survives re-renders and surfaces server errors.

### Dev
- `cargo test` runs green on this checkout: 711 passed, 0 failed (was: did
  not compile; HealthKit privacy-boundary guard tests now actually run).

## 0.2.0 — 2026-06-06

Full UI redesign + a packet-analysis workbench on the VPS.

### App (Apple-Health-clean redesign)
- **3-tab structure** — Today / Trends / More (was Home / More).
- **Today** — design-system cards (`GooseTheme` accents, flat `gooseCard` surfaces):
  64pt live-BPM hero with LIVE badge, battery/connection chip in the header,
  HRV + Steps stat cards (ours-labelled), hourly HR range bars with day average,
  hourly steps bars. Tap the HR or Steps card for an **hour-by-hour drill-down**
  (selectable bars, chevron stepping, per-hour list).
- **Trends** (new) — W/M/6M switcher; resting-HR/HRV trend cards when history
  exists; honest empty states for steps history and our own sleep estimate.
- **More** — regrouped (Device / Band / Capture & Sync / Debug / Profile & Info),
  decoded-band summary moved here from Today, link to the VPS Packet Inspector.
- **Charts reset at local midnight** — the minutely feeds send the phone's
  timezone and the server windows "today" from the user's midnight.

### VPS (whoop-band repo)
- **Packet Inspector** at `/inspector` — frame browser over `raw_frame` with
  type/time filters, registry-annotated hex view (decoded vs unknown bytes),
  byte-offset-over-time plotting with HR/accel overlays + Pearson r, server-side
  auto-scan correlation ranking, CSV export. 27 unit tests on real captured frames.
- Minutely HR/steps endpoints accept an IANA `tz` for local-midnight day windows.

## 0.1.0 — 2026-06-05

First stable cut of the local-first WHOOP 4.0 companion: the band streams to the
iPhone app over Bluetooth, which forwards to the self-hosted VPS for processing
and display. No WHOOP app, no WHOOP cloud.

### Working end-to-end
- **Live heart rate** off the band over BLE (GEN4).
- **Accurate battery** via `GET_BATTERY` (the `0x2A19` characteristic reads garbage
  on GEN4 and is ignored).
- **Charging detection** from the signed battery current (int16-LE at offset 20 of
  the BATTERY_LEVEL/EXTENDED_BATTERY_INFORMATION events) — reliable even though the
  band drops its CHARGING_OFF events.
- **Steps** computed server-side from the raw accelerometer (band-pass 0.6–3 Hz +
  peak-count). Our own count, not WHOOP's.
- **Pulse waveform + HRV (RMSSD)** from the raw optical/PPG signal — our own work.
- **Background / locked capture** — `bluetooth-central` + state restoration keep the
  stream flowing to the server with the screen off (verified live).
- **Self-healing connection** — recovers from zombie (dead-handle) links, silent
  stalls (no data > 70 s), and heals on app foreground.
- **Disk-backed offline outbox** — raw frames survive internet outages and upload
  (stamped at their capture time) when connectivity returns; survives an app kill.
- **Diagnostic log streaming** to the VPS for live debugging.
- **Dashboard + app views** — live pulse, minute-by-minute HR (candlesticks), steps,
  battery, accurate charging state.
- **CI/CD** — push to `main` → multi-arch image build → Portainer redeploy (arm64 VPS).

### Known limitations (honest)
- **HR history backfill is built but unproven** — the band ignores our GEN4 history
  request (0 type-47 frames returned so far); the request payload still needs
  cracking. A band-disconnect gap (phone dead / out of range) is currently lost.
- **Steps / pulse / HRV are live-only** — never recoverable for a gap (the raw
  streams aren't buffered on the band).
- **Decoded-HR samples + diagnostic logs** still upload fire-and-forget; only the raw
  frames are outbox-protected (frames reconstruct everything server-side).
- **Gyroscope** not yet decoded. **SpO2 / sleep / recovery / strain** intentionally
  out of scope (proprietary / cloud-only).
- Continuous BLE streaming drains the phone faster — keep it charged for long capture.

### Field-verified protocol facts
See `CLAUDE.md` → "Field-verified on the live device" for the confirmed GEN4 framing,
battery/charging decode, stream offsets, and the iOS background-connection gotcha.
