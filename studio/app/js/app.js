/* Macaw Studio: the editor's state, undo history, actions (every menu item and shortcut), saving. */
"use strict";
const A = S.app = {
  doc: null, path: null, savedText: "", sel: [], ctx: null, tool: "V", activeScreen: null, clip: null,
  hist: [], hi: -1, settings: {}, leftTab: "layers", rightTab: "design", dirty: false
};
S.DEFAULT_SETTINGS = {
  theme: "dark", uiScale: 1, grid: 8, snap: true, gridSnap: true, guides: true, rulers: true, chrome: true, safe: false, showHidden: false,
  nudge: 1, bigNudge: 8, defaultDevice: "iphone15pro", openLast: true, shortcuts: {}, recent: [], starred: [],
  send: { delivery: "github", scale: 2, includeKeep: false, token: "", repo: "t6wy26zj95-creator/mp3-player", branch: "main" }
};

/* ---------- little UI helpers used everywhere ---------- */
S.toast = (msg, err = false, ms = 2600) => { const t = S.h("div", { cls: "toast" + (err ? " err" : "") }, msg); document.body.append(t); setTimeout(() => t.remove(), ms); };
S.icon = (name, size = 16, sw = 2) => { const s = document.createElement("span"); s.style.display = "inline-flex"; s.innerHTML = S.iconSVG(name, size, "currentColor", sw); return s; };

/* ---------- history ---------- */
const snap = () => JSON.stringify({ name: A.doc.name, screens: A.doc.screens, links: A.doc.links, guides: A.doc.guides, colorStyles: A.doc.colorStyles, textStyles: A.doc.textStyles, myParts: A.doc.myParts, message: A.doc.message });
A.resetHistory = () => { A.hist = [{ s: snap(), label: "Opened", sel: [] }]; A.hi = 0; };
A.commit = (label = "Change") => {
  autoStatus();
  const s = snap();
  if (A.hist[A.hi] && A.hist[A.hi].s === s) { A.refresh(); return; }
  A.hist = A.hist.slice(0, A.hi + 1);
  const last = A.hist[A.hi];
  if (last && last.label === label && label.startsWith("~") && Date.now() - last.t < 800) A.hist[A.hi] = { s, label, sel: A.sel.slice(), t: Date.now() };   // typing in a field: one undo step
  else { A.hist.push({ s, label, sel: A.sel.slice(), t: Date.now() }); A.hi++; }
  if (A.hist.length > 600) { A.hist.shift(); A.hi--; }
  A.markDirty(); A.refresh();
};
/* a "keep" screen you've edited becomes "changed" by itself (unless you picked its status by hand) */
function autoStatus() {
  for (const sc of (A.doc && A.doc.screens) || []) {
    if (sc.status !== "keep" || sc.statusByHand) continue;
    let edited = (sc.removed || []).length > 0;
    if (!edited) S.walk(sc.items, it => { if (it.status && it.status !== "keep") edited = true; });
    if (edited) sc.status = "changed";
  }
}
const restore = h => { const o = JSON.parse(h.s); Object.assign(A.doc, o); A.sel = (h.sel || []).filter(id => S.findIn(A.doc, id)); A.markDirty(); A.refresh(); };
A.undo = () => { if (A.hi > 0) { A.hi--; restore(A.hist[A.hi]); S.toast("Undo: " + A.hist[A.hi + 1].label.replace("~", ""), false, 1200); } };
A.redo = () => { if (A.hi < A.hist.length - 1) { A.hi++; restore(A.hist[A.hi]); S.toast("Redo: " + A.hist[A.hi].label.replace("~", ""), false, 1200); } };
A.jumpHistory = i => { if (i >= 0 && i < A.hist.length) { A.hi = i; restore(A.hist[i]); } };

/* ---------- redraw ---------- */
let rq = 0;
A.refresh = (parts = { canvas: 1, left: 1, right: 1 }) => {
  A._pending = Object.assign(A._pending || {}, parts);
  if (rq) return;
  rq = requestAnimationFrame(() => {
    rq = 0; const p = A._pending; A._pending = null;
    if (p.canvas && S.canvas) S.canvas.render();
    if (p.left && S.panels) S.panels.renderLeft();
    if (p.right && S.panels) S.panels.renderRight();
    if (S.canvas) S.canvas.overlay();
    A.updateChrome();
  });
};
A.updateChrome = () => {
  const $ = id => document.getElementById(id);
  $("doc-title").textContent = A.doc ? A.doc.name : "";
  $("b-undo").disabled = A.hi <= 0; $("b-redo").disabled = A.hi >= A.hist.length - 1;
  const z = Math.round((A.doc ? A.doc.view.zoom : 1) * 100) + "%";
  $("b-zoom").textContent = z; $("st-zoom").textContent = z;
  const sd = $("savedot"); sd.classList.toggle("busy", A.dirty); sd.lastChild.textContent = A.dirty ? "Saving…" : "Saved";
  const st = A.settings;
  $("st-snap").classList.toggle("off", !st.snap); $("st-grid").textContent = "Grid " + st.grid + " px"; $("st-grid").classList.toggle("off", !st.gridSnap);
  $("st-guides").classList.toggle("off", !st.guides); $("st-rulers").classList.toggle("off", !st.rulers);
  document.body.classList.toggle("norulers", !st.rulers); document.body.classList.toggle("show-hidden", !!st.showHidden);
  const its = A.selItems();
  $("st-sel").innerHTML = its.length === 1 ? `1 selected: <b>${S.esc(its[0].name)}</b>` : its.length ? `<b>${its.length}</b> selected` : A.selScreen ? `Screen: <b>${S.esc(A.screen()?.name || "")}</b>` : "Nothing selected";
  document.querySelectorAll(".tool").forEach(t => t.classList.toggle("on", t.dataset.tool === A.tool));
};

