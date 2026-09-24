// ============================================================
// goose-screens-c.jsx — Direction C · "Ledger"
// Same 4-tab IA as Direction A, restyled: editorial, serif
// numerals, hairline rules, no cards. A quiet daily journal.
// ============================================================

function LedgerLine({ label, value, unit, band, color, provisional, decimals }) {
  const inb = band ? GOOSE.inBand(value, band) : true;
  return (
    <div className="g-row" style={{ alignItems: "baseline" }}>
      <span className="g-dot" style={{ background: color, alignSelf: "center" }}></span>
      <span style={{ flex: 1, fontSize: 14, color: "var(--text-2)" }}>
        {label}{provisional ? <span className="g-prov" style={{ marginLeft: 7 }}>prov.</span> : null}
      </span>
      <span style={{ fontSize: 12, color: inb ? "var(--text-3)" : "var(--range)", marginRight: 4 }}>
        {band ? (inb ? "usual" : value > band.hi ? "above usual" : "below usual") : ""}
      </span>
      <span className="g-num" style={{ fontSize: 24 }}>
        {decimals != null ? value.toFixed(decimals) : value}
        <span className="g-unit" style={{ fontSize: 12 }}>{unit}</span>
      </span>
    </div>
  );
}

// ---------------- C1 · Today (ledger) ----------------
function ScreenCToday() {
  const n = GOOSE.lastNight, b = GOOSE.bands;
  return (
    <Phone className="ledger" tabs={TABS_A} active="Today">
      <div className="g-body" style={{ gap: "calc(10px * var(--u))" }}>
        <div style={{ paddingBottom: 6 }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600 }}>
            Tuesday — June 10, 2026
          </div>
          <h1 className="g-h1" style={{ fontSize: 34, marginTop: 6 }}>A mostly usual morning.</h1>
          <p className="g-sub" style={{ fontSize: 14.5, marginTop: 6, lineHeight: 1.5 }}>
            HRV and resting heart rate sat inside your own range; wrist temperature and respiratory rate both read a touch above theirs.
          </p>
        </div>

        <div className="g-card">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", paddingTop: 10 }}>
            <span style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600 }}>Right now</span>
            <span className="g-pill live" style={{ fontSize: 11 }}>
              <span className="g-dot" style={{ background: "var(--heart)", width: 6, height: 6 }}></span>live · band 64%
            </span>
          </div>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
            <div className="g-num" style={{ fontSize: 64 }}>{GOOSE.hrNow}<span className="g-unit" style={{ fontSize: 16 }}>bpm</span></div>
            <LiveSpark w={140} h={44}></LiveSpark>
          </div>
          <DayHRChart data={GOOSE.hrHourly} h={110}></DayHRChart>
          <GapNote>13:00–15:00 — band away; heart rate will backfill, steps won't</GapNote>
        </div>

        <div className="g-card" style={{ gap: 0 }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, padding: "12px 0 4px" }}>
            {n.dateLabel} — our numbers
          </div>
          <div className="g-rows">
            <LedgerLine label="Overnight HRV (rMSSD)" value={n.hrv} unit="ms" band={b.hrv} color="var(--hrv)" decimals={1}></LedgerLine>
            <LedgerLine label="Resting heart rate" value={n.rhr} unit="bpm" band={b.rhr} color="var(--heart)"></LedgerLine>
            <LedgerLine label="Respiratory rate" value={n.resp} unit="rpm" band={b.resp} color="var(--resp)" provisional={true} decimals={1}></LedgerLine>
            <LedgerLine label="Wrist temperature" value={n.temp} unit="°C" band={b.temp} color="var(--temp)" provisional={true} decimals={1}></LedgerLine>
            <LedgerLine label="Sleep, our detection" value={"7h 12m"} unit="" color="var(--sleep)"></LedgerLine>
          </div>
        </div>

        <div className="g-card">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", paddingTop: 10 }}>
            <span style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600 }}>Steps</span>
            <span className="g-num" style={{ fontSize: 24 }}>7,392</span>
          </div>
          <StepsBars data={GOOSE.stepsHourly} h={64}></StepsBars>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- C2 · Trends (ledger) ----------------
function ScreenCTrends() {
  const b = GOOSE.bands;
  const mk = (key) => GOOSE.vitalsDaily.map((d) => ({ value: d[key], label: d.date.slice(5).replace("-", "/") }));
  const Block = ({ title, color, value, unit, series, band, fmt, provisional }) => (
    <div className="g-card" style={{ gap: 6 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", paddingTop: 10 }}>
        <span style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600 }}>
          {title}{provisional ? <span className="g-prov" style={{ marginLeft: 7 }}>prov.</span> : null}
        </span>
        <span className="g-num" style={{ fontSize: 24 }}>{value}<span className="g-unit" style={{ fontSize: 12 }}>{unit}</span></span>
      </div>
      <BandTrend series={series} band={band} color={color} h={84} fmt={fmt}></BandTrend>
    </div>
  );
  return (
    <Phone className="ledger" tabs={TABS_A} active="Trends">
      <div className="g-body" style={{ gap: "calc(10px * var(--u))" }}>
        <div style={{ paddingBottom: 2 }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.14em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600 }}>
            The week in review
          </div>
          <h1 className="g-h1" style={{ fontSize: 30, marginTop: 6 }}>Steady, with one warm night.</h1>
        </div>
        <Seg items={["W", "M", "6M"]} on="W"></Seg>
        <Block title="Overnight HRV" color="var(--hrv)" value="73.5" unit="ms" series={mk("hrv")} band={b.hrv}></Block>
        <Block title="Resting heart rate" color="var(--heart)" value="58" unit="bpm" series={mk("rhr")} band={b.rhr}></Block>
        <Block title="Wrist temperature" color="var(--temp)" value="34.0" unit="°C" series={mk("temp")} band={b.temp} fmt={(v) => v.toFixed(1)} provisional={true}></Block>
        <div className="g-card">
          <div style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, paddingTop: 10 }}>Sleep, five nights</div>
          <SleepBars nights={GOOSE.sleepNights} h={96}></SleepBars>
        </div>
        <div className="g-ours">Shaded regions are your own usual ranges, learned from your recent history.</div>
      </div>
    </Phone>
  );
}

Object.assign(window, { ScreenCToday, ScreenCTrends, LedgerLine });
