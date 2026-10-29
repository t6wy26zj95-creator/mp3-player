/* The canvas: phone screens on an endless board, selecting, moving, stretching, rotating, snapping, the drawing tools,
   notes, tap links, rulers and guides. */
"use strict";
(() => {
const C = S.canvas = {};
const $ = id => document.getElementById(id);
let cv, world, ov, live = null;          // live = what the mouse is doing right now
const LINK_COLORS = ["#4c8dff", "#9b7bff", "#3ecf8e", "#ff9f43", "#ff4d8d", "#2bb3c0"];

/* ---------- coordinates ---------- */
const V = () => A.doc.view;
const rect = () => cv.getBoundingClientRect();
C.toWorld = (cx, cy) => { const r = rect(), v = V(); return { x: (cx - r.left - v.x) / v.zoom, y: (cy - r.top - v.y) / v.zoom }; };
C.toCanvas = (wx, wy) => { const v = V(); return { x: v.x + wx * v.zoom, y: v.y + wy * v.zoom }; };
/* an item's box in world coordinates */
C.box = id => { const p = S.absPos(A.doc, id); if (!p) return null; return { x: p.screen.x + p.x, y: p.screen.y + p.y, w: p.w, h: p.h, rot: p.rot, screen: p.screen }; };
const screenAt = (wx, wy) => { for (let i = A.doc.screens.length - 1; i >= 0; i--) { const s = A.doc.screens[i]; if (wx >= s.x && wx <= s.x + s.w && wy >= s.y && wy <= s.y + s.h) return s; } return null; };
const elOf = id => world.querySelector(`[data-id="${id}"]`);

/* ---------- drawing the screens ---------- */
C.render = () => {
  if (!A.doc) return;
  world.innerHTML = "";
  for (const sc of A.doc.screens) {
    const d = S.DEVICES[sc.device] || S.DEVICES.custom;
    const wrap = S.h("div", { cls: "screen-wrap" + (sc.id === A.activeScreen ? " active" : "") + (d.radius >= 40 && sc.chrome !== false ? " device" : ""), "data-sid": sc.id });
    wrap.style.left = sc.x + "px"; wrap.style.top = sc.y + "px"; wrap.style.width = sc.w + "px"; wrap.style.height = sc.h + "px";
    const lab = S.h("div", { cls: "screen-label", "data-slabel": sc.id });
    lab.append(S.h("span", { cls: "tag " + sc.status }, sc.status), S.h("b", {}, sc.name), S.h("span", {}, `${d.name === "Custom" ? "" : d.name + " · "}${sc.w} × ${sc.h}`));
    if (sc.basedOn) lab.append(S.h("span", { style: { color: "var(--dim)" } }, "· from MacawP3"));
    wrap.append(lab);
    const el = S.renderScreen(A.doc, sc, { chrome: A.settings.chrome && sc.chrome !== false, showHidden: A.settings.showHidden });
    wrap.append(el);
    if (A.settings.safe) { const [t, r, b, l] = d.safe; [[0, 0, sc.w, t], [0, sc.h - b, sc.w, b], [0, 0, l, sc.h], [sc.w - r, 0, r, sc.h]].forEach(([x, y, w, h]) => { if (w > 0 && h > 0) el.append(S.h("div", { cls: "safe-band", style: { left: x + "px", top: y + "px", width: w + "px", height: h + "px" } })); }); }
    if (sc.grid && sc.grid.on) { const g = sc.grid, cw = (sc.w - g.margin * 2 - g.gap * (g.cols - 1)) / g.cols; for (let i = 0; i < g.cols; i++) el.append(S.h("div", { cls: "grid-col", style: { left: g.margin + i * (cw + g.gap) + "px", width: cw + "px" } })); }
    world.append(wrap);
  }
  if (A.editing) { const t = A.editing; A.editing = null; setTimeout(() => C.editText(t), 0); }
  C.applyView();
};
C.applyView = () => {
  const v = V();
  world.style.transform = `translate(${v.x}px,${v.y}px) scale(${v.zoom})`;
  const g = 16 * Math.max(0.5, Math.min(2, v.zoom)); cv.style.backgroundSize = `${g}px ${g}px`; cv.style.backgroundPosition = `${v.x}px ${v.y}px`;
  world.querySelectorAll(".screen-label").forEach(l => { l.style.transform = `scale(${1 / v.zoom})`; l.style.marginBottom = (l.parentNode.classList.contains("device") ? 14 : 6) / v.zoom + "px"; });
  world.querySelectorAll(".screen-wrap.device").forEach(w => w.style.setProperty("--inv", 1));
  C.overlay();
};

/* ---------- the overlay: selection, guides, notes, links ---------- */
const hnd = (x, y, cls, h, cur) => S.h("div", { cls: "hnd " + cls, "data-h": h, style: { left: x + "px", top: y + "px", cursor: cur } });
const CURS = { nw: "nwse-resize", se: "nwse-resize", ne: "nesw-resize", sw: "nesw-resize", n: "ns-resize", s: "ns-resize", e: "ew-resize", w: "ew-resize" };
C.overlay = () => {
  if (!A.doc || !ov) return;
  ov.innerHTML = "";
  const v = V(), z = v.zoom;
  const toC = (b) => { const p = C.toCanvas(b.x, b.y); return { x: p.x, y: p.y, w: b.w * z, h: b.h * z }; };
  /* group I'm working inside */
  if (A.ctx) { const b = C.box(A.ctx); if (b) { const c = toC(b); ov.append(S.h("div", { cls: "selbox group-ctx", style: { left: c.x + "px", top: c.y + "px", width: c.w + "px", height: c.h + "px", transform: b.rot ? `rotate(${b.rot}deg)` : "", transformOrigin: "50% 50%" } })); } }
  /* hover */
  if (A.hover && !A.sel.includes(A.hover) && !live) { const b = C.box(A.hover); if (b) { const c = toC(b); ov.append(S.h("div", { cls: "hoverbox", style: { left: c.x + "px", top: c.y + "px", width: c.w + "px", height: c.h + "px", transform: b.rot ? `rotate(${b.rot}deg)` : "", transformOrigin: "50% 50%" } })); } }
  /* selection */
  const items = A.selItems().filter(i => C.box(i.id));
  if (A.selScreen && !items.length) { const sc = A.screen(); if (sc) { const c = toC(sc); ov.append(S.h("div", { cls: "selbox", style: { left: c.x + "px", top: c.y + "px", width: c.w + "px", height: c.h + "px" } })); } }
  if (items.length && !(live && live.kind === "text")) {
    let b;
    if (items.length === 1) b = C.box(items[0].id);
    else { const bs = items.map(i => C.box(i.id)); const x0 = Math.min(...bs.map(q => q.x)), y0 = Math.min(...bs.map(q => q.y)); b = { x: x0, y: y0, w: Math.max(...bs.map(q => q.x + q.w)) - x0, h: Math.max(...bs.map(q => q.y + q.h)) - y0, rot: 0 };
      for (const q of bs) { const c = toC(q); ov.append(S.h("div", { cls: "selbox multi-child", style: { left: c.x + "px", top: c.y + "px", width: c.w + "px", height: c.h + "px", transform: q.rot ? `rotate(${q.rot}deg)` : "", transformOrigin: "50% 50%" } })); } }
    const c = toC(b);
    const box = S.h("div", { cls: "selbox", style: { left: c.x + "px", top: c.y + "px", width: c.w + "px", height: c.h + "px", transform: b.rot ? `rotate(${b.rot}deg)` : "", transformOrigin: "50% 50%" } });
    const locked = items.some(i => i.locked), isLine = items.length === 1 && items[0].type === "line";
    if (!locked && A.tool === "V") {
      const W = c.w, H = c.h;
      if (isLine) { const L = items[0]; const p1 = L.flipLine ? [0, H] : [0, 0], p2 = L.flipLine ? [W, 0] : [W, H]; box.append(hnd(p1[0], p1[1], "", "l1", "crosshair"), hnd(p2[0], p2[1], "", "l2", "crosshair")); }
      else {
        for (const [h, x, y] of [["nw", 0, 0], ["ne", W, 0], ["sw", 0, H], ["se", W, H]]) box.append(S.h("div", { cls: "hnd rot", "data-h": "rot", style: { left: x + (x ? 10 : -10) + "px", top: y + (y ? 10 : -10) + "px" } }));
        const hs = [["nw", 0, 0], ["ne", W, 0], ["sw", 0, H], ["se", W, H]];
        if (W > 24) hs.push(["n", W / 2, 0], ["s", W / 2, H]); if (H > 24) hs.push(["w", 0, H / 2], ["e", W, H / 2]);
        for (const [h, x, y] of hs) box.append(hnd(x, y, "", h, CURS[h]));
      }
    }
    ov.append(box);
    const it0 = items[0];
    const tagTxt = items.length === 1 ? `${S.round(it0.w)} × ${S.round(it0.h)}${it0.rot ? ` · ${S.round(it0.rot)}°` : ""}` : `${S.round(b.w)} × ${S.round(b.h)}`;
    const ty = b.rot ? c.y + c.h / 2 + Math.max(c.w, c.h) / 2 + 10 : c.y + c.h + 8;
    ov.append(S.h("div", { cls: "sizetag", style: { left: c.x + c.w / 2 + "px", top: ty + "px" } }, tagTxt));
  }
  /* smart guides while dragging */
  if (live && live.guides) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    for (const g of live.guides) { const a = C.toCanvas(g.x1, g.y1), bb = C.toCanvas(g.x2, g.y2); const l = document.createElementNS(svg.namespaceURI, "line"); Object.entries({ x1: a.x, y1: a.y, x2: bb.x, y2: bb.y, stroke: "#ff4d8d", "stroke-width": 1 }).forEach(([k, vv]) => l.setAttribute(k, vv)); svg.append(l); }
    ov.append(svg);
    for (const L of live.labels || []) { const p = C.toCanvas(L.x, L.y); ov.append(S.h("div", { cls: "gl", style: { left: p.x + "px", top: p.y + "px" } }, L.t)); }
  }
  /* measuring (M tool, or hold Alt) */
  if (A.measure && A.sel.length === 1 && A.hover && A.hover !== A.sel[0]) drawMeasure(C.box(A.sel[0]), C.box(A.hover));
  /* marquee */
  if (live && live.kind === "marquee" && live.r) { const p = C.toCanvas(live.r.x, live.r.y); ov.append(S.h("div", { cls: "marquee", style: { left: p.x + "px", top: p.y + "px", width: live.r.w * z + "px", height: live.r.h * z + "px" } })); }
  if (live && live.kind === "draw" && live.r) { const p = C.toCanvas(live.r.x, live.r.y); ov.append(S.h("div", { cls: "marquee", style: { left: p.x + "px", top: p.y + "px", width: live.r.w * z + "px", height: live.r.h * z + "px", borderRadius: A.tool === "O" ? "50%" : "0" } })); ov.append(S.h("div", { cls: "sizetag", style: { left: p.x + live.r.w * z / 2 + "px", top: p.y + live.r.h * z + 8 + "px" } }, `${S.round(live.r.w)} × ${S.round(live.r.h)}`)); }
  drawLinks(); drawPins(); drawGuides(); drawRulers(); drawMinimap();
};
function drawMeasure(a, b) {
  if (!a || !b) return;
  const lines = [], labels = [];
  const cyA = a.y + a.h / 2, cxA = a.x + a.w / 2;
  if (b.x >= a.x + a.w) { lines.push([a.x + a.w, cyA, b.x, cyA]); labels.push([(a.x + a.w + b.x) / 2, cyA, b.x - a.x - a.w]); }
  else if (b.x + b.w <= a.x) { lines.push([b.x + b.w, cyA, a.x, cyA]); labels.push([(b.x + b.w + a.x) / 2, cyA, a.x - b.x - b.w]); }
  else { if (b.x !== a.x) { lines.push([Math.min(a.x, b.x), cyA, Math.max(a.x, b.x), cyA]); labels.push([(a.x + b.x) / 2, cyA - 8 / V().zoom, Math.abs(a.x - b.x)]); } }
  if (b.y >= a.y + a.h) { lines.push([cxA, a.y + a.h, cxA, b.y]); labels.push([cxA, (a.y + a.h + b.y) / 2, b.y - a.y - a.h]); }
  else if (b.y + b.h <= a.y) { lines.push([cxA, b.y + b.h, cxA, a.y]); labels.push([cxA, (b.y + b.h + a.y) / 2, a.y - b.y - b.h]); }
  else if (b.y !== a.y) { lines.push([cxA, Math.min(a.y, b.y), cxA, Math.max(a.y, b.y)]); labels.push([cxA + 10 / V().zoom, (a.y + b.y) / 2, Math.abs(a.y - b.y)]); }
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  for (const [x1, y1, x2, y2] of lines) { const p = C.toCanvas(x1, y1), q = C.toCanvas(x2, y2); const l = document.createElementNS(svg.namespaceURI, "line"); [["x1", p.x], ["y1", p.y], ["x2", q.x], ["y2", q.y], ["stroke", "#ff4d4d"], ["stroke-width", 1]].forEach(([k, v]) => l.setAttribute(k, v)); svg.append(l); }
  ov.append(svg);
  const bc = C.toCanvas(b.x, b.y); ov.append(S.h("div", { cls: "hoverbox", style: { left: bc.x + "px", top: bc.y + "px", width: b.w * V().zoom + "px", height: b.h * V().zoom + "px", outlineColor: "#ff4d4d" } }));
  for (const [x, y, t] of labels) { const p = C.toCanvas(x, y); ov.append(S.h("div", { cls: "gl", style: { left: p.x + "px", top: p.y + "px", background: "#ff4d4d" } }, S.round(t, 1))); }
}
function drawLinks() {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); let any = false;
  const defs = document.createElementNS(svg.namespaceURI, "defs"); svg.append(defs);
  const one = (from, to, col, id, label) => {
    any = true;
    const mk = document.createElementNS(svg.namespaceURI, "marker"); const mid = "ah" + Math.random().toString(36).slice(2, 7);
    [["id", mid], ["viewBox", "0 0 10 10"], ["refX", 9], ["refY", 5], ["markerWidth", 7], ["markerHeight", 7], ["orient", "auto"]].forEach(([k, v]) => mk.setAttribute(k, v));
    mk.innerHTML = `<path d="M0 0L10 5L0 10z" fill="${col}"/>`; defs.append(mk);
    const a = C.toCanvas(from.x, from.y), b = C.toCanvas(to.x, to.y), dx = Math.max(60, Math.abs(b.x - a.x) / 2);
    const dir = b.x >= a.x ? 1 : -1;
    const p = document.createElementNS(svg.namespaceURI, "path");
    p.setAttribute("d", `M${a.x} ${a.y} C ${a.x + dx * dir} ${a.y}, ${b.x - dx * dir} ${b.y}, ${b.x} ${b.y}`);
    [["stroke", col], ["stroke-width", A.selLink === id ? 3.5 : 2.2], ["fill", "none"], ["marker-end", `url(#${mid})`]].forEach(([k, v]) => p.setAttribute(k, v));
    svg.append(p);
    const c = S.h("circle"); const dot = document.createElementNS(svg.namespaceURI, "circle"); [["cx", a.x], ["cy", a.y], ["r", 4], ["fill", col]].forEach(([k, v]) => dot.setAttribute(k, v)); svg.append(dot);
    if (label) { const L = S.h("div", { cls: "link-label", style: { left: (a.x + b.x) / 2 + "px", top: (a.y + b.y) / 2 - 2 + "px", background: col }, "data-link": id }, label); ov.append(L); }
  };
  A.doc.links.forEach((l, i) => {
    const b = C.box(l.from), sc = S.screenOf(A.doc, l.to); if (!b || !sc) return;
    const toLeft = sc.x > b.x + b.w / 2;
    one({ x: toLeft ? b.x + b.w : b.x, y: b.y + b.h / 2 }, { x: toLeft ? sc.x : sc.x + sc.w, y: sc.y + Math.min(sc.h / 2, 120) }, LINK_COLORS[i % LINK_COLORS.length], l.id, `${l.on} → ${l.motion}`);
  });
  if (live && live.kind === "link" && live.cur) { const b = C.box(live.from); if (b) one({ x: b.x + b.w, y: b.y + b.h / 2 }, live.cur, "#4c8dff", "live", live.target ? "→ " + live.target.name : "drop on a screen"); }
  if (any) ov.prepend(svg);
}
C.noteOrder = () => { const out = []; for (const sc of A.doc.screens) { if (sc.note) out.push({ kind: "screen", id: sc.id, sc, note: sc.note, done: sc.noteDone }); S.walk(sc.items, it => { if (it.note && it.note.text) out.push({ kind: "item", id: it.id, it, sc, note: it.note.text, done: it.note.done }); }); } return out; };
function drawPins() {
  C.noteOrder().forEach((n, i) => {
    let p;
    if (n.kind === "screen") p = C.toCanvas(n.sc.x + 6, n.sc.y + 18);
    else { const b = C.box(n.id); if (!b) return; p = C.toCanvas(b.x + b.w, b.y); p.x -= 6; p.y += 6; }
    const pin = S.h("div", { cls: "pin" + (n.done ? " done" : ""), "data-pin": n.id, style: { left: p.x + "px", top: p.y + "px" }, title: n.note }, S.h("span", {}, i + 1));
    ov.append(pin);
    if (A.openNote === n.id) ov.append(noteCard(n, p, i + 1));
  });
  if (A.openNote && !C.noteOrder().find(n => n.id === A.openNote)) {   // a new, still empty note
    const f = S.findIn(A.doc, A.openNote), sc = S.screenOf(A.doc, A.openNote);
    let p; if (f) { const b = C.box(A.openNote); p = C.toCanvas(b.x + b.w, b.y); } else if (sc) p = C.toCanvas(sc.x + 6, sc.y + 18);
    if (p) ov.append(noteCard({ kind: f ? "item" : "screen", id: A.openNote, it: f && f.item, sc: sc || (f && f.screen), note: "" }, p, "new"));
  }
}
function noteCard(n, p, num) {
  const ta = S.h("textarea", { placeholder: "What should Claude know? e.g. make it glow when playing" }); ta.value = n.note || "";
  const save = () => {
    const v = ta.value.trim();
    if (n.kind === "item") { const it = S.findIn(A.doc, n.id)?.item; if (!it) return; if (v) it.note = Object.assign(it.note || {}, { text: v }); else delete it.note; }
    else { const sc = S.screenOf(A.doc, n.id); sc.note = v; }
    A.openNote = null; A.commit("Note");
  };
  const quick = ["same as now", "bigger", "smaller", "match the album colour", "only on iPhone", "only on desktop"];
  const card = S.h("div", { cls: "notecard", style: { left: Math.min(p.x + 12, ov.clientWidth - 236) + "px", top: Math.max(4, p.y - 6) + "px" } },
    S.h("b", {}, `NOTE ${num} · on ${n.kind === "item" ? (n.it?.name || "item") : (n.sc?.name || "screen")}`), ta,
    S.h("div", { style: { display: "flex", flexWrap: "wrap", gap: "4px", margin: "4px 0" } }, quick.map(q => S.h("span", { style: { background: "rgba(0,0,0,.08)", borderRadius: "8px", padding: "1px 6px", cursor: "pointer", fontSize: "10.5px" }, onclick: () => { ta.value = (ta.value ? ta.value.trim() + " " : "") + q + "."; ta.focus(); } }, q))),
    S.h("div", { cls: "nb" },
      n.note ? S.h("span", { onclick: () => { if (n.kind === "item") { const it = S.findIn(A.doc, n.id).item; it.note.done = !it.note.done; } else { const sc = S.screenOf(A.doc, n.id); sc.noteDone = !sc.noteDone; } A.openNote = null; A.commit("Note done"); } }, n.done ? "Reopen" : "Mark done") : null,
      n.note ? S.h("span", { onclick: () => { ta.value = ""; save(); } }, "Delete") : null,
      S.h("span", { onclick: save }, "Save")));
  card.addEventListener("pointerdown", e => e.stopPropagation());
  ta.addEventListener("keydown", e => { if (e.key === "Enter" && (e.ctrlKey || !e.shiftKey)) { e.preventDefault(); save(); } if (e.key === "Escape") { A.openNote = null; C.overlay(); } e.stopPropagation(); });
  setTimeout(() => ta.focus(), 0);
  return card;
}
function drawGuides() {
  if (!A.settings.rulers) return;
  (A.doc.guides || []).forEach((g, i) => {
    const p = C.toCanvas(g.axis === "x" ? g.pos : 0, g.axis === "y" ? g.pos : 0);
    const el = S.h("div", { cls: "guide-line " + g.axis, "data-guide": i, style: g.axis === "x" ? { left: p.x + "px" } : { top: p.y + "px" }, title: "Drag to move, drag onto the ruler to remove, double-click to type a position" });
    ov.append(el);
  });
}
function drawRulers() {
  if (!A.settings.rulers) return;
  const rx = $("ruler-x"), ry = $("ruler-y"), z = V().zoom, sc = A.screen(), ox = sc ? sc.x : 0, oy = sc ? sc.y : 0;
  const step = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000].find(s => s * z >= 60) || 5000;
  const r = rect();
  let hx = "", hy = "";
  const x0 = C.toWorld(r.left, 0).x - ox, x1 = C.toWorld(r.right, 0).x - ox;
  for (let v = Math.floor(x0 / step) * step; v <= x1; v += step) { const p = C.toCanvas(v + ox, 0).x - 20; hx += `<span style="position:absolute;left:${p}px;top:0;height:20px;border-left:1px solid var(--line2);padding:2px 0 0 3px">${v}</span>`; }
  const y0 = C.toWorld(0, r.top).y - oy, y1 = C.toWorld(0, r.bottom).y - oy;
  for (let v = Math.floor(y0 / step) * step; v <= y1; v += step) { const p = C.toCanvas(0, v + oy).y - 20; hy += `<span style="position:absolute;top:${p}px;left:0;width:20px;border-top:1px solid var(--line2);writing-mode:vertical-rl;transform:rotate(180deg);padding:3px 0 0 2px;height:${step * z}px;box-sizing:border-box;display:flex;justify-content:flex-end">${v}</span>`; }
  rx.innerHTML = hx; ry.innerHTML = hy;
  const its = A.selItems();
  if (its.length === 1) { const b = C.box(its[0].id); if (b) { const p = C.toCanvas(b.x, b.y); rx.insertAdjacentHTML("beforeend", `<i style="position:absolute;left:${p.x - 20}px;width:${b.w * z}px;top:0;bottom:0;background:rgba(76,141,255,.22)"></i>`); ry.insertAdjacentHTML("beforeend", `<i style="position:absolute;top:${p.y - 20}px;height:${b.h * z}px;left:0;right:0;background:rgba(76,141,255,.22)"></i>`); } }
}
function drawMinimap() {
  const mm = $("minimap"), z = V().zoom;
  if (z <= 2 || !A.doc.screens.length) { mm.classList.add("hide"); return; }
  mm.classList.remove("hide"); mm.innerHTML = "";
  const ss = A.doc.screens, x0 = Math.min(...ss.map(s => s.x)) - 100, y0 = Math.min(...ss.map(s => s.y)) - 100, x1 = Math.max(...ss.map(s => s.x + s.w)) + 100, y1 = Math.max(...ss.map(s => s.y + s.h)) + 100;
  const k = Math.min(180 / (x1 - x0), 120 / (y1 - y0));
  for (const s of ss) mm.append(S.h("i", { style: { left: (s.x - x0) * k + "px", top: (s.y - y0) * k + "px", width: s.w * k + "px", height: s.h * k + "px" } }));
  const r = rect(), a = C.toWorld(r.left, r.top), b = C.toWorld(r.right, r.bottom);
  mm.append(S.h("b", { style: { left: (a.x - x0) * k + "px", top: (a.y - y0) * k + "px", width: (b.x - a.x) * k + "px", height: (b.y - a.y) * k + "px" } }));
  mm.onpointerdown = e => { const mr = mm.getBoundingClientRect(); const wx = (e.clientX - mr.left) / k + x0, wy = (e.clientY - mr.top) / k + y0; const v = V(); v.x = r.width / 2 - wx * v.zoom; v.y = r.height / 2 - wy * v.zoom; C.applyView(); e.stopPropagation(); };
}

