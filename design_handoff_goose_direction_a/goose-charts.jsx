// ============================================================
// goose-charts.jsx — SVG chart components for the Goose redesign
// All charts show honest gaps (hatched) and personal usual bands.
// Reads chart-style tweak from GooseCtx { chartStyle: 'band'|'line'|'bars' }
// ============================================================

const GooseCtx = React.createContext({ chartStyle: "band" });

let __gooseHatchN = 0;
function GapHatch({ id, color }) {
  return (
    <pattern id={id} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="6" height="6" fill="transparent"></rect>
      <line x1="0" y1="0" x2="0" y2="6" stroke={color || "rgba(168,184,214,0.18)"} strokeWidth="1.5"></line>
    </pattern>
  );
}

// ---------- daily vitals trend vs personal usual band ----------
function BandTrend({ series, band, color, w = 315, h = 96, fmt }) {
  const { chartStyle } = React.useContext(GooseCtx);
  const pad = { t: 10, b: 18, l: 4, r: 40 };
  const vals = series.map((d) => d.value);
  const min = Math.min(...vals, band.lo) - (band.hi - band.lo) * 0.35 - 0.0001;
  const max = Math.max(...vals, band.hi) + (band.hi - band.lo) * 0.35 + 0.0001;
  const y = (v) => pad.t + (1 - (v - min) / (max - min)) * (h - pad.t - pad.b);
  const x = (i) => pad.l + (i / Math.max(series.length - 1, 1)) * (w - pad.l - pad.r);
  const fmtV = fmt || ((v) => v);
  const last = series[series.length - 1];

  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      {/* personal usual band */}
      <rect x={pad.l} y={y(band.hi)} width={w - pad.l - pad.r} height={Math.max(y(band.lo) - y(band.hi), 2)}
        fill={color} opacity="0.10" rx="3"></rect>
      <line x1={pad.l} x2={w - pad.r} y1={y(band.mean)} y2={y(band.mean)}
        stroke={color} opacity="0.25" strokeDasharray="2 4" strokeWidth="1"></line>
      <text x={w - pad.r + 6} y={y(band.hi) + 4} fontSize="9.5" fill="var(--text-3)">{fmtV(band.hi)}</text>
      <text x={w - pad.r + 6} y={y(band.lo) + 4} fontSize="9.5" fill="var(--text-3)">{fmtV(band.lo)}</text>

      {chartStyle === "bars" &&
        series.map((d, i) => {
          const bwb = Math.max(2, (w - pad.l - pad.r) / series.length - 2);
          return (
            <rect key={i} x={x(i) - bwb / 2} y={y(d.value)} width={bwb} height={Math.max(h - pad.b - y(d.value), 2)}
              rx={Math.min(4, bwb / 2)} fill={color} opacity={i === series.length - 1 ? 0.95 : 0.45}></rect>
          );
        })}
      {chartStyle !== "bars" && (
        <polyline
          points={series.map((d, i) => x(i) + "," + y(d.value)).join(" ")}
          fill="none" stroke={color} strokeWidth={series.length > 40 ? 1.4 : 2} strokeLinejoin="round" strokeLinecap="round"
          opacity={chartStyle === "line" ? 0.9 : 0.75}></polyline>
      )}
      {chartStyle !== "bars" &&
        series.map((d, i) =>
          series.length > 10 && i !== series.length - 1 ? null : (
            <circle key={i} cx={x(i)} cy={y(d.value)} r={i === series.length - 1 ? 4 : 2.5}
              fill={i === series.length - 1 ? color : "var(--bg)"}
              stroke={color} strokeWidth="1.5"></circle>
          )
        )}
      {/* x labels: first + last */}
      <text x={x(0)} y={h - 4} fontSize="9.5" fill="var(--text-3)">{series[0].label}</text>
      <text x={x(series.length - 1)} y={h - 4} fontSize="9.5" fill="var(--text-3)" textAnchor="middle">{last.label}</text>
    </svg>
  );
}

