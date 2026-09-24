// ============================================================
// goose-screens-a.jsx — Direction A · "Quiet Companion"
// Safe 4-tab IA: Today · Morning · Trends · More
// Soft cards, big numerals, recovery gets a real home (Morning).
// ============================================================

// mini horizontal usual-band gauge: lo..hi with value dot
function BandGauge({ value, band, color, w = 132 }) {
  const span = band.hi - band.lo;
  const min = band.lo - span * 0.6, max = band.hi + span * 0.6;
  const px = (v) => Math.min(Math.max(((v - min) / (max - min)) * w, 3), w - 3);
  return (
    <svg width={w} height="14" viewBox={"0 0 " + w + " 14"} style={{ display: "block" }}>
      <rect x="0" y="5.5" width={w} height="3" rx="1.5" fill="var(--line-strong)"></rect>
      <rect x={px(band.lo)} y="4" width={px(band.hi) - px(band.lo)} height="6" rx="3" fill={color} opacity="0.32"></rect>
      <circle cx={px(value)} cy="7" r="4" fill={color} stroke="var(--bg)" strokeWidth="1.5"></circle>
    </svg>
  );
}

function VitalTile({ label, color, value, unit, band, provisional, decimals }) {
  return (
    <div className="g-card" style={{ gap: "calc(8px * var(--u))", minWidth: 0 }}>
      <CardTitle color={color}>{label}{provisional ? <span style={{ color: "var(--text-3)" }}> *</span> : null}</CardTitle>
      <div className="g-num" style={{ fontSize: 30 }}>
        {decimals != null ? value.toFixed(decimals) : value}<span className="g-unit">{unit}</span>
      </div>
      <BandGauge value={value} band={band} color={color}></BandGauge>
      <BandPill value={value} band={band} compact={true}></BandPill>
    </div>
  );
}

function HeaderA({ title, sub, right }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 10 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <h1 className="g-h1">{title}</h1>
        {sub ? <p className="g-sub" style={{ whiteSpace: "nowrap" }}>{sub}</p> : null}
      </div>
      {right ? <div style={{ flex: "none" }}>{right}</div> : null}
    </div>
  );
}

function BatteryChip() {
  return (
    <span className="g-pill mut" style={{ marginTop: 6 }}>
      <span className="g-dot" style={{ background: "var(--activity)", width: 7, height: 7 }}></span>
      Band · {GOOSE.battery.pct}%
    </span>
  );
}

