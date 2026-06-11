// ============================================================
// proto-screens.jsx — Direction A prototype screens (interactive)
// Tabs: Today · Morning · Trends · More; details: Sleep, HRV.
// ============================================================

// ---------------- Today ----------------
function PToday() {
  const nav = usePNav();
  const { heroStyle, bandAway } = React.useContext(GooseCtx);
  const [hr, setHr] = React.useState(GOOSE.hrNow);
  const [tick, setTick] = React.useState(0);
  React.useEffect(() => {
    if (bandAway) return;
    const id = setInterval(() => {
      setHr((v) => Math.max(58, Math.min(96, v + Math.round((Math.random() - 0.48) * 4))));
      setTick((t) => t + 1);
    }, 1000);
    return () => clearInterval(id);
  }, [bandAway]);

  return (
    <PScreen screenLabel="Today">
      <div className="g-body">
        <HeaderA title="Today" sub="Tuesday, June 10"
          right={
            <span className="g-pill mut" style={{ marginTop: 6 }}>
              <span className={"g-dot" + (bandAway ? "" : "")} style={{ background: bandAway ? "var(--text-3)" : "var(--activity)", width: 7, height: 7 }}></span>
              {bandAway ? "Band · away" : "Band · " + GOOSE.battery.pct + "%"}
            </span>
          }></HeaderA>

        <div className="g-card">
          <CardTitle color="var(--heart)"
            right={
              bandAway ? (
                <span className="g-pill mut">out of range</span>
              ) : (
                <span className="g-pill live"><span className="g-dot p-livedot" style={{ background: "var(--heart)", width: 7, height: 7 }}></span>live</span>
              )
            }>
            Heart rate
          </CardTitle>

          {heroStyle === "arc" && !bandAway ? (
            <div style={{ position: "relative", display: "flex", justifyContent: "center", padding: "4px 0" }}>
              <DayArc data={GOOSE.hrHourly} size={264}></DayArc>
              <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
                <div className="g-num" style={{ fontSize: 50 }}>{hr}</div>
                <div style={{ fontSize: 12, color: "var(--text-2)", fontWeight: 600 }}>bpm now</div>
              </div>
            </div>
          ) : (
            <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
              {bandAway ? (
                <div className="g-num" style={{ fontSize: 58, color: "var(--text-3)" }}>—<span className="g-unit">bpm</span></div>
              ) : (
                <div className="g-num" style={{ fontSize: 58 }}>{hr}<span className="g-unit">bpm</span></div>
              )}
              {bandAway ? null : <LiveSpark w={130} h={40} seed={3 + (tick % 7)}></LiveSpark>}
            </div>
          )}

          {bandAway ? (
            <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.45 }}>
              Last seen 12:48, about 10 m is the limit. The band keeps recording heart rate on its own — it backfills when you're back in range.
            </div>
          ) : (
            <div className="g-ours">From the band over Bluetooth · day range 54–130 · avg 82</div>
          )}
          {heroStyle === "arc" && !bandAway ? null : <DayHRChart data={GOOSE.hrHourly}></DayHRChart>}
          <GapNote>Band was away 13:00–15:00 — HR backfills next sync</GapNote>
        </div>

        <div className="g-card">
          <CardTitle color="var(--activity)">Steps</CardTitle>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
            <div className="g-num" style={{ fontSize: 34 }}>7,392</div>
            <span className="g-pill mut">{bandAway ? "paused — band away" : "so far today"}</span>
          </div>
          <StepsBars data={GOOSE.stepsHourly}></StepsBars>
          <GapNote>{bandAway ? "Steps aren't buffered by the band — this gap will stay" : "Steps only count while connected — gaps stay gaps"}</GapNote>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <div className="g-card p-tappable" style={{ gap: "calc(8px * var(--u))" }} onClick={() => nav.pushDetail("hrv")}>
            <CardTitle color="var(--hrv)">Live HRV</CardTitle>
            <div className="g-num" style={{ fontSize: 28, color: bandAway ? "var(--text-3)" : undefined }}>{bandAway ? "—" : "61"}<span className="g-unit">ms</span></div>
            <div className="g-ours">Instantaneous &amp; noisy — tap to see how it differs from overnight</div>
          </div>
          <div className="g-card" style={{ gap: "calc(8px * var(--u))" }}>
            <CardTitle color="var(--charge)">Energy</CardTitle>
            <div className="g-num" style={{ fontSize: 28 }}>72<span className="g-unit">/100</span></div>
            <div className="g-ours">Our HR-based estimate, computed on this phone</div>
          </div>
        </div>
      </div>
    </PScreen>
  );
}

