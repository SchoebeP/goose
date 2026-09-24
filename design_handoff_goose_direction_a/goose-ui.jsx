// ============================================================
// goose-ui.jsx — shared UI primitives for the Goose redesign
// ============================================================

// ---------- icons (1.6px stroke, calm line style) ----------
function GIcon({ name, size = 22, color = "currentColor" }) {
  const p = { fill: "none", stroke: color, strokeWidth: 1.7, strokeLinecap: "round", strokeLinejoin: "round" };
  const paths = {
    heart: <path {...p} d="M11 19c-4.5-3.4-7.5-6.2-7.5-9.5C3.5 6.7 5.6 5 8 5c1.3 0 2.4.6 3 1.6C11.6 5.6 12.7 5 14 5c2.4 0 4.5 1.7 4.5 4.5 0 3.3-3 6.1-7.5 9.5z"></path>,
    sunrise: <g {...p}><path d="M4 16h14"></path><path d="M7.5 16a3.5 3.5 0 0 1 7 0"></path><path d="M11 9V6.5M5.6 11.6l-1.4-1.4M16.4 11.6l1.4-1.4"></path></g>,
    trends: <g {...p}><path d="M4 17l4.2-5 3.3 3 5.5-7"></path><circle cx="17" cy="8" r="1.4"></circle></g>,
    moon: <path {...p} d="M17.5 13.5A6.7 6.7 0 0 1 8.5 4.5a7 7 0 1 0 9 9z"></path>,
    dots: <g fill="currentColor" stroke="none"><circle cx="5.5" cy="11" r="1.6"></circle><circle cx="11" cy="11" r="1.6"></circle><circle cx="16.5" cy="11" r="1.6"></circle></g>,
    pulse: <path {...p} d="M3 11.5h3.4l1.8-4.5 2.8 8 1.9-5 1.2 1.5H19"></path>,
    steps: <g {...p}><path d="M7 4.5c1.7 0 2.6 1.4 2.6 3.2 0 2-1 3.3-2.4 3.3S4.9 9.7 4.9 7.7C4.9 5.9 5.7 4.5 7 4.5z"></path><path d="M6 13.5c1.5 0 2.4 1.2 2.4 2.7S7.5 18.8 6.3 18.8 4 17.7 4 16.2 4.7 13.5 6 13.5z" transform="translate(8.5 -1.5)"></path></g>,
    chev: <path {...p} d="M8.5 5.5L14 11l-5.5 5.5"></path>,
    band: <g {...p}><rect x="8" y="3.5" width="6" height="15" rx="3"></rect><path d="M8 7.5h6M8 14.5h6"></path></g>,
    gear: <g {...p}><circle cx="11" cy="11" r="3"></circle><path d="M11 3.8v2M11 16.2v2M3.8 11h2M16.2 11h2M5.9 5.9l1.4 1.4M14.7 14.7l1.4 1.4M16.1 5.9l-1.4 1.4M7.3 14.7l-1.4 1.4"></path></g>,
    lock: <g {...p}><rect x="5.5" y="10" width="11" height="8" rx="2.5"></rect><path d="M8 10V7.5a3 3 0 0 1 6 0V10"></path></g>,
    bolt: <path {...p} d="M12 3.5L6 12.5h4.5L10 18.5l6-9h-4.5z"></path>,
    day: <g {...p}><circle cx="11" cy="11" r="4"></circle><path d="M11 3.5V5M11 17v1.5M3.5 11H5M17 11h1.5M5.7 5.7l1 1M15.3 15.3l1 1M16.3 5.7l-1 1M6.7 15.3l-1 1"></path></g>,
    history: <g {...p}><path d="M4.5 11a6.5 6.5 0 1 1 1.9 4.6"></path><path d="M4.5 11V7.5M4.5 11H8"></path><path d="M11 7.8V11l2.3 1.5"></path></g>,
  };
  return <svg width={size} height={size} viewBox="0 0 22 22">{paths[name]}</svg>;
}