// ---------------- A1 · Today ----------------
function ScreenAToday() {
  return (
    <Phone tabs={TABS_A} active="Today">
      <div className="g-body">
        <HeaderA title="Today" sub="Tuesday, June 10" right={<BatteryChip></BatteryChip>}></HeaderA>

        <div className="g-card">
          <CardTitle color="var(--heart)" right={<span className="g-pill live"><span className="g-dot" style={{ background: "var(--heart)", width: 7, height: 7 }}></span>live</span>}>
            Heart rate
          </CardTitle>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
            <div className="g-num" style={{ fontSize: 58 }}>{GOOSE.hrNow}<span className="g-unit">bpm</span></div>
            <LiveSpark w={130} h={40}></LiveSpark>
          </div>
          <div className="g-ours">From the band over Bluetooth · day range 54–130 · avg 82</div>
          <DayHRChart data={GOOSE.hrHourly}></DayHRChart>
          <GapNote>Band was away 13:00–15:00 — HR backfills next sync</GapNote>
        </div>

        <div className="g-card">
          <CardTitle color="var(--activity)">Steps</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 34 }}>7,392</div>
            <span className="g-pill mut">so far today</span>
          </div>
          <StepsBars data={GOOSE.stepsHourly}></StepsBars>
          <GapNote>Steps only count while connected — gaps stay gaps</GapNote>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <div className="g-card" style={{ gap: "calc(8px * var(--u))" }}>
            <CardTitle color="var(--hrv)">Live HRV</CardTitle>
            <div className="g-num" style={{ fontSize: 28 }}>61<span className="g-unit">ms</span></div>
            <div className="g-ours">Instantaneous &amp; noisy — your overnight HRV lives in Morning</div>
          </div>
          <div className="g-card" style={{ gap: "calc(8px * var(--u))" }}>
            <CardTitle color="var(--charge)">Energy</CardTitle>
            <div className="g-num" style={{ fontSize: 28 }}>72<span className="g-unit">/100</span></div>
            <div className="g-ours">Our HR-based estimate, computed on this phone</div>
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- A2 · Morning (recovery's new home) ----------------
function ScreenAMorning() {
  const n = GOOSE.lastNight, b = GOOSE.bands;
  return (
    <Phone tabs={TABS_A} active="Morning">
      <div className="g-body">
        <HeaderA title="This morning" sub={n.dateLabel + " · " + n.processedLabel}></HeaderA>

        <div className="g-card" style={{ background: "linear-gradient(180deg, color-mix(in oklab, var(--hrv) 9%, var(--surface)), var(--surface))" }}>
          <div style={{ fontFamily: "var(--font-display)", fontSize: 21, fontWeight: 600, lineHeight: 1.3 }}>
            HRV and resting heart rate sit in your usual range — wrist temp and respiratory both read at the top of yours.
          </div>
          <div className="g-ours">Judged against your own last weeks, not population norms. Our numbers, never WHOOP's.</div>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <VitalTile label="Overnight HRV" color="var(--hrv)" value={n.hrv} unit="ms" band={b.hrv} decimals={1}></VitalTile>
          <VitalTile label="Resting HR" color="var(--heart)" value={n.rhr} unit="bpm" band={b.rhr}></VitalTile>
          <VitalTile label="Respiratory" color="var(--resp)" value={n.resp} unit="rpm" band={b.resp} provisional={true} decimals={1}></VitalTile>
          <VitalTile label="Wrist temp" color="var(--temp)" value={n.temp} unit="°C" band={b.temp} provisional={true} decimals={1}></VitalTile>
        </div>

        <div className="g-card">
          <CardTitle color="var(--sleep)" right={<GIcon name="chev" size={16} color="var(--text-3)"></GIcon>}>Sleep</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 34, whiteSpace: "nowrap" }}>7h 12m</div>
            <span className="g-pill ok">close to your 7h 24m average</span>
          </div>
          <div className="g-ours">Detected by us from movement + HR — not WHOOP sleep stages</div>
        </div>

        <div className="g-card" style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
          <GIcon name="moon" size={20} color="var(--text-3)"></GIcon>
          <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.45 }}>
            Today's resting HR (77 bpm) is partial and reads high. Tonight's sleep completes the picture — check back tomorrow morning.
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- A3 · Trends ----------------
function ScreenATrends() {
  const b = GOOSE.bands;
  const mk = (key) => GOOSE.vitalsDaily.map((d) => ({ value: d[key], label: d.date.slice(5).replace("-", "/") }));
  return (
    <Phone tabs={TABS_A} active="Trends">
      <div className="g-body">
        <HeaderA title="Trends"></HeaderA>
        <Seg items={["W", "M", "6M"]} on="W"></Seg>

        <div className="g-card">
          <CardTitle color="var(--hrv)" right={<Delta value={-0.7} unit="ms" good={true}></Delta>}>Overnight HRV</CardTitle>
          <div className="g-num" style={{ fontSize: 28 }}>73.5<span className="g-unit">ms</span></div>
          <BandTrend series={mk("hrv")} band={b.hrv} color="var(--hrv)"></BandTrend>
        </div>

        <div className="g-card">
          <CardTitle color="var(--heart)" right={<Delta value={3} unit="bpm" good={false}></Delta>}>Resting HR</CardTitle>
          <div className="g-num" style={{ fontSize: 28 }}>58<span className="g-unit">bpm</span></div>
          <BandTrend series={mk("rhr")} band={b.rhr} color="var(--heart)"></BandTrend>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <div className="g-card" style={{ gap: "calc(7px * var(--u))", minWidth: 0 }}>
            <CardTitle color="var(--temp)">Wrist temp<span style={{ color: "var(--text-3)" }}> *</span></CardTitle>
            <div className="g-num" style={{ fontSize: 24 }}>34.0<span className="g-unit">°C</span></div>
            <BandTrend series={mk("temp")} band={b.temp} color="var(--temp)" w={140} h={64} fmt={(v) => v.toFixed(1)}></BandTrend>
          </div>
          <div className="g-card" style={{ gap: "calc(7px * var(--u))", minWidth: 0 }}>
            <CardTitle color="var(--resp)">Respiratory<span style={{ color: "var(--text-3)" }}> *</span></CardTitle>
            <div className="g-num" style={{ fontSize: 24 }}>15.4<span className="g-unit">rpm</span></div>
            <BandTrend series={mk("resp")} band={b.resp} color="var(--resp)" w={140} h={64} fmt={(v) => v.toFixed(2)}></BandTrend>
          </div>
        </div>
        <div className="g-ours" style={{ marginTop: "calc(-6px * var(--u))" }}>* provisional — coarse skin-temp &amp; respiratory calibration</div>

        <div className="g-card">
          <CardTitle color="var(--sleep)">Sleep</CardTitle>
          <SleepBars nights={GOOSE.sleepNights}></SleepBars>
        </div>

        <div className="g-card">
          <CardTitle color="var(--activity)">Steps per day</CardTitle>
          <StepsBars data={GOOSE.stepsHourly}></StepsBars>
          <GapNote>Only days the band streamed — step history can't backfill</GapNote>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- A4 · Sleep detail ----------------
function ScreenASleep() {
  return (
    <Phone tabs={TABS_A} active="Morning">
      <div className="g-body">
        <div style={{ display: "flex", alignItems: "center", gap: 4, color: "var(--text-2)", fontSize: 14, fontWeight: 600 }}>
          <GIcon name="chev" size={15} color="var(--text-3)"></GIcon>
          <span style={{ transform: "scaleX(-1)", display: "none" }}></span>
          <span style={{ marginLeft: -22, paddingLeft: 20 }}>Morning</span>
        </div>
        <HeaderA title="Sleep" sub="Night of Jun 8–9"></HeaderA>

        <div className="g-card">
          <CardTitle color="var(--sleep)">Last night</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 52, whiteSpace: "nowrap" }}>7<span className="g-unit" style={{ fontSize: "0.5em" }}>h</span> 12<span className="g-unit" style={{ fontSize: "0.5em" }}>m</span></div>
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <span className="g-pill mut">in bed ~23:10 – 06:40</span>
            <span className="g-pill ok">near your average</span>
          </div>
          <div className="g-ours">Our own detection from movement + heart rate. We don't show sleep stages — the band doesn't give us enough to do them honestly.</div>
        </div>

        <div className="g-card">
          <CardTitle color="var(--sleep)">This week</CardTitle>
          <SleepBars nights={GOOSE.sleepNights} h={120}></SleepBars>
        </div>

        <div className="g-card">
          <CardTitle>Nights</CardTitle>
          <div className="g-rows">
            {[...GOOSE.sleepNights].reverse().map((nt) => (
              <div className="g-row" key={nt.date}>
                <span style={{ flex: 1, color: "var(--text-2)", fontSize: 14 }}>{nt.date}</span>
                <span className="g-num" style={{ fontSize: 17 }}>{GOOSE.fmtSleep(nt.min)}</span>
                <GIcon name="chev" size={14} color="var(--text-3)"></GIcon>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- A5 · HRV detail (two HRVs, separated) ----------------
function ScreenAHrv() {
  const b = GOOSE.bands;
  const mk = GOOSE.vitalsDaily.map((d) => ({ value: d.hrv, label: d.date.slice(5).replace("-", "/") }));
  return (
    <Phone tabs={TABS_A} active="Morning">
      <div className="g-body">
        <HeaderA title="HRV" sub="Two different numbers — don't mix them"></HeaderA>

        <div className="g-card">
          <CardTitle color="var(--hrv)">Overnight HRV · rMSSD</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 48 }}>73.5<span className="g-unit">ms</span></div>
            <BandPill value={73.5} band={b.hrv}></BandPill>
          </div>
          <div className="g-ours">One number per night, from thousands of R–R intervals while you sleep. This is the one to watch.</div>
          <BandTrend series={mk} band={b.hrv} color="var(--hrv)" h={110}></BandTrend>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "var(--text-3)" }}>
            <span>Your usual: 67–80 ms</span><span>mean 73 ms</span>
          </div>
        </div>

        <div className="g-card" style={{ borderStyle: "dashed" }}>
          <CardTitle color="var(--hrv)" right={<span className="g-pill live"><span className="g-dot" style={{ background: "var(--hrv)", width: 7, height: 7 }}></span>live</span>}>Live HRV</CardTitle>
          <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
            <div className="g-num" style={{ fontSize: 30, color: "var(--text-2)" }}>61<span className="g-unit">ms</span></div>
            <LiveSpark color="var(--hrv)" w={140} h={36} seed={8}></LiveSpark>
          </div>
          <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.45 }}>
            Computed from the last few minutes of R–R intervals. It swings with every breath and posture change — interesting to watch, wrong to compare against overnight values.
          </div>
        </div>

        <div className="g-card" style={{ flexDirection: "row", gap: 12, alignItems: "center" }}>
          <GIcon name="lock" size={20} color="var(--text-3)"></GIcon>
          <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.45 }}>
            rMSSD is our own calculation, on your hardware. It is not WHOOP's recovery score, and we don't make one.
          </div>
        </div>
      </div>
    </Phone>
  );
}