// ---------------- Morning ----------------
function PMorning() {
  const nav = usePNav();
  const n = GOOSE.lastNight, b = GOOSE.bands;
  return (
    <PScreen screenLabel="Morning">
      <div className="g-body">
        <div className="g-card" style={{ background: "linear-gradient(180deg, color-mix(in oklab, var(--hrv) 9%, var(--surface)), var(--surface))", gap: 6 }}>
          <div style={{ fontSize: 11.5, letterSpacing: "0.12em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, whiteSpace: "nowrap" }}>
            {n.dateLabel} · just processed
          </div>
          <h1 className="g-h1" style={{ fontSize: 27, lineHeight: 1.15 }}>A mostly usual morning.</h1>
          <p className="g-sub" style={{ lineHeight: 1.5 }}>
            HRV and resting heart rate sit in your range — wrist temp and respiratory both read at the top of theirs.
          </p>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <div className="p-tappable" onClick={() => nav.pushDetail("hrv")}>
            <VitalTile label="HRV" color="var(--hrv)" value={n.hrv} unit="ms" band={b.hrv} decimals={1}></VitalTile>
          </div>
          <VitalTile label="Resting HR" color="var(--heart)" value={n.rhr} unit="bpm" band={b.rhr}></VitalTile>
          <VitalTile label="Respiratory" color="var(--resp)" value={n.resp} unit="rpm" band={b.resp} provisional={true} decimals={1}></VitalTile>
          <VitalTile label="Wrist temp" color="var(--temp)" value={n.temp} unit="°C" band={b.temp} provisional={true} decimals={1}></VitalTile>
        </div>
        <div className="g-ours" style={{ marginTop: "calc(-6px * var(--u))" }}>* provisional — coarse skin-temp &amp; respiratory calibration</div>

        <div className="g-card p-tappable" onClick={() => nav.pushDetail("sleep")}>
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

        <div className="g-ours" style={{ textAlign: "center" }}>
          Judged against your own last weeks, not population norms. Our numbers, never WHOOP's.
        </div>
      </div>
    </PScreen>
  );
}

// ---------------- Trends ----------------
function PTrends() {
  const [period, setPeriod] = React.useState("W");
  const p = GPROTO.periods[period];
  const b = GOOSE.bands;
  return (
    <PScreen screenLabel="Trends">
      <div className="g-body">
        <HeaderA title="Trends"></HeaderA>
        <div className="g-seg">
          {["W", "M", "6M"].map((s) => (
            <div key={s} className={s === period ? "on" : ""} onClick={() => setPeriod(s)} style={{ cursor: "pointer" }}>{s}</div>
          ))}
        </div>

        <div className="g-card">
          <CardTitle color="var(--hrv)" right={<Delta value={-0.7} unit="ms" good={true}></Delta>}>Overnight HRV</CardTitle>
          <div className="g-num" style={{ fontSize: 28 }}>{p.latest.hrv}<span className="g-unit">ms</span></div>
          <BandTrend series={p.hrv} band={b.hrv} color="var(--hrv)"></BandTrend>
        </div>

        <div className="g-card">
          <CardTitle color="var(--heart)" right={<Delta value={3} unit="bpm" good={false}></Delta>}>Resting HR</CardTitle>
          <div className="g-num" style={{ fontSize: 28 }}>{p.latest.rhr}<span className="g-unit">bpm</span></div>
          <BandTrend series={p.rhr} band={b.rhr} color="var(--heart)"></BandTrend>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", gap: "calc(12px * var(--u))" }}>
          <div className="g-card" style={{ gap: "calc(7px * var(--u))", minWidth: 0 }}>
            <CardTitle color="var(--temp)">Wrist temp<span style={{ color: "var(--text-3)" }}> *</span></CardTitle>
            <div className="g-num" style={{ fontSize: 24 }}>{p.latest.temp}<span className="g-unit">°C</span></div>
            <BandTrend series={p.temp} band={b.temp} color="var(--temp)" w={140} h={64} fmt={(v) => v.toFixed(1)}></BandTrend>
          </div>
          <div className="g-card" style={{ gap: "calc(7px * var(--u))", minWidth: 0 }}>
            <CardTitle color="var(--resp)">Respiratory<span style={{ color: "var(--text-3)" }}> *</span></CardTitle>
            <div className="g-num" style={{ fontSize: 24 }}>{p.latest.resp}<span className="g-unit">rpm</span></div>
            <BandTrend series={p.resp} band={b.resp} color="var(--resp)" w={140} h={64} fmt={(v) => v.toFixed(2)}></BandTrend>
          </div>
        </div>
        <div className="g-ours" style={{ marginTop: "calc(-6px * var(--u))" }}>* provisional — coarse skin-temp &amp; respiratory calibration</div>

        <div className="g-card">
          <CardTitle color="var(--sleep)">Sleep</CardTitle>
          <SleepBars nights={p.sleep}></SleepBars>
        </div>

        <div className="g-card">
          <CardTitle color="var(--activity)">Steps per day</CardTitle>
          <DailyBars data={p.steps}></DailyBars>
          <GapNote>Only days the band streamed — step history can't backfill</GapNote>
        </div>
      </div>
    </PScreen>
  );
}

// ---------------- More ----------------
function PMore() {
  const MoreRow = ({ icon, label, sub, right }) => (
    <div className="g-row p-tappable">
      <span style={{ color: "var(--text-3)" }}><GIcon name={icon} size={20}></GIcon></span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, fontWeight: 600 }}>{label}</div>
        {sub ? <div style={{ fontSize: 12.5, color: "var(--text-3)", marginTop: 1 }}>{sub}</div> : null}
      </div>
      {right || <GIcon name="chev" size={15} color="var(--text-3)"></GIcon>}
    </div>
  );
  return (
    <PScreen screenLabel="More">
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
    </PScreen>
  );
}