/* ---------- view ---------- */
C.zoomSet = (z, cx, cy) => {
  const r = rect(), v = V(); z = S.clamp(z, 0.1, 8);
  cx = cx ?? r.width / 2; cy = cy ?? r.height / 2;
  const wx = (cx - v.x) / v.zoom, wy = (cy - v.y) / v.zoom;
  v.zoom = z; v.x = cx - wx * z; v.y = cy - wy * z; C.applyView(); A.updateChrome(); A.markViewDirty();
};
A.markViewDirty = S.debounce(() => { if (A.doc) A.save(); }, 4000);
C.zoomBy = f => C.zoomSet(V().zoom * f);
C.zoomToBox = (b, pad = 60) => {
  const r = rect(); if (!r.width) return;
  const z = S.clamp(Math.min((r.width - pad * 2) / b.w, (r.height - pad * 2 - 60) / b.h), 0.1, 4), v = V();
  v.zoom = z; v.x = r.width / 2 - (b.x + b.w / 2) * z; v.y = (r.height - 50) / 2 - (b.y + b.h / 2) * z; C.applyView(); A.updateChrome();
};
C.zoomFit = () => { const ss = A.doc.screens; if (!ss.length) return; const x0 = Math.min(...ss.map(s => s.x)), y0 = Math.min(...ss.map(s => s.y)); C.zoomToBox({ x: x0, y: y0 - 30, w: Math.max(...ss.map(s => s.x + s.w)) - x0, h: Math.max(...ss.map(s => s.y + s.h)) - y0 + 30 }); };
C.zoomTo = sc => C.zoomToBox({ x: sc.x, y: sc.y - 30, w: sc.w, h: sc.h + 30 });
C.zoomSel = () => { const its = A.selItems(); if (!its.length) { if (A.screen()) C.zoomTo(A.screen()); return; } const bs = its.map(i => C.box(i.id)); const x0 = Math.min(...bs.map(b => b.x)), y0 = Math.min(...bs.map(b => b.y)); C.zoomToBox({ x: x0, y: y0, w: Math.max(...bs.map(b => b.x + b.w)) - x0, h: Math.max(...bs.map(b => b.y + b.h)) - y0 }, 120); };