/* ---------- selection ---------- */
A.selItems = () => A.sel.map(id => S.findIn(A.doc, id)).filter(Boolean).map(f => f.item);
A.select = (ids, add = false) => {
  ids = [].concat(ids || []);
  A.selScreen = false;
  A.sel = add ? [...new Set(A.sel.filter(x => !ids.includes(x)).concat(ids.filter(x => !A.sel.includes(x))))] : ids;
  const f = A.sel.length && S.findIn(A.doc, A.sel[0]);
  if (f) { A.activeScreen = f.screen.id; const anc = S.ancestors(A.doc, f.item.id); if (A.ctx && !anc.find(a => a.id === A.ctx)) A.ctx = anc.length ? anc[anc.length - 1].id : null; }
  A.refresh({ left: 1, right: 1 });
};
A.selectScreen = id => { A.sel = []; A.ctx = null; A.activeScreen = id; A.selScreen = true; A.refresh({ left: 1, right: 1 }); };
A.screen = () => A.doc.screens.find(s => s.id === A.activeScreen) || A.doc.screens[0];

/* ---------- editing items ---------- */
const TRACK = ["x", "y", "w", "h", "rot", "opacity", "fills", "stroke", "radius", "effects", "text", "icon", "slider", "toggle", "image", "hidden", "layout"];
/* every change to an item goes through here, so a MacawP3 piece you touch becomes "changed" and remembers what it was */
/* new text and buttons are named after what they say ("Play all" instead of "Button 3"), until you rename them */
A.nameFromText = (it, before, after) => {
  if (!it || it.nameByHand || !["text", "button", "badge"].includes(it.type)) return;
  const short = s => String(s || "").replace(/\s+/g, " ").trim().slice(0, 32);
  const generic = new RegExp("^(" + (S.TYPES[it.type]?.label || it.type) + "|Text|Button|Badge)( \\d+)?$");
  if ((generic.test(it.name) || (before && it.name === short(before))) && short(after)) it.name = short(after);
};
A.touch = (it, key) => {
  if (!it) return;
  if (it.status === "keep" && TRACK.includes(key)) it.status = "changed";
  if (it.status === "changed" && it.orig && TRACK.includes(key)) { it.changedFrom = it.changedFrom || {}; if (!(key in it.changedFrom)) it.changedFrom[key] = S.clone(it.orig[key]); }
};
A.setProp = (it, path, val, label) => {   // path like "text.size" or "x"
  const keys = path.split("."), top = keys[0];
  let target = it;
  if (it.viewState && it.viewState !== "normal" && ["fills", "stroke", "effects", "text", "icon", "opacity", "w", "h"].includes(top)) {   // editing the Pressed / Playing look
    it.states = it.states || {}; const st = it.states[it.viewState] = it.states[it.viewState] || {};
    if (!(top in st)) st[top] = S.clone(it[top]) ?? (top === "fills" || top === "effects" ? [] : {});
    target = st;
  } else A.touch(it, top);
  let o = target; for (let i = 0; i < keys.length - 1; i++) { if (o[keys[i]] == null || typeof o[keys[i]] !== "object") o[keys[i]] = {}; o = o[keys[i]]; }
  o[keys[keys.length - 1]] = val;
  if (label !== false) A.commit(label || "~" + path);
};
/* MacawP3 parts remember how they looked when copied, for "changedFrom" */
A.stampOrig = items => S.walk(items, it => { if (it.status === "keep" && !it.orig) { const o = {}; for (const k of TRACK) if (k in it) o[k] = S.clone(it[k]); it.orig = o; } });

/* groups always wrap their children exactly */
A.fitGroup = g => {
  if (!g || g.type !== "group" || !g.children.length || g.layout) return;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const c of g.children) { x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y); x1 = Math.max(x1, c.x + c.w); y1 = Math.max(y1, c.y + c.h); }
  if (x0 === 0 && y0 === 0 && g.w === x1 && g.h === y1) return;
  for (const c of g.children) { c.x = S.round(c.x - x0, 2); c.y = S.round(c.y - y0, 2); }
  g.x = S.round(g.x + x0, 2); g.y = S.round(g.y + y0, 2); g.w = S.round(x1 - x0, 2); g.h = S.round(y1 - y0, 2);
};
A.fitParents = id => { for (const a of S.ancestors(A.doc, id).reverse()) A.fitGroup(a); };