// ---------------- detail: Sleep ----------------
function DSleep() {
  const nav = usePNav();
  return (
    <PScreen detail={true} onBack={nav.pop} title="Morning" screenLabel="Sleep detail">
      <div className="g-body">
        <HeaderA title="Sleep" sub="Night of Jun 8–9"></HeaderA>
        <div className="g-card">
          <CardTitle color="var(--sleep)">Last night</CardTitle>
          <div className="g-num" style={{ fontSize: 52, whiteSpace: "nowrap" }}>7<span className="g-unit" style={{ fontSize: "0.5em" }}>h</span> 12<span className="g-unit" style={{ fontSize: "0.5em" }}>m</span></div>
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
              </div>
            ))}
          </div>
        </div>
      </div>
    </PScreen>
  );
}

// ---------------- detail: HRV ----------------
function DHrv() {
  const nav = usePNav();
  const b = GOOSE.bands;
  const mk = GOOSE.vitalsDaily.map((d) => ({ value: d.hrv, label: d.date.slice(5).replace("-", "/") }));
  return (
    <PScreen detail={true} onBack={nav.pop} title="Back" screenLabel="HRV detail">
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
          <CardTitle color="var(--hrv)" right={<span className="g-pill live"><span className="g-dot p-livedot" style={{ background: "var(--hrv)", width: 7, height: 7 }}></span>live</span>}>Live HRV</CardTitle>
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
    </PScreen>
  );
}

Object.assign(window, { PToday, PMorning, PTrends, PMore, DSleep, DHrv });
