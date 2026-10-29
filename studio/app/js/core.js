/* Macaw Studio core: the design data (screens, items), helpers, and the renderer that turns items into page elements.
   Used by the editor (index.html) and by the picture export (render.html). Plain script, everything hangs off window.S. */
"use strict";
const S = window.S = window.S || {};

/* ---------- small helpers ---------- */
S.uid = (p = "i") => p + Math.random().toString(36).slice(2, 8) + Date.now().toString(36).slice(-3);
S.clone = o => o === undefined ? undefined : JSON.parse(JSON.stringify(o));
S.clamp = (v, a, b) => Math.max(a, Math.min(b, v));
S.round = (v, d = 0) => { const m = 10 ** d; return Math.round(v * m) / m; };
S.esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
S.h = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k === "style" && typeof v === "object") Object.assign(e.style, v);
    else if (k.startsWith("on") && typeof v === "function") e.addEventListener(k.slice(2), v);
    else if (k === "html") e.innerHTML = v;
    else if (k === "cls") e.className = v;
    else e.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat()) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
};
S.debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

/* colours: "#rrggbb", "#rrggbbaa", "rgba(...)" in, {r,g,b,a} out and back */
S.parseColor = c => {
  c = String(c || "").trim();
  let m = /^#([0-9a-f]{3,8})$/i.exec(c);
  if (m) {
    let h = m[1]; if (h.length <= 4) h = [...h].map(x => x + x).join("");
    const n = i => parseInt(h.slice(i, i + 2), 16);
    return { r: n(0), g: n(2), b: n(4), a: h.length === 8 ? n(6) / 255 : 1 };
  }
  m = /^rgba?\(([^)]+)\)$/i.exec(c);
  if (m) { const p = m[1].split(/[ ,/]+/).filter(Boolean).map(parseFloat); return { r: p[0] || 0, g: p[1] || 0, b: p[2] || 0, a: p[3] ?? 1 }; }
  return { r: 0, g: 0, b: 0, a: 1 };
};
S.hex = ({ r, g, b }) => "#" + [r, g, b].map(v => S.clamp(Math.round(v), 0, 255).toString(16).padStart(2, "0")).join("").toUpperCase();
S.rgba = (c, op = 1) => { const p = S.parseColor(c); const a = S.round(p.a * op, 3); return a >= 1 ? S.hex(p) : `rgba(${p.r},${p.g},${p.b},${a})`; };
S.hexA = c => { const p = S.parseColor(c); return p.a >= 1 ? S.hex(p) : S.hex(p) + Math.round(p.a * 255).toString(16).padStart(2, "0").toUpperCase(); };
S.hsv2rgb = (h, s, v) => { const f = n => { const k = (n + h / 60) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); }; return { r: f(5) * 255, g: f(3) * 255, b: f(1) * 255 }; };
S.rgb2hsv = ({ r, g, b }) => { r /= 255; g /= 255; b /= 255; const v = Math.max(r, g, b), c = v - Math.min(r, g, b); let h = 0; if (c) h = v === r ? ((g - b) / c) % 6 : v === g ? (b - r) / c + 2 : (r - g) / c + 4; return { h: (h * 60 + 360) % 360, s: v ? c / v : 0, v }; };

/* ---------- devices (sizes in points, like the real phones) ---------- */
S.DEVICES = {
  iphone15pro:  { name: "iPhone 15 Pro", w: 393, h: 852, radius: 55, island: true, safe: [59, 0, 34, 0] },
  iphone15proL: { name: "iPhone 15 Pro (landscape)", w: 852, h: 393, radius: 55, island: false, safe: [0, 59, 21, 59] },
  iphoneSE:     { name: "iPhone SE", w: 375, h: 667, radius: 0, island: false, safe: [20, 0, 0, 0] },
  telegram:     { name: "Telegram mini app", w: 393, h: 700, radius: 0, island: false, safe: [0, 0, 34, 0] },
  ipad:         { name: "iPad", w: 820, h: 1180, radius: 18, island: false, safe: [24, 0, 20, 0] },
  desktop:      { name: "Desktop window", w: 1280, h: 800, radius: 10, island: false, safe: [44, 0, 0, 0] },
  custom:       { name: "Custom", w: 400, h: 800, radius: 0, island: false, safe: [0, 0, 0, 0] }
};