// ---------- phone shell ----------
function StatusBar() {
  return (
    <div className="g-statusbar">
      <span>9:41</span>
      <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <svg width="18" height="12" viewBox="0 0 18 12" fill="var(--text)">
          <rect x="0" y="7" width="3" height="5" rx="1"></rect><rect x="5" y="4.5" width="3" height="7.5" rx="1"></rect>
          <rect x="10" y="2" width="3" height="10" rx="1"></rect><rect x="15" y="0" width="3" height="12" rx="1" opacity="0.35"></rect>
        </svg>
        <svg width="17" height="12" viewBox="0 0 17 12" fill="var(--text)">
          <path d="M8.5 9.8a1.5 1.5 0 1 0 0 2.2 1.5 1.5 0 0 0 0-2.2z"></path>
          <path d="M3.6 7.2a7 7 0 0 1 9.8 0l-1.5 1.6a4.8 4.8 0 0 0-6.8 0z" opacity="0.8"></path>
          <path d="M0.8 4.3a11 11 0 0 1 15.4 0l-1.5 1.6a8.9 8.9 0 0 0-12.4 0z" opacity="0.55"></path>
        </svg>
        <svg width="25" height="12" viewBox="0 0 25 12">
          <rect x="0.5" y="0.5" width="21" height="11" rx="3.5" fill="none" stroke="var(--text-3)"></rect>
          <rect x="2" y="2" width="13" height="8" rx="2" fill="var(--text)"></rect>
          <rect x="22.7" y="3.8" width="2" height="4.4" rx="1" fill="var(--text-3)"></rect>
        </svg>
      </div>
    </div>
  );
}

function Phone({ children, className, tabs, active, footer }) {
  const { density, contrast } = React.useContext(GooseCtx);
  return (
    <div className={"g-phone" + (className ? " " + className : "")}
      data-density={density} data-contrast={contrast}>
      <StatusBar></StatusBar>
      {children}
      {tabs ? <TabBar tabs={tabs} active={active}></TabBar> : footer || null}
      <div className="g-homebar"></div>
    </div>
  );
}

function TabBar({ tabs, active }) {
  return (
    <div className="g-tabbar">
      {tabs.map((t) => (
        <div key={t.label} className={"g-tab" + (t.label === active ? " on" : "")}>
          <GIcon name={t.icon} size={23}></GIcon>
          <span>{t.label}</span>
        </div>
      ))}
    </div>
  );
}

// ---------- common bits ----------
function CardTitle({ color, children, right }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, minWidth: 0 }}>
      <h3 className="g-card-title" style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" }}>
        {color ? <span className="g-dot" style={{ background: color }}></span> : null}
        {children}
      </h3>
      {right ? <span style={{ flex: "none", display: "inline-flex" }}>{right}</span> : null}
    </div>
  );
}

// in-band judgement pill, vs the owner's own usual range
function BandPill({ value, band, compact }) {
  const inb = GOOSE.inBand(value, band);
  const nearHi = inb && value >= band.hi - (band.hi - band.lo) * 0.08;
  const label = !inb
    ? value > band.hi ? "above usual" : "below usual"
    : nearHi ? "top of usual" : "in your usual range";
  const cls = inb ? (nearHi ? "warn" : "ok") : "warn";
  return <span className={"g-pill " + cls}>{compact ? label.replace("in your usual range", "usual") : label}</span>;
}

function Delta({ value, unit, good }) {
  const up = value > 0;
  const col = good == null ? "var(--text-2)" : (up === good ? "var(--activity)" : "var(--range)");
  return (
    <span style={{ fontSize: 12.5, fontWeight: 600, color: col, whiteSpace: "nowrap" }}>
      {up ? "▲" : "▼"} {Math.abs(value)}{unit ? " " + unit : ""} vs prev
    </span>
  );
}

function Seg({ items, on }) {
  return (
    <div className="g-seg">
      {items.map((s) => <div key={s} className={s === on ? "on" : ""}>{s}</div>)}
    </div>
  );
}

function OursNote({ children }) {
  return <div className="g-ours">{children || "rMSSD — our own number, not WHOOP's"}</div>;
}

function GapNote({ children }) {
  return (
    <div className="g-gapnote">
      <svg width="14" height="10" viewBox="0 0 14 10">
        <rect x="0.5" y="0.5" width="13" height="9" rx="2" fill="none" stroke="var(--text-3)" strokeDasharray="2 2"></rect>
      </svg>
      {children}
    </div>
  );
}

const TABS_A = [
  { label: "Today", icon: "pulse" },
  { label: "Morning", icon: "sunrise" },
  { label: "Trends", icon: "trends" },
  { label: "More", icon: "dots" },
];

const TABS_B = [
  { label: "Day", icon: "day" },
  { label: "History", icon: "history" },
  { label: "Band", icon: "band" },
];

Object.assign(window, {
  GIcon, StatusBar, Phone, TabBar, CardTitle, BandPill, Delta, Seg,
  OursNote, GapNote, TABS_A, TABS_B,
});
