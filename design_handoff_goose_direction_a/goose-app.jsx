// ============================================================
// goose-app.jsx — canvas assembly + Tweaks
// ============================================================

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "palette": "Signal",
  "density": "regular",
  "chartStyle": "band",
  "contrastBoost": false
}/*EDITMODE-END*/;

const GOOSE_PALETTES = {
  Signal: { heart: "#FF8177", hrv: "#B9A3FF", activity: "#8BD9A9", sleep: "#86B9FF", range: "#FFB876", charge: "#FFD479", resp: "#74D6CF", temp: "#FFA98F" },
  Dawn:   { heart: "#FF9077", hrv: "#D2A6E8", activity: "#ABD98B", sleep: "#92C4E8", range: "#FFC07A", charge: "#FFDB8C", resp: "#8FD9C4", temp: "#FFB48A" },
  Mist:   { heart: "#E8918C", hrv: "#A6A9E0", activity: "#8FC9AD", sleep: "#8FB7E0", range: "#E0B086", charge: "#E0CB8F", resp: "#82C6C2", temp: "#E0A28F" },
};

// ---------- intro / rationale ----------
function BriefCard() {
  return (
    <div className="brief-card">
      <h2>Goose redesign — assumptions &amp; reasoning</h2>
      <h3>What I anchored on</h3>
      <ul>
        <li><strong>Recovery gets a home.</strong> The overnight vitals + personal bands are the richest data; every direction gives "this morning" first-class placement.</li>
        <li><strong>Anchored to the last complete night</strong> (Jun 8–9), never "today" — so the morning view is always full, and today's partial resting HR is explained, not shown blank.</li>
        <li><strong>Honest gaps.</strong> Hatched regions for band-away time; copy says whether data backfills (HR: yes, steps: no).</li>
        <li><strong>Two HRVs, separated.</strong> Live HRV is labelled noisy and points to the overnight number; the HRV detail screen explains both.</li>
        <li><strong>SpO2 is fully omitted</strong>, per your choice.</li>
        <li>"Our own numbers" framing appears once per screen, quietly — not as a banner.</li>
      </ul>
      <h3>The three directions</h3>
      <ul>
        <li><strong>A · Quiet Companion</strong> — the safe one. 4 tabs (Today · Morning · Trends · More), soft cards, familiar iOS patterns.</li>
        <li><strong>B · Day Arc</strong> — the adventurous one. The day is a 24h loop: a radial hero where sleep, heart rate, gaps and "now" live on one clock. 3 tabs (Day · History · Band).</li>
        <li><strong>C · Ledger</strong> — same IA as A, restyled as a quiet serif journal: hairlines instead of cards, editorial headlines that judge the day.</li>
      </ul>
      <h3>Use the Tweaks panel for</h3>
      <p>Accent palette (Signal / Dawn / Mist) · density · chart style (band / line / bars) · text-contrast boost. Everything updates live across all screens.</p>
    </div>
  );
}

// ---------- design language specimen ----------
function DesignLanguage() {
  const sw = (name, v) => (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
      <span style={{ width: 34, height: 34, borderRadius: 12, background: "var(--" + v + ")" }}></span>
      <span style={{ fontSize: 10.5, color: "var(--text-3)", fontWeight: 600 }}>{name}</span>
    </div>
  );
  return (
    <div style={{ background: "var(--bg)", color: "var(--text)", fontFamily: "var(--font-body)", height: "100%", boxSizing: "border-box", padding: "28px 30px", display: "flex", flexDirection: "column", gap: 22 }}>
      <div style={{ display: "flex", gap: 30, alignItems: "baseline" }}>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 8 }}>Numerals &amp; display — Schibsted Grotesk</div>
          <div className="g-num" style={{ fontSize: 64 }}>73.5<span className="g-unit">ms</span></div>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 8 }}>Body — Albert Sans</div>
          <div style={{ fontSize: 14, color: "var(--text-2)", lineHeight: 1.5 }}>Calm, friendly, judged against your own normal — never population norms.</div>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 8 }}>Direction C — Source Serif 4</div>
          <div style={{ fontFamily: "var(--font-serif)", fontSize: 22, fontWeight: 600 }}>A usual morning.</div>
        </div>
      </div>

      <div>
        <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>Per-metric accents (tweakable)</div>
        <div style={{ display: "flex", gap: 18 }}>
          {sw("heart", "heart")}{sw("HRV", "hrv")}{sw("activity", "activity")}{sw("sleep", "sleep")}
          {sw("range", "range")}{sw("charge", "charge")}{sw("resp", "resp")}{sw("temp", "temp")}
        </div>
      </div>

      <div style={{ display: "flex", gap: 26, alignItems: "flex-start" }}>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>Honesty kit</div>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", maxWidth: 330 }}>
            <span className="g-pill ok">in your usual range</span>
            <span className="g-pill warn">above usual</span>
            <span className="g-prov">provisional</span>
            <GapNote>band away — gap stays a gap</GapNote>
          </div>
        </div>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>Personal band gauge</div>
          <BandGauge value={73.5} band={GOOSE.bands.hrv} color="var(--hrv)" w={170}></BandGauge>
          <div style={{ fontSize: 11, color: "var(--text-3)", marginTop: 6 }}>dot = last night · pill = your usual 67–80</div>
        </div>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.1em", textTransform: "uppercase", color: "var(--text-3)", fontWeight: 600, marginBottom: 10 }}>Framing line</div>
          <div className="g-ours" style={{ maxWidth: 180 }}>rMSSD — our own number, computed on your hardware. Never WHOOP's.</div>
        </div>
      </div>
    </div>
  );
}