/* the MacawP3 look, taken from index.html */
S.MACAW = {
  font: "Inter",
  bg: "radial-gradient(120% 80% at 60% 55%, #1d4e5c 0%, #123440 45%, #0a1a20 100%)",
  bgLight: "radial-gradient(120% 80% at 60% 55%, #e9d9b8 0%, #c9b48c 50%, #8f7a55 100%)",
  colors: [
    ["White", "#FFFFFF"], ["Ink", "#0A1A20"], ["Deep teal", "#123440"], ["Teal", "#1D4E5C"], ["Bright teal", "#2BB3C0"],
    ["Toggle on", "#3E8E86"], ["Gold", "#F2C14E"], ["Amber", "#E8A04C"], ["Brick", "#B54A3A"], ["Glass", "rgba(255,255,255,0.10)"],
    ["Glass border", "rgba(255,255,255,0.15)"], ["Text dim", "rgba(255,255,255,0.55)"], ["Tab off", "rgba(255,255,255,0.40)"]
  ]
};

/* ---------- items ---------- */
S.TYPES = {
  frame: { label: "Frame", icon: "frame" }, group: { label: "Group", icon: "group" }, rect: { label: "Rectangle", icon: "square" },
  ellipse: { label: "Circle", icon: "circle" }, line: { label: "Line", icon: "minus" }, path: { label: "Drawing", icon: "pen-tool" },
  text: { label: "Text", icon: "type" }, button: { label: "Button", icon: "rectangle-horizontal" }, image: { label: "Image", icon: "image" },
  icon: { label: "Icon", icon: "star" }, slider: { label: "Slider", icon: "sliders-horizontal" }, toggle: { label: "Toggle", icon: "toggle-right" },
  checkbox: { label: "Checkbox", icon: "square-check" }, input: { label: "Text field", icon: "text-cursor-input" },
  placeholder: { label: "Placeholder", icon: "square-dashed" }, progress: { label: "Progress ring", icon: "loader-circle" },
  badge: { label: "Badge", icon: "badge" }, cover: { label: "Album cover", icon: "disc-3" }
};