/* ---------- picking what's under the mouse ---------- */
const itemPath = id => { const anc = S.ancestors(A.doc, id); const f = S.findIn(A.doc, id); return f ? anc.concat(f.item) : []; };
C.pick = (e, deep = false) => {
  const el = document.elementFromPoint(e.clientX, e.clientY);
  if (!el || !world.contains(el)) return null;
  const itEl = el.closest(".it"); if (!itEl) return null;
  let path = itemPath(itEl.dataset.id);
  const li = path.findIndex(p => p.locked); if (li >= 0) path = path.slice(0, li);
  if (!path.length) return null;
  if (deep) return path[path.length - 1].id;
  if (A.ctx) { const i = path.findIndex(p => p.id === A.ctx); if (i >= 0 && i < path.length - 1) return path[i + 1].id; }
  for (const sid of A.sel) if (path.some(p => p.id === sid)) return sid;   // clicking inside what's selected keeps it
  return path[0].id;
};

/* ---------- snapping ---------- */
function snapTargets(sc, exclude) {
  const xs = [0, sc.w / 2, sc.w].map(v => ({ v: v + sc.x, b: { x: sc.x, y: sc.y, w: sc.w, h: sc.h } })), ys = [0, sc.h / 2, sc.h].map(v => ({ v: v + sc.y, b: { x: sc.x, y: sc.y, w: sc.w, h: sc.h } }));
  const boxes = [];
  const addList = (list) => { for (const it of list) { if (exclude.has(it.id) || it.hidden) continue; const b = C.box(it.id); if (!b) continue; boxes.push(b); xs.push({ v: b.x, b }, { v: b.x + b.w / 2, b }, { v: b.x + b.w, b }); ys.push({ v: b.y, b }, { v: b.y + b.h / 2, b }, { v: b.y + b.h, b }); } };
  addList(sc.items);
  const ctxList = new Set();
  for (const id of exclude) { const f = S.findIn(A.doc, id); if (f && f.parent && !ctxList.has(f.parent.id)) { ctxList.add(f.parent.id); addList(f.parent.children); const pb = C.box(f.parent.id); if (pb) { xs.push({ v: pb.x, b: pb }, { v: pb.x + pb.w / 2, b: pb }, { v: pb.x + pb.w, b: pb }); ys.push({ v: pb.y, b: pb }, { v: pb.y + pb.h / 2, b: pb }, { v: pb.y + pb.h, b: pb }); } } }
  for (const g of A.doc.guides || []) (g.axis === "x" ? xs : ys).push({ v: g.pos, b: null, guide: true });
  return { xs, ys, boxes };
}
/* moves box b (world coords) so its edges/centre land on nearby lines; returns the shift and the pink lines to draw */
function snapBox(b, sc, exclude, edges = { x: [0, 0.5, 1], y: [0, 0.5, 1] }) {
  const T = 6 / V().zoom, out = { dx: 0, dy: 0, guides: [], labels: [] };
  if (!A.settings.snap) { if (A.settings.gridSnap) gridSnap(b, sc, out, edges); return out; }
  const { xs, ys, boxes } = snapTargets(sc, exclude);
  let bx = null, by = null;
  for (const f of edges.x) { const v = b.x + b.w * f; for (const t of xs) { const d = t.v - v; if (Math.abs(d) <= T && (!bx || Math.abs(d) < Math.abs(bx.d))) bx = { d, t, f }; } }
  for (const f of edges.y) { const v = b.y + b.h * f; for (const t of ys) { const d = t.v - v; if (Math.abs(d) <= T && (!by || Math.abs(d) < Math.abs(by.d))) by = { d, t, f }; } }
  if (bx) out.dx = bx.d; if (by) out.dy = by.d;
  if (!bx || !by) { const g = { dx: 0, dy: 0 }; if (A.settings.gridSnap) gridSnap({ x: b.x + out.dx, y: b.y + out.dy, w: b.w, h: b.h }, sc, g, edges); if (!bx) out.dx = g.dx; if (!by) out.dy = g.dy; }
  const nb = { x: b.x + out.dx, y: b.y + out.dy, w: b.w, h: b.h };
  if (A.settings.guides) {
    if (bx) { const x = bx.t.v, all = xs.filter(t => Math.abs(t.v - x) < 0.5 && t.b); const ys2 = [nb.y, nb.y + nb.h, ...all.flatMap(t => [t.b.y, t.b.y + t.b.h])]; out.guides.push({ x1: x, y1: Math.min(...ys2), x2: x, y2: Math.max(...ys2) }); if (bx.t.guide) out.guides.push({ x1: x, y1: sc.y - 2000, x2: x, y2: sc.y + 4000 }); }
    if (by) { const y = by.t.v, all = ys.filter(t => Math.abs(t.v - y) < 0.5 && t.b); const xs2 = [nb.x, nb.x + nb.w, ...all.flatMap(t => [t.b.x, t.b.x + t.b.w])]; out.guides.push({ x1: Math.min(...xs2), y1: y, x2: Math.max(...xs2), y2: y }); }
    /* gaps to the nearest neighbours */
    const cy = nb.y + nb.h / 2, cx = nb.x + nb.w / 2;
    const near = (dir) => {
      let best = null;
      for (const o of boxes) {
        const ovY = o.y < nb.y + nb.h && o.y + o.h > nb.y, ovX = o.x < nb.x + nb.w && o.x + o.w > nb.x;
        let d = null;
        if (dir === "l" && ovY && o.x + o.w <= nb.x) d = nb.x - (o.x + o.w); if (dir === "r" && ovY && o.x >= nb.x + nb.w) d = o.x - nb.x - nb.w;
        if (dir === "t" && ovX && o.y + o.h <= nb.y) d = nb.y - (o.y + o.h); if (dir === "b" && ovX && o.y >= nb.y + nb.h) d = o.y - nb.y - nb.h;
        if (d != null && d < 400 && (!best || d < best.d)) best = { d, o };
      }
      return best;
    };
    for (const dir of ["l", "r", "t", "b"]) {
      const n = near(dir); if (!n || n.d < 1) continue;
      if (dir === "l") { out.guides.push({ x1: nb.x - n.d, y1: cy, x2: nb.x, y2: cy }); out.labels.push({ x: nb.x - n.d / 2, y: cy, t: S.round(n.d) }); }
      if (dir === "r") { out.guides.push({ x1: nb.x + nb.w, y1: cy, x2: nb.x + nb.w + n.d, y2: cy }); out.labels.push({ x: nb.x + nb.w + n.d / 2, y: cy, t: S.round(n.d) }); }
      if (dir === "t") { out.guides.push({ x1: cx, y1: nb.y - n.d, x2: cx, y2: nb.y }); out.labels.push({ x: cx, y: nb.y - n.d / 2, t: S.round(n.d) }); }
      if (dir === "b") { out.guides.push({ x1: cx, y1: nb.y + nb.h, x2: cx, y2: nb.y + nb.h + n.d }); out.labels.push({ x: cx, y: nb.y + nb.h + n.d / 2, t: S.round(n.d) }); }
    }
    if (bx && bx.f === 0.5 && Math.abs(bx.t.v - (sc.x + sc.w / 2)) < 0.5) out.labels.push({ x: bx.t.v, y: nb.y - 12 / V().zoom, t: "centre" });
  }
  return out;
}
function gridSnap(b, sc, out, edges) {
  const g = A.settings.grid || 8;
  const fx = edges.x.includes(0) ? 0 : edges.x[0], fy = edges.y.includes(0) ? 0 : edges.y[0];
  if (edges.x.length) { const v = b.x + b.w * fx - sc.x; out.dx = Math.round(v / g) * g - v; }
  if (edges.y.length) { const v = b.y + b.h * fy - sc.y; out.dy = Math.round(v / g) * g - v; }
}