// ---------- IA diagrams ----------
function IADiagram({ title, note, tabs, detail }) {
  return (
    <div style={{ background: "var(--bg)", color: "var(--text)", fontFamily: "var(--font-body)", height: "100%", boxSizing: "border-box", padding: "22px 22px", display: "flex", flexDirection: "column", gap: 14 }}>
      <div>
        <div style={{ fontFamily: "var(--font-display)", fontSize: 17, fontWeight: 700 }}>{title}</div>
        <div style={{ fontSize: 12.5, color: "var(--text-2)", marginTop: 4, lineHeight: 1.45 }}>{note}</div>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        {tabs.map((t) => (
          <div key={t.name} style={{ flex: 1, border: "1px solid " + (t.hot ? "var(--hrv)" : "var(--line-strong)"), borderRadius: 12, padding: "10px 8px", background: t.hot ? "rgba(185,163,255,0.08)" : "var(--surface)" }}>
            <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6, color: t.hot ? "var(--hrv)" : "var(--text)" }}>{t.name}</div>
            {t.items.map((it) => (
              <div key={it} style={{ fontSize: 11, color: "var(--text-2)", padding: "3px 0", borderTop: "1px solid var(--line)" }}>{it}</div>
            ))}
          </div>
        ))}
      </div>
      <div style={{ fontSize: 11.5, color: "var(--text-3)", lineHeight: 1.5 }}>{detail}</div>
    </div>
  );
}