S.newItem = (type, o = {}) => {
  const base = { id: S.uid(), type, name: o.name || S.TYPES[type]?.label || type, x: 0, y: 0, w: 100, h: 100, rot: 0, opacity: 1,
    fills: [], stroke: null, radius: 0, effects: [], status: "new" };
  const d = {
    frame: { fills: [{ kind: "solid", color: "rgba(255,255,255,0.06)" }], radius: 16, clip: true, children: [] },
    group: { children: [] },
    rect: { fills: [{ kind: "solid", color: "#2BB3C0" }], radius: 0 },
    ellipse: { fills: [{ kind: "solid", color: "#F2C14E" }] },
    line: { h: 0, stroke: { color: "#FFFFFF", width: 2, style: "solid" } },
    path: { fills: [], stroke: { color: "#FFFFFF", width: 3, style: "solid" }, path: { d: "", vw: 100, vh: 100 } },
    text: { w: 200, h: 24, text: { content: "Text", font: "Inter", size: 17, weight: 600, lh: 0, ls: 0, align: "left", valign: "top", color: "#FFFFFF", sizing: "hug", overflow: "wrap", sample: "fixed" } },
    button: { w: 160, h: 48, radius: 24, fills: [{ kind: "solid", color: "rgba(255,255,255,0.10)" }], stroke: { color: "rgba(255,255,255,0.15)", width: 1, style: "solid" },
      text: { content: "Button", font: "Inter", size: 15, weight: 600, lh: 0, ls: 0, align: "center", valign: "middle", color: "#FFFFFF", sample: "fixed" }, icon: { name: "", size: 18, color: "#FFFFFF", pos: "left" } },
    image: { w: 160, h: 160, radius: 12, image: { src: "", fit: "cover" } },
    icon: { w: 24, h: 24, icon: { name: "play", size: 24, color: "#FFFFFF", stroke: 2, filled: false } },
    slider: { w: 240, h: 20, slider: { value: 0.4, track: "rgba(255,255,255,0.20)", fill: "#FFFFFF", knob: "#FFFFFF", knobSize: 14, thickness: 4 } },
    toggle: { w: 46, h: 28, toggle: { on: true, onColor: "#3E8E86", offColor: "rgba(255,255,255,0.10)", knob: "#FFFFFF" } },
    checkbox: { w: 22, h: 22, radius: 6, toggle: { on: true, onColor: "#2BB3C0", offColor: "rgba(255,255,255,0.10)", knob: "#FFFFFF" } },
    input: { w: 280, h: 40, radius: 10, fills: [{ kind: "solid", color: "rgba(255,255,255,0.08)" }], stroke: { color: "rgba(255,255,255,0.15)", width: 1, style: "solid" },
      text: { content: "Search songs", font: "Inter", size: 15, weight: 400, lh: 0, ls: 0, align: "left", valign: "middle", color: "rgba(255,255,255,0.45)", sample: "fixed" }, icon: { name: "search", size: 16, color: "rgba(255,255,255,0.45)", pos: "left" } },
    placeholder: { w: 240, h: 120, radius: 12, stroke: { color: "rgba(255,255,255,0.45)", width: 1.5, style: "dashed" },
      text: { content: "Something goes here", font: "Inter", size: 13, weight: 500, lh: 0, ls: 0, align: "center", valign: "middle", color: "rgba(255,255,255,0.6)", sample: "fixed" } },
    progress: { w: 48, h: 48, slider: { value: 0.65, track: "rgba(255,255,255,0.15)", fill: "#2BB3C0", thickness: 5 } },
    badge: { w: 28, h: 20, radius: 10, fills: [{ kind: "solid", color: "#E5484D" }], text: { content: "3", font: "Inter", size: 12, weight: 700, lh: 0, ls: 0, align: "center", valign: "middle", color: "#FFFFFF", sample: "fixed" } },
    cover: { w: 160, h: 160, radius: 12, fills: [{ kind: "linear", color: "#E8A04C", color2: "#5A1F4A", angle: 135 }], cover: { sample: true },
      effects: [{ kind: "glow", color: "cover", blur: 40, spread: 0, x: 0, y: 12, opacity: 0.45, on: true }] }
  }[type] || {};
  return Object.assign(base, S.clone(d), o, { id: o.id || base.id });
};

/* walk the item tree */
S.walk = (items, fn, parent = null, depth = 0) => { for (const it of items || []) { if (fn(it, parent, depth) === false) return false; if (it.children && S.walk(it.children, fn, it, depth + 1) === false) return false; } };
S.findIn = (doc, id) => {   // -> { item, parent (item or null), screen, list (the array it sits in), index }
  for (const sc of doc.screens) {
    let r = null;
    const look = (list, parent) => { for (let i = 0; i < list.length; i++) { const it = list[i]; if (it.id === id) { r = { item: it, parent, screen: sc, list, index: i }; return true; } if (it.children && look(it.children, it)) return true; } return false; };
    if (look(sc.items, null)) return r;
  }
  return null;
};
S.screenOf = (doc, id) => doc.screens.find(s => s.id === id);
S.ancestors = (doc, id) => { const out = []; let f = S.findIn(doc, id); while (f && f.parent) { out.unshift(f.parent); f = S.findIn(doc, f.parent.id); } return out; };
/* position of an item inside its screen (adds up the groups it sits in) */
S.absPos = (doc, id) => { const f = S.findIn(doc, id); if (!f) return null; let x = f.item.x, y = f.item.y; for (const a of S.ancestors(doc, id)) { x += a.x; y += a.y; } return { x, y, w: f.item.w, h: f.item.h, rot: f.item.rot || 0, screen: f.screen }; };

/* ---------- styles that live on the design (colour styles, text styles) ---------- */
S.resolveColor = (doc, c) => { if (c && typeof c === "object" && c.style) { const st = (doc.colorStyles || []).find(s => s.id === c.style); return st ? st.color : "#000"; } return c; };

