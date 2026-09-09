// ============================================================
// proto-data.js — extended demo series for the Direction A prototype
// W = the real 5 days from the brief. M / 6M are synthesized demo
// history (deterministic, seeded) representing months of wear.
// Steps keep honest band-away gaps in every period.
// ============================================================
(function () {
  const G = window.GOOSE;

  function mulberry(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function dayLabel(i) {
    const d = new Date(2026, 5, 9); d.setDate(d.getDate() - i);
    return (d.getMonth() + 1) + "/" + d.getDate();
  }

  function genVitals(days, band, seed, decimals) {
    const r = mulberry(seed);
    const out = [];
    const span = (band.hi - band.lo) / 2;
    let v = band.mean;
    for (let i = days - 1; i >= 0; i--) {
      v = v + (r() * 2 - 1) * span * 0.55 + (band.mean - v) * 0.25;
      const clipped = Math.max(band.lo - span * 0.9, Math.min(band.hi + span * 0.9, v));
      out.push({ value: Number(clipped.toFixed(decimals)), label: dayLabel(i) });
    }
    return out;
  }

  function genSteps(days, seed) {
    const r = mulberry(seed);
    const out = [];
    for (let i = days - 1; i >= 0; i--) {
      if (r() < 0.12) out.push({ gap: true, label: dayLabel(i) }); // band away that day
      else out.push({ v: Math.round(3200 + r() * 9000), label: dayLabel(i) });
    }
    return out;
  }

  function genSleep(days, seed) {
    const r = mulberry(seed);
    const out = [];
    for (let i = days - 1; i >= 0; i--) {
      out.push({ min: Math.round(360 + r() * 130), date: dayLabel(i) });
    }
    return out;
  }

  const realW = (key, decimals) =>
    G.vitalsDaily.map((d) => ({ value: Number(d[key].toFixed(decimals)), label: d.date.slice(5).replace("-", "/") }));

  window.GPROTO = {
    periods: {
      W: {
        hrv: realW("hrv", 1), rhr: realW("rhr", 0), temp: realW("temp", 1), resp: realW("resp", 2),
        steps: genSteps(7, 11), sleep: G.sleepNights,
        latest: { hrv: "73.5", rhr: "58", temp: "34.0", resp: "15.4" },
      },
      M: {
        hrv: genVitals(30, G.bands.hrv, 21, 1), rhr: genVitals(30, G.bands.rhr, 22, 0),
        temp: genVitals(30, G.bands.temp, 23, 1), resp: genVitals(30, G.bands.resp, 24, 2),
        steps: genSteps(30, 12), sleep: genSleep(30, 31),
        latest: { hrv: "73.5", rhr: "58", temp: "34.0", resp: "15.4" },
      },
      "6M": {
        hrv: genVitals(180, G.bands.hrv, 41, 1), rhr: genVitals(180, G.bands.rhr, 42, 0),
        temp: genVitals(180, G.bands.temp, 43, 1), resp: genVitals(180, G.bands.resp, 44, 2),
        steps: genSteps(180, 13), sleep: genSleep(180, 51),
        latest: { hrv: "73.5", rhr: "58", temp: "34.0", resp: "15.4" },
      },
    },
  };
})();