A.uniqueName = (base, sc) => { const names = new Set(); S.walk(sc.items, i => names.add(i.name)); if (!names.has(base)) return base; for (let k = 2; ; k++) if (!names.has(base + " " + k)) return base + " " + k; };
A.addItem = (it, screen, parentId = null, select = true) => {
  screen = screen || A.screen();
  if (!screen) { S.toast("Add a screen first (Screens tab, + New)", true); return; }
  const parent = parentId && S.findIn(A.doc, parentId);
  (parent ? parent.item.children : screen.items).push(it);
  if (parentId) A.fitParents(it.id);
  if (select) { A.activeScreen = screen.id; A.sel = [it.id]; A.selScreen = false; }
  A.commit("Add " + it.name);
  return it;
};
A.deleteSel = () => {
  const items = A.selItems(); if (!items.length) { if (A.selScreen) A.deleteScreen(A.activeScreen); return; }
  for (const it of items) {
    const f = S.findIn(A.doc, it.id); if (!f || it.locked) continue;
    if (it.part && it.part.startsWith("macawp3:") || it.status === "keep" || it.status === "changed") {   // a real app piece: tell Claude it was taken out on purpose
      const p = S.absPos(A.doc, it.id);
      (f.screen.removed = f.screen.removed || []).push({ name: it.name, part: it.part || "", box: { x: S.round(p.x), y: S.round(p.y), w: S.round(it.w), h: S.round(it.h) } });
    }
    f.list.splice(f.index, 1);
    if (f.parent) { if (f.parent.type === "group" && !f.parent.children.length) { const g = S.findIn(A.doc, f.parent.id); g.list.splice(g.index, 1); } else A.fitParents(f.parent.children[0]?.id); }
    A.doc.links = A.doc.links.filter(l => l.from !== it.id);
  }
  A.sel = []; A.commit("Delete");
};
A.deleteScreen = id => {
  const i = A.doc.screens.findIndex(s => s.id === id); if (i < 0) return;
  if (!confirm(`Delete the screen "${A.doc.screens[i].name}"? (Undo brings it back.)`)) return;
  const sc = A.doc.screens[i], ids = new Set(); S.walk(sc.items, it => ids.add(it.id));
  A.doc.screens.splice(i, 1);
  A.doc.links = A.doc.links.filter(l => l.to !== id && !ids.has(l.from));
  A.activeScreen = A.doc.screens[0]?.id; A.sel = []; A.selScreen = false; A.commit("Delete screen");
};
const reid = it => { S.walk([it], i => { i.id = S.uid(); }); return it; };
A.copy = (cut = false) => {
  const items = A.selItems(); if (!items.length) return;
  A.clip = items.map(it => { const c = S.clone(it); const p = S.absPos(A.doc, it.id); c.x = p.x; c.y = p.y; return c; });
  S.host.copyText(JSON.stringify({ macawStudio: 1, items: A.clip }));
  if (cut) A.deleteSel(); else S.toast(`Copied ${items.length} item${items.length > 1 ? "s" : ""}`, false, 1000);
};
A.paste = (inPlace = false, items = null) => {
  items = items || A.clip; if (!items || !items.length) return;
  const sc = A.screen(); if (!sc) return;
  const ids = [];
  for (const src of items) {
    const it = reid(S.clone(src));
    if (!inPlace) { it.x += 16; it.y += 16; }
    it.status = "new"; delete it.orig; delete it.changedFrom; S.walk([it], c => { if (c.status === "keep" || c.status === "changed") { c.status = "new"; delete c.orig; delete c.changedFrom; } });
    sc.items.push(it); ids.push(it.id);
  }
  A.clip = items.map(i => Object.assign(S.clone(i), inPlace ? {} : { x: i.x + 16, y: i.y + 16 }));
  A.sel = ids; A.activeScreen = sc.id; A.commit("Paste");
};
A.lastMove = null;
A.duplicate = () => {
  const items = A.selItems(); if (!items.length) return;
  const ids = [], d = A.lastMove || { dx: 16, dy: 16 };
  for (const it of items) {
    const f = S.findIn(A.doc, it.id), c = reid(S.clone(it));
    c.x += d.dx; c.y += d.dy; c.name = it.name; S.walk([c], x => { if (x.status !== "new") { x.status = "new"; delete x.orig; delete x.changedFrom; } });
    f.list.splice(f.index + 1, 0, c); ids.push(c.id); if (f.parent) A.fitParents(c.id);
  }
  A.sel = ids; A.dupMode = true; A.commit("Duplicate");
};
A.group = () => {
  const items = A.selItems(); if (items.length < 1) return;
  const f0 = S.findIn(A.doc, items[0].id), list = f0.list;
  const fs = items.map(it => S.findIn(A.doc, it.id)).filter(f => f.list === list).sort((a, b) => a.index - b.index);
  const g = S.newItem("group", { name: A.uniqueName("Group", f0.screen), children: [] });
  const at = fs[fs.length - 1].index;
  fs.forEach(f => g.children.push(f.item));
  for (const f of fs.slice().reverse()) list.splice(f.index, 1);
  list.splice(at - fs.length + 1, 0, g);
  g.x = 0; g.y = 0; g.w = 1; g.h = 1; A.fitGroup(g); if (f0.parent) A.fitParents(g.id);
  A.sel = [g.id]; A.commit("Group");
};
A.ungroup = () => {
  const ids = [];
  for (const it of A.selItems()) {
    if (!it.children || !it.children.length || it.type !== "group" && it.type !== "frame") { ids.push(it.id); continue; }
    const f = S.findIn(A.doc, it.id);
    const kids = it.children.map(c => Object.assign(c, { x: c.x + it.x, y: c.y + it.y }));
    if (it.type === "frame") { it.children = []; f.list.splice(f.index + 1, 0, ...kids); }   // frames stay, their contents come out
    else f.list.splice(f.index, 1, ...kids);
    ids.push(...kids.map(k => k.id));
  }
  A.sel = ids; A.commit("Ungroup");
};
A.wrapAuto = () => {
  let items = A.selItems(); if (!items.length) return;
  if (!(items.length === 1 && (items[0].type === "frame" || items[0].type === "group"))) { A.group(); items = A.selItems(); }
  const g = items[0]; const kids = g.children;
  const spanX = Math.max(...kids.map(k => k.x + k.w)) - Math.min(...kids.map(k => k.x)), spanY = Math.max(...kids.map(k => k.y + k.h)) - Math.min(...kids.map(k => k.y));
  const dir = spanX >= spanY ? "row" : "col";
  kids.sort((a, b) => dir === "row" ? a.x - b.x : a.y - b.y);
  g.layout = { dir, gap: 8, pad: 0, align: "center", justify: "start", hug: true };
  A.touch(g, "layout"); A.commit("Auto layout");
};
A.restack = how => {
  for (const it of A.selItems()) {
    const f = S.findIn(A.doc, it.id), L = f.list; L.splice(f.index, 1);
    const i = how === "front" ? L.length : how === "back" ? 0 : how === "up" ? Math.min(L.length, f.index + 1) : Math.max(0, f.index - 1);
    L.splice(i, 0, it);
  }
  A.commit("Reorder");
};
A.align = how => {
  const items = A.selItems(); if (!items.length) return;
  const abs = items.map(it => ({ it, p: S.absPos(A.doc, it.id) }));
  let box;
  if (items.length === 1) { const f = S.findIn(A.doc, items[0].id); box = f.parent ? { x: f.parent.x - abs[0].p.x + items[0].x, y: 0, w: f.parent.w, h: f.parent.h } : { x: 0, y: 0, w: f.screen.w, h: f.screen.h }; if (f.parent) { const pp = S.absPos(A.doc, f.parent.id); box = { x: pp.x, y: pp.y, w: pp.w, h: pp.h }; } }
  else { const x0 = Math.min(...abs.map(a => a.p.x)), y0 = Math.min(...abs.map(a => a.p.y)); box = { x: x0, y: y0, w: Math.max(...abs.map(a => a.p.x + a.p.w)) - x0, h: Math.max(...abs.map(a => a.p.y + a.p.h)) - y0 }; }
  for (const { it, p } of abs) {
    let nx = p.x, ny = p.y;
    if (how === "left") nx = box.x; if (how === "hcenter") nx = box.x + (box.w - it.w) / 2; if (how === "right") nx = box.x + box.w - it.w;
    if (how === "top") ny = box.y; if (how === "vcenter") ny = box.y + (box.h - it.h) / 2; if (how === "bottom") ny = box.y + box.h - it.h;
    A.touch(it, "x"); A.touch(it, "y"); it.x = S.round(it.x + nx - p.x, 2); it.y = S.round(it.y + ny - p.y, 2);
  }
  items.forEach(it => A.fitParents(it.id)); A.commit("Align");
};
A.distribute = axis => {
  const items = A.selItems(); if (items.length < 3) return S.toast("Pick 3 or more items to spread out");
  const k = axis === "h" ? "x" : "y", d = axis === "h" ? "w" : "h";
  const s = items.slice().sort((a, b) => a[k] - b[k]);
  const total = s.reduce((t, i) => t + i[d], 0), span = s[s.length - 1][k] + s[s.length - 1][d] - s[0][k], gap = (span - total) / (s.length - 1);
  let pos = s[0][k]; for (const it of s) { A.touch(it, k); it[k] = S.round(pos, 2); pos += it[d] + gap; }
  A.commit("Spread evenly");
};
A.matchSize = d => { const items = A.selItems(); if (items.length < 2) return; for (const it of items.slice(1)) { A.touch(it, d); it[d] = items[0][d]; } A.commit("Match size"); };
A.flip = ax => { for (const it of A.selItems()) { A.touch(it, "flip"); if (it.type === "line" && ax === "x") it.flipLine = !it.flipLine; else it[ax === "x" ? "flipX" : "flipY"] = !it[ax === "x" ? "flipX" : "flipY"]; } A.commit("Flip"); };
A.nudge = (dx, dy) => {
  const items = A.selItems().filter(i => !i.locked); if (!items.length) return;
  for (const it of items) { A.touch(it, "x"); A.touch(it, "y"); it.x = S.round(it.x + dx, 2); it.y = S.round(it.y + dy, 2); A.fitParents(it.id); }
  A.commit("~Nudge");
};
A.toggleProp = k => { const items = A.selItems(); if (!items.length) return; const v = !items[0][k]; for (const it of items) { if (k === "hidden") A.touch(it, k); it[k] = v; } if (k === "locked" && v) A.sel = []; A.commit(k === "hidden" ? (v ? "Hide" : "Show") : (v ? "Lock" : "Unlock")); };
A.setStatus = st => {
  const items = A.selItems();
  if (!items.length && A.selScreen) { A.screen().status = st; A.screen().statusByHand = true; return A.commit("Mark screen " + st); }
  for (const it of items) it.status = st;
  A.commit("Mark as " + st);
};
A.copyStyle = () => { const it = A.selItems()[0]; if (!it) return; A.styleClip = S.clone({ fills: it.fills, stroke: it.stroke, radius: it.radius, effects: it.effects, opacity: it.opacity, text: it.text && Object.assign({}, it.text, { content: undefined }) }); S.toast("Style copied", false, 1000); };
A.pasteStyle = () => {
  if (!A.styleClip) return;
  for (const it of A.selItems()) for (const [k, v] of Object.entries(A.styleClip)) {
    if (v === undefined) continue; A.touch(it, k);
    if (k === "text") { if (it.text) it.text = Object.assign({}, it.text, S.clone(v), { content: it.text.content }); } else it[k] = S.clone(v);
  }
  A.commit("Paste style");
};
A.selectAll = () => { const sc = A.screen(); if (!sc) return; const ctx = A.ctx && S.findIn(A.doc, A.ctx); A.select((ctx ? ctx.item.children : sc.items).filter(i => !i.locked && !i.hidden).map(i => i.id)); };