// ---------- hourly HR range chart (lo–hi per hour, honest gaps) ----------
function DayHRChart({ data, w = 315, h = 130 }) {
  const { chartStyle } = React.useContext(GooseCtx);
  const hid = "hrgap" + __gooseHatchN++;
  const pad = { t: 8, b: 18, l: 4, r: 30 };
  const lo = 45, hi = 135;
  const y = (v) => pad.t + (1 - (v - lo) / (hi - lo)) * (h - pad.t - pad.b);
  const bw = (w - pad.l - pad.r) / 24;
  const x = (hr) => pad.l + hr * bw;
  const present = data.filter((d) => !d.gap);

  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      <defs><GapHatch id={hid}></GapHatch></defs>
      {[60, 90, 120].map((g) => (
        <g key={g}>
          <line x1={pad.l} x2={w - pad.r} y1={y(g)} y2={y(g)} stroke="var(--line)" strokeWidth="1"></line>
          <text x={w - pad.r + 5} y={y(g) + 3.5} fontSize="9.5" fill="var(--text-3)">{g}</text>
        </g>
      ))}
      {data.map((d) =>
        d.gap ? (
          <rect key={d.h} x={x(d.h) + 1} y={pad.t} width={bw - 2} height={h - pad.t - pad.b}
            fill={"url(#" + hid + ")"} rx="3"></rect>
        ) : chartStyle === "line" ? null : (
          <rect key={d.h} x={x(d.h) + 1.5} y={y(d.hi)} width={bw - 3}
            height={Math.max(y(d.lo) - y(d.hi), 3)} rx={(bw - 3) / 2}
            fill="var(--heart)" opacity="0.55"></rect>
        )
      )}
      {chartStyle !== "bars" && (
        <polyline
          points={present.map((d) => (x(d.h) + bw / 2) + "," + y(d.avg)).join(" ")}
          fill="none" stroke="var(--heart)" strokeWidth="2"
          strokeLinejoin="round" strokeLinecap="round"
          opacity={chartStyle === "line" ? 0.95 : 0.0}></polyline>
      )}
      {chartStyle === "line" &&
        present.map((d) => (
          <circle key={d.h} cx={x(d.h) + bw / 2} cy={y(d.avg)} r="2" fill="var(--heart)"></circle>
        ))}
      {[0, 6, 12, 18].map((hr) => (
        <text key={hr} x={x(hr) + 2} y={h - 4} fontSize="9.5" fill="var(--text-3)">
          {hr === 0 ? "00" : hr}
        </text>
      ))}
      <text x={x(24) - 2} y={h - 4} fontSize="9.5" fill="var(--text-3)" textAnchor="end">24</text>
    </svg>
  );
}

// ---------- hourly steps bars (live-only, gaps not backfillable) ----------
function StepsBars({ data, w = 315, h = 96 }) {
  const hid = "stgap" + __gooseHatchN++;
  const pad = { t: 8, b: 18, l: 4, r: 4 };
  const max = Math.max(...data.filter((d) => !d.gap).map((d) => d.v), 1);
  const bw = (w - pad.l - pad.r) / 24;
  const x = (hr) => pad.l + hr * bw;
  const y = (v) => pad.t + (1 - v / max) * (h - pad.t - pad.b);
  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      <defs><GapHatch id={hid}></GapHatch></defs>
      {data.map((d) =>
        d.gap ? (
          <rect key={d.h} x={x(d.h) + 1} y={pad.t} width={bw - 2} height={h - pad.t - pad.b}
            fill={"url(#" + hid + ")"} rx="3"></rect>
        ) : (
          <rect key={d.h} x={x(d.h) + 1.5} y={d.v === 0 ? h - pad.b - 2 : y(d.v)} width={bw - 3}
            height={d.v === 0 ? 2 : Math.max(h - pad.b - y(d.v), 2)} rx="2.5"
            fill="var(--activity)" opacity={d.v === 0 ? 0.25 : 0.8}></rect>
        )
      )}
      {[0, 6, 12, 18].map((hr) => (
        <text key={hr} x={x(hr) + 2} y={h - 4} fontSize="9.5" fill="var(--text-3)">
          {hr === 0 ? "00" : hr}
        </text>
      ))}
      <text x={x(24) - 2} y={h - 4} fontSize="9.5" fill="var(--text-3)" textAnchor="end">24</text>
    </svg>
  );
}

