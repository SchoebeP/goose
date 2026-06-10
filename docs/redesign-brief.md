# Goose (WHOOP 4.0 companion) — data & redesign brief

A self-contained brief for a designer redesigning the app. It covers **exactly
what data exists, what's real vs. stubbed, how to get it, the current screens,
and the rules**. Everything here is verified against the live system on
2026-06-10.

---

## 1. What the app is

A **local-first** companion for a **WHOOP 4.0** band. It reads biometrics off
the band over Bluetooth, stores them on hardware the owner controls, and shows
them in the owner's own app — **no WHOOP app, no WHOOP cloud**. All computed
metrics are **our own**, never presented as WHOOP's numbers.

**Hard product rules (must survive any redesign):**
- **Local-only / private.** Data goes only to the owner's own machines (iPhone +
  their own VPS over their private network). No third-party analytics.
- **Our own numbers.** Every derived metric is labelled as ours (e.g. "rMSSD —
  our own number"), never "WHOOP's recovery/strain/sleep".
- **Non-medical.** No diagnoses or medical claims — raw signals + rough
  estimates only.
- **Out of scope (proprietary, never shown):** WHOOP's Recovery %, the 0–21
  Strain score, WHOOP sleep stages.

---

## 2. Architecture / where the data lives

```
WHOOP 4.0 band ──BLE──> iPhone app (SwiftUI + embedded Rust core)
                            │  (decodes packets; shows live values)
                            └──HTTPS──> VPS (FastAPI + Postgres)
                                          │  (stores history; computes daily metrics)
                                          └──> app fetches it back as JSON feeds
```

Two sources of truth the UI can read:
1. **Live, on-device (BLE):** instantaneous values while the band is in range —
   heart rate, instantaneous HRV, battery, connection state.
2. **Server-computed (VPS):** everything aggregated over time — per-minute and
   per-day series with personal "usual range" bands. **This is where the rich
   data is**, because the band streams continuously to the VPS even though the
   on-device scorer only sees data during explicit capture sessions.

**Connectivity reality (affects empty states):** the band only streams when it's
in Bluetooth range of the phone (~10 m) and not the sole-owner conflict. Worn +
near = ~24 h/day coverage. Out of range or charging = gaps. **Heart rate is
backfillable** from the band's onboard buffer; **steps are not** (raw
accelerometer isn't buffered). So step history only exists for recently-streamed
days — design step views to show gaps honestly, never invent them.

---

## 3. THE DATA DICTIONARY — what's real, what isn't

Status legend: **REAL** = trustworthy values shipping now · **CALIBRATED** =
real and converted to physical units (coarse fit, provisional) · **RAW-ONLY** =
real signal but uncalibrated index · **STUBBED** = not computable from current
captures, do not design around it.

| Metric | Status | Typical range (this owner) | Cadence | Source |
|---|---|---|---|---|
| **Heart rate (live BPM)** | REAL | 50–130 bpm | ~1 Hz live | BLE type-40 / standard HR |
| **Heart rate (per-minute)** | REAL | avg/min/max per minute | 1/min | VPS `hr/minutely` |
| **HRV — instantaneous (rMSSD)** | REAL (noisy) | swings a lot | live | on-device, live R-R |
| **HRV — overnight (rMSSD)** | REAL | ~46–80 ms | 1/night | VPS, overnight R-R |
| **Resting HR** | REAL | ~50–58 bpm | 1/night | VPS, overnight low |
| **Respiratory rate** | **STUBBED / FAKE** | always ~15.4 rpm | — | `resp_raw` is a near-constant packet field: across 512,916 samples it has only **3 distinct values, 3073 in 99.1% of them** (15.4 = 3073÷200). It is **not a real measurement** — do not show it, same as SpO2. |
| **Skin / wrist temperature** | CALIBRATED | ~33–34 °C | 1/night | NTC thermistor + 2-point fit; coarse, provisional. (Verified real: 469 distinct raw values, clear overnight circadian curve.) |
| **Steps** | REAL | day total + per-minute | 1/min, live-only | VPS, accelerometer; NOT backfillable |
| **Sleep (duration / nights)** | REAL (our detection) | per-night minutes | 1/night | VPS `sleep/nights` |
| **Battery %** | REAL | 0–100 | event | band GET_BATTERY cmd (NOT the standard BLE char — that reads garbage on 4.0) |
| **Charging state** | REAL | on/off | event | battery-current sign |
| **Accelerometer (raw IMU)** | REAL | 3-axis, ~100 Hz | live | type-43 |
| **Stress / "energy"** | REAL (our estimate) | 0–100 | on-device | local HR-based estimate, iOS-side |
| **SpO2 (blood oxygen)** | **STUBBED** | — | — | **NOT computable.** Band emits only DC optical levels (red/IR), no pulsatile waveform; a real ratio-of-ratios SpO2 needs a raw red+IR PPG stream the band doesn't currently expose. **Do not show a number; either omit or show an honest "not available on this band" state.** |

**Two metrics are NOT real — design them out: SpO2 and Respiratory Rate.** Both
read packet fields that don't carry a live measurement (SpO2 = DC-only optical;
respiratory = a constant). The genuinely real set is: **heart rate, overnight
HRV, resting HR, skin temperature, steps, sleep, battery, accelerometer.**