/* ---------- screens ---------- */
A.placeNewScreen = sc => {
  const last = A.doc.screens.reduce((m, s) => Math.max(m, s.x + s.w), -120);
  sc.x = last + 120; sc.y = A.doc.screens[0] ? A.doc.screens[0].y : 0;
  return sc;
};
A.addScreen = (sc, label = "Add screen") => { A.placeNewScreen(sc); A.stampOrig(sc.items); A.doc.screens.push(sc); A.activeScreen = sc.id; A.sel = []; A.selScreen = true; A.commit(label); S.canvas && S.canvas.zoomTo(sc); return sc; };
A.duplicateScreen = id => {
  const sc = S.screenOf(A.doc, id); if (!sc) return;
  const c = S.clone(sc); c.id = S.uid("s"); c.name = sc.name + " copy"; S.walk(c.items, i => { i.id = S.uid(); });
  const i = A.doc.screens.indexOf(sc); A.doc.screens.splice(i + 1, 0, c);
  c.x = sc.x + sc.w + 120; for (const o of A.doc.screens.slice(i + 2)) o.x += sc.w + 120;
  A.activeScreen = c.id; A.commit("Duplicate screen");
};

/* ---------- parts I make myself (kept in the app, so every design has them) ---------- */
A.saveAsPart = async () => {
  const it = A.selItems()[0]; if (!it) return S.toast("Select something to save as a part");
  const name = await S.dlg.prompt("Save as my part", "Name", it.name); if (!name) return;
  const id = S.uid("mp"), master = S.clone(it); master.x = 0; master.y = 0; master.name = name;
  A.settings.myParts = (A.settings.myParts || []).concat({ id, name, item: master });
  it.partRef = id; A.saveSettings(); A.commit("Save as part"); S.toast(`Saved "${name}" in Parts > Mine`);
};
A.updatePartFrom = () => {
  const it = A.selItems()[0]; if (!it || !it.partRef) return S.toast("Select a copy of one of your parts");
  const p = (A.settings.myParts || []).find(x => x.id === it.partRef); if (!p) return;
  p.item = Object.assign(S.clone(it), { x: 0, y: 0, name: p.name }); A.saveSettings(); A.syncPartCopies(p.id);
};
A.syncPartCopies = pid => {
  const p = (A.settings.myParts || []).find(x => x.id === pid); if (!p) return;
  let n = 0;
  for (const sc of A.doc.screens) S.walk(sc.items, (it, parent) => {
    if (it.partRef !== pid) return;
    const keepPos = { id: it.id, x: it.x, y: it.y, name: it.name, status: it.status, note: it.note, partRef: pid };
    const fresh = S.clone(p.item); S.walk(fresh.children || [], c => { c.id = S.uid(); });
    for (const k of Object.keys(it)) delete it[k];
    Object.assign(it, fresh, keepPos); n++;
  });
  A.commit("Update part copies"); S.toast(`Updated ${n} cop${n === 1 ? "y" : "ies"} of "${p.name}"`);
};