// ---------- per-night sleep duration bars ----------
function SleepBars({ nights, w = 315, h = 110, goalMin = 450 }) {
  const pad = { t: 10, b: 20, l: 4, r: 36 };
  const max = 9 * 60;
  const bw = (w - pad.l - pad.r) / nights.length;
  const x = (i) => pad.l + i * bw;
  const y = (v) => pad.t + (1 - v / max) * (h - pad.t - pad.b);
  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      <line x1={pad.l} x2={w - pad.r} y1={y(goalMin)} y2={y(goalMin)}
        stroke="var(--sleep)" opacity="0.3" strokeDasharray="2 4" strokeWidth="1"></line>
      <text x={w - pad.r + 5} y={y(goalMin) + 3.5} fontSize="9.5" fill="var(--text-3)">7h30</text>
      {nights.map((n, i) => (
        <g key={i}>
          <rect x={x(i) + bw * 0.18} y={y(n.min)} width={bw * 0.64}
            height={Math.max(h - pad.b - y(n.min), 2)} rx={Math.min(7, bw * 0.3)}
            fill="var(--sleep)" opacity={i === nights.length - 1 ? 0.95 : 0.5}></rect>
          {nights.length <= 8 ? (
            <text x={x(i) + bw / 2} y={h - 6} fontSize="9" fill="var(--text-3)" textAnchor="middle">
              {(n.date || "").split("–")[1] || n.date}
            </text>
          ) : null}
        </g>
      ))}
      {nights.length > 8 ? (
        <g>
          <text x={pad.l} y={h - 6} fontSize="9" fill="var(--text-3)">{nights[0].date}</text>
          <text x={w - pad.r} y={h - 6} fontSize="9" fill="var(--text-3)" textAnchor="end">{nights[nights.length - 1].date}</text>
        </g>
      ) : null}
    </svg>
  );
}

// ---------- live HR sparkline (last few minutes, noisy) ----------
function LiveSpark({ color = "var(--heart)", w = 120, h = 34, seed = 3 }) {
  const pts = [];
  for (let i = 0; i < 40; i++) {
    const v = Math.sin(i * 0.55 + seed) * 5 + Math.sin(i * 1.7 + seed * 2) * 3 + Math.sin(i * 0.13) * 6;
    pts.push((i / 39) * w + "," + (h / 2 - v));
  }
  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      <polyline points={pts.join(" ")} fill="none" stroke={color} strokeWidth="1.8"
        strokeLinejoin="round" strokeLinecap="round" opacity="0.9"></polyline>
    </svg>
  );
}

