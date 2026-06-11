// ============================================================
// goose-screens-b.jsx — Direction B · "Day Arc"
// Adventurous time-based IA: Day · History · Band
// The day is one continuous loop — night feeds morning feeds now.
// ============================================================

function MiniVital({ label, value, unit, band, color, provisional }) {
  const inb = GOOSE.inBand(value, band);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 3, alignItems: "center", flex: 1 }}>
      <div style={{ fontSize: 10.5, fontWeight: 600, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--text-3)" }}>
        {label}{provisional ? "*" : ""}
      </div>
      <div className="g-num" style={{ fontSize: 21 }}>{value}<span className="g-unit" style={{ fontSize: 10 }}>{unit}</span></div>
      <span className="g-dot" style={{ background: inb ? color : "var(--range)", width: 6, height: 6, opacity: inb ? 0.9 : 1 }}></span>
    </div>
  );
}

// ---------------- B1 · Day ----------------
function ScreenBDay() {
  const n = GOOSE.lastNight, b = GOOSE.bands;
  return (
    <Phone tabs={TABS_B} active="Day">
      <div className="g-body" style={{ gap: "calc(16px * var(--u))" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div>
            <h1 className="g-h1" style={{ fontSize: 24 }}>Tuesday</h1>
            <p className="g-sub">June 10 · one loop, midnight to midnight</p>
          </div>
          <span className="g-pill mut">
            <span className="g-dot" style={{ background: "var(--activity)", width: 7, height: 7 }}></span>64%
          </span>
        </div>

        {/* hero: 24h arc with live HR in the middle */}
        <div style={{ position: "relative", display: "flex", justifyContent: "center", padding: "6px 0" }}>
          <DayArc data={GOOSE.hrHourly} size={296}></DayArc>
          <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 2 }}>
            <span className="g-pill live" style={{ fontSize: 11 }}>
              <span className="g-dot" style={{ background: "var(--heart)", width: 6, height: 6 }}></span>live
            </span>
            <div className="g-num" style={{ fontSize: 54 }}>{GOOSE.hrNow}</div>
            <div style={{ fontSize: 12.5, color: "var(--text-2)", fontWeight: 600 }}>bpm right now</div>
          </div>
        </div>

        <div style={{ display: "flex", justifyContent: "center", gap: 16, fontSize: 11.5, color: "var(--text-3)" }}>
          <span style={{ display: "flex", alignItems: "center", gap: 5 }}><span className="g-dot" style={{ background: "var(--heart)" }}></span>heart rate</span>
          <span style={{ display: "flex", alignItems: "center", gap: 5 }}><span className="g-dot" style={{ background: "var(--sleep)" }}></span>sleep</span>
          <span style={{ display: "flex", alignItems: "center", gap: 5 }}><span style={{ width: 12, borderTop: "2px dashed var(--text-3)" }}></span>band away</span>
        </div>

        {/* morning digest strip */}
        <div className="g-card" style={{ gap: "calc(12px * var(--u))" }}>
          <CardTitle color="var(--hrv)" right={<GIcon name="chev" size={15} color="var(--text-3)"></GIcon>}>
            This morning · {n.dateLabel.toLowerCase()}
          </CardTitle>
          <div style={{ display: "flex", gap: 6 }}>
            <MiniVital label="HRV" value={n.hrv} unit="ms" band={b.hrv} color="var(--hrv)"></MiniVital>
            <MiniVital label="Rest HR" value={n.rhr} unit="bpm" band={b.rhr} color="var(--heart)"></MiniVital>
            <MiniVital label="Resp" value={n.resp} unit="rpm" band={b.resp} color="var(--resp)" provisional={true}></MiniVital>
            <MiniVital label="Temp" value={n.temp} unit="°C" band={b.temp} color="var(--temp)" provisional={true}></MiniVital>
          </div>
          <div className="g-ours">Dots judge against your own normal — orange = outside it · *provisional</div>
        </div>

        {/* the day as a stream */}
        <div className="g-card" style={{ gap: "calc(10px * var(--u))" }}>
          <CardTitle color="var(--activity)">Day so far</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 26 }}>7,392<span className="g-unit">steps</span></div>
            <GapNote>2h gap while charging</GapNote>
          </div>
          <StepsBars data={GOOSE.stepsHourly} h={70}></StepsBars>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "2px 6px", color: "var(--text-3)", fontSize: 12.5 }}>
          <GIcon name="moon" size={16}></GIcon>
          Tonight closes the loop — tomorrow's morning report needs a full night of wear.
        </div>
      </div>
    </Phone>
  );
}

// ---------------- B2 · History (stream of mornings) ----------------
function DayStripe({ date, hrv, rhr, temp, sleepMin, partial }) {
  const b = GOOSE.bands;
  const cell = (v, band, color, fmt) =>
    v == null ? (
      <span style={{ flex: 1, textAlign: "center", color: "var(--text-3)", fontSize: 13 }}>—</span>
    ) : (
      <span style={{ flex: 1, textAlign: "center" }}>
        <span className="g-num" style={{ fontSize: 16, color: GOOSE.inBand(v, band) ? "var(--text)" : "var(--range)" }}>
          {fmt ? fmt(v) : v}
        </span>
      </span>
    );
  return (
    <div className="g-row" style={{ gap: 6 }}>
      <span style={{ width: 64, fontSize: 12.5, color: partial ? "var(--text-3)" : "var(--text-2)", fontWeight: 600 }}>{date}</span>
      {cell(hrv, b.hrv, "var(--hrv)", (v) => v.toFixed(0))}
      {cell(rhr, b.rhr, "var(--heart)")}
      {cell(temp, b.temp, "var(--temp)", (v) => v.toFixed(1))}
      <span style={{ flex: 1, textAlign: "right", fontSize: 13, color: "var(--text-2)" }}>
        {sleepMin ? GOOSE.fmtSleep(sleepMin) : "—"}
      </span>
    </div>
  );
}