/* ---------- saving ---------- */
A.markDirty = () => { A.dirty = true; A.autosave(); A.updateChrome && A.updateChrome(); };
A.docText = () => JSON.stringify(A.doc);
A.autosave = S.debounce(() => A.save(), 1500);
A.save = async (quiet = true) => {
  if (!A.doc) return;
  A.doc.updated = Date.now();
  const text = A.docText();
  try {
    if (!A.path) A.path = await S.host.newDesignPath(A.doc.name);
    A.path = await S.host.writeDesign(A.path, text);
    A.dirty = false; A.savedText = text;
    S.host.backup(A.doc.id, A.doc.name, text);
    A.remember(A.path);
  } catch (e) { S.toast("Could not save: " + e.message, true); }
  A.updateChrome();
};
A.remember = p => { const r = (A.settings.recent || []).filter(x => x !== p); r.unshift(p); A.settings.recent = r.slice(0, 30); A.settings.lastOpen = p; A.saveSettings(); };
A.saveSettings = S.debounce(() => S.host.setSettings(A.settings), 300);
A.applySettings = () => {
  document.documentElement.classList.toggle("light", A.settings.theme === "light");
  S.host.setTheme(A.settings.theme);
  S.host.setZoom(A.settings.uiScale || 1);
};
A.open = (doc, path = null) => {
  if (!doc || doc.app !== "macaw-studio") { S.toast("That isn't a Macaw Studio design", true); return; }
  doc.links = doc.links || []; doc.guides = doc.guides || []; doc.versions = doc.versions || []; doc.view = doc.view || { x: 80, y: 80, zoom: 0.75 };
  doc.colorStyles = doc.colorStyles || []; doc.textStyles = doc.textStyles || []; doc.myParts = doc.myParts || [];
  A.doc = doc; A.path = path; A.sel = []; A.ctx = null; A.activeScreen = doc.screens[0]?.id; A.selScreen = false; A.dirty = false;
  A.resetHistory(); S.home && S.home.close();
  if (path) A.remember(path);
  A.refresh();
  setTimeout(() => S.canvas && (doc.screens.length ? S.canvas.zoomFit() : null), 30);
};
A.openPath = async p => { try { A.open(JSON.parse(await S.host.readFile(p)), p); } catch (e) { S.toast("Could not open it: " + e.message, true); } };
A.openFile = async () => { const r = await S.host.openDialog(); if (r) { try { A.open(JSON.parse(r.text), r.path.endsWith(".macaw") && r.inDesigns ? r.path : null); if (!A.path) A.save(); } catch (e) { S.toast("Could not read that file", true); } } };
A.rename = async () => { const n = await S.dlg.prompt("Rename design", "Name", A.doc.name); if (n && n !== A.doc.name) { A.doc.name = n; if (A.path) A.path = await S.host.renameDesign(A.path, n); A.commit("Rename design"); } };
A.saveVersion = async () => {
  const n = await S.dlg.prompt("Save version", "Name this version", "Version " + (A.doc.versions.length + 1)); if (!n) return;
  A.doc.versions.push({ id: S.uid("v"), name: n, date: Date.now(), data: JSON.parse(snap()) }); A.markDirty(); A.refresh({ left: 1 }); S.toast(`Saved "${n}"`);
};
A.restoreVersion = v => { if (!confirm(`Go back to "${v.name}"? Your current work stays in Undo.`)) return; Object.assign(A.doc, S.clone(v.data)); A.sel = []; A.commit("Restore " + v.name); };
A.versionSideBySide = v => {   // the old version's screens next to the current ones, so you can compare
  const off = Math.max(...A.doc.screens.map(s => s.y + s.h)) + 200;
  for (const s of v.data.screens) { const c = S.clone(s); c.id = S.uid("s"); c.name = s.name + " (" + v.name + ")"; c.y += off; S.walk(c.items, i => { i.id = S.uid(); }); c.status = "keep"; A.doc.screens.push(c); }
  A.commit("Show " + v.name); S.canvas.zoomFit();
};