/* ---------- mouse ---------- */
let spaceDown = false;
C.setTool = t => {
  if (t === "D") return C.eyedrop();
  A.tool = t; A.measure = t === "M";
  cv.style.cursor = { H: "grab", T: "text", N: "copy", K: "alias", M: "help", V: "default" }[t] || "crosshair";
  const hints = { F: "Drag to draw a frame. Outside a phone, it makes a new screen.", R: "Drag to draw a box. Shift for a square.", O: "Drag to draw a circle. Shift for a perfect circle.", L: "Drag to draw a line. Shift keeps it straight.",
    P: "Hold the mouse down and draw.", T: "Click to type. Drag to make a box that wraps.", B: "Click to drop a button, or drag to size it.", I: "Click where the image goes.", C: "Click where the icon goes.", S: "Click to drop a slider.",
    N: "Click anything to pin a note on it.", K: "Drag from a button to the screen it should open.", M: "Select one thing, then point at another to measure the gap.", H: "Drag to move around." };
  $("st-hint").textContent = hints[t] || "";
  A.updateChrome(); C.overlay();
};
function startLive(e, o) { live = Object.assign({ sx: e.clientX, sy: e.clientY, w0: C.toWorld(e.clientX, e.clientY), moved: false }, o); cv.setPointerCapture(e.pointerId); }