**Personal "usual range" bands.** Every *daily* signal (HRV, resting HR,
respiratory, skin temp, steps, sleep) comes from the server with a personal band
`{lo, hi, mean}` over recent history plus an `in_usual_band` judgement and
`delta_vs_prev`. This is a strong design hook — show each value **relative to the
owner's own normal** ("in your usual range" / "lower than usual"), not against
population norms.

**Important data-freshness quirk (the redesign must handle):** the *current day*
often has only **resting HR** computed (a partial-day minimum that reads high);
HRV / respiratory / skin temp aren't computed until a night is fully processed,
so they're dated **yesterday**. Anchor "last night / recovery" cards on the most
recent **complete** night, not on "today", or you get one value filled and the
rest blank.

---

## 4. API — how a redesigned app gets the data

Base: `https://<your-vps>/whoop/ingest/...` — token-authed via header
`X-Ingest-Token` (the same token the app uploads with). All read endpoints take
`tz` (IANA, e.g. `Europe/Paris`) so "today" windows from the owner's local
midnight.

**Feeds a new app would consume:**
| Endpoint | Returns |
|---|---|
| `GET /ingest/hr/minutely?tz=` | today's HR per minute: `{minutes:[{minute,bpm,lo,hi,n}], count}` |
| `GET /ingest/steps/minutely?tz=` | today's steps per minute (accel-derived) |
| `GET /ingest/vitals/daily?days=14&tz=` | **daily recovery vitals** — `signals.{resting_hr,hrv_rmssd,respiratory_rpm,skin_temp_c}`, each `{series:[{date,value}], band:{lo,hi,mean}, latest, delta_vs_prev, unit}`. Fast (no frame scan). |
| `GET /ingest/trends?period=W\|M\|6M&tz=` | full trends: the four vitals **plus** `steps_per_day` and `sleep_minutes` (slower — scans raw frames for steps) |
| `GET /ingest/trends/last-night?tz=` | morning card: last night's value per signal + in-usual-band flags |
| `GET /ingest/sleep/nights?days=&tz=` | per-night sleep (our detection) |
| `GET /ingest/calibration/skin-temp` | skin-temp calibration state (ready? fit?) |
| `GET /api/hr/latest`, `/api/battery/latest` | latest single values |

Live values (HR now, instantaneous HRV, battery, connection) come straight from
the **on-device BLE client**, not these feeds.

---

## 5. Current app — screens & known IA problems

**Shipped tab bar (only 3):** **Today · Trends · More**.
Other screens exist in code but are **untabbed / unreachable**: a full Health
hub, and per-metric detail screens for **Recovery, Sleep, Strain, Stress,
Cardio Load, Energy Bank**, plus a Coach (LLM) view.

**Today** currently stacks: live HR hero · battery/connection chip · HRV+Steps
stat cards · hourly HR-range chart · hourly steps chart · stress/energy ·
(just-added) Recovery Vitals card (HRV / resting HR / respiratory / wrist temp).

