// ============================================================
// proto-shell.jsx — device frame, scaling, navigation, tab bar
// for the Direction A clickable prototype.
// ============================================================

const PNavCtx = React.createContext(null);

function usePNav() { return React.useContext(PNavCtx); }

function PScale({ children }) {
  const [scale, setScale] = React.useState(1);
  React.useEffect(() => {
    const fit = () => {
      const s = Math.min((window.innerHeight - 48) / 874, (window.innerWidth - 32) / 415, 1);
      setScale(Math.max(s, 0.3));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);
  return (
    <div className="p-stage">
      <div style={{ transform: "scale(" + scale + ")" }}>{children}</div>
    </div>
  );
}

function PTabBar() {
  const nav = usePNav();
  return (
    <div className="g-tabbar">
      {TABS_A.map((t) => (
        <div key={t.label} className={"g-tab" + (t.label === nav.tab ? " on" : "")}
          onClick={() => nav.setTab(t.label)}>
          <GIcon name={t.icon} size={23}></GIcon>
          <span>{t.label}</span>
        </div>
      ))}
    </div>
  );
}

// a full screen inside the device: status bar + scrollable content + tab bar
function PScreen({ children, detail, onBack, title, screenLabel }) {
  return (
    <div className={detail ? undefined : "p-screen"} data-screen-label={screenLabel}
      style={detail ? { display: "flex", flexDirection: "column", height: "100%" } : undefined}>
      <StatusBar></StatusBar>
      {detail ? (
        <div style={{ padding: "2px 12px 0" }}>
          <div className="p-back" onClick={onBack}>
            <span style={{ display: "inline-block", transform: "scaleX(-1)" }}>
              <GIcon name="chev" size={17}></GIcon>
            </span>
            {title || "Back"}
          </div>
        </div>
      ) : null}
      <div className="p-content">{children}</div>
      {detail ? null : <PTabBar></PTabBar>}
      <div className="g-homebar"></div>
    </div>
  );
}

// device root: manages active tab + pushed detail with exit animation
function PDevice({ tweaks, screens, details }) {
  const [tab, setTabRaw] = React.useState(() => {
    try { return localStorage.getItem("goose-proto-tab") || "Today"; } catch (e) { return "Today"; }
  });
  const [detail, setDetail] = React.useState(null); // {key, closing}
  const setTab = (t) => {
    setTabRaw(t);
    setDetail(null);
    try { localStorage.setItem("goose-proto-tab", t); } catch (e) {}
  };
  const pushDetail = (key) => setDetail({ key, closing: false });
  const pop = () => {
    setDetail((d) => (d ? { ...d, closing: true } : null));
    setTimeout(() => setDetail(null), 230);
  };
  const nav = { tab, setTab, pushDetail, pop };
  const ActiveTab = screens[tab] || screens.Today;
  const ActiveDetail = detail ? details[detail.key] : null;
  // No entrance animation on first mount or while the document is hidden:
  // hidden documents freeze CSS animations at frame 0 (opacity 0) and the
  // screen looks blank. Animate only user-driven changes in a visible doc.
  const firstMount = React.useRef(true);
  React.useEffect(() => { firstMount.current = false; }, []);
  const visible = typeof document !== "undefined" && document.visibilityState === "visible";
  return (
    <PNavCtx.Provider value={nav}>
      <div className="p-device" data-density={tweaks.density === "regular" ? null : tweaks.density}
        data-contrast={tweaks.contrastBoost ? "boost" : null}>
        <div className={(!firstMount.current && visible ? "p-tabfade " : "") + "p-screen"} key={tab} style={{ position: "absolute", inset: 0 }}>
          <ActiveTab></ActiveTab>
        </div>
        {ActiveDetail ? (
          <div className={"p-detail" + (visible ? "" : " no-anim") + (detail.closing ? " closing" : "")}
            data-density={tweaks.density === "regular" ? null : tweaks.density}>
            <ActiveDetail></ActiveDetail>
          </div>
        ) : null}
      </div>
    </PNavCtx.Provider>
  );
}

Object.assign(window, { PNavCtx, usePNav, PScale, PTabBar, PScreen, PDevice });