function onDown(e) {
  if (e.button === 2) return;
  cv.focus();
  closeTextBar();
  const target = e.target;
  if (A.openNote && !target.closest(".notecard")) { A.openNote = null; C.overlay(); }
  /* panning */
  if (e.button === 1 || spaceDown || A.tool === "H") { e.preventDefault(); startLive(e, { kind: "pan", vx: V().x, vy: V().y }); cv.style.cursor = "grabbing"; return; }
  if (target.closest("#minimap") || target.closest("#toolbar") || target.closest("#zoomctl")) return;
  /* rulers: drag out a guide */
  if (target.closest("#ruler-x") || target.closest("#ruler-y")) { const axis = target.closest("#ruler-x") ? "y" : "x"; A.doc.guides.push({ axis, pos: 0 }); startLive(e, { kind: "guide", gi: A.doc.guides.length - 1, axis }); return; }
  if (target.dataset.guide != null) { startLive(e, { kind: "guide", gi: +target.dataset.guide, axis: A.doc.guides[+target.dataset.guide].axis }); return; }
  if (target.closest(".pin")) { A.openNote = target.closest(".pin").dataset.pin; const f = S.findIn(A.doc, A.openNote); if (f) A.sel = [A.openNote]; A.refresh({ right: 1 }); return; }
  if (target.closest(".link-label")) { A.selLink = target.closest(".link-label").dataset.link; A.rightTab = "notes"; A.refresh({ right: 1 }); return; }
  /* handles */
  const h = target.dataset.h;
  if (h) { e.stopPropagation(); return beginResize(e, h); }
  const w = C.toWorld(e.clientX, e.clientY);
  const slab = target.closest("[data-slabel]");
  if (slab) { const sc = S.screenOf(A.doc, slab.dataset.slabel); A.selectScreen(sc.id); startLive(e, { kind: "movescreen", sc, x0: sc.x, y0: sc.y }); return; }
  const sc = screenAt(w.x, w.y);
  if (A.tool === "V" || A.tool === "M") {
    const id = C.pick(e, e.ctrlKey || e.metaKey);
    if (id) {
      if (e.shiftKey) { A.select(id, true); C.overlay(); return; }
      if (!A.sel.includes(id)) A.select(id);
      if (e.altKey && !A.measure) { A.duplicate(); }   // Alt + drag = drag a copy
      beginMove(e);
      return;
    }
    if (sc) A.activeScreen = sc.id;
    if (!e.shiftKey) { A.sel = []; A.selScreen = false; if (!sc) A.ctx = null; }
    startLive(e, { kind: "marquee", add: e.shiftKey ? A.sel.slice() : [], sc });
    A.refresh({ left: 1, right: 1 });
    return;
  }
  if (A.tool === "N") { const id = C.pick(e, true) || null; if (id) { A.sel = [id]; A.openNote = id; } else if (sc) { A.selectScreen(sc.id); A.openNote = sc.id; } A.refresh(); return; }
  if (A.tool === "K") { const id = C.pick(e); if (!id) return S.toast("Start the arrow on a button or other item"); A.sel = [id]; startLive(e, { kind: "link", from: id }); return; }
  if (A.tool === "I") { if (!sc) return S.toast("Click inside a phone screen"); return C.pickImages({ sc, x: w.x - sc.x, y: w.y - sc.y }); }
  if (A.tool === "C") { if (!sc) return S.toast("Click inside a phone screen"); return S.dlg.iconPicker(n => C.placeIcon(n, { sc, x: w.x - sc.x, y: w.y - sc.y })); }
  if (A.tool === "P") { if (!sc) return S.toast("Draw inside a phone screen"); startLive(e, { kind: "pen", sc, pts: [[w.x, w.y]] }); return; }
  /* box tools */
  if (!sc && A.tool !== "F") return S.toast("Draw inside a phone screen");
  startLive(e, { kind: "draw", sc, r: null });
}
function onMove(e) {
  const w = C.toWorld(e.clientX, e.clientY);
  $("st-pos").textContent = (() => { const sc = A.screen(); return sc ? `X ${Math.round(w.x - sc.x)} · Y ${Math.round(w.y - sc.y)}` : ""; })();
  if (!live) {
    const id = (A.tool === "V" || A.tool === "M" || A.tool === "N" || A.tool === "K") && e.target && world.contains(e.target) ? C.pick(e, e.ctrlKey) : null;
    const meas = A.tool === "M" || e.altKey;
    if (id !== A.hover || meas !== A.measure) { A.hover = id; A.measure = meas; C.overlay(); }
    return;
  }
  const dx = e.clientX - live.sx, dy = e.clientY - live.sy;
  if (!live.moved && Math.hypot(dx, dy) < 3) return;
  live.moved = true;
  const z = V().zoom, wdx = dx / z, wdy = dy / z;
  switch (live.kind) {
    case "pan": { const v = V(); v.x = live.vx + dx; v.y = live.vy + dy; C.applyView(); break; }
    case "guide": { const g = A.doc.guides[live.gi]; g.pos = S.round(live.axis === "x" ? w.x : w.y); const r = rect(); live.del = live.axis === "x" ? e.clientX - r.left < 20 : e.clientY - r.top < 20; C.overlay(); break; }
    case "movescreen": { live.sc.x = S.round(live.x0 + wdx); live.sc.y = S.round(live.y0 + wdy); const wrap = world.querySelector(`[data-sid="${live.sc.id}"]`); if (wrap) { wrap.style.left = live.sc.x + "px"; wrap.style.top = live.sc.y + "px"; } C.overlay(); break; }
    case "move": doMove(wdx, wdy, e); break;
    case "resize": doResize(w, e); break;
    case "rotate": { const a = Math.atan2(w.y - live.c.y, w.x - live.c.x) * 180 / Math.PI; let r = live.r0 + a - live.a0; if (e.shiftKey) r = Math.round(r / 15) * 15; r = S.round(((r % 360) + 540) % 360 - 180, 1); live.it.rot = r; const el = elOf(live.it.id); if (el) el.style.transform = `rotate(${r}deg)`; C.overlay(); break; }
    case "marquee": {
      const r = { x: Math.min(live.w0.x, w.x), y: Math.min(live.w0.y, w.y), w: Math.abs(w.x - live.w0.x), h: Math.abs(w.y - live.w0.y) }; live.r = r;
      const ids = []; const ctx = A.ctx && S.findIn(A.doc, A.ctx);
      const lists = ctx ? [ctx.item.children] : A.doc.screens.map(s => s.items);
      for (const list of lists) for (const it of list) { if (it.locked || it.hidden) continue; const b = C.box(it.id); if (b && b.x < r.x + r.w && b.x + b.w > r.x && b.y < r.y + r.h && b.y + b.h > r.y) ids.push(it.id); }
      A.sel = [...new Set(live.add.concat(ids))]; C.overlay(); break;
    }
    case "draw": {
      let x0 = live.w0.x, y0 = live.w0.y, x1 = w.x, y1 = w.y;
      if (e.shiftKey && A.tool !== "L") { const s = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)); x1 = x0 + s * Math.sign(x1 - x0 || 1); y1 = y0 + s * Math.sign(y1 - y0 || 1); }
      if (e.shiftKey && A.tool === "L") { const ang = Math.round(Math.atan2(y1 - y0, x1 - x0) / (Math.PI / 4)) * Math.PI / 4, len = Math.hypot(x1 - x0, y1 - y0); x1 = x0 + Math.cos(ang) * len; y1 = y0 + Math.sin(ang) * len; }
      if (A.settings.gridSnap && A.tool !== "L") { const sc = live.sc || { x: 0, y: 0 }, g = A.settings.grid; const sn = v => Math.round(v / g) * g; x0 = sn(x0 - sc.x) + sc.x; y0 = sn(y0 - sc.y) + sc.y; x1 = sn(x1 - sc.x) + sc.x; y1 = sn(y1 - sc.y) + sc.y; }
      live.r = { x: Math.min(x0, x1), y: Math.min(y0, y1), w: Math.abs(x1 - x0), h: Math.abs(y1 - y0) }; live.up = (y1 < y0) !== (x1 < x0); C.overlay(); break;
    }
    case "pen": { live.pts.push([w.x, w.y]); drawPenLive(); break; }
    case "link": { live.cur = w; live.target = screenAt(w.x, w.y); C.overlay(); break; }
  }
}
function onUp(e) {
  if (!live) return;
  const L = live; live = null;
  try { cv.releasePointerCapture(e.pointerId); } catch (x) {}
  switch (L.kind) {
    case "pan": cv.style.cursor = A.tool === "H" ? "grab" : spaceDown ? "grab" : ""; C.setTool(A.tool); A.markViewDirty(); break;
    case "guide": if (L.del || !L.moved) A.doc.guides.splice(L.gi, 1); A.commit("Guide"); break;
    case "movescreen": if (L.moved) A.commit("Move screen"); break;
    case "move": endMove(L); break;
    case "resize": case "rotate": if (L.moved) { (L.its || [L.it]).forEach(it => { A.touch(it, "x"); A.touch(it, "w"); A.fitParents(it.id); }); A.commit(L.kind === "rotate" ? "Rotate" : "Resize"); } else C.overlay(); break;
    case "marquee": if (!L.moved && L.sc && !e.shiftKey) { A.ctx = null; } A.refresh({ left: 1, right: 1 }); break;
    case "draw": finishDraw(L, e); break;
    case "pen": finishPen(L); break;
    case "link": {
      const sc = L.target;
      if (sc) { A.doc.links.push({ id: S.uid("l"), from: L.from, to: sc.id, on: "tap", motion: "slide" }); A.selLink = A.doc.links[A.doc.links.length - 1].id; A.rightTab = "notes"; A.commit("Tap link"); S.toast(`Tapping it opens "${sc.name}". Change how in the Notes tab.`); }
      else C.overlay();
      break;
    }
  }
}

/* moving */
function beginMove(e) {
  const its = A.selItems().filter(i => !i.locked);
  if (!its.length) return;
  const b0s = its.map(i => C.box(i.id));
  const x0 = Math.min(...b0s.map(b => b.x)), y0 = Math.min(...b0s.map(b => b.y));
  const bb = { x: x0, y: y0, w: Math.max(...b0s.map(b => b.x + b.w)) - x0, h: Math.max(...b0s.map(b => b.y + b.h)) - y0 };
  const exclude = new Set(); its.forEach(i => S.walk([i], c => exclude.add(c.id)));
  startLive(e, { kind: "move", its, starts: its.map(i => ({ x: i.x, y: i.y })), bb, sc: b0s[0].screen, exclude });
}
function doMove(dx, dy, e) {
  const L = live;
  if (e.shiftKey) { if (Math.abs(dx) > Math.abs(dy)) dy = 0; else dx = 0; }
  const nb = { x: L.bb.x + dx, y: L.bb.y + dy, w: L.bb.w, h: L.bb.h };
  const s = e.ctrlKey ? { dx: 0, dy: 0, guides: [], labels: [] } : snapBox(nb, L.sc, L.exclude);
  dx += s.dx; dy += s.dy; L.guides = s.guides; L.labels = s.labels; L.dx = dx; L.dy = dy;
  L.its.forEach((it, i) => { it.x = S.round(L.starts[i].x + dx, 2); it.y = S.round(L.starts[i].y + dy, 2); const el = elOf(it.id); if (el) { el.style.left = it.x + "px"; el.style.top = it.y + "px"; } });
  C.overlay();
}
function endMove(L) {
  if (!L.moved) {   // a click without a drag: select the deeper thing next time you click (like Figma)
    return A.refresh({ left: 1, right: 1 });
  }
  /* dropped onto another screen? move it there */
  const its = L.its;
  for (const it of its) {
    const f = S.findIn(A.doc, it.id); if (!f || f.parent) continue;
    const b = C.box(it.id), cx = b.x + b.w / 2, cy = b.y + b.h / 2, to = screenAt(cx, cy);
    if (to && to !== f.screen) { f.list.splice(f.index, 1); it.x = S.round(cx - to.x - it.w / 2, 2); it.y = S.round(cy - to.y - it.h / 2, 2); to.items.push(it); A.activeScreen = to.id; }
  }
  its.forEach(it => { A.touch(it, "x"); A.touch(it, "y"); A.fitParents(it.id); });
  if (A.dupMode) { A.lastMove = { dx: L.dx, dy: L.dy }; A.dupMode = false; }
  A.commit("Move");
}