function ScreenBHistory() {
  const v = [...GOOSE.vitalsDaily].reverse();
  const sleep = [...GOOSE.sleepNights].reverse();
  return (
    <Phone tabs={TABS_B} active="History">
      <div className="g-body">
        <div>
          <h1 className="g-h1" style={{ fontSize: 24 }}>History</h1>
          <p className="g-sub">Every morning, against your own usual</p>
        </div>
        <Seg items={["W", "M", "6M"]} on="W"></Seg>

        <div className="g-card">
          <CardTitle color="var(--hrv)">Overnight HRV</CardTitle>
          <BandTrend series={GOOSE.vitalsDaily.map((d) => ({ value: d.hrv, label: d.date.slice(5).replace("-", "/") }))}
            band={GOOSE.bands.hrv} color="var(--hrv)" h={104}></BandTrend>
          <div className="g-ours">Shaded = your usual 67–80 ms · dashed = your mean</div>
        </div>

        <div className="g-card" style={{ gap: 4 }}>
          <div className="g-row" style={{ paddingTop: 4, paddingBottom: 8, gap: 6 }}>
            <span style={{ width: 64, fontSize: 10.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--text-3)" }}>date</span>
            {["hrv", "rhr", "temp"].map((k) => (
              <span key={k} style={{ flex: 1, textAlign: "center", fontSize: 10.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--text-3)" }}>{k}</span>
            ))}
            <span style={{ flex: 1, textAlign: "right", fontSize: 10.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", color: "var(--text-3)" }}>sleep</span>
          </div>
          <div className="g-rows">
            <DayStripe date="Today" partial={true}></DayStripe>
            {v.map((d, i) => (
              <DayStripe key={d.date} date={d.date.slice(5).replace("-", " Jun ").length ? "Jun " + Number(d.date.slice(8)) : d.date}
                hrv={d.hrv} rhr={d.rhr} temp={d.temp} sleepMin={(sleep[i] || {}).min}></DayStripe>
            ))}
          </div>
          <div className="g-ours">Today shows “—” until tonight is processed. Orange = outside your usual range.</div>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- B3 · Band ----------------
function ScreenBBand() {
  return (
    <Phone tabs={TABS_B} active="Band">
      <div className="g-body" style={{ gap: "calc(16px * var(--u))" }}>
        <div>
          <h1 className="g-h1" style={{ fontSize: 24 }}>Band</h1>
          <p className="g-sub">WHOOP 4.0 · talking to this phone only</p>
        </div>

        <div className="g-card" style={{ alignItems: "center", gap: "calc(14px * var(--u))", paddingTop: 24, paddingBottom: 24 }}>
          <div style={{ position: "relative", width: 120, height: 120 }}>
            <svg width="120" height="120" viewBox="0 0 120 120">
              <circle cx="60" cy="60" r="52" fill="none" stroke="var(--line-strong)" strokeWidth="7"></circle>
              <circle cx="60" cy="60" r="52" fill="none" stroke="var(--charge)" strokeWidth="7" strokeLinecap="round"
                strokeDasharray={2 * Math.PI * 52} strokeDashoffset={2 * Math.PI * 52 * (1 - 0.64)}
                transform="rotate(-90 60 60)"></circle>
            </svg>
            <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
              <div className="g-num" style={{ fontSize: 30 }}>64%</div>
              <div style={{ fontSize: 11, color: "var(--text-3)", fontWeight: 600 }}>not charging</div>
            </div>
          </div>
          <span className="g-pill ok">
            <span className="g-dot" style={{ background: "var(--activity)", width: 7, height: 7 }}></span>
            connected · streaming
          </span>
        </div>

        <div className="g-card" style={{ paddingTop: 4, paddingBottom: 4 }}>
          <div className="g-rows">
            <div className="g-row">
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600 }}>HR buffer backfill</div>
                <div style={{ fontSize: 12.5, color: "var(--text-3)" }}>Band remembers HR while away — syncs when you're back in range</div>
              </div>
              <span className="g-pill ok">up to date</span>
            </div>
            <div className="g-row">
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600 }}>Steps while away</div>
                <div style={{ fontSize: 12.5, color: "var(--text-3)" }}>Not buffered by the band — those gaps are permanent</div>
              </div>
              <span className="g-pill warn">gaps stay</span>
            </div>
            <div className="g-row">
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 600 }}>Skin-temp calibration</div>
                <div style={{ fontSize: 12.5, color: "var(--text-3)" }}>Coarse 2-point fit</div>
              </div>
              <span className="g-prov">provisional</span>
            </div>
          </div>
        </div>

        <div className="g-card" style={{ flexDirection: "row", gap: 12, alignItems: "flex-start" }}>
          <GIcon name="lock" size={20} color="var(--activity)"></GIcon>
          <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.5 }}>
            Phone ↔ your server, over your own network. Nothing leaves hardware you own.
          </div>
        </div>
      </div>
    </Phone>
  );
}

Object.assign(window, { ScreenBDay, ScreenBHistory, ScreenBBand, MiniVital });