**Trends:** W/M/6M switcher with resting-HR / HRV history etc.

**More:** device connect, capture/sync, debug, profile.

**Known problems a redesign should fix:**
- **Recovery has no home.** The richest data (overnight HRV/RHR/temp + personal
  bands + last-night-vs-usual judgement) had no reachable screen; it's currently
  bolted onto Today as a card. A redesign should give recovery/"this morning" a
  proper place.
- **SpO2 shows blank** because it isn't computable — needs an honest treatment,
  not an empty tile.
- **Live vs. overnight HRV are two different things** shown near each other
  (instantaneous noisy rMSSD vs. last night's resting rMSSD) — easy to confuse;
  the redesign should label/separate them.
- **Empty/stale states matter a lot** because of connectivity gaps — every view
  needs a graceful "band wasn't connected" state.

---

## 6. Visual / UX constraints

- **Dark, chart-first, mobile.** Readable one-handed.
- **Per-metric accent colors already exist** (heart red, HRV purple, activity
  green, sleep blue, range orange, charging yellow).
- **Honesty over polish:** show real gaps, label provisional metrics (skin temp,
  respiratory) as provisional, and never fabricate values to fill a layout.
- **"Our own numbers" framing** throughout; no WHOOP branding or proprietary
  scores.

---

## 7. One-line summary for the designer

> Design a private, dark, chart-first iPhone app around **heart rate (live +
> daily), overnight HRV, resting HR, calibrated skin temperature, steps, and
> sleep — each shown against the owner's own personal "usual range."** Give
> recovery/"this morning" a real home, handle connectivity gaps honestly, treat
> skin-temp as provisional (coarse calibration), and **omit SpO2 and Respiratory
> Rate — neither is a real measurement on this band.**

---

## 8. Appendix — real sample data (design with these)

**Daily vitals, last week (from `/ingest/vitals/daily`, this owner):**

| date | HRV (rMSSD) | Resting HR | Skin temp |
|---|---|---|---|
| 2026-06-05 | 80.2 ms | 57 bpm | 33.6 °C |
| 2026-06-06 | 71.0 ms | 54 bpm | 33.7 °C |
| 2026-06-07 | 62.7 ms | 60 bpm | 34.0 °C |
| 2026-06-08 | 74.2 ms | 55 bpm | 33.4 °C |
| 2026-06-09 | 73.5 ms | 58 bpm | 34.0 °C |
| 2026-06-10 (partial — today) | — | 77 bpm* | — |

\* today's resting HR reads high (partial-day minimum); HRV / skin temp for today
appear only after tonight is processed — the "today is partial" quirk from §3.
(Respiratory omitted — it's a constant placeholder, not a measurement.)

**Personal usual-range bands (example, current):** HRV `{lo 67, hi 80, mean 73}`
ms · Resting HR `{lo 51, hi 67, mean 59}` bpm · Skin temp `{lo 33.5, hi 34.0,
mean 33.7}` °C · Respiratory `{lo 15.34, hi 15.36, mean 15.35}` rpm.

**Live heart rate (Today chart, real):** e.g. avg 82 bpm, range 54–130 bpm over
the day, hundreds of per-minute points.

**Rough data volume held (≈, grows daily):** ~790k live HR samples · ~330k R-R
intervals · ~510k history samples (the channel rows: hr/rr/skin_temp_raw/
spo2_red/spo2_ir/resp_raw) · ~1.5M raw frames · ~300k IMU samples · spanning
~1 week of continuous wear. So **trend/history views have plenty to draw on.**

**Raw channels that exist but aren't surfaced (future hooks):** raw NTC
thermistor index (452–957, real), raw optical red/IR DC (the SpO2 inputs,
~444–691 / ~543–601 — DC only, can't make SpO2), full 3-axis ~100 Hz
accelerometer, and a per-frame `quality` flag. (The `resp_raw` field is a
constant — 3073 in 99% of samples — so it is **not** a usable respiration hook.)