/* stretching */
function beginResize(e, h) {
  const its = A.selItems().filter(i => !i.locked); if (!its.length) return;
  if (h === "rot") { const it = its[0], b = C.box(it.id); const c = { x: b.x + b.w / 2, y: b.y + b.h / 2 }, w = C.toWorld(e.clientX, e.clientY); return startLive(e, { kind: "rotate", it, c, r0: it.rot || 0, a0: Math.atan2(w.y - c.y, w.x - c.x) * 180 / Math.PI }); }
  if (h === "l1" || h === "l2") { const it = its[0]; return startLive(e, { kind: "resize", line: h, it, s: { x: it.x, y: it.y, w: it.w, h: it.h, flip: !!it.flipLine }, sc: C.box(it.id).screen, exclude: new Set([it.id]) }); }
  const bs = its.map(i => C.box(i.id));
  const x0 = Math.min(...bs.map(b => b.x)), y0 = Math.min(...bs.map(b => b.y));
  const bb = its.length === 1 ? bs[0] : { x: x0, y: y0, w: Math.max(...bs.map(b => b.x + b.w)) - x0, h: Math.max(...bs.map(b => b.y + b.h)) - y0, rot: 0 };
  const exclude = new Set(); its.forEach(i => S.walk([i], c => exclude.add(c.id)));
  startLive(e, { kind: "resize", h, its, it: its[0], bb, sc: bs[0].screen, exclude, snaps: its.map(i => S.clone(i)), starts: bs });
}
const scaleKids = (it, kx, ky) => { if (!it.children) return; for (const c of it.children) { c.x = S.round(c.x * kx, 2); c.y = S.round(c.y * ky, 2); c.w = S.round(c.w * kx, 2); c.h = S.round(c.h * ky, 2); scaleKids(c, kx, ky); } };
function doResize(w, e) {
  const L = live;
  if (L.line) {   // a line: move one end
    const it = L.it, s = L.s, base = C.box(it.id); const ox = base.x - it.x, oy = base.y - it.y;   // parent offset in world
    const ends = s.flip ? [[s.x, s.y + s.h], [s.x + s.w, s.y]] : [[s.x, s.y], [s.x + s.w, s.y + s.h]];
    const other = L.line === "l1" ? ends[1] : ends[0];
    let px = w.x - ox, py = w.y - oy;
    if (e.shiftKey) { const ang = Math.round(Math.atan2(py - other[1], px - other[0]) / (Math.PI / 4)) * Math.PI / 4, len = Math.hypot(px - other[0], py - other[1]); px = other[0] + Math.cos(ang) * len; py = other[1] + Math.sin(ang) * len; }
    it.x = S.round(Math.min(px, other[0]), 2); it.y = S.round(Math.min(py, other[1]), 2); it.w = S.round(Math.abs(px - other[0]), 2); it.h = S.round(Math.abs(py - other[1]), 2);
    it.flipLine = (py < other[1]) !== (px < other[0]);
    rerenderItem(it); C.overlay(); return;
  }
  const hx = L.h.includes("w") ? 0 : L.h.includes("e") ? 1 : 0.5, hy = L.h.includes("n") ? 0 : L.h.includes("s") ? 1 : 0.5;
  const b = L.bb, rot = (b.rot || 0) * Math.PI / 180, cos = Math.cos(rot), sin = Math.sin(rot);
  const wdx = w.x - L.w0.x, wdy = w.y - L.w0.y;
  let ldx = wdx * cos + wdy * sin, ldy = -wdx * sin + wdy * cos;    // mouse movement in the item's own direction
  const fromCentre = e.altKey;
  const sx = hx === 1 ? 1 : hx === 0 ? -1 : 0, sy = hy === 1 ? 1 : hy === 0 ? -1 : 0;
  let nw = b.w + sx * ldx * (fromCentre ? 2 : 1), nh = b.h + sy * ldy * (fromCentre ? 2 : 1);
  const keepRatio = e.shiftKey || (L.its.length === 1 && ["image", "icon", "cover", "progress"].includes(L.it.type) && !e.shiftKey && sx && sy);
  if (keepRatio && sx && sy) { const k = Math.max(nw / b.w, nh / b.h); nw = b.w * k; nh = b.h * k; }
  else if (e.shiftKey && !sx) nw = b.w * nh / b.h; else if (e.shiftKey && !sy) nh = b.h * nw / b.w;
  nw = Math.max(1, nw); nh = Math.max(L.it.type === "line" ? 0 : 1, nh);
  const ax = fromCentre ? 0.5 : 1 - hx, ay = fromCentre ? 0.5 : 1 - hy;
  const cx0 = b.x + b.w / 2, cy0 = b.y + b.h / 2;
  const ra = (px, py) => ({ x: px * cos - py * sin, y: px * sin + py * cos });
  const a0 = ra((ax - 0.5) * b.w, (ay - 0.5) * b.h), anchor = { x: cx0 + a0.x, y: cy0 + a0.y };
  const a1 = ra((ax - 0.5) * nw, (ay - 0.5) * nh);
  let ncx = anchor.x - a1.x, ncy = anchor.y - a1.y;
  let nb = { x: ncx - nw / 2, y: ncy - nh / 2, w: nw, h: nh };
  /* snap the moving edges */
  L.guides = []; L.labels = [];
  if (!rot && !e.ctrlKey) {
    const edges = { x: sx === 1 ? [1] : sx === -1 ? [0] : [], y: sy === 1 ? [1] : sy === -1 ? [0] : [] };
    const s = snapBox(nb, L.sc, L.exclude, edges);
    if (sx === 1) nb.w += s.dx; if (sx === -1) { nb.x += s.dx; nb.w -= s.dx; }
    if (sy === 1) nb.h += s.dy; if (sy === -1) { nb.y += s.dy; nb.h -= s.dy; }
    L.guides = s.guides.filter(g => g.x1 === g.x2 ? edges.x.length : edges.y.length); L.labels = [];
  }
  /* apply */
  if (L.its.length === 1) {
    const it = L.it, s0 = L.snaps[0], st = L.starts[0];
    const offx = st.x - s0.x, offy = st.y - s0.y;   // world minus parent coords
    it.x = S.round(nb.x - offx, 2); it.y = S.round(nb.y - offy, 2); it.w = S.round(nb.w, 2); it.h = S.round(nb.h, 2);
    if (it.children && it.type === "group") { it.children = S.clone(s0.children); scaleKids(it, it.w / s0.w, it.h / s0.h); }
    if (it.type === "text" && sx) it.text.sizing = "fixed";
    if (it.type === "icon") it.icon.size = Math.round(Math.min(it.w, it.h));
    rerenderItem(it);
  } else {
    const kx = nb.w / b.w, ky = nb.h / b.h;
    L.its.forEach((it, i) => { const s0 = L.snaps[i], st = L.starts[i]; const offx = st.x - s0.x, offy = st.y - s0.y;
      it.x = S.round(nb.x + (st.x - b.x) * kx - offx, 2); it.y = S.round(nb.y + (st.y - b.y) * ky - offy, 2); it.w = S.round(s0.w * kx, 2); it.h = S.round(s0.h * ky, 2);
      if (it.children && it.type === "group") { it.children = S.clone(s0.children); scaleKids(it, kx, ky); } rerenderItem(it); });
  }
  C.overlay();
}
function rerenderItem(it) {
  const el = elOf(it.id); if (!el) return;
  const f = S.findIn(A.doc, it.id); if (f && f.parent && f.parent.layout) return C.render();
  const n = S.renderItem(A.doc, it, { showHidden: A.settings.showHidden }); el.replaceWith(n);
}

/* drawing new things */
function parentAt(sc, wx, wy) {   // the frame you drew inside, if any
  let best = null;
  S.walk(sc.items, it => { if (it.type !== "frame" || it.hidden || it.locked) return; const b = C.box(it.id); if (b && wx >= b.x && wx <= b.x + b.w && wy >= b.y && wy <= b.y + b.h) best = it; });
  return best;
}
function finishDraw(L, e) {
  const t = A.tool, w = C.toWorld(e.clientX, e.clientY);
  let r = L.r;
  if (t === "F" && !L.sc) {   // a new screen
    const d = S.DEVICES[A.settings.defaultDevice] || S.DEVICES.iphone15pro;
    const sc = S.newScreen(r && r.w > 40 ? "custom" : A.settings.defaultDevice, { name: "Screen " + (A.doc.screens.length + 1) });
    if (r && r.w > 40 && r.h > 40) { sc.w = Math.round(r.w); sc.h = Math.round(r.h); sc.x = Math.round(r.x); sc.y = Math.round(r.y); } else { sc.x = Math.round(w.x); sc.y = Math.round(w.y); sc.w = d.w; sc.h = d.h; }
    A.doc.screens.push(sc); A.activeScreen = sc.id; A.selScreen = true; A.sel = []; C.setTool("V"); A.commit("New screen"); return;
  }
  const sc = L.sc; if (!sc) return;
  const type = { F: "frame", R: "rect", O: "ellipse", L: "line", T: "text", B: "button", S: "slider" }[t]; if (!type) return;
  const it = S.newItem(type);
  const click = !r || (r.w < 4 && r.h < 4);
  if (click) { const dw = { frame: 200, rect: 120, ellipse: 100, line: 160, text: 0, button: 160, slider: 240 }[type] ?? 100; r = { x: L.w0.x - (type === "text" ? 0 : dw / 2), y: L.w0.y - (type === "text" ? 10 : it.h / 2 || 50), w: type === "text" ? 0 : dw, h: type === "line" ? 0 : type === "text" ? 0 : (type === "frame" || type === "rect" || type === "ellipse") ? dw : it.h }; }
  const parent = parentAt(sc, r.x + 1, r.y + 1);
  const pb = parent ? C.box(parent.id) : { x: sc.x, y: sc.y };
  it.x = S.round(r.x - pb.x); it.y = S.round(r.y - pb.y);
  if (type === "text") { if (!click && r.w > 20) { it.w = Math.round(r.w); it.h = Math.max(24, Math.round(r.h)); it.text.sizing = "fixed"; it.text.overflow = "wrap"; } else { it.w = 40; it.h = 22; } it.text.content = ""; }
  else { it.w = Math.round(r.w); it.h = Math.round(r.h); }
  if (type === "line") { it.flipLine = !click && L.up; if (click) it.h = 0; }
  it.name = A.uniqueName(S.TYPES[type].label, sc);
  A.addItem(it, sc, parent ? parent.id : null);
  C.setTool("V");
  if (type === "text") { A.editing = it.id; C.render(); }
}
function drawPenLive() {
  const svgId = "penlive"; let s = ov.querySelector("#" + svgId);
  if (!s) { s = document.createElementNS("http://www.w3.org/2000/svg", "svg"); s.id = svgId; ov.append(s); }
  const pts = live.pts.map(([x, y]) => { const p = C.toCanvas(x, y); return p.x + "," + p.y; }).join(" ");
  s.innerHTML = `<polyline points="${pts}" fill="none" stroke="#4c8dff" stroke-width="2"/>`;
}
function finishPen(L) {
  const pts = L.pts; if (pts.length < 2) return C.overlay();
  const sc = L.sc, xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys), w = Math.max(1, Math.max(...xs) - x0), h = Math.max(1, Math.max(...ys) - y0);
  /* thin the points, then draw smooth curves through them */
  const keep = [pts[0]]; for (const p of pts) { const q = keep[keep.length - 1]; if (Math.hypot(p[0] - q[0], p[1] - q[1]) * V().zoom > 4) keep.push(p); }
  keep.push(pts[pts.length - 1]);
  const rel = keep.map(([x, y]) => [S.round(x - x0, 1), S.round(y - y0, 1)]);
  let d = `M${rel[0][0]} ${rel[0][1]}`;
  for (let i = 1; i < rel.length - 1; i++) { const mx = (rel[i][0] + rel[i + 1][0]) / 2, my = (rel[i][1] + rel[i + 1][1]) / 2; d += ` Q${rel[i][0]} ${rel[i][1]} ${S.round(mx, 1)} ${S.round(my, 1)}`; }
  d += ` L${rel[rel.length - 1][0]} ${rel[rel.length - 1][1]}`;
  const close = Math.hypot(pts[0][0] - pts[pts.length - 1][0], pts[0][1] - pts[pts.length - 1][1]) * V().zoom < 12 && pts.length > 10;
  if (close) d += " Z";
  const it = S.newItem("path", { name: A.uniqueName("Drawing", sc), x: S.round(x0 - sc.x), y: S.round(y0 - sc.y), w: S.round(w), h: S.round(h), path: { d, vw: S.round(w), vh: S.round(h) } });
  A.addItem(it, sc);
}