/* ---------- actions: every menu item, toolbar button and shortcut ---------- */
const act = {};
A.actions = act;
const def = (id, label, key, run, o = {}) => { act[id] = Object.assign({ id, label, key, run }, o); };
const hasSel = () => A.sel.length > 0;
def("new", "New design…", "Ctrl+N", () => S.home.open("new"));
def("home", "Home", "", () => S.home.open());
def("open", "Open…", "Ctrl+O", () => A.openFile());
def("save", "Save now", "Ctrl+S", () => A.save(false).then(() => S.toast("Saved", false, 900)));
def("savecopy", "Save a copy…", "Ctrl+Shift+S", () => S.host.saveCopyDialog(A.doc.name, A.docText()));
def("rename", "Rename design…", "", () => A.rename());
def("version", "Save version…", "Ctrl+Alt+S", () => A.saveVersion());
def("exportpng", "Export picture…", "Ctrl+Shift+P", () => S.exporter.exportPictureDialog());
def("send", "Send to Claude…", "Ctrl+Shift+E", () => S.exporter.sendDialog());
def("askclaude", "Ask Claude", "Ctrl+J", () => S.chat.focus());
def("settings", "Settings…", "Ctrl+,", () => S.dlg.settings());
def("undo", "Undo", "Ctrl+Z", () => A.undo());
def("redo", "Redo", "Ctrl+Y", () => A.redo(), { alt: "Ctrl+Shift+Z" });
def("history", "History…", "", () => S.dlg.history());
def("cut", "Cut", "Ctrl+X", () => A.copy(true), { en: hasSel });
def("copy", "Copy", "Ctrl+C", () => A.copy(), { en: hasSel });
def("paste", "Paste", "Ctrl+V", () => S.canvas.pasteFromSystem(false));
def("pastein", "Paste in place", "Ctrl+Shift+V", () => S.canvas.pasteFromSystem(true));
def("dup", "Duplicate", "Ctrl+D", () => A.duplicate(), { en: hasSel });
def("del", "Delete", "Delete", () => A.deleteSel(), { alt: "Backspace" });
def("selall", "Select all", "Ctrl+A", () => A.selectAll());
def("deselect", "Select none", "Escape", () => S.canvas.escape());
def("copystyle", "Copy style", "Ctrl+Alt+C", () => A.copyStyle(), { en: hasSel });
def("pastestyle", "Paste style", "Ctrl+Alt+V", () => A.pasteStyle(), { en: hasSel });
def("find", "Command search…", "Ctrl+K", () => S.dlg.palette(), { alt: "Ctrl+/" });
def("group", "Group", "Ctrl+G", () => A.group(), { en: hasSel });
def("ungroup", "Ungroup", "Ctrl+Shift+G", () => A.ungroup(), { en: hasSel });
def("autolayout", "Wrap in auto layout", "Shift+A", () => A.wrapAuto(), { en: hasSel });
def("front", "Bring to front", "Ctrl+Shift+]", () => A.restack("front"), { en: hasSel });
def("up", "Bring forward", "Ctrl+]", () => A.restack("up"), { en: hasSel });
def("down", "Send backward", "Ctrl+[", () => A.restack("down"), { en: hasSel });
def("back", "Send to back", "Ctrl+Shift+[", () => A.restack("back"), { en: hasSel });
for (const [k, l, key] of [["left", "Align left", "Alt+A"], ["hcenter", "Align centre", "Alt+H"], ["right", "Align right", "Alt+D"], ["top", "Align top", "Alt+W"], ["vcenter", "Align middle", "Alt+V"], ["bottom", "Align bottom", "Alt+S"]])
  def("al-" + k, l, key, () => A.align(k), { en: hasSel });