/* ---------- the design ---------- */
S.newDoc = (name = "Untitled design") => ({
  app: "macaw-studio", format: 1, id: S.uid("d"), name, created: Date.now(), updated: Date.now(),
  screens: [], links: [], guides: [], colorStyles: S.MACAW.colors.slice(0, 9).map(([n, c]) => ({ id: S.uid("c"), name: n, color: c })),
  textStyles: [
    { id: S.uid("t"), name: "Screen title", font: "Inter", size: 30, weight: 700, lh: 0, ls: 0 },
    { id: S.uid("t"), name: "Song title", font: "Inter", size: 17, weight: 600, lh: 0, ls: 0 },
    { id: S.uid("t"), name: "Body", font: "Inter", size: 15, weight: 400, lh: 0, ls: 0 },
    { id: S.uid("t"), name: "Caption", font: "Inter", size: 11, weight: 600, lh: 0, ls: 0.5 }
  ],
  myParts: [], versions: [], view: { x: 80, y: 80, zoom: 0.75 }, message: ""
});
S.newScreen = (device = "iphone15pro", o = {}) => {
  const d = S.DEVICES[device] || S.DEVICES.iphone15pro;
  return Object.assign({ id: S.uid("s"), name: o.name || "Screen", device, w: d.w, h: d.h, x: 0, y: 0, status: "new", note: "", section: "",
    bg: { kind: "macaw", color: "#0A1A20", image: "" }, tone: "dark", chrome: true, items: [], grid: { on: false, cols: 2, gap: 16, margin: 24 } }, o);
};

/* auto layout: lays out the children of frames/groups that have item.layout = { dir, gap, pad, align, justify, hug } */
S.applyLayout = items => {
  for (const it of items || []) {
    if (it.children) S.applyLayout(it.children);
    const L = it.layout; if (!L || !it.children || !it.children.length) continue;
    const pad = +L.pad || 0, gap = +L.gap || 0, row = L.dir !== "col";
    const kids = it.children.filter(c => !c.hidden && !c.absolute);
    const main = kids.reduce((s, c) => s + (row ? c.w : c.h), 0) + gap * Math.max(0, kids.length - 1);
    const cross = kids.reduce((m, c) => Math.max(m, row ? c.h : c.w), 0);
    if (L.hug) { if (row) { it.w = main + pad * 2; it.h = cross + pad * 2; } else { it.h = main + pad * 2; it.w = cross + pad * 2; } }
    const inner = (row ? it.w : it.h) - pad * 2, innerX = (row ? it.h : it.w) - pad * 2;
    let pos = pad, step = gap;
    if (L.justify === "center") pos = pad + (inner - main) / 2;
    else if (L.justify === "end") pos = pad + inner - main;
    else if (L.justify === "between" && kids.length > 1) step = gap + (inner - main) / (kids.length - 1);
    for (const c of kids) {
      if (c.fillCross) { if (row) c.h = innerX; else c.w = innerX; }
      const cs = row ? c.h : c.w;
      const off = L.align === "center" ? (innerX - cs) / 2 : L.align === "end" ? innerX - cs : 0;
      if (row) { c.x = S.round(pos, 2); c.y = S.round(pad + off, 2); pos += c.w + step; }
      else { c.y = S.round(pos, 2); c.x = S.round(pad + off, 2); pos += c.h + step; }
    }
  }
};

/* an item as it looks in its current preview state (Pressed, Playing...) */
S.STATES = ["normal", "pressed", "disabled", "playing", "paused"];
S.view = it => {
  const st = it.viewState && it.viewState !== "normal" && it.states && it.states[it.viewState];
  if (!st) return it;
  const v = Object.assign({}, it, S.clone(st));
  if (st.text) v.text = Object.assign({}, it.text, st.text);
  if (st.icon) v.icon = Object.assign({}, it.icon, st.icon);
  return v;
};

/* ---------- rendering ---------- */
S.iconSVG = (name, size = 24, color = "#fff", stroke = 2, filled = false) => {
  const ic = window.ICONS && window.ICONS[name];
  if (!ic) return `<svg viewBox="0 0 24 24" width="${size}" height="${size}"><rect x="3" y="3" width="18" height="18" rx="3" fill="none" stroke="${color}" stroke-dasharray="3 2"/></svg>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${size}" height="${size}" fill="${filled ? color : "none"}" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round">${ic[0]}</svg>`;
};

