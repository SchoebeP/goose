// ============================================================
// Goose redesign — sample data, taken from the brief's appendix
// (real values from /ingest/vitals/daily + bands, 2026-06-10).
// Sleep durations are plausible placeholders (none in brief).
// ============================================================
(function () {
  const vitalsDaily = [
    { date: "2026-06-05", hrv: 80.2, rhr: 57, resp: 15.4, temp: 33.6 },
    { date: "2026-06-06", hrv: 71.0, rhr: 54, resp: 15.4, temp: 33.7 },
    { date: "2026-06-07", hrv: 62.7, rhr: 60, resp: 15.4, temp: 34.0 },
    { date: "2026-06-08", hrv: 74.2, rhr: 55, resp: 15.4, temp: 33.4 },
    { date: "2026-06-09", hrv: 73.5, rhr: 58, resp: 15.4, temp: 34.0 },
  ];

  const bands = {
    hrv:  { lo: 67,    hi: 80,    mean: 73,    unit: "ms"  },
    rhr:  { lo: 51,    hi: 67,    mean: 59,    unit: "bpm" },
    temp: { lo: 33.5,  hi: 34.0,  mean: 33.7,  unit: "°C"  },
    resp: { lo: 15.34, hi: 15.36, mean: 15.35, unit: "rpm" },
  };

  // Last fully-processed night (the “dated yesterday” quirk): 2026-06-09.
  const lastNight = {
    dateLabel: "Night of Jun 8–9",
    processedLabel: "processed this morning",
    hrv: 73.5, rhr: 58, resp: 15.4, temp: 34.0,
    sleepMin: 432, // 7h 12m — our own detection, placeholder duration
  };

  // Today (2026-06-10) is partial: only resting HR computed, reads high.
  const todayPartial = { rhr: 77 };

  // Hourly HR ranges for today — avg 82, day range 54–130 (per brief).
  // null = band out of range (honest gap, 13:00–15:00 charging/away).
  const hrHourly = [
    { h: 0,  lo: 54, hi: 66, avg: 58 }, { h: 1,  lo: 54, hi: 62, avg: 57 },
    { h: 2,  lo: 55, hi: 61, avg: 57 }, { h: 3,  lo: 54, hi: 60, avg: 56 },
    { h: 4,  lo: 55, hi: 63, avg: 58 }, { h: 5,  lo: 56, hi: 68, avg: 60 },
    { h: 6,  lo: 58, hi: 79, avg: 66 }, { h: 7,  lo: 64, hi: 95, avg: 78 },
    { h: 8,  lo: 70, hi: 108, avg: 86 }, { h: 9,  lo: 74, hi: 122, avg: 95 },
    { h: 10, lo: 78, hi: 130, avg: 101 }, { h: 11, lo: 72, hi: 112, avg: 90 },
    { h: 12, lo: 68, hi: 98, avg: 84 },
    { h: 13, gap: true }, { h: 14, gap: true },
    { h: 15, lo: 70, hi: 102, avg: 85 }, { h: 16, lo: 72, hi: 99, avg: 86 },
    { h: 17, lo: 75, hi: 110, avg: 92 },
  ];
  const hrNow = 71;

  // Hourly steps — live-only, NOT backfillable; same 13–15h gap shown honestly.
  const stepsHourly = [
    { h: 0, v: 0 }, { h: 1, v: 0 }, { h: 2, v: 0 }, { h: 3, v: 0 },
    { h: 4, v: 0 }, { h: 5, v: 12 }, { h: 6, v: 180 }, { h: 7, v: 640 },
    { h: 8, v: 1240 }, { h: 9, v: 890 }, { h: 10, v: 1530 }, { h: 11, v: 760 },
    { h: 12, v: 430 }, { h: 13, gap: true }, { h: 14, gap: true },
    { h: 15, v: 510 }, { h: 16, v: 880 }, { h: 17, v: 320 },
  ];
  const stepsTotal = 7392;

  // Per-night sleep minutes, our own detection (placeholder durations).
  const sleepNights = [
    { date: "Jun 4–5", min: 451 }, { date: "Jun 5–6", min: 418 },
    { date: "Jun 6–7", min: 389 }, { date: "Jun 7–8", min: 462 },
    { date: "Jun 8–9", min: 432 },
  ];

  const battery = { pct: 64, charging: false };

  function fmtSleep(min) {
    return Math.floor(min / 60) + "h " + (min % 60).toString().padStart(2, "0") + "m";
  }
  function inBand(v, b) { return v >= b.lo && v <= b.hi; }

  window.GOOSE = {
    vitalsDaily, bands, lastNight, todayPartial,
    hrHourly, hrNow, stepsHourly, stepsTotal,
    sleepNights, battery, fmtSleep, inBand,
  };
})();