/* ---------- text editing on the canvas ---------- */
C.editText = id => {
  const f = S.findIn(A.doc, id); if (!f || !f.item.text) return;
  const it = f.item, el = elOf(id); if (!el) return;
  const t = el.querySelector(".tx") || el.querySelector(".bl") || (() => { const s = S.h("span", { cls: "bl" }); el.append(s); return s; })();
  t.contentEditable = "plaintext-only"; t.classList.add("editing-text"); t.textContent = it.text.content || "";
  if (it.type === "text" && it.text.sizing === "hug") t.style.minWidth = "4px";
  live = { kind: "text" }; C.overlay(); live = null;
  t.focus(); const range = document.createRange(); range.selectNodeContents(t); const s = window.getSelection(); s.removeAllRanges(); s.addRange(range);
  showTextBar(it, el);
  const grow = () => { if (it.type === "text" && it.text.sizing === "hug") { it.w = Math.max(4, Math.ceil(t.scrollWidth)); it.h = Math.max(it.text.size * 1.25, Math.ceil(t.scrollHeight)); el.style.width = it.w + "px"; el.style.height = it.h + "px"; } };
  t.addEventListener("input", grow);
  t.addEventListener("keydown", e => { e.stopPropagation(); if (e.key === "Escape" || (e.key === "Enter" && e.ctrlKey)) { e.preventDefault(); t.blur(); } });
  t.addEventListener("blur", () => {
    setTimeout(() => { if (document.activeElement && document.activeElement.closest && document.activeElement.closest(".textbar")) return; finish(); }, 0);
  });
  let done = false;
  const finish = () => {
    if (done) return; done = true; closeTextBar();
    const v = t.innerText.replace(/\n$/, "");
    if (!v && it.type === "text") { const g = S.findIn(A.doc, id); if (g) g.list.splice(g.index, 1); A.sel = []; A.commit("Delete empty text"); return; }
    grow(); A.touch(it, "text"); A.nameFromText(it, it.text.content, v); it.text.content = v; A.commit("Edit text");
  };
  C._finishText = finish;
};
let textBar = null;
function closeTextBar() { if (textBar) { textBar.remove(); textBar = null; } }
function showTextBar(it, el) {
  closeTextBar();
  const r = el.getBoundingClientRect();
  const T = it.text, upd = (k, v) => { A.touch(it, "text"); T[k] = v; const tx = el.querySelector(".tx,.bl"); if (tx) { const n = S.renderItem(A.doc, it); const nt = n.querySelector(".tx,.bl"); if (nt) { tx.style.cssText = nt.style.cssText; } } };
  const fonts = ["Inter", "Segoe UI", "Arial", "Georgia", "Times New Roman", "Courier New", "Verdana", "Trebuchet MS", "Impact", "Comic Sans MS"];
  const keepFocus = e => e.preventDefault();
  textBar = S.h("div", { cls: "textbar pop", style: { left: Math.max(8, r.left) + "px", top: Math.max(48, r.top - 46) + "px" } },
    S.h("div", { cls: "fld", style: { width: "120px" } }, (() => { const s = S.h("select", { onchange: e => upd("font", e.target.value) }, fonts.map(f => S.h("option", { value: f, selected: T.font === f }, f))); return s; })()),
    S.h("div", { cls: "fld", style: { width: "92px" } }, S.h("select", { onchange: e => upd("weight", +e.target.value) }, [[300, "Light"], [400, "Regular"], [500, "Medium"], [600, "Semibold"], [700, "Bold"], [800, "Extra bold"]].map(([v, l]) => S.h("option", { value: v, selected: +T.weight === v }, l)))),
    S.h("div", { cls: "fld", style: { width: "56px" } }, S.h("input", { type: "number", value: T.size, min: 4, max: 300, onchange: e => upd("size", +e.target.value) })),
    S.h("button", { cls: "ib" + (T.weight >= 700 ? " on" : ""), onmousedown: keepFocus, onclick: e => { upd("weight", T.weight >= 700 ? 400 : 700); e.currentTarget.classList.toggle("on"); } }, S.icon("bold", 14)),
    S.h("button", { cls: "ib" + (T.italic ? " on" : ""), onmousedown: keepFocus, onclick: e => { upd("italic", !T.italic); e.currentTarget.classList.toggle("on"); } }, S.icon("italic", 14)),
    S.h("button", { cls: "ib" + (T.deco === "underline" ? " on" : ""), onmousedown: keepFocus, onclick: e => { upd("deco", T.deco === "underline" ? "" : "underline"); e.currentTarget.classList.toggle("on"); } }, S.icon("underline", 14)),
    ...["left", "center", "right"].map(a => S.h("button", { cls: "ib" + (T.align === a ? " on" : ""), onmousedown: keepFocus, onclick: e => { upd("align", a); textBar.querySelectorAll(".al").forEach(b => b.classList.remove("on")); e.currentTarget.classList.add("on"); } }, S.icon("align-" + a, 14))).map(b => (b.classList.add("al"), b)),
    (() => { const sw = S.h("span", { cls: "sw", style: { margin: "0 4px" }, onmousedown: keepFocus }, S.h("i", { style: { background: S.resolveColor(A.doc, T.color) } })); sw.onclick = () => S.dlg.colorPicker(sw, T.color, c => { upd("color", c); sw.firstChild.style.background = c; }); return sw; })(),
    S.h("button", { cls: "ib", title: "Upper case", onmousedown: keepFocus, onclick: () => upd("case", T.case === "uppercase" ? "" : "uppercase") }, "Aa")
  );
  textBar.addEventListener("mousedown", e => { if (e.target.tagName !== "SELECT" && e.target.tagName !== "INPUT") e.preventDefault(); });
  document.body.append(textBar);
}

/* ---------- other canvas actions ---------- */
C.escape = () => {
  if (A.openNote) { A.openNote = null; return C.overlay(); }
  if (A.tool !== "V") return C.setTool("V");
  if (A.ctx) return C.exitGroup();
  A.sel = []; A.selScreen = false; A.selLink = null; A.refresh({ left: 1, right: 1 });
};
C.enter = () => {
  const it = A.selItems()[0]; if (!it) return;
  if (it.text && !it.children) return C.editText(it.id);
  if (it.children && it.children.length) { A.ctx = it.id; A.select(it.children[it.children.length - 1].id); }
};
C.exitGroup = () => { if (!A.ctx) { const it = A.selItems()[0]; if (it) { const f = S.findIn(A.doc, it.id); if (f && f.parent) { A.select(f.parent.id); } } return; } const g = A.ctx; const anc = S.ancestors(A.doc, g); A.ctx = anc.length ? anc[anc.length - 1].id : null; A.select(g); };
C.addNote = () => { const id = A.sel[0] || (A.selScreen ? A.activeScreen : null); if (!id) return S.toast("Select something first"); A.openNote = id; C.overlay(); };
C.insertCentered = (it, sc) => {
  sc = sc || A.screen(); if (!sc) return S.toast("Add a screen first", true);
  const r = rect(), c = C.toWorld(r.left + r.width / 2, r.top + r.height / 2);
  let cx = c.x - sc.x, cy = c.y - sc.y; if (cx < 0 || cx > sc.w || cy < 0 || cy > sc.h) { cx = sc.w / 2; cy = sc.h / 2; }
  it.x = S.round(S.clamp(cx - it.w / 2, -it.w / 2, sc.w - it.w / 2)); it.y = S.round(S.clamp(cy - it.h / 2, 0, sc.h - 20));
  it.name = A.uniqueName(it.name, sc);
  A.addItem(it, sc);
};
C.placeIcon = (name, at) => { const it = S.newItem("icon", { name: name.replace(/-/g, " ") + " icon", w: 32, h: 32, icon: { name, size: 32, color: "#FFFFFF", stroke: 2, filled: false } }); if (at) { it.x = S.round(at.x - 16); it.y = S.round(at.y - 16); it.name = A.uniqueName(it.name, at.sc); A.addItem(it, at.sc); } else C.insertCentered(it); C.setTool("V"); };
const readImg = file => new Promise(res => { const r = new FileReader(); r.onload = () => { const im = new Image(); im.onload = () => res({ src: r.result, w: im.naturalWidth, h: im.naturalHeight, name: file.name }); im.onerror = () => res(null); im.src = r.result; }; r.readAsDataURL(file); });
C.imageItem = (img, sc, x, y, maxW = 300) => {
  const k = Math.min(1, maxW / img.w, (sc.h * 0.8) / img.h);
  const it = S.newItem("image", { name: A.uniqueName((img.name || "Image").replace(/\.[^.]+$/, ""), sc), w: S.round(img.w * k), h: S.round(img.h * k), radius: 0, image: { src: img.src, fit: "cover" } });
  it.x = S.round((x ?? sc.w / 2) - it.w / 2); it.y = S.round((y ?? sc.h / 2) - it.h / 2);
  A.assetAdd(img);
  return it;
};
A.assetAdd = img => { A.doc.assets = A.doc.assets || []; if (!A.doc.assets.find(a => a.src === img.src)) A.doc.assets.push({ id: S.uid("a"), name: img.name || "Image", src: img.src, w: img.w, h: img.h }); };
C.pickImages = (at) => {
  const inp = $("file-img"); inp.value = "";
  inp.onchange = async () => {
    const sc = at ? at.sc : A.screen(); if (!sc) return S.toast("Add a screen first", true);
    let i = 0; const ids = [];
    for (const f of inp.files) { const img = await readImg(f); if (!img) continue; const it = C.imageItem(img, sc, (at ? at.x : sc.w / 2) + i * 20, (at ? at.y : sc.h / 2) + i * 20); sc.items.push(it); ids.push(it.id); i++; }
    if (ids.length) { A.sel = ids; A.activeScreen = sc.id; A.commit("Add image"); }
    C.setTool("V");
  };
  inp.click();
};
C.traceImage = () => {
  const inp = $("file-img"); inp.value = "";
  inp.onchange = async () => {
    const f = inp.files[0]; if (!f) return; const img = await readImg(f); if (!img) return;
    const sc = S.newScreen(A.settings.defaultDevice, { name: "Traced: " + img.name.replace(/\.[^.]+$/, "") });
    const k = Math.max(sc.w / img.w, sc.h / img.h);
    sc.items.push(S.newItem("image", { name: "Reference image", x: S.round((sc.w - img.w * k) / 2), y: S.round((sc.h - img.h * k) / 2), w: S.round(img.w * k), h: S.round(img.h * k), radius: 0, opacity: 0.4, locked: true, reference: true, status: "keep", image: { src: img.src, fit: "cover" } }));
    sc.chrome = false; A.assetAdd(img);
    A.addScreen(sc, "Trace image"); S.toast("The image is locked and faded. Draw on top of it. Unlock it in Layers.");
  };
  inp.click();
};
C.eyedrop = async () => {
  const its = A.selItems();
  if (window.EyeDropper) {
    try {
      const r = await new window.EyeDropper().open(); const c = r.sRGBHex.toUpperCase();
      if (its.length) { for (const it of its) { if (it.type === "text") A.setProp(it, "text.color", c, false); else if (it.type === "icon") A.setProp(it, "icon.color", c, false); else A.setProp(it, "fills", [{ kind: "solid", color: c }], false); } A.commit("Eyedropper"); S.toast("Colour " + c + " applied"); }
      else { S.host.copyText(c); A.recentColor(c); S.toast("Copied " + c); }
    } catch (e) {}
  } else S.toast("The eyedropper needs the Windows app");
};
A.recentColor = c => { A.settings.recentColors = [c].concat((A.settings.recentColors || []).filter(x => x !== c)).slice(0, 12); A.saveSettings(); };