// ---------------- A6 · More ----------------
function ScreenAMore() {
  const MoreRow = ({ icon, label, sub, right }) => (
    <div className="g-row">
      <span style={{ color: "var(--text-3)" }}><GIcon name={icon} size={20}></GIcon></span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, fontWeight: 600 }}>{label}</div>
        {sub ? <div style={{ fontSize: 12.5, color: "var(--text-3)", marginTop: 1 }}>{sub}</div> : null}
      </div>
      {right || <GIcon name="chev" size={15} color="var(--text-3)"></GIcon>}
    </div>
  );
  return (
    <Phone tabs={TABS_A} active="More">
      <div className="g-body">
        <HeaderA title="More"></HeaderA>

        <div className="g-card">
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div style={{ width: 46, height: 46, borderRadius: 14, background: "var(--surface-3)", display: "flex", alignItems: "center", justifyContent: "center" }}>
              <GIcon name="band" size={26} color="var(--text-2)"></GIcon>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: "var(--font-display)", fontSize: 17, fontWeight: 700 }}>WHOOP 4.0 band</div>
              <div style={{ fontSize: 13, color: "var(--text-2)" }}>Connected · in range</div>
            </div>
            <div style={{ textAlign: "right" }}>
              <div className="g-num" style={{ fontSize: 22 }}>64%</div>
              <div style={{ fontSize: 11.5, color: "var(--text-3)" }}>not charging</div>
            </div>
          </div>
        </div>

        <div className="g-card" style={{ paddingTop: 4, paddingBottom: 4 }}>
          <div className="g-rows">
            <MoreRow icon="bolt" label="Capture & sync" sub="Last sync 2 min ago · backfilling HR buffer"></MoreRow>
            <MoreRow icon="day" label="Skin-temp calibration" sub="Coarse 2-point fit · provisional" right={<span className="g-prov">prov.</span>}></MoreRow>
            <MoreRow icon="pulse" label="Coach" sub="Ask questions about your own data"></MoreRow>
            <MoreRow icon="gear" label="Debug & developer"></MoreRow>
          </div>
        </div>

        <div className="g-card" style={{ flexDirection: "row", gap: 12, alignItems: "flex-start" }}>
          <GIcon name="lock" size={20} color="var(--activity)"></GIcon>
          <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.5 }}>
            <strong style={{ color: "var(--text)" }}>Local-first.</strong> Your data moves between this phone and your own server — nowhere else. No analytics, no third parties, no WHOOP cloud. Every number here is computed by Goose.
          </div>
        </div>

        <div className="g-ours" style={{ textAlign: "center" }}>
          Goose 0.4 · not a medical device · raw signals &amp; rough estimates only
        </div>
      </div>
    </Phone>
  );
}

Object.assign(window, {
  BandGauge, VitalTile, HeaderA, ScreenAToday, ScreenAMorning, ScreenATrends,
  ScreenASleep, ScreenAHrv, ScreenAMore,
});