// ---------- 24h day arc (Direction B hero) ----------
// Radial clock: outer arc = HR intensity per hour (gaps = faint hatch dots),
// inner arc = sleep window. "Now" marker at current hour.
function DayArc({ data, sleepFromH = 23.2, sleepToH = 7.4, nowH = 17.6, size = 280 }) {
  const cx = size / 2, cy = size / 2;
  const rOuter = size / 2 - 14, wOuter = 13;
  const rSleep = rOuter - 24;
  const a = (h) => ((h / 24) * 360 - 90) * (Math.PI / 180);
  const arcPath = (r, h0, h1) => {
    const x0 = cx + r * Math.cos(a(h0)), y0 = cy + r * Math.sin(a(h0));
    const x1 = cx + r * Math.cos(a(h1)), y1 = cy + r * Math.sin(a(h1));
    const large = h1 - h0 > 12 ? 1 : 0;
    return "M " + x0 + " " + y0 + " A " + r + " " + r + " 0 " + large + " 1 " + x1 + " " + y1;
  };
  const heat = (avg) => {
    if (avg == null) return null;
    const t = Math.min(Math.max((avg - 55) / 60, 0), 1);
    return { opacity: 0.25 + t * 0.75, width: wOuter * (0.45 + t * 0.55) };
  };
  const nowX = cx + (rOuter + 9) * Math.cos(a(nowH));
  const nowY = cy + (rOuter + 9) * Math.sin(a(nowH));
  return (
    <svg width={size} height={size} viewBox={"0 0 " + size + " " + size} style={{ display: "block" }}>
      {/* hour ticks */}
      {[0, 6, 12, 18].map((h) => (
        <text key={h} x={cx + (rOuter + 1) * Math.cos(a(h)) * 1.0} y={cy + (rOuter + 1) * Math.sin(a(h)) + 3}
          fontSize="9" fill="var(--text-3)" textAnchor="middle">{h === 0 ? "24" : h}</text>
      ))}
      {/* HR hours */}
      {data.map((d) => {
        if (d.gap) {
          return (
            <path key={d.h} d={arcPath(rOuter - wOuter / 2, d.h + 0.1, d.h + 0.9)} fill="none"
              stroke="var(--text-3)" strokeWidth="2" strokeDasharray="1.5 4" opacity="0.5"></path>
          );
        }
        const ht = heat(d.avg);
        return (
          <path key={d.h} d={arcPath(rOuter - wOuter / 2, d.h + 0.08, d.h + 0.92)} fill="none"
            stroke="var(--heart)" strokeWidth={ht.width} opacity={ht.opacity} strokeLinecap="round"></path>
        );
      })}
      {/* future hours, faint track */}
      {Array.from({ length: 24 }, (_, h) => h).filter((h) => !data.some((d) => d.h === h)).map((h) => (
        <path key={h} d={arcPath(rOuter - wOuter / 2, h + 0.08, h + 0.92)} fill="none"
          stroke="var(--line-strong)" strokeWidth="2.5" strokeLinecap="round" opacity="0.6"></path>
      ))}
      {/* sleep window (wraps midnight) */}
      <path d={arcPath(rSleep, sleepFromH - 24, sleepToH)} fill="none" stroke="var(--sleep)"
        strokeWidth="5" strokeLinecap="round" opacity="0.75"></path>
      {/* now marker */}
      <circle cx={nowX} cy={nowY} r="3.5" fill="var(--text)"></circle>
    </svg>
  );
}

// ---------- generic daily bars with honest gaps (steps per day) ----------
function DailyBars({ data, w = 315, h = 96, color = "var(--activity)" }) {
  const hid = "dbgap" + __gooseHatchN++;
  const pad = { t: 8, b: 18, l: 4, r: 4 };
  const vals = data.filter((d) => !d.gap).map((d) => d.v);
  const max = Math.max(...vals, 1);
  const bw = (w - pad.l - pad.r) / data.length;
  const x = (i) => pad.l + i * bw;
  const y = (v) => pad.t + (1 - v / max) * (h - pad.t - pad.b);
  return (
    <svg width={w} height={h} viewBox={"0 0 " + w + " " + h} style={{ display: "block" }}>
      <defs><GapHatch id={hid}></GapHatch></defs>
      {data.map((d, i) =>
        d.gap ? (
          <rect key={i} x={x(i) + Math.min(1, bw * 0.1)} y={pad.t} width={Math.max(bw - 2, 1.2)} height={h - pad.t - pad.b}
            fill={"url(#" + hid + ")"} rx={Math.min(3, bw * 0.3)}></rect>
        ) : (
          <rect key={i} x={x(i) + Math.min(1.5, bw * 0.12)} y={y(d.v)} width={Math.max(bw - 3, 1.2)}
            height={Math.max(h - pad.b - y(d.v), 2)} rx={Math.min(2.5, bw * 0.3)}
            fill={color} opacity={i === data.length - 1 ? 0.95 : 0.65}></rect>
        )
      )}
      <text x={pad.l} y={h - 4} fontSize="9.5" fill="var(--text-3)">{data[0].label}</text>
      <text x={w - pad.r} y={h - 4} fontSize="9.5" fill="var(--text-3)" textAnchor="end">{data[data.length - 1].label}</text>
    </svg>
  );
}

Object.assign(window, { GooseCtx, BandTrend, DayHRChart, StepsBars, SleepBars, LiveSpark, DayArc, DailyBars });