def("dist-h", "Spread evenly across", "Alt+Shift+H", () => A.distribute("h"), { en: hasSel });
def("dist-v", "Spread evenly down", "Alt+Shift+V", () => A.distribute("v"), { en: hasSel });
def("match-w", "Match width", "", () => A.matchSize("w"), { en: hasSel });
def("match-h", "Match height", "", () => A.matchSize("h"), { en: hasSel });
def("flip-x", "Flip across", "Shift+H", () => A.flip("x"), { en: hasSel });
def("flip-y", "Flip down", "Shift+V", () => A.flip("y"), { en: hasSel });
def("lock", "Lock / unlock", "Ctrl+L", () => A.toggleProp("locked"), { en: hasSel });
def("hide", "Hide / show", "Ctrl+H", () => A.toggleProp("hidden"), { en: hasSel });
def("savepart", "Save as my part", "Ctrl+Alt+K", () => A.saveAsPart(), { en: hasSel });
def("updatepart", "Update my part from this", "", () => A.updatePartFrom(), { en: () => A.selItems()[0]?.partRef });
def("swappart", "Swap part…", "", () => S.dlg.swapPart(), { en: hasSel });
def("note", "Add note for Claude", "", () => S.canvas.addNote(), { en: () => hasSel() || A.selScreen });
for (const st of ["new", "changed", "keep", "remove"]) def("mark-" + st, { new: "New idea", changed: "Changed", keep: "Keep as is", remove: "Remove from app" }[st], "", () => A.setStatus(st));
def("addscreen", "New screen…", "", () => S.dlg.newScreen());
def("dupscreen", "Duplicate screen", "", () => A.duplicateScreen(A.activeScreen));
def("delscreen", "Delete screen", "", () => A.deleteScreen(A.activeScreen));
def("copymacaw", "Copy a MacawP3 screen…", "", () => S.dlg.newScreen("macaw"));
def("openimage", "Open an image to trace…", "", () => S.canvas.traceImage());
def("img", "Image…", "", () => S.canvas.pickImages());
def("iconpick", "Icon…", "", () => S.dlg.iconPicker(n => S.canvas.placeIcon(n)));
for (const t of ["toggle", "checkbox", "input", "placeholder", "progress", "badge", "slider", "cover"]) def("ins-" + t, S.TYPES[t].label, "", () => S.canvas.insertCentered(S.newItem(t)));
def("ins-divider", "Divider", "", () => S.canvas.insertCentered(S.newItem("line", { name: "Divider", w: 300, stroke: { color: "rgba(255,255,255,0.12)", width: 1, style: "solid" } })));
def("ins-tabbar", "Tab bar", "", () => S.canvas.insertCentered(S.BASIC.find(b => b.id === "b-tabbar").make()));
def("ins-search", "Search bar", "", () => S.canvas.insertCentered(S.newItem("input", { name: "Search bar" })));
def("ins-row", "List row", "", () => S.canvas.insertCentered(S.BASIC.find(b => b.id === "b-list").make()));
def("zoomin", "Zoom in", "Ctrl+=", () => S.canvas.zoomBy(1.25), { alt: "Ctrl+Shift+=" });
def("zoomout", "Zoom out", "Ctrl+-", () => S.canvas.zoomBy(0.8));
def("zoomfit", "Zoom to fit all", "Shift+1", () => S.canvas.zoomFit());
def("zoomsel", "Zoom to selection", "Shift+2", () => S.canvas.zoomSel());
def("zoom50", "Zoom 50%", "", () => S.canvas.zoomSet(0.5));
def("zoom100", "Zoom 100%", "Shift+0", () => S.canvas.zoomSet(1));
def("zoom200", "Zoom 200%", "", () => S.canvas.zoomSet(2));
const tog = (k, l, key) => def("t-" + k, l, key, () => { A.settings[k] = !A.settings[k]; A.saveSettings(); A.refresh(); }, { check: () => !!A.settings[k] });
tog("snap", "Snap to things", "Ctrl+Shift+'");
tog("gridSnap", "Snap to grid", "Ctrl+'");
tog("guides", "Smart guides", "");
tog("rulers", "Rulers", "Shift+R");
tog("chrome", "Phone notch and status bar", "");
tog("safe", "Safe areas", "");
tog("showHidden", "Show hidden items", "");
def("panels", "Hide side panels", "Tab", () => { document.body.classList.toggle("nopanels"); S.canvas && S.canvas.overlay(); }, { check: () => document.body.classList.contains("nopanels") });
def("theme", "Light theme", "", () => { A.settings.theme = A.settings.theme === "light" ? "dark" : "light"; A.applySettings(); A.saveSettings(); }, { check: () => A.settings.theme === "light" });
def("preview", "Preview", "Ctrl+Enter", () => S.modes.preview());
def("compare", "Compare with the real app", "", () => S.modes.compare());
def("link", "Add tap link", "K", () => S.canvas.setTool("K"));
def("shortcuts", "Keyboard shortcuts", "?", () => S.dlg.shortcuts());
def("about", "About Macaw Studio", "", () => S.dlg.about());
def("update", "Check for updates", "", () => S.dlg.settings("updates"));
def("guide", "How it works", "F1", () => S.dlg.helpGuide());
/* tools */
S.TOOLS = [["V", "Select", "mouse-pointer-2"], ["H", "Hand", "hand"], "|", ["F", "Frame", "frame"], ["R", "Rectangle", "square"], ["O", "Circle", "circle"], ["L", "Line", "minus"], ["P", "Pen", "pen-tool"], "|",
  ["T", "Text", "type"], ["B", "Button", "rectangle-horizontal"], ["I", "Image", "image"], ["C", "Icon", "star"], ["S", "Slider", "sliders-horizontal"], "|", ["N", "Note for Claude", "sticky-note"], ["K", "Tap link", "spline"], ["M", "Measure", "ruler"], ["D", "Eyedropper", "pipette"]];
