# Radiograph — Goose UI design system (2026-07)

Replaces "Direction A / Apple-Health-clean" (dark navy, cards, per-metric rainbow accents).
Deliberately its opposite on every axis.

## Thesis
The app is a medical instrument you own: your strap, your signal, read like film on a
light box. Cool, clinical, editorial — not a fitness rainbow.

## Tokens

Color (light / dark = "film" / "negative"):
- `film`      #EFF2F4 / #101315 — screen ground
- `ink`       #171A1E / #E8ECEF — primary text, chart strokes
- `graphite`  #5E6771 / #8B949E — secondary text
- `hairline`  #D7DEE3 / #232A2F — rules, dividers, axes
- `arterial`  #C2242E / #E04A52 — RESERVED: only live/now (live HR, pulse spine, now-markers)
- `wash`      #E4E9EC / #181D21 — chart fills, pressed states

Rule: charts are ink-monochrome. Red never encodes a metric — it encodes "happening now".

Type:
- Display: New York serif (`.fontDesign(.serif)`), for big numerals + screen titles. Weights: .medium numbers, .semibold titles.
- Body: SF Pro (default), regular/medium.
- Utility: SF Mono, uppercase, tracked +1.5, for eyebrow labels, units, timestamps, raw values.

Layout:
- No cards, no rounded containers. Full-bleed sections separated by 0.5pt hairlines.
- Left-aligned oversized serif numerals (44–64pt) with small mono eyebrows above ("RESTING HR").
- Units set in mono at ~40% the numeral size, baseline-aligned.
- Generous top whitespace; screens read as a ledger, not a dashboard.

## Signature
**Pulse spine** — a thin live waveform ribbon under each screen title that beats at the
current heart rate (animation period = 60/BPM). Arterial red while live-connected;
dotted hairline with mono caption "no signal" when not. It is the one bold element;
everything else stays quiet.

## Copy
Sentence case, plain verbs. "Live", "Last night", "This week", "Bring the band in range".
Never system vocabulary in main screens (frames/packets live only in Debug).

## Motion
One orchestrated moment: pulse spine beat + numerals settling on connect. No scattered
card animations. Respect Reduce Motion (spine becomes static waveform).

## Migration
New file `InkTheme.swift` + `InkComponents.swift`; legacy GooseTheme stays until all
screens migrate. Debug screens keep function, get retinted only.

## Notes / tried
- Rejected warm-cream+serif+terracotta (AI default #1) — ground moved cool.
- Rejected per-metric accent colors — monochrome ink is the identity.
- Flatline for "disconnected" rejected (grim) → dotted "no signal" instead.
