# Handoff: Goose — Direction A "Quiet Companion" (iOS health-band companion app)

## Overview
Goose is a local-first iOS companion app for a WHOOP 4.0 band that the user runs **without** WHOOP's cloud — all metrics are computed by the app/user's own server ("our numbers, never WHOOP's"). This handoff covers the chosen design direction (**Direction A · Quiet Companion**): a dark, calm, chart-first 4-tab app that finally gives overnight recovery data a first-class home.

Target implementation: **SwiftUI** (the user's existing Swift app). Recreate the screens natively — SwiftUI views, Swift Charts (or custom `Canvas`/`Path` drawing for the band charts), `TabView`, `NavigationStack`.

## About the Design Files
The files in this bundle are **design references created in HTML/React** — interactive prototypes showing the intended look and behavior. They are NOT production code to copy. The task is to **recreate these designs in the Swift app** using its established patterns (SwiftUI, Swift Charts, etc.). The HTML is the source of truth for visuals, spacing, copy, and interaction behavior; read it for exact values.

- `Goose Prototype A.html` + `proto-*.jsx` — the interactive prototype (START HERE)
- `Goose Redesign.html` + `goose-screens-*.jsx` — the wider static exploration canvas (3 directions; A won)
- `goose.css` — all design tokens (colors, type, spacing, radii)
- `goose-charts.jsx` — exact chart-drawing logic (band trend, day HR ranges, step bars, sleep bars, gap hatching)
- `goose-data.js` / `proto-data.js` — sample data shapes & values

## Fidelity
**High-fidelity.** Colors, typography, spacing, copy, and interactions are final design intent. Recreate pixel-faithfully, substituting platform-native equivalents where appropriate (SF symbols ↔ the line icons, system blur for tab bar, etc.).

## Product principles (bake these into implementation)
1. **Honest gaps.** When the band is away/out of range, charts show hatched gap regions — never interpolate. Copy states whether data backfills: heart rate DOES (band buffers it), steps DON'T (permanent gaps).
2. **Anchored to the last complete night.** The Morning tab always shows the most recent fully-processed night (e.g. "Night of Jun 8–9"), never a half-built "today". Today's partial resting HR is explained, not displayed as truth.
3. **Personal bands, not population norms.** Every vital is judged against the user's own usual range (lo–hi learned from recent history). Status copy: "usual" / "top of usual" / "above usual" / "below usual".
4. **Two HRVs, separated.** Overnight rMSSD (one number/night, the one to watch) vs live HRV (noisy, last few minutes). Never visually conflated.
5. **Provisional metrics** (wrist temp, respiratory rate — coarse calibration) are marked with a quiet asterisk `*` and a single footnote: "* provisional — coarse skin-temp & respiratory calibration".
6. **No SpO2 anywhere. No WHOOP recovery score.** No sleep stages (copy explains why: "the band doesn't give us enough to do them honestly").
7. **Local-first privacy** statement on More tab.

## Information architecture
4 tabs (`TabView`):
| Tab | Icon idea (SF Symbol) | Contents |
|---|---|---|
| Today | `waveform.path.ecg` | Live HR hero, day HR range chart, steps, live HRV tile, energy tile |
| Morning | `sunrise` | Editorial headline, 2×2 overnight vitals grid, sleep card, partial-today note |
| Trends | `chart.xyaxis.line` | W/M/6M segmented control, HRV + RHR full cards, temp + resp half tiles, sleep bars, steps/day |
| More | `ellipsis` | Band/battery card, settings rows, privacy statement |

Pushed details (`NavigationStack`): **Sleep detail** (from Morning sleep card), **HRV detail** (from Morning HRV tile or Today live-HRV tile).

## Design tokens (from `goose.css`)
### Colors — surfaces & text (dark only)
- Background `#0B0E13`; card surface `#131823`; raised `#1A2130` / `#222A3C`
- Hairline `rgba(168,184,214,0.10)`, strong hairline `rgba(168,184,214,0.18)`
- Text primary `#E9EDF5`, secondary `#A7B0C0`, tertiary `#6F7889`

### Colors — per-metric accents ("Signal" palette, the default)
- Heart `#FF8177` · HRV `#B9A3FF` · Activity/steps `#8BD9A9` · Sleep `#86B9FF`
- Out-of-range/warn `#FFB876` · Battery/energy `#FFD479` · Respiratory `#74D6CF` · Temp `#FFA98F`

### Pill backgrounds (status chips)
- ok: `rgba(139,217,169,0.13)` text activity-green · warn: `rgba(255,184,118,0.14)` text orange
- muted: `rgba(168,184,214,0.10)` text secondary · live: `rgba(255,129,119,0.13)` text heart-red

### Typography
- Display/numerals: **Schibsted Grotesk** Bold (700), tracking −0.02em, tabular numerals. (iOS fallback: SF Pro Rounded or SF Pro Display Bold with monospaced digits.)
- Body: **Albert Sans** (400/600). (iOS fallback: SF Pro Text.)
- Card section titles: 13px, 600, uppercase, +0.06em tracking, secondary color
- Hero numerals: 58px (Today HR), 48–52px (detail heroes), 28–34px (card values), 24px (half tiles)
- Body 15px, sub 14px, captions/footnotes 11–12.5px
- Screen H1: 28px/700, −0.015em

### Shape & spacing
- Card radius 20px, chip radius full, badge radius 5px
- Card padding 16×18; screen gutter 20px; inter-card gap 14px (a density multiplier `--u` scales paddings/gaps: compact 0.78, comfy 1.12)
- Cards: surface bg + 1px hairline border, no shadows

## Screens — layout & content
(Exact copy strings are in the JSX; key structure below.)

### Today
1. Header: "Today" + date sub; right: muted pill "Band · 64%".
2. **Heart rate card**: title row w/ red dot + "live" pill (pulsing dot, 1.6s ease pulse); 58px live bpm numeral (ticks ~1Hz, ±small random walk 58–96) next to a small live sparkline; caption "From the band over Bluetooth · day range 54–130 · avg 82"; **day HR chart** (per-hour lo–hi rounded vertical bars in heart color at 55% opacity, 45–135 bpm scale, gridlines at 60/90/120, hatched columns for away-hours 13:00–15:00); gap note "Band was away 13:00–15:00 — HR backfills next sync".
3. **Steps card**: 34px total "7,392" + muted pill "so far today"; hourly bars (activity green, zero-hours show 2px stubs, hatched gap columns); gap note "Steps only count while connected — gaps stay gaps".
4. Two half tiles: **Live HRV** (61 ms, caption pointing to overnight) → pushes HRV detail; **Energy** (72/100, "Our HR-based estimate, computed on this phone").
5. **Band-away state** (the prototype's "Band out of range" tweak): HR numeral becomes "—" in tertiary color, live pill → "out of range", copy explains backfill; steps pill → "paused — band away".

### Morning
1. **Hero card** with vertical gradient from 9% HRV-purple mix → surface: overline "NIGHT OF JUN 8–9 · JUST PROCESSED" (11.5px caps), headline "A mostly usual morning." (27px display), sub explaining which vitals sit where.
2. **2×2 vitals grid** (columns must be `minmax(0,1fr)`-equivalent; tiles never clip): HRV 73.5 ms · Resting HR 58 bpm · Respiratory* 15.4 rpm · Wrist temp* 34.0 °C. Each tile: dot+caps title, 30px value, **band gauge** (132×14 track: full-width 3px line, thicker 6px tinted segment for the usual band, 4px value dot with bg ring), status pill ("usual" / "above usual" / "top of usual"). HRV tile pushes HRV detail.
3. Footnote: "* provisional — coarse skin-temp & respiratory calibration".
4. **Sleep card** → pushes Sleep detail: "7h 12m" (34px) + ok pill "close to your 7h 24m average"; caption "Detected by us from movement + HR — not WHOOP sleep stages".
5. Note row (moon icon): today's partial RHR (77 bpm) reads high; check back tomorrow.
6. Centered footnote: "Judged against your own last weeks, not population norms. Our numbers, never WHOOP's."

### Trends
1. Segmented control W / M / 6M (animated selection; W = real 5 days, M/6M = longer series).
2. Full cards for **Overnight HRV** and **Resting HR**: value + delta chip ("▼ 0.7 ms vs prev" green when good), **band-trend chart**: shaded usual-range band (10% accent), dashed mean line, 2px value line with terminal dot, right-edge band labels, first/last x labels. At 30/180 points: thinner line, only terminal dot.
3. Half tiles: Wrist temp* and Respiratory* (same chart at 140×64) + shared provisional footnote.
4. **Sleep** card: per-night rounded bars vs dashed 7h30 goal line (last night emphasized at full opacity).
5. **Steps per day**: daily bars with hatched columns for no-wear days; gap note "Only days the band streamed — step history can't backfill".

### More
1. **Band card**: 46px rounded-square icon well, "WHOOP 4.0 band / Connected · in range", right-aligned 64% + "not charging".
2. Settings rows (hairline-divided): Capture & sync (sub: "Last sync 2 min ago · backfilling HR buffer"), Skin-temp calibration (prov. badge), Coach ("Ask questions about your own data"), Debug & developer.
3. **Privacy card** (lock icon, green): "Local-first. Your data moves between this phone and your own server — nowhere else. No analytics, no third parties, no WHOOP cloud. Every number here is computed by Goose."
4. Centered footnote: "Goose 0.4 · not a medical device · raw signals & rough estimates only".

### Sleep detail (pushed)
Hero "7h 12m" (52px), pills "in bed ~23:10 – 06:40" + "near your average", honesty caption about no sleep stages; "This week" sleep bars; "Nights" list rows (date + duration).

### HRV detail (pushed)
"Two different numbers — don't mix them" sub. Card 1: **Overnight HRV · rMSSD** 73.5 ms + usual-range pill, explanation ("One number per night, from thousands of R–R intervals… the one to watch"), 5-night band trend, "Your usual: 67–80 ms / mean 73 ms". Card 2 (dashed border): **Live HRV** 61 ms in secondary color + live pill + sparkline, explanation that it swings with breath/posture. Card 3 (lock): "rMSSD is our own calculation, on your hardware. It is not WHOOP's recovery score, and we don't make one."

## Interactions & behavior
- Tab switch: 0.24s ease fade+8px rise of incoming screen. **Important lesson from the prototype:** never play entrance animations when the app/scene is backgrounded or on first mount-while-hidden; gate on scene visibility.
- Detail push: 0.28s `cubic-bezier(0.2,0.8,0.2,1)` slide-in from right with left shadow; pop reverses in 0.22s. (In SwiftUI just use `NavigationStack` default push.)
- Live HR: update ~1 Hz with smooth random walk while connected; freeze to "—" when band away.
- Tappable cards: pressed state ≈ brightness +18% & scale 0.985 (0.15s).
- All hit targets ≥ 44pt. Respect Reduce Motion (disable fades/pulses).
- Persist last selected tab across launches.

## State management (suggested)
- `BandConnectionState`: connected / outOfRange / charging — drives Today hero, pills, steps pause copy.
- `MorningReport?`: latest fully-processed night (date label, hrv, rhr, resp, temp, sleepMinutes) — nil ⇒ first-run empty state.
- `PersonalBands`: per-metric `{lo, hi, mean}` learned from history (sample: HRV 67–80 mean 73 ms; RHR 51–67 mean 59; temp 33.5–34.0 mean 33.7 °C; resp 15.34–15.36 mean 15.35 rpm).
- `TrendPeriod`: .week/.month/.sixMonths.
- Hour series with explicit `gap` flags (never nil-as-zero).

## Data shapes
See `goose-data.js` (real sample values from the product brief) and `proto-data.js` (synthesized M/6M demo series, deterministic seeded generator). Note: sleep durations are placeholder values — wire to real detection output.

## Assets
No bitmap assets. Icons are 1.7px-stroke line glyphs (22×22) drawn inline — map to SF Symbols. Fonts: Schibsted Grotesk + Albert Sans (Google Fonts; or substitute SF Pro equivalents).

## Files in this bundle
- `Goose Prototype A.html`, `proto-shell.jsx`, `proto-screens.jsx`, `proto-app.jsx`, `proto-data.js`, `proto.css` — interactive prototype
- `Goose Redesign.html`, `goose-app.jsx`, `goose-screens-a/b/c.jsx` — exploration canvas (context; Directions B/C were not chosen)
- `goose-ui.jsx` — shared primitives (icons, pills, gauges, tab bar)
- `goose-charts.jsx` — chart math & rendering (port this logic)
- `goose.css` — design tokens
- `goose-data.js` — sample data

## Suggested Claude Code kickoff prompt
> Implement the "Direction A · Quiet Companion" design from design_handoff_goose_direction_a/ in my SwiftUI app. Read README.md first, then Goose Prototype A.html + proto-screens.jsx + goose.css for exact values. Build: GooseTheme (tokens), the four tab screens, Sleep & HRV detail pushes, and the four chart views (band trend, day HR ranges, gap-aware bar charts, sleep bars) with hatched gap rendering. Use my existing networking/BLE layers for data; keep all copy verbatim from the README.