/* paste: images and text from Windows' clipboard, or things copied inside the studio */
let pasteShift = false;
C.handlePaste = async (data, inPlace) => {
  const sc = A.screen();
  const files = data.files || [];
  if (files.length && sc) {
    const ids = [];
    for (const f of files) { if (!f.type.startsWith("image/")) continue; const img = await readImg(f); if (!img) continue; const it = C.imageItem(img, sc); sc.items.push(it); ids.push(it.id); }
    if (ids.length) { A.sel = ids; A.commit("Paste image"); return; }
  }
  if (data.image && sc) { const img = await new Promise(res => { const im = new Image(); im.onload = () => res({ src: data.image, w: im.naturalWidth, h: im.naturalHeight, name: "Pasted image" }); im.onerror = () => res(null); im.src = data.image; }); if (img) { const it = C.imageItem(img, sc); sc.items.push(it); A.sel = [it.id]; A.commit("Paste image"); return; } }
  const text = data.text || "";
  if (text.startsWith('{"macawStudio"')) { try { const o = JSON.parse(text); return A.paste(inPlace, o.items); } catch (e) {} }
  if (A.clip && (!text || text.includes("macawStudio"))) return A.paste(inPlace);
  if (text.trim() && sc) { const it = S.newItem("text", { text: Object.assign(S.newItem("text").text, { content: text.trim().slice(0, 2000), sizing: text.length > 40 ? "fixed" : "hug", overflow: "wrap" }) }); if (text.length > 40) it.w = 300; C.insertCentered(it, sc); }
};
C.pasteFromSystem = async inPlace => {
  let data = {};
  try { if (S.host.readClipboard) data = await S.host.readClipboard(); else data.text = await navigator.clipboard.readText(); } catch (e) {}
  C.handlePaste(data, inPlace);
};

/* ---------- start ---------- */
C.init = () => {
  cv = $("canvas"); world = $("world"); ov = $("overlay");
  /* tool bar */
  const tb = $("toolbar");
  for (const t of S.TOOLS) {
    if (t === "|") { tb.append(S.h("div", { cls: "tsep" })); continue; }
    const b = S.h("button", { cls: "tool", "data-tool": t[0], title: `${t[1]} (${t[0]})`, onclick: () => C.setTool(t[0]) }, S.icon(t[2], 17), S.h("small", {}, t[0]));
    tb.append(b);
  }
  cv.addEventListener("pointerdown", onDown);
  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onUp);
  cv.addEventListener("dblclick", e => {
    if (e.target.dataset.guide != null) { const g = A.doc.guides[+e.target.dataset.guide], sc = A.screen(); S.dlg.prompt("Guide position", "Pixels from the " + (g.axis === "x" ? "left" : "top") + " of " + (sc ? sc.name : "the board"), String(g.pos - (sc ? (g.axis === "x" ? sc.x : sc.y) : 0))).then(v => { if (v != null && v !== "") { g.pos = +v + (sc ? (g.axis === "x" ? sc.x : sc.y) : 0); A.commit("Guide"); } }); return; }
    if (e.target.closest("[data-slabel]")) { const sc = S.screenOf(A.doc, e.target.closest("[data-slabel]").dataset.slabel); S.dlg.prompt("Rename screen", "Name", sc.name).then(n => { if (n) { sc.name = n; A.commit("Rename screen"); } }); return; }
    if (A.tool !== "V") return;
    const deep = C.pick(e, true); if (!deep) return;
    const cur = A.sel[0];
    const path = itemPath(deep);
    if (cur && path.some(p => p.id === cur) && cur !== deep) {   // go one level into the group
      const i = path.findIndex(p => p.id === cur); A.ctx = cur; A.select(path[i + 1].id); C.overlay(); return;
    }
    const it = S.findIn(A.doc, deep).item;
    if (it.text && deep === (cur || deep)) { A.sel = [deep]; C.editText(deep); }
  });
  cv.addEventListener("contextmenu", e => {
    e.preventDefault();
    if (A.tool === "V") { const id = C.pick(e, e.ctrlKey); if (id && !A.sel.includes(id)) A.select(id); }
    const sl = e.target.closest("[data-slabel]"); if (sl) A.selectScreen(sl.dataset.slabel);
    S.dlg.contextMenu(e.clientX, e.clientY);
  });
  cv.addEventListener("wheel", e => {
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) { const r = rect(); C.zoomSet(V().zoom * Math.exp(-e.deltaY * (e.deltaMode ? 0.05 : 0.0025)), e.clientX - r.left, e.clientY - r.top); return; }
    const v = V(), k = e.deltaMode ? 30 : 1;
    if (e.shiftKey) { v.x -= (e.deltaY || e.deltaX) * k; } else { v.x -= e.deltaX * k; v.y -= e.deltaY * k; }
    C.applyView(); A.markViewDirty();
  }, { passive: false });
  window.addEventListener("keydown", e => {
    if (e.code === "Space" && !spaceDown && !(e.target.closest && e.target.closest("input,textarea,select,[contenteditable]"))) { spaceDown = true; cv.style.cursor = "grab"; e.preventDefault(); }
    if (e.key === "Alt") { e.preventDefault(); if (!A.measure && A.sel.length) { A.measure = true; C.overlay(); } }
    if (e.key === "Shift") pasteShift = true;
  });
  window.addEventListener("keyup", e => {
    if (e.code === "Space") { spaceDown = false; C.setTool(A.tool); }
    if (e.key === "Alt") { A.measure = A.tool === "M"; C.overlay(); }
    if (e.key === "Shift") pasteShift = false;
  });
  document.addEventListener("paste", e => {
    if (e.target.closest && e.target.closest("input,textarea,[contenteditable]")) return;
    if (!A.doc || document.getElementById("home") && !$("home").classList.contains("hide")) return;
    e.preventDefault();
    C.handlePaste({ files: [...(e.clipboardData.files || [])], text: e.clipboardData.getData("text/plain") }, pasteShift);
  });
  /* files dragged in from Explorer */
  cv.addEventListener("dragover", e => { if ([...e.dataTransfer.types].includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } });
  cv.addEventListener("drop", async e => {
    e.preventDefault();
    const w = C.toWorld(e.clientX, e.clientY), sc = screenAt(w.x, w.y) || A.screen();
    const pdata = e.dataTransfer.getData("application/x-macaw-part");
    if (pdata) return S.panels.dropPart(pdata, sc, w);
    const ids = [];
    for (const f of e.dataTransfer.files) {
      if (/\.macaw$/i.test(f.name)) { const t = await f.text(); try { A.open(JSON.parse(t)); A.save(); } catch (x) { S.toast("Could not read " + f.name, true); } return; }
      if (f.type.startsWith("image/") && sc) { const img = await readImg(f); if (!img) continue; const it = C.imageItem(img, sc, w.x - sc.x + ids.length * 20, w.y - sc.y + ids.length * 20); sc.items.push(it); ids.push(it.id); }
    }
    if (ids.length) { A.sel = ids; A.commit("Add image"); }
  });
  cv.addEventListener("dragover", e => { if ([...e.dataTransfer.types].includes("application/x-macaw-part")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } });
  new ResizeObserver(() => C.overlay()).observe(cv);
  C.setTool("V");
};
})();