// ---------- App ----------
function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const pal = GOOSE_PALETTES[t.palette] || GOOSE_PALETTES.Signal;
  const vars = {};
  Object.keys(pal).forEach((k) => { vars["--" + k] = pal[k]; });
  const ctx = {
    chartStyle: t.chartStyle,
    density: t.density === "regular" ? null : t.density,
    contrast: t.contrastBoost ? "boost" : null,
  };
  return (
    <GooseCtx.Provider value={ctx}>
      <div style={{ ...vars, height: "100%" }}>
        <DesignCanvas>
          <DCSection id="brief" title="Brief, system & IA" subtitle="Read me first — assumptions, the shared design language, and three IA shapes">
            <DCArtboard id="brief-note" label="Assumptions & reasoning" width={470} height={710}>
              <BriefCard></BriefCard>
            </DCArtboard>
            <DCArtboard id="lang" label="Design language (shared by all directions)" width={780} height={420}>
              <DesignLanguage></DesignLanguage>
            </DCArtboard>
            <DCArtboard id="ia-a" label="IA 1 · Four tabs (Direction A & C)" width={360} height={400}>
              <IADiagram
                title="Today · Morning · Trends · More"
                note="Recovery gets its own tab. Smallest change from the shipped app — Today keeps live data, Morning owns the overnight story."
                tabs={[
                  { name: "Today", items: ["live HR", "day HR chart", "steps", "live HRV*", "energy"] },
                  { name: "Morning", hot: true, items: ["last night's 4 vitals", "vs usual bands", "sleep", "→ HRV detail", "→ sleep detail"] },
                  { name: "Trends", items: ["W / M / 6M", "4 vitals", "steps", "sleep"] },
                  { name: "More", items: ["band & battery", "sync", "calibration", "privacy"] },
                ]}
                detail="* live HRV stays on Today but is labelled noisy and links to Morning. Unreachable screens (Sleep, HRV detail) hang off Morning."></IADiagram>
            </DCArtboard>
            <DCArtboard id="ia-b" label="IA 2 · Time-based (Direction B)" width={360} height={400}>
              <IADiagram
                title="Day · History · Band"
                note="One 'Day' surface ordered by time: last night → this morning's report → now → tonight. No Today/Morning split to explain."
                tabs={[
                  { name: "Day", hot: true, items: ["24h arc hero", "morning digest", "live now", "steps so far", "tonight hint"] },
                  { name: "History", items: ["mornings stream", "band charts", "honest '—' for today"] },
                  { name: "Band", items: ["battery ring", "backfill status", "calibration", "privacy"] },
                ]}
                detail="Riskier: recovery is a section, not a tab — but the clock metaphor makes the night-feeds-morning causality visible."></IADiagram>
            </DCArtboard>
          </DCSection>

          <DCSection id="dir-a" title="Direction A · Quiet Companion (safe)" subtitle="4-tab IA, soft cards, big numerals — familiar iOS health patterns, recovery finally has a home">
            <DCArtboard id="a-today" label="A1 · Today" width={393} height={980}><ScreenAToday></ScreenAToday></DCArtboard>
            <DCArtboard id="a-morning" label="A2 · Morning — recovery's new home" width={393} height={1020}><ScreenAMorning></ScreenAMorning></DCArtboard>
            <DCArtboard id="a-trends" label="A3 · Trends" width={393} height={1260}><ScreenATrends></ScreenATrends></DCArtboard>
            <DCArtboard id="a-sleep" label="A4 · Sleep detail" width={393} height={970}><ScreenASleep></ScreenASleep></DCArtboard>
            <DCArtboard id="a-hrv" label="A5 · HRV detail — two HRVs, separated" width={393} height={930}><ScreenAHrv></ScreenAHrv></DCArtboard>
            <DCArtboard id="a-more" label="A6 · More" width={393} height={852}><ScreenAMore></ScreenAMore></DCArtboard>
          </DCSection>

          <DCSection id="dir-b" title="Direction B · Day Arc (adventurous)" subtitle="The day as one 24h loop — sleep, heart rate, gaps and 'now' share a single clock">
            <DCArtboard id="b-day" label="B1 · Day" width={393} height={1000}><ScreenBDay></ScreenBDay></DCArtboard>
            <DCArtboard id="b-history" label="B2 · History — stream of mornings" width={393} height={900}><ScreenBHistory></ScreenBHistory></DCArtboard>
            <DCArtboard id="b-band" label="B3 · Band" width={393} height={852}><ScreenBBand></ScreenBBand></DCArtboard>
          </DCSection>

          <DCSection id="dir-c" title="Direction C · Ledger (editorial remix of A)" subtitle="Same 4-tab IA as A, restyled — serif numerals, hairlines, headlines that judge the day">
            <DCArtboard id="c-today" label="C1 · Today (ledger)" width={393} height={1080}><ScreenCToday></ScreenCToday></DCArtboard>
            <DCArtboard id="c-trends" label="C2 · Trends (ledger)" width={393} height={1080}><ScreenCTrends></ScreenCTrends></DCArtboard>
          </DCSection>
        </DesignCanvas>

        <TweaksPanel>
          <TweakSection label="Color"></TweakSection>
          <TweakRadio label="Accent palette" value={t.palette} options={["Signal", "Dawn", "Mist"]}
            onChange={(v) => setTweak("palette", v)}></TweakRadio>
          <TweakToggle label="Boost text contrast" value={t.contrastBoost}
            onChange={(v) => setTweak("contrastBoost", v)}></TweakToggle>
          <TweakSection label="Layout"></TweakSection>
          <TweakRadio label="Density" value={t.density} options={["compact", "regular", "comfy"]}
            onChange={(v) => setTweak("density", v)}></TweakRadio>
          <TweakSection label="Charts"></TweakSection>
          <TweakRadio label="Style" value={t.chartStyle} options={["band", "line", "bars"]}
            onChange={(v) => setTweak("chartStyle", v)}></TweakRadio>
        </TweaksPanel>
      </div>
    </GooseCtx.Provider>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App></App>);
