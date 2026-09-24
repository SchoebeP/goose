// ============================================================
// proto-app.jsx — Direction A prototype bootstrap + Tweaks
// ============================================================

const PROTO_TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "palette": "Signal",
  "density": "regular",
  "chartStyle": "band",
  "contrastBoost": false,
  "heroStyle": "chart",
  "bandAway": false
}/*EDITMODE-END*/;

const PROTO_PALETTES = {
  Signal: { heart: "#FF8177", hrv: "#B9A3FF", activity: "#8BD9A9", sleep: "#86B9FF", range: "#FFB876", charge: "#FFD479", resp: "#74D6CF", temp: "#FFA98F" },
  Dawn:   { heart: "#FF9077", hrv: "#D2A6E8", activity: "#ABD98B", sleep: "#92C4E8", range: "#FFC07A", charge: "#FFDB8C", resp: "#8FD9C4", temp: "#FFB48A" },
  Mist:   { heart: "#E8918C", hrv: "#A6A9E0", activity: "#8FC9AD", sleep: "#8FB7E0", range: "#E0B086", charge: "#E0CB8F", resp: "#82C6C2", temp: "#E0A28F" },
};

function ProtoApp() {
  const [t, setTweak] = useTweaks(PROTO_TWEAK_DEFAULTS);
  const pal = PROTO_PALETTES[t.palette] || PROTO_PALETTES.Signal;
  const vars = {};
  Object.keys(pal).forEach((k) => { vars["--" + k] = pal[k]; });
  const ctx = { chartStyle: t.chartStyle, heroStyle: t.heroStyle, bandAway: t.bandAway };
  return (
    <GooseCtx.Provider value={ctx}>
      <div style={{ ...vars, height: "100%" }}>
        <PScale>
          <PDevice tweaks={t}
            screens={{ Today: PToday, Morning: PMorning, Trends: PTrends, More: PMore }}
            details={{ sleep: DSleep, hrv: DHrv }}></PDevice>
        </PScale>
        <TweaksPanel>
          <TweakSection label="State"></TweakSection>
          <TweakToggle label="Band out of range" value={t.bandAway}
            onChange={(v) => setTweak("bandAway", v)}></TweakToggle>
          <TweakSection label="Today hero"></TweakSection>
          <TweakRadio label="Style" value={t.heroStyle} options={["chart", "arc"]}
            onChange={(v) => setTweak("heroStyle", v)}></TweakRadio>
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

ReactDOM.createRoot(document.getElementById("root")).render(<ProtoApp></ProtoApp>);