S.fillCSS = (doc, f, it) => {
  if (!f || f.on === false) return null;
  const op = f.opacity ?? 1, c1 = S.rgba(S.resolveColor(doc, f.color) || "#000", op), c2 = S.rgba(S.resolveColor(doc, f.color2) || "#000", op);
  switch (f.kind) {
    case "linear": return `linear-gradient(${f.angle ?? 180}deg, ${c1}, ${c2})`;
    case "radial": return `radial-gradient(circle at 50% 50%, ${c1}, ${c2})`;
    case "cover": return `linear-gradient(135deg, ${S.rgba("#E8A04C", op)}, ${S.rgba("#B54A3A", op)} 55%, ${S.rgba("#5A1F4A", op)})`;   // stands in for the song's own art
    case "image": return f.image ? `url("${f.image}") center/${f.fit || "cover"} no-repeat` : null;
    default: return `linear-gradient(${c1}, ${c1})`;
  }
};
S.radiusCSS = r => Array.isArray(r) ? r.map(v => (+v || 0) + "px").join(" ") : (+r || 0) + "px";

S.renderItem = (doc, raw, opts = {}) => {
  const it = S.view(raw);
  const el = document.createElement("div");
  el.className = "it it-" + it.type + (it.hidden ? " is-hidden" : "");
  el.dataset.id = it.id;
  const st = el.style;
  st.left = it.x + "px"; st.top = it.y + "px"; st.width = Math.max(0, it.w) + "px"; st.height = Math.max(0, it.h) + "px";
  if (it.rot) st.transform = `rotate(${it.rot}deg)`;
  if (it.flipX || it.flipY) st.transform = (st.transform || "") + ` scale(${it.flipX ? -1 : 1},${it.flipY ? -1 : 1})`;
  if (it.opacity != null && it.opacity < 1) st.opacity = it.opacity;
  if (it.hidden && !opts.showHidden) st.display = "none";
  const br = it.type === "ellipse" ? "50%" : S.radiusCSS(it.radius);
  if (!["line", "path", "text", "icon", "slider", "progress", "group"].includes(it.type)) st.borderRadius = br;
  const bgs = (it.fills || []).map(f => S.fillCSS(doc, f, it)).filter(Boolean).reverse();
  const shapeBg = !["line", "path", "text", "icon", "slider", "toggle", "progress", "checkbox"].includes(it.type);
  if (shapeBg && bgs.length) st.background = bgs.join(", ");
  if (it.stroke && it.stroke.width && shapeBg && it.stroke.on !== false) {
    const s = it.stroke, col = S.resolveColor(doc, s.color);
    if (s.pos === "outside") st.outline = `${s.width}px ${s.style || "solid"} ${col}`;
    else st.boxShadow = "";   // filled in below with the effects so they combine
    if (s.pos !== "outside") { st.border = `${s.width}px ${s.style || "solid"} ${col}`; st.boxSizing = "border-box"; }
  }
  /* effects */
  const shadows = [], filters = [];
  for (const e of it.effects || []) {
    if (e.on === false) continue;
    const col = e.color === "cover" ? S.rgba("#E88C4C", e.opacity ?? 0.45) : S.rgba(S.resolveColor(doc, e.color) || "#000", e.opacity ?? 1);
    if (e.kind === "shadow") shadows.push(`${e.x || 0}px ${e.y || 0}px ${e.blur || 0}px ${e.spread || 0}px ${col}`);
    if (e.kind === "inner") shadows.push(`inset ${e.x || 0}px ${e.y || 0}px ${e.blur || 0}px ${e.spread || 0}px ${col}`);
    if (e.kind === "glow") shadows.push(`${e.x || 0}px ${e.y || 0}px ${e.blur || 24}px ${e.spread || 0}px ${col}`);
    if (e.kind === "blur") filters.push(`blur(${e.blur || 4}px)`);
    if (e.kind === "glass") {
      const g = { clear: [6, 120, 0.02], frosted: [20, 140, 0.08], liquid: [25, 180, 0.05], tinted: [18, 150, 0.16] }[e.glass || "liquid"];
      st.backdropFilter = `blur(${e.blur ?? g[0]}px) saturate(${g[1]}%)`;
      if (!bgs.length) st.background = `rgba(255,255,255,${g[2]})`;
      shadows.push("inset 0 1px 0 rgba(255,255,255,0.25)", "0 20px 50px rgba(0,0,0,0.30)");
      if (!it.stroke) { st.border = "1px solid rgba(255,255,255,0.14)"; st.boxSizing = "border-box"; }
    }
  }
  if (["text", "icon", "line", "path"].includes(it.type)) {   // shadows on shapes without a box follow their outline
    const ds = (it.effects || []).filter(e => e.on !== false && (e.kind === "shadow" || e.kind === "glow")).map(e => `drop-shadow(${e.x || 0}px ${e.y || 0}px ${(e.blur || 0) / 2}px ${e.color === "cover" ? S.rgba("#E88C4C", e.opacity ?? 0.45) : S.rgba(S.resolveColor(doc, e.color) || "#000", e.opacity ?? 1)})`);
    filters.push(...ds);
  } else if (shadows.length) st.boxShadow = shadows.join(", ");
  if (filters.length) st.filter = filters.join(" ");

  const T = it.text, txt = T ? S.sampleText(T) : "";
  const textStyle = (e, t) => {
    const ts = t.style && (doc.textStyles || []).find(s => s.id === t.style);
    const f = ts ? Object.assign({}, t, ts) : t;
    e.style.fontFamily = `"${f.font || "Inter"}", Inter, system-ui, sans-serif`;
    e.style.fontSize = (f.size || 15) + "px"; e.style.fontWeight = f.weight || 400;
    e.style.lineHeight = f.lh ? f.lh + "px" : "1.25"; e.style.letterSpacing = (f.ls || 0) + "px";
    e.style.color = S.resolveColor(doc, t.color) || "#fff"; e.style.textAlign = t.align || "left";
    if (t.italic) e.style.fontStyle = "italic";
    if (t.deco) e.style.textDecoration = t.deco;
    if (t.case) e.style.textTransform = t.case;
  };
  switch (it.type) {
    case "text": {
      const tx = S.h("div", { cls: "tx" }); tx.textContent = txt; textStyle(tx, T);
      if (T.overflow === "ellipsis") Object.assign(tx.style, { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
      else if (T.sizing === "hug") tx.style.whiteSpace = "pre";
      else tx.style.whiteSpace = "pre-wrap";
      el.style.display = "flex"; el.style.flexDirection = "column";
      el.style.justifyContent = T.valign === "middle" ? "center" : T.valign === "bottom" ? "flex-end" : "flex-start";
      if (bgs.length) tx.style.background = bgs.join(","), tx.style.webkitBackgroundClip = "text", tx.style.color = "transparent";
      el.append(tx); break;
    }
    case "button": case "input": case "placeholder": case "badge": {
      el.style.display = "flex"; el.style.alignItems = "center"; el.style.gap = "8px"; el.style.padding = "0 " + (it.pad ?? (it.type === "badge" ? 6 : 14)) + "px";
      el.style.justifyContent = T && T.align === "left" ? "flex-start" : T && T.align === "right" ? "flex-end" : "center";
      el.style.boxSizing = "border-box"; el.style.overflow = "hidden";
      const I = it.icon;
      const icon = I && I.name ? S.h("span", { cls: "bi", html: S.iconSVG(I.name, I.size || 18, S.resolveColor(doc, I.color) || "#fff", I.stroke || 2, I.filled) }) : null;
      const lab = txt ? S.h("span", { cls: "bl" }, txt) : null;
      if (lab) { textStyle(lab, T); lab.style.whiteSpace = "nowrap"; lab.style.overflow = "hidden"; lab.style.textOverflow = "ellipsis"; }
      if (icon && I.pos === "right") { lab && el.append(lab); el.append(icon); } else { icon && el.append(icon); lab && el.append(lab); }
      if (icon && I.pos === "only" && lab) lab.remove();
      break;
    }
    case "icon": {
      const I = it.icon || {};
      el.innerHTML = S.iconSVG(I.name, Math.min(it.w, it.h), S.resolveColor(doc, I.color) || "#fff", I.stroke || 2, I.filled);
      el.firstChild.style.width = "100%"; el.firstChild.style.height = "100%"; el.firstChild.style.display = "block";
      break;
    }
    case "image": {
      const I = it.image || {};
      if (I.src) { const im = S.h("img", { src: I.src, draggable: "false" }); Object.assign(im.style, { width: "100%", height: "100%", objectFit: I.fit || "cover", borderRadius: "inherit", display: "block" }); el.append(im); }
      else { el.classList.add("img-empty"); el.innerHTML = S.iconSVG("image", Math.min(48, it.w / 2, it.h / 2), "rgba(255,255,255,.35)"); }
      el.style.overflow = "hidden"; break;
    }
    case "cover": {
      el.style.overflow = "hidden";
      el.append(S.h("div", { cls: "cover-shine" }));
      break;
    }
    case "line": {
      const s = it.stroke || { color: "#fff", width: 2 }, w = Math.max(it.w, 1), hh = Math.max(it.h, 1);
      const [x1, y1, x2, y2] = it.flipLine ? [0, it.h, it.w, 0] : [0, 0, it.w, it.h];
      el.style.overflow = "visible";
      el.innerHTML = `<svg width="${w}" height="${hh}" style="overflow:visible;position:absolute;left:0;top:0"><line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${S.resolveColor(doc, s.color)}" stroke-width="${s.width}" stroke-linecap="${s.cap || "round"}" ${s.style === "dashed" ? `stroke-dasharray="${s.width * 3} ${s.width * 2}"` : s.style === "dotted" ? `stroke-dasharray="0 ${s.width * 2}"` : ""}/></svg>`;
      break;
    }
    case "path": {
      const P = it.path || {}, s = it.stroke, fill = (it.fills || [])[0];
      el.innerHTML = `<svg viewBox="0 0 ${P.vw || 100} ${P.vh || 100}" preserveAspectRatio="none" width="100%" height="100%" style="overflow:visible;display:block"><path d="${S.esc(P.d)}" fill="${fill ? S.rgba(S.resolveColor(doc, fill.color), fill.opacity ?? 1) : "none"}" stroke="${s ? S.resolveColor(doc, s.color) : "none"}" stroke-width="${s ? s.width : 0}" vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
      break;
    }
    case "slider": {
      const L = it.slider || {}, th = L.thickness || 4, ks = L.knobSize ?? 14, v = S.clamp(L.value ?? 0.4, 0, 1);
      el.innerHTML = `<div style="position:absolute;left:0;right:0;top:50%;height:${th}px;margin-top:${-th / 2}px;border-radius:${th}px;background:${S.resolveColor(doc, L.track)}"></div>
        <div style="position:absolute;left:0;width:${v * 100}%;top:50%;height:${th}px;margin-top:${-th / 2}px;border-radius:${th}px;background:${S.resolveColor(doc, L.fill)}"></div>
        ${ks ? `<div style="position:absolute;left:calc(${v * 100}% - ${ks / 2}px);top:50%;width:${ks}px;height:${ks}px;margin-top:${-ks / 2}px;border-radius:50%;background:${S.resolveColor(doc, L.knob)};box-shadow:0 1px 4px rgba(0,0,0,.35)"></div>` : ""}`;
      break;
    }
    case "progress": {
      const L = it.slider || {}, th = L.thickness || 5, r = 50 - th, c = 2 * Math.PI * r, v = S.clamp(L.value ?? 0.5, 0, 1);
      el.innerHTML = `<svg viewBox="0 0 100 100" width="100%" height="100%"><circle cx="50" cy="50" r="${r}" fill="none" stroke="${S.resolveColor(doc, L.track)}" stroke-width="${th * 2}"/><circle cx="50" cy="50" r="${r}" fill="none" stroke="${S.resolveColor(doc, L.fill)}" stroke-width="${th * 2}" stroke-linecap="round" stroke-dasharray="${c * v} ${c}" transform="rotate(-90 50 50)"/></svg>`;
      break;
    }
    case "toggle": {
      const T2 = it.toggle || {}, k = it.h - 6;
      el.style.borderRadius = it.h / 2 + "px"; el.style.background = S.resolveColor(doc, T2.on ? T2.onColor : T2.offColor);
      el.style.border = "1px solid rgba(255,255,255,.2)"; el.style.boxSizing = "border-box";
      el.innerHTML = `<div style="position:absolute;top:2px;${T2.on ? "right" : "left"}:2px;width:${k}px;height:${k}px;border-radius:50%;background:${S.resolveColor(doc, T2.knob)};box-shadow:0 1px 3px rgba(0,0,0,.3)"></div>`;
      break;
    }
    case "checkbox": {
      const T2 = it.toggle || {};
      el.style.background = S.resolveColor(doc, T2.on ? T2.onColor : T2.offColor); el.style.border = "1.5px solid rgba(255,255,255,.3)"; el.style.boxSizing = "border-box";
      if (T2.on) el.innerHTML = S.iconSVG("check", it.w - 6, S.resolveColor(doc, T2.knob) || "#fff", 3);
      el.style.display = "grid"; el.style.placeItems = "center"; break;
    }
  }
  if (it.children) {
    if (it.clip) el.style.overflow = "hidden";
    for (const c of it.children) el.append(S.renderItem(doc, c, opts));
  }
  return el;
};

S.sampleText = T => {
  if (!T) return "";
  const s = T.sample;
  if (s === "song") return T.content || "Midnight Drive";
  if (s === "artist") return T.content || "Aurora Fields";
  return T.content ?? "";
};

/* a whole screen: background, the items, and (if asked) the phone's island / status bar / home bar */
S.screenBG = (doc, sc) => {
  const b = sc.bg || {};
  if (b.kind === "color") return S.resolveColor(doc, b.color);
  if (b.kind === "image" && b.image) return `url("${b.image}") center/cover no-repeat`;
  return sc.tone === "light" ? S.MACAW.bgLight : S.MACAW.bg;
};
S.renderScreen = (doc, sc, opts = {}) => {
  const d = S.DEVICES[sc.device] || S.DEVICES.custom;
  const el = S.h("div", { cls: "scr", "data-screen": sc.id });
  Object.assign(el.style, { width: sc.w + "px", height: sc.h + "px", background: S.screenBG(doc, sc), borderRadius: (opts.square ? 0 : d.radius) + "px" });
  S.applyLayout(sc.items);
  for (const it of sc.items) el.append(S.renderItem(doc, it, opts));
  if (sc.chrome !== false && opts.chrome !== false) el.append(S.chrome(sc, d));
  return el;
};
S.chrome = (sc, d) => {
  const light = sc.tone === "light", col = light ? "#111" : "#fff";
  const c = S.h("div", { cls: "chrome" });
  if (d.island) c.append(S.h("div", { cls: "island" }));
  if (["iphone15pro", "iphoneSE", "ipad"].includes(sc.device)) {
    const sb = S.h("div", { cls: "sbar", style: { color: col, top: d.island ? "18px" : "4px" } });
    sb.innerHTML = `<span>9:41</span><span class="sbr">${S.iconSVG("signal", 16, col, 2.5)}${S.iconSVG("wifi", 16, col, 2.5)}${S.iconSVG("battery-full", 22, col, 2)}</span>`;
    c.append(sb);
  }
  if (sc.device === "iphone15pro" || sc.device === "iphone15proL") c.append(S.h("div", { cls: "homebar", style: { background: col } }));
  return c;
};

/* CSS the renderer needs (shared with render.html) */
S.RENDER_CSS = `
.scr{position:relative;overflow:hidden;color:#fff;font-family:Inter,system-ui,sans-serif;isolation:isolate}
.it{position:absolute;box-sizing:border-box;transform-origin:50% 50%}
.it-group{overflow:visible}
.it .tx{width:100%;word-break:break-word}
.it .bi{display:inline-flex;flex:none}.it .bi svg{display:block}
.it-icon svg{pointer-events:none}
.it.img-empty{display:grid;place-items:center;background:repeating-linear-gradient(45deg,rgba(255,255,255,.06) 0 8px,rgba(255,255,255,.02) 8px 16px)}
.cover-shine{position:absolute;inset:0;background:linear-gradient(160deg,rgba(255,255,255,.18),transparent 40%);pointer-events:none}
.chrome{position:absolute;inset:0;pointer-events:none;z-index:99999}
.chrome .island{position:absolute;top:11px;left:50%;transform:translateX(-50%);width:124px;height:36px;background:#000;border-radius:20px}
.chrome .sbar{position:absolute;left:34px;right:28px;display:flex;justify-content:space-between;align-items:center;font:600 16px Inter,system-ui,sans-serif;height:24px}
.chrome .sbr{display:flex;gap:5px;align-items:center}
.chrome .homebar{position:absolute;bottom:8px;left:50%;transform:translateX(-50%);width:134px;height:5px;border-radius:3px;opacity:.85}
`;