for (const t of S.TOOLS) if (t !== "|") def("tool-" + t[0], t[1] + " tool", t[0], () => S.canvas.setTool(t[0]));

A.keyOf = id => (A.settings.shortcuts && A.settings.shortcuts[id]) ?? act[id]?.key ?? "";
A.run = id => { const a = act[id]; if (!a) return; if (a.en && !a.en()) return; a.run(); };

A.MENUS = {
  File: ["home", "new", "open", "-", "save", "savecopy", "rename", "version", "-", "exportpng", "send", "askclaude", "-", "settings"],
  Edit: ["undo", "redo", "history", "-", "cut", "copy", "paste", "pastein", "dup", "del", "-", "selall", "copystyle", "pastestyle", "-", "find"],
  View: ["zoomin", "zoomout", "zoomfit", "zoomsel", "zoom50", "zoom100", "zoom200", "-", "t-rulers", "t-guides", "t-snap", "t-gridSnap", "t-chrome", "t-safe", "t-showHidden", "-", "panels", "theme"],
  Insert: ["addscreen", "copymacaw", "openimage", "-", "img", "iconpick", "ins-slider", "ins-toggle", "ins-checkbox", "ins-input", "ins-search", "ins-tabbar", "ins-row", "ins-progress", "ins-badge", "ins-divider", "ins-placeholder", "ins-cover", "-", "note"],
  Arrange: ["group", "ungroup", "autolayout", "-", "front", "up", "down", "back", "-", "al-left", "al-hcenter", "al-right", "al-top", "al-vcenter", "al-bottom", "dist-h", "dist-v", "match-w", "match-h", "-", "flip-x", "flip-y", "lock", "hide", "-", "savepart", "updatepart", "swappart"],
  Prototype: ["preview", "compare", "link", "-", "dupscreen", "delscreen", "-", "mark-new", "mark-changed", "mark-keep", "mark-remove"],
  Help: ["guide", "shortcuts", "-", "update", "about"]
};

/* keyboard */
A.keyString = e => {
  let k = e.key;
  if (k === " ") k = "Space"; else if (k.length === 1) k = k.toUpperCase();
  if (e.code && /^Digit\d$/.test(e.code) && e.shiftKey) k = e.code.slice(5);
  const byCode = { BracketRight: "]", BracketLeft: "[", Quote: "'", Equal: "=", Minus: "-", Comma: "," }[e.code];
  if (byCode) k = byCode;
  if (k === "+") k = "=";
  if (["Control", "Shift", "Alt", "Meta"].includes(k)) return "";
  return (e.ctrlKey || e.metaKey ? "Ctrl+" : "") + (e.altKey ? "Alt+" : "") + (e.shiftKey && !(k === "?" ) ? "Shift+" : "") + k;
};
A.handleKey = e => {
  const t = e.target, typing = t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
  const ks = A.keyString(e); if (!ks) return;
  if (typing) {
    if (ks === "Escape" && t.isContentEditable) t.blur();
    if (["Ctrl+S", "Ctrl+Shift+E", "Ctrl+Enter"].includes(ks)) { e.preventDefault(); A.run({ "Ctrl+S": "save", "Ctrl+Shift+E": "send", "Ctrl+Enter": "preview" }[ks]); }
    return;
  }
  if (ks === "Escape" && document.querySelector(".pop")) { S.dlg.closePop(); return; }   // Esc closes an open menu first
  if (document.querySelector(".scrim") && ks !== "Escape") return;
  if (/^(Shift\+)?Arrow/.test(ks)) { e.preventDefault(); const n = e.shiftKey ? A.settings.bigNudge : A.settings.nudge; const d = { ArrowLeft: [-n, 0], ArrowRight: [n, 0], ArrowUp: [0, -n], ArrowDown: [0, n] }[e.key]; A.nudge(...d); return; }
  if (ks === "Enter" && A.sel.length === 1) { e.preventDefault(); return S.canvas.enter(); }
  if (ks === "Shift+Enter") { e.preventDefault(); return S.canvas.exitGroup(); }
  for (const id in act) {
    if (A.keyOf(id) === ks || act[id].alt === ks) { e.preventDefault(); A.run(id); return; }
  }
};
