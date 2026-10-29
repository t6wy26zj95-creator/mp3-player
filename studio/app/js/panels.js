/* The side panels. Left: Screens, Layers, Parts, Assets. Right: Design (every setting of what you picked), Notes, Code peek. */
"use strict";
(() => {
const P = S.panels = {};
const $ = id => document.getElementById(id);
const h = S.h;
A.expanded = new Set();
const FONTS = ["Inter", "Segoe UI", "Arial", "Helvetica", "Georgia", "Times New Roman", "Courier New", "Verdana", "Tahoma", "Trebuchet MS", "Impact", "Comic Sans MS", "Consolas", "JetBrains Mono", "SF Pro Display"];
P.localFonts = null;
const allFonts = () => [...new Set(FONTS.concat(P.localFonts || []))];

/* ---------- little form pieces ---------- */
/* a number box; drag its letter left/right to change the value */
const num = (label, value, set, o = {}) => {
  const inp = h("input", { type: "text", value: value === "mixed" ? "Mixed" : (value ?? "") === "" ? "" : S.round(+value, o.dec ?? 1) + (o.unit || "") });
  const commit = v => { let n = parseFloat(String(v).replace(/[^\d.+\-*/() ]/g, "")); if (/[+\-*/]/.test(String(v).slice(1))) { try { n = Function('"use strict";return (' + String(v).replace(/[^\d.+\-*/() ]/g, "") + ")")(); } catch (e) {} } if (isNaN(n)) return; if (o.min != null) n = Math.max(o.min, n); if (o.max != null) n = Math.min(o.max, n); set(n); };
  inp.addEventListener("change", () => commit(inp.value));
  inp.addEventListener("keydown", e => { if (e.key === "Enter") { inp.blur(); } if (e.key === "ArrowUp" || e.key === "ArrowDown") { e.preventDefault(); const d = (e.key === "ArrowUp" ? 1 : -1) * (e.shiftKey ? 10 : o.step || 1); const n = (parseFloat(inp.value) || 0) + d; inp.value = S.round(n, o.dec ?? 1); commit(n); } e.stopPropagation(); });
  const em = h("em", { title: o.title || "Drag to change" }, label);
  em.addEventListener("pointerdown", e => {
    e.preventDefault(); const x0 = e.clientX, v0 = parseFloat(inp.value) || 0; let moved = false;
    const mv = ev => { moved = true; const n = S.round(v0 + (ev.clientX - x0) * (o.step || 1) * (ev.shiftKey ? 10 : 1), o.dec ?? 1); inp.value = n; set(o.min != null ? Math.max(o.min, n) : n, true); };
    const up = () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); if (moved) A.commit("Change " + (o.name || label)); };
    window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
  });
  return h("div", { cls: "fld", title: o.title || "" }, label ? em : null, inp);
};
const seg = (opts, value, set, o = {}) => h("div", { cls: "seg", style: o.style || {} }, opts.map(([v, l, tip]) => h("span", { cls: v === value ? "on" : "", title: tip || "", onclick: () => set(v) }, typeof l === "string" && l.startsWith("i:") ? S.icon(l.slice(2), 14) : l)));
const sel = (opts, value, set, o = {}) => h("div", { cls: "fld", style: o.style || {} }, h("select", { onchange: e => set(e.target.value) }, opts.map(([v, l]) => h("option", { value: v, selected: String(v) === String(value) }, l))));
const tog = (on, set, label) => h("label", { cls: "row", style: { cursor: "pointer", gap: "8px" } }, h("button", { cls: "tog" + (on ? " on" : ""), onclick: e => { e.preventDefault(); set(!on); } }), label || "");
const swatch = (color, set, o = {}) => {
  const sw = h("span", { cls: "sw", title: "Pick a colour" }, h("i", { style: { background: S.resolveColor(A.doc, color) || "transparent" } }));
  sw.onclick = () => S.dlg.colorPicker(sw, color, set, o);
  return sw;
};
const colorField = (color, set, o = {}) => {
  const st = color && typeof color === "object" && color.style && (A.doc.colorStyles || []).find(s => s.id === color.style);
  const raw = S.resolveColor(A.doc, color) || "#000000", p = S.parseColor(raw);
  const hex = h("input", { value: st ? st.name : S.hex(p), title: st ? "Linked to the colour style " + st.name : "", readonly: !!st });
  hex.addEventListener("change", () => { let v = hex.value.trim(); if (/^[0-9a-f]{3,8}$/i.test(v)) v = "#" + v; if (/^#[0-9a-f]{3,8}$/i.test(v) || /^rgba?\(/.test(v)) set(p.a < 1 && v.length === 7 ? S.rgba(v, p.a) : v); });
  hex.addEventListener("keydown", e => { if (e.key === "Enter") hex.blur(); e.stopPropagation(); });
  const op = h("input", { value: Math.round(p.a * 100) + "%", style: { width: "44px", flex: "none", textAlign: "right", paddingRight: "6px" } });
  op.addEventListener("change", () => { const a = S.clamp(parseFloat(op.value) || 0, 0, 100) / 100; set(S.rgba(S.hex(p), a)); });
  op.addEventListener("keydown", e => { if (e.key === "Enter") op.blur(); e.stopPropagation(); });
  return h("div", { cls: "fld" }, swatch(color, set, o), hex, st ? null : op);
};
const section = (title, body, o = {}) => h("div", { cls: "sec" }, h("h4", {}, h("span", {}, title), o.right || (o.hint ? h("i", {}, o.hint) : null)), ...[].concat(body).filter(Boolean));
const row = (...kids) => h("div", { cls: "row" }, ...kids.filter(Boolean));
const lbl = t => h("span", { cls: "lbl" }, t);
const ib = (icon, title, fn, o = {}) => h("button", { cls: "ib" + (o.on ? " on" : ""), title, onclick: fn }, S.icon(icon, 15));

/* ---------- LEFT ---------- */
P.renderLeft = () => {
  const pane = $("left-pane"); if (!A.doc) return;
  document.querySelectorAll("#left-tabs span").forEach(s => s.classList.toggle("on", s.dataset.t === A.leftTab));
  const st = pane.scrollTop; pane.innerHTML = "";
  ({ screens: leftScreens, layers: leftLayers, parts: leftParts, assets: leftAssets })[A.leftTab](pane);
  pane.scrollTop = st;
};

/* a small picture of a screen */
P.thumb = (sc, w, hgt) => {
  const box = h("div", { style: { position: "absolute", inset: "0", overflow: "hidden" } });
  const k = Math.min(w / sc.w, hgt / sc.h);
  const el = S.renderScreen(A.doc, sc, { chrome: false, square: true });
  Object.assign(el.style, { position: "absolute", left: (w - sc.w * k) / 2 + "px", top: (hgt - sc.h * k) / 2 + "px", transform: `scale(${k})`, transformOrigin: "0 0", pointerEvents: "none" });
  box.append(el); return box;
};

function leftScreens(pane) {
  const top = section("Screens", [], { right: h("span", { cls: "add", title: "New screen", onclick: () => S.dlg.newScreen() }, "+ New") });
  pane.append(top);
  const list = h("div", { style: { padding: "4px 6px" } });
  const sections = [...new Set(A.doc.screens.map(s => s.section || ""))];
  let dragId = null;
  for (const secName of sections) {
    if (secName) list.append(h("div", { cls: "section-h" }, secName));
    for (const sc of A.doc.screens.filter(s => (s.section || "") === secName)) {
      const th = h("div", { cls: "scr-thumb" }); th.append(P.thumb(sc, 34, 52));
      const li = h("div", { cls: "li scr-li" + (sc.id === A.activeScreen ? " sel" : ""), draggable: "true" }, th,
        h("div", { cls: "nm" }, h("div", { style: { fontWeight: 600, color: "var(--ink)", overflow: "hidden", textOverflow: "ellipsis" } }, sc.name), h("div", { style: { color: "var(--dim)", fontSize: "11px" } }, `${sc.w} × ${sc.h}${sc.basedOn ? " · MacawP3" : ""}`)),
        h("span", { cls: "tag " + sc.status }, sc.status),
        h("div", { cls: "act" }, h("span", { title: "Duplicate", onclick: e => { e.stopPropagation(); A.duplicateScreen(sc.id); } }, S.icon("copy", 13)), h("span", { title: "Delete", onclick: e => { e.stopPropagation(); A.deleteScreen(sc.id); } }, S.icon("trash-2", 13))));
      li.onclick = () => { A.selectScreen(sc.id); S.canvas.zoomTo(sc); };
      li.ondblclick = () => S.dlg.prompt("Rename screen", "Name", sc.name).then(n => { if (n) { sc.name = n; A.commit("Rename screen"); } });
      li.oncontextmenu = e => { e.preventDefault(); A.selectScreen(sc.id); S.dlg.screenMenu(e.clientX, e.clientY, sc); };
      li.ondragstart = e => { dragId = sc.id; e.dataTransfer.effectAllowed = "move"; };
      li.ondragover = e => { if (!dragId) return; e.preventDefault(); li.classList.add("dragover-before"); };
      li.ondragleave = () => li.classList.remove("dragover-before");
      li.ondrop = e => { e.preventDefault(); li.classList.remove("dragover-before"); if (!dragId || dragId === sc.id) return; const from = A.doc.screens.findIndex(s => s.id === dragId); const [m] = A.doc.screens.splice(from, 1); m.section = sc.section; A.doc.screens.splice(A.doc.screens.indexOf(sc), 0, m); A.commit("Reorder screens"); };
      list.append(li);
    }
  }
  if (!A.doc.screens.length) list.append(h("div", { cls: "empty" }, "No screens yet.", h("br"), h("button", { cls: "pbtn sm", style: { marginTop: "8px" }, onclick: () => S.dlg.newScreen() }, "+ New screen")));
  pane.append(list);
  pane.append(h("div", { style: { padding: "6px 12px" } }, h("button", { cls: "pbtn sm", onclick: lineUp, title: "Put the screens in a row in this order" }, S.icon("columns-3", 13), "Line up screens")));
  /* versions */
  const vs = A.doc.versions || [];
  pane.append(section("Versions", [
    vs.length ? null : h("div", { cls: "hint" }, "Save a version to keep a snapshot you can go back to or compare with."),
    ...vs.slice().reverse().map(v => h("div", { cls: "li", style: { height: "auto", padding: "5px 6px", alignItems: "flex-start", flexDirection: "column", gap: "4px" } },
      h("div", { style: { display: "flex", width: "100%", gap: "6px" } }, S.icon("history", 13), h("b", { style: { fontWeight: 600 } }, v.name), h("span", { style: { marginLeft: "auto", color: "var(--dim)" } }, new Date(v.date).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }))),
      h("div", { style: { display: "flex", gap: "4px" } }, h("button", { cls: "pbtn sm", onclick: () => A.restoreVersion(v) }, "Go back to it"), h("button", { cls: "pbtn sm", onclick: () => A.versionSideBySide(v) }, "Show next to now"), h("button", { cls: "pbtn sm danger", onclick: () => { if (confirm("Delete this version?")) { A.doc.versions = vs.filter(x => x !== v); A.markDirty(); P.renderLeft(); } } }, "Delete"))))
  ], { right: h("span", { cls: "add", onclick: () => A.saveVersion(), title: "Save version (Ctrl+Alt+S)" }, "+ Save") }));
}
function lineUp() { let x = 0; const y = A.doc.screens[0]?.y || 0; for (const s of A.doc.screens) { s.x = x; s.y = y; x += s.w + 120; } A.commit("Line up screens"); S.canvas.zoomFit(); }

/* layers */
const typeIcon = it => it.type === "group" && it.layout ? (it.layout.dir === "col" ? "rows-3" : "columns-3") : (S.TYPES[it.type]?.icon || "square");
function leftLayers(pane) {
  const sc = A.screen();
  if (!sc) { pane.append(h("div", { cls: "empty" }, "No screen yet. Make one in the Screens tab.")); return; }
  const flt = h("input", { placeholder: "Filter: a name, a kind (button), or changed / new / notes", value: A.layerFilter || "", style: { width: "100%", height: "26px", padding: "0 8px" } });
  flt.addEventListener("input", () => { A.layerFilter = flt.value; P.renderLeft(); setTimeout(() => { const f = $("left-pane").querySelector("input"); f.focus(); f.setSelectionRange(f.value.length, f.value.length); }); });
  flt.addEventListener("keydown", e => e.stopPropagation());
  pane.append(h("div", { cls: "sec", style: { paddingBottom: "8px" } }, h("h4", {}, h("span", {}, sc.name), h("i", {}, sc.status)), flt));
  const tree = h("div", { style: { padding: "4px 6px 20px" } });
  const q = (A.layerFilter || "").trim().toLowerCase();
  const match = it => !q || it.name.toLowerCase().includes(q) || it.type.includes(q) || (S.TYPES[it.type]?.label || "").toLowerCase().includes(q) || it.status === q || (q === "notes" && it.note && it.note.text) || (it.text && String(it.text.content).toLowerCase().includes(q));
  const anyMatch = it => match(it) || (it.children || []).some(anyMatch);
  const selAnc = new Set(); for (const id of A.sel) for (const a of S.ancestors(A.doc, id)) selAnc.add(a.id);
  let drag = null;
  const rowFor = (it, depth, list, parent) => {
    if (q && !anyMatch(it)) return;
    const kids = it.children && it.children.length;
    const open = kids && (q || A.expanded.has(it.id) || selAnc.has(it.id));
    const li = h("div", { cls: "li" + (A.sel.includes(it.id) ? " sel" : "") + (it.hidden ? " dim" : ""), style: { paddingLeft: 4 + depth * 14 + "px" }, draggable: "true" },
      h("span", { cls: "tw", onclick: e => { e.stopPropagation(); if (open) { A.expanded.delete(it.id); selAnc.has(it.id) && A.sel.length && (A.sel = [it.id]); } else A.expanded.add(it.id); P.renderLeft(); } }, kids ? S.icon(open ? "chevron-down" : "chevron-right", 11) : ""),
      h("span", { cls: "ic" }, S.icon(typeIcon(it), 13)),
      h("span", { cls: "nm" }, it.name),
      it.note && it.note.text ? h("span", { title: it.note.text, style: { color: "var(--warn)" } }, S.icon("sticky-note", 12)) : null,
      it.status !== "new" || it.part ? h("span", { cls: "tag " + it.status }, it.status) : null,
      h("div", { cls: "act" + (it.hidden || it.locked ? " keep" : "") },
        h("span", { title: it.locked ? "Unlock" : "Lock", onclick: e => { e.stopPropagation(); it.locked = !it.locked; A.commit(it.locked ? "Lock" : "Unlock"); } }, S.icon(it.locked ? "lock" : "lock-open", 12)),
        h("span", { title: it.hidden ? "Show" : "Hide", onclick: e => { e.stopPropagation(); A.touch(it, "hidden"); it.hidden = !it.hidden; A.commit(it.hidden ? "Hide" : "Show"); } }, S.icon(it.hidden ? "eye-off" : "eye", 12))));
    li.onclick = e => {
      const anc = S.ancestors(A.doc, it.id); A.ctx = anc.length ? anc[anc.length - 1].id : null;
      if (e.shiftKey && A.sel.length) { // range select in the same list
        const ids = list.map(x => x.id), a = ids.indexOf(A.sel[A.sel.length - 1]), b = ids.indexOf(it.id);
        if (a >= 0) return A.select(ids.slice(Math.min(a, b), Math.max(a, b) + 1));
      }
      A.select(it.id, e.ctrlKey || e.metaKey); S.canvas.overlay();
    };
    li.ondblclick = e => {
      e.stopPropagation();
      const inp = h("input", { cls: "ren", value: it.name }); li.querySelector(".nm").replaceWith(inp); inp.focus(); inp.select();
      const done = () => { if (inp.value.trim() && inp.value !== it.name) { it.name = inp.value.trim(); it.nameByHand = true; A.commit("Rename"); } else P.renderLeft(); };
      inp.onblur = done; inp.onkeydown = ev => { ev.stopPropagation(); if (ev.key === "Enter") inp.blur(); if (ev.key === "Escape") { inp.value = it.name; inp.blur(); } };
    };
    li.oncontextmenu = e => { e.preventDefault(); if (!A.sel.includes(it.id)) A.select(it.id); S.dlg.contextMenu(e.clientX, e.clientY); };
    li.onmouseenter = () => { A.hover = it.id; S.canvas.overlay(); };
    li.onmouseleave = () => { A.hover = null; S.canvas.overlay(); };
    li.ondragstart = e => { drag = it.id; e.dataTransfer.effectAllowed = "move"; e.dataTransfer.setData("text/plain", it.id); };
    li.ondragover = e => {
      if (!drag || drag === it.id) return; e.preventDefault();
      const r = li.getBoundingClientRect(), y = (e.clientY - r.top) / r.height;
      li.classList.remove("dragover-before", "dragover-after", "dragover-in");
      li.dataset.drop = it.children && y > 0.25 && y < 0.75 ? "in" : y < 0.5 ? "before" : "after";
      li.classList.add("dragover-" + li.dataset.drop);
    };
    li.ondragleave = () => li.classList.remove("dragover-before", "dragover-after", "dragover-in");
    li.ondrop = e => {
      e.preventDefault(); li.classList.remove("dragover-before", "dragover-after", "dragover-in");
      const src = S.findIn(A.doc, drag); if (!src || S.ancestors(A.doc, it.id).some(a => a.id === drag)) return;
      const absOld = S.absPos(A.doc, drag);
      src.list.splice(src.index, 1);
      const tgt = S.findIn(A.doc, it.id);
      let newParent;
      if (li.dataset.drop === "in") { it.children.push(src.item); newParent = it; }   // top of the list = front, so the end of children
      else { const i = tgt.list.indexOf(it); tgt.list.splice(li.dataset.drop === "before" ? i + 1 : i, 0, src.item); newParent = tgt.parent; }
      const pp = newParent ? S.absPos(A.doc, newParent.id) : { x: 0, y: 0 };
      if (tgt.screen !== src.screen || true) { src.item.x = S.round(absOld.x - pp.x, 2); src.item.y = S.round(absOld.y - pp.y, 2); }
      if (src.parent) A.fitGroup(src.parent); A.fitParents(src.item.id);
      A.sel = [src.item.id]; A.commit("Move layer"); drag = null;
    };
    tree.append(li);
    if (open) for (const c of it.children.slice().reverse()) rowFor(c, depth + 1, it.children.slice().reverse(), it);
  };
  const top = sc.items.slice().reverse();
  for (const it of top) rowFor(it, 0, top, null);
  if (!sc.items.length) tree.append(h("div", { cls: "empty" }, "This screen is empty. Pick a tool at the bottom, or drag something in from Parts."));
  if (sc.removed && sc.removed.length) tree.append(h("div", { cls: "section-h" }, "Removed from the app"), ...sc.removed.map((r, i) => h("div", { cls: "li dim" }, h("span", { cls: "ic" }, S.icon("trash-2", 12)), h("span", { cls: "nm" }, r.name), h("span", { cls: "tag remove" }, "remove"), h("div", { cls: "act" }, h("span", { title: "Forget this (Claude won't be told to remove it)", onclick: () => { sc.removed.splice(i, 1); A.commit("Forget removal"); } }, S.icon("x", 12))))));
  pane.append(tree);
}

/* parts */
A.partsTab = "macaw";
P.partItem = def => { const it = def.make(); A.stampOrig([it]); return it; };
P.dropPart = (data, sc, w) => {
  const [kind, id] = data.split(":");
  if (kind === "scr") { const d = S.PARTS.find(p => p.id === id); const s = d.screen(); s.x = Math.round(w.x); s.y = Math.round(w.y); A.stampOrig(s.items); A.doc.screens.push(s); A.activeScreen = s.id; A.commit("Add " + s.name); return; }
  if (!sc) return S.toast("Drop it on a phone screen");
  const it = makePart(kind, id); if (!it) return;
  it.x = S.round(w.x - sc.x - it.w / 2); it.y = S.round(w.y - sc.y - it.h / 2); it.name = A.uniqueName(it.name, sc);
  A.addItem(it, sc);
};
const makePart = (kind, id) => {
  if (kind === "mp") { const d = S.PARTS.find(p => p.id === id); return d && P.partItem(d); }
  if (kind === "basic") { const d = S.BASIC.find(p => p.id === id); return d && d.make(); }
  if (kind === "mine") { const d = (A.settings.myParts || []).find(p => p.id === id); if (!d) return null; const it = S.clone(d.item); S.walk([it], i => { i.id = S.uid(); }); it.partRef = d.id; it.status = "new"; return it; }
};
P.makePart = makePart;
function leftParts(pane) {
  const q = h("input", { placeholder: "Search parts…", value: A.partQ || "", style: { width: "100%", height: "26px", padding: "0 8px" } });
  q.addEventListener("input", () => { A.partQ = q.value; P.renderLeft(); const f = $("left-pane").querySelector("input"); f.focus(); f.setSelectionRange(f.value.length, f.value.length); });
  q.addEventListener("keydown", e => e.stopPropagation());
  pane.append(h("div", { cls: "sec" }, q, h("div", { style: { margin: "8px 0 6px", display: "flex" } }, seg([["macaw", "MacawP3"], ["basic", "Basic"], ["mine", "Mine"]], A.partsTab, v => { A.partsTab = v; P.renderLeft(); })),
    h("div", { cls: "hint" }, A.partsTab === "macaw" ? "Built from the real player's sizes and colours. Click to add, or drag onto a screen. Whole screens add a new phone." : A.partsTab === "basic" ? "Plain pieces for new ideas." : "Your own parts. Select something and press Ctrl+Alt+K to save it here.")));
  const qq = (A.partQ || "").toLowerCase();
  const card = (name, kind, id, isScreen, make) => {
    const c = h("div", { cls: "pcard" + (isScreen ? " scr" : ""), draggable: "true", title: name });
    const th = h("div", { cls: "th" });
    try {
      if (isScreen) th.append(P.thumb(make(), 110, 120));
      else { const it = make(); it.x = 0; it.y = 0; const k = Math.min(1, 100 / it.w, 64 / Math.max(it.h, 1)); const el = S.renderItem(A.doc, it); el.style.position = "relative"; el.style.left = "0"; el.style.top = "0"; const wrap = h("div", { style: { width: it.w * k + "px", height: Math.max(it.h, 1) * k + "px", position: "relative" } }); el.style.transform = `scale(${k})`; el.style.transformOrigin = "0 0"; wrap.append(el); th.append(wrap); }
    } catch (e) { th.textContent = "?"; }
    c.append(th, h("div", { cls: "nm" }, name));
    c.onclick = () => { if (isScreen) { const s = make(); A.addScreen(s, "Add " + s.name); } else { const it = makePart(kind, id); S.canvas.insertCentered(it); } };
    c.ondragstart = e => { e.dataTransfer.setData("application/x-macaw-part", (isScreen ? "scr" : kind) + ":" + id); e.dataTransfer.effectAllowed = "copy"; };
    if (kind === "mine") c.oncontextmenu = e => { e.preventDefault(); S.dlg.menuAt(e.clientX, e.clientY, [["Update every copy in this design", () => A.syncPartCopies(id)], ["Rename", async () => { const p = A.settings.myParts.find(x => x.id === id); const n = await S.dlg.prompt("Rename part", "Name", p.name); if (n) { p.name = n; A.saveSettings(); P.renderLeft(); } }], ["Delete", () => { if (confirm("Delete this part? Copies already on screens stay.")) { A.settings.myParts = A.settings.myParts.filter(x => x.id !== id); A.saveSettings(); P.renderLeft(); } }]]); };
    return c;
  };
  if (A.partsTab === "macaw") {
    const groups = [...new Set(S.PARTS.map(p => p.group))];
    for (const g of groups) {
      const ps = S.PARTS.filter(p => p.group === g && (!qq || p.name.toLowerCase().includes(qq))); if (!ps.length) continue;
      pane.append(h("div", { cls: "section-h", style: { padding: "10px 12px 0" } }, g));
      const grid = h("div", { cls: "pgrid" }); ps.forEach(p => grid.append(card(p.name, "mp", p.id, !!p.screen, p.screen || p.make))); pane.append(grid);
    }
  } else if (A.partsTab === "basic") {
    const grid = h("div", { cls: "pgrid" }); S.BASIC.filter(p => !qq || p.name.toLowerCase().includes(qq)).forEach(p => grid.append(card(p.name, "basic", p.id, false, p.make))); pane.append(grid);
  } else {
    const mine = (A.settings.myParts || []).filter(p => !qq || p.name.toLowerCase().includes(qq));
    if (!mine.length) pane.append(h("div", { cls: "empty" }, "Nothing here yet.", h("br"), "Select something on a screen, then Arrange > Save as my part."));
    const grid = h("div", { cls: "pgrid" }); mine.forEach(p => grid.append(card(p.name, "mine", p.id, false, () => S.clone(p.item)))); pane.append(grid);
  }
}

/* assets */
function leftAssets(pane) {
  const assets = A.doc.assets || [];
  pane.append(section("Images", [
    h("div", { cls: "row" }, h("button", { cls: "pbtn sm", onclick: () => S.canvas.pickImages() }, S.icon("upload", 13), "Add image"), h("span", { cls: "hint" }, "or paste (Ctrl+V), or drag from Explorer")),
    assets.length ? h("div", { style: { display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "6px" } }, assets.map(a => {
      const t = h("div", { title: a.name + " · click to add", style: { height: "70px", borderRadius: "6px", background: `var(--panel2) url("${a.src}") center/cover`, cursor: "pointer", border: "1px solid var(--line)" } });
      t.onclick = () => { const sc = A.screen(); if (!sc) return; const it = S.canvas.imageItem(a, sc); A.addItem(it, sc); };
      t.oncontextmenu = e => { e.preventDefault(); S.dlg.menuAt(e.clientX, e.clientY, [["Remove from Assets", () => { A.doc.assets = assets.filter(x => x !== a); A.markDirty(); P.renderLeft(); }]]); };
      return t;
    })) : null
  ]));
  const used = new Set(); for (const sc of A.doc.screens) S.walk(sc.items, it => { if (it.icon && it.icon.name) used.add(it.icon.name); });
  pane.append(section("Icons", [
    h("div", { cls: "row" }, h("button", { cls: "pbtn sm", onclick: () => S.dlg.iconPicker(n => S.canvas.placeIcon(n)) }, S.icon("search", 13), "Browse " + Object.keys(window.ICONS || {}).length + " icons")),
    used.size ? h("div", { cls: "icgrid" }, [...used].map(n => h("span", { title: n, onclick: () => S.canvas.placeIcon(n), html: S.iconSVG(n, 20, "currentColor") }))) : h("div", { cls: "hint" }, "Icons you use show up here.")
  ]));
  pane.append(section("Colour styles", [
    h("div", { cls: "hint", style: { marginBottom: "6px" } }, "Click to colour what's selected. Change a style and everything using it changes."),
    ...(A.doc.colorStyles || []).map(cs => {
      const r = h("div", { cls: "li" }, swatch(cs.color, c => { cs.color = c; A.commit("~Colour style"); }), h("span", { cls: "nm" }, cs.name), h("span", { style: { color: "var(--dim)", fontSize: "11px" } }, S.hexA(cs.color)));
      r.onclick = e => { if (e.target.closest(".sw")) return; const its = A.selItems(); if (!its.length) return S.toast("Select something to colour"); for (const it of its) { if (it.type === "text") A.setProp(it, "text.color", { style: cs.id }, false); else if (it.type === "icon") A.setProp(it, "icon.color", { style: cs.id }, false); else A.setProp(it, "fills", [{ kind: "solid", color: { style: cs.id } }], false); } A.commit("Use colour style"); };
      r.ondblclick = () => S.dlg.prompt("Rename colour", "Name", cs.name).then(n => { if (n) { cs.name = n; A.commit("Rename colour style"); } });
      r.oncontextmenu = e => { e.preventDefault(); S.dlg.menuAt(e.clientX, e.clientY, [["Rename", () => r.ondblclick()], ["Delete", () => { A.doc.colorStyles = A.doc.colorStyles.filter(x => x !== cs); for (const sc of A.doc.screens) S.walk(sc.items, it => { const fix = o => { if (o && typeof o === "object") for (const k in o) { if (o[k] && typeof o[k] === "object" && o[k].style === cs.id) o[k] = cs.color; else fix(o[k]); } }; fix(it); }); A.commit("Delete colour style"); }]]); };
      return r;
    }),
    h("button", { cls: "pbtn sm", style: { marginTop: "6px" }, onclick: async () => { const it = A.selItems()[0]; const c = it ? (it.type === "text" ? it.text.color : it.fills && it.fills[0] ? it.fills[0].color : "#2BB3C0") : "#2BB3C0"; const n = await S.dlg.prompt("New colour style", "Name", "My colour"); if (n) { A.doc.colorStyles.push({ id: S.uid("c"), name: n, color: S.resolveColor(A.doc, c) }); A.commit("Add colour style"); } } }, "+ Colour style")
  ]));
  pane.append(section("Text styles", [
    ...(A.doc.textStyles || []).map(ts => {
      const r = h("div", { cls: "li", title: "Click to use it on the selected text" }, h("span", { cls: "nm", style: { fontFamily: ts.font, fontWeight: ts.weight } }, ts.name), h("span", { style: { color: "var(--dim)", fontSize: "11px" } }, `${ts.size} · ${ts.weight}`));
      r.onclick = () => { const its = A.selItems().filter(i => i.text); if (!its.length) return S.toast("Select some text"); for (const it of its) A.setProp(it, "text.style", ts.id, false); A.commit("Use text style"); };
      r.oncontextmenu = e => { e.preventDefault(); S.dlg.menuAt(e.clientX, e.clientY, [["Edit…", () => S.dlg.textStyle(ts)], ["Delete", () => { A.doc.textStyles = A.doc.textStyles.filter(x => x !== ts); for (const sc of A.doc.screens) S.walk(sc.items, it => { if (it.text && it.text.style === ts.id) { Object.assign(it.text, { font: ts.font, size: ts.size, weight: ts.weight, lh: ts.lh, ls: ts.ls }); delete it.text.style; } }); A.commit("Delete text style"); }]]); };
      r.ondblclick = () => S.dlg.textStyle(ts);
      return r;
    }),
    h("button", { cls: "pbtn sm", style: { marginTop: "6px" }, onclick: () => { const it = A.selItems().find(i => i.text); const t = it ? it.text : { font: "Inter", size: 15, weight: 400, lh: 0, ls: 0 }; const ts = { id: S.uid("t"), name: "New style", font: t.font, size: t.size, weight: t.weight, lh: t.lh || 0, ls: t.ls || 0 }; A.doc.textStyles.push(ts); A.commit("Add text style"); S.dlg.textStyle(ts); } }, "+ Text style (from selection)")
  ]));
  const usedFonts = new Set(); for (const sc of A.doc.screens) S.walk(sc.items, it => { if (it.text) usedFonts.add(it.text.font || "Inter"); });
  pane.append(section("Fonts", [
    h("div", {}, [...usedFonts].map(f => h("div", { cls: "li" }, h("span", { cls: "nm", style: { fontFamily: f } }, f), f === "Inter" ? h("span", { cls: "hint" }, "the app's font") : null))),
    h("div", { cls: "hint", style: { marginTop: "6px" } }, P.localFonts ? `${P.localFonts.length} fonts on this PC are available in the Text settings.` : "Fonts installed on your PC show up in the Text settings."),
    !P.localFonts && window.queryLocalFonts ? h("button", { cls: "pbtn sm", style: { marginTop: "6px" }, onclick: P.loadFonts }, "Load my PC's fonts") : null
  ]));
}
P.loadFonts = async () => { try { const fs = await window.queryLocalFonts(); P.localFonts = [...new Set(fs.map(f => f.family))].sort(); A.settings.fontsLoaded = true; A.saveSettings(); P.renderLeft(); P.renderRight(); } catch (e) { S.toast("Windows didn't share the font list"); } };

/* ---------- RIGHT ---------- */
P.renderRight = () => {
  const pane = $("right-pane"); if (!A.doc) return;
  if (pane.contains(document.activeElement) && document.activeElement.tagName === "TEXTAREA") return;   // don't wipe a note while it's being typed
  document.querySelectorAll("#right-tabs span").forEach(s => s.classList.toggle("on", s.dataset.t === A.rightTab));
  const nn = S.canvas.noteOrder().length; $("right-tabs").children[1].textContent = "Notes" + (nn || A.doc.links.length ? ` (${nn + A.doc.links.length})` : "");
  const st = pane.scrollTop; pane.innerHTML = "";
  ({ design: rightDesign, notes: rightNotes, code: rightCode })[A.rightTab](pane);
  pane.scrollTop = st;
};

function rightDesign(pane) {
  const its = A.selItems();
  if (!its.length) return screenProps(pane);
  if (its.length > 1) return multiProps(pane, its);
  itemProps(pane, its[0]);
}
const alignRow = () => row(
  ib("align-start-vertical", "Align left (Alt+A)", () => A.run("al-left")), ib("align-center-vertical", "Align centre (Alt+H)", () => A.run("al-hcenter")), ib("align-end-vertical", "Align right (Alt+D)", () => A.run("al-right")),
  ib("align-start-horizontal", "Align top (Alt+W)", () => A.run("al-top")), ib("align-center-horizontal", "Align middle (Alt+V)", () => A.run("al-vcenter")), ib("align-end-horizontal", "Align bottom (Alt+S)", () => A.run("al-bottom")),
  ib("align-horizontal-space-around", "Spread evenly across", () => A.run("dist-h")), ib("align-vertical-space-around", "Spread evenly down", () => A.run("dist-v")));

function screenProps(pane) {
  const sc = A.screen();
  if (!sc) { pane.append(h("div", { cls: "empty" }, "Nothing here yet.", h("br"), h("button", { cls: "pbtn", style: { marginTop: "10px" }, onclick: () => S.dlg.newScreen() }, "+ New screen"))); return; }
  const set = (k, v, lab) => { sc[k] = v; A.commit(lab || "~Screen " + k); };
  const nm = h("input", { value: sc.name, style: { flex: 1, height: "26px", padding: "0 7px" } });
  nm.onchange = () => set("name", nm.value || "Screen", "Rename screen"); nm.onkeydown = e => { e.stopPropagation(); if (e.key === "Enter") nm.blur(); };
  pane.append(section("Screen", [
    row(nm),
    row(sel(Object.entries(S.DEVICES).map(([k, d]) => [k, d.name]), sc.device, v => { const d = S.DEVICES[v]; sc.device = v; if (v !== "custom") { sc.w = d.w; sc.h = d.h; } A.commit("Change device"); })),
    row(num("W", sc.w, (v, l) => { sc.w = Math.round(v); sc.device = sc.device === "custom" || S.DEVICES[sc.device].w === sc.w ? sc.device : "custom"; l ? S.canvas.render() : A.commit("Screen size"); }, { min: 50, dec: 0 }), num("H", sc.h, (v, l) => { sc.h = Math.round(v); l ? S.canvas.render() : A.commit("Screen size"); }, { min: 50, dec: 0 })),
    row(num("X", sc.x, (v, l) => { sc.x = v; l ? S.canvas.render() : A.commit("Move screen"); }, { dec: 0 }), num("Y", sc.y, (v, l) => { sc.y = v; l ? S.canvas.render() : A.commit("Move screen"); }, { dec: 0 })),
    sc.basedOn ? h("div", { cls: "hint" }, "Copied from the real MacawP3 " + sc.basedOn + " screen.") : null
  ]));
  pane.append(section("Background", [
    row(seg([["macaw", "MacawP3"], ["color", "Colour"], ["image", "Image"]], sc.bg.kind, v => { sc.bg.kind = v; A.commit("Background"); })),
    sc.bg.kind === "macaw" ? row(seg([["dark", "Dark wallpaper"], ["light", "Light wallpaper"]], sc.tone, v => set("tone", v, "Wallpaper tone"))) : null,
    sc.bg.kind === "color" ? row(colorField(sc.bg.color, c => { sc.bg.color = c; A.commit("~Background"); })) : null,
    sc.bg.kind === "image" ? row(h("button", { cls: "pbtn sm", onclick: () => { const inp = $("file-img"); inp.value = ""; inp.onchange = () => { const f = inp.files[0]; if (!f) return; const r = new FileReader(); r.onload = () => { sc.bg.image = r.result; A.commit("Wallpaper image"); }; r.readAsDataURL(f); }; inp.click(); } }, "Choose wallpaper…")) : null,
    tog(sc.chrome !== false, v => set("chrome", v, "Phone chrome"), "Show notch, status bar and home bar")
  ]));
  pane.append(section("Layout grid", [
    tog(sc.grid.on, v => { sc.grid.on = v; A.commit("Layout grid"); }, "Show columns"),
    sc.grid.on ? row(num("Cols", sc.grid.cols, v => { sc.grid.cols = Math.max(1, Math.round(v)); A.commit("~Grid"); }, { dec: 0, min: 1 }), num("Gap", sc.grid.gap, v => { sc.grid.gap = v; A.commit("~Grid"); }, { dec: 0, min: 0 }), num("Edge", sc.grid.margin, v => { sc.grid.margin = v; A.commit("~Grid"); }, { dec: 0, min: 0 })) : null
  ]));
  const note = h("textarea", { rows: 3, placeholder: "Anything Claude should know about this whole screen" }); note.value = sc.note || "";
  note.onchange = () => set("note", note.value.trim(), "Screen note"); note.onkeydown = e => e.stopPropagation();
  const secIn = h("input", { value: sc.section || "", placeholder: "e.g. Player ideas", style: { flex: 1, height: "26px", padding: "0 7px" } });
  secIn.onchange = () => set("section", secIn.value.trim(), "Section"); secIn.onkeydown = e => e.stopPropagation();
  pane.append(section("Status for Claude", [
    row(seg([["new", "New"], ["changed", "Changed"], ["keep", "Keep"], ["remove", "Remove"]], sc.status, v => { sc.statusByHand = true; set("status", v, "Screen status"); })),
    note, row(lbl("Section"), secIn)
  ]));
  pane.append(section("Design", [h("div", { cls: "hint" }, `${A.doc.screens.length} screens · ${A.doc.links.length} tap links · ${S.canvas.noteOrder().length} notes. Colours, text styles and images are in the Assets tab.`)]));
}

function multiProps(pane, its) {
  pane.append(section(`${its.length} selected`, [alignRow(),
    row(h("button", { cls: "pbtn sm", onclick: () => A.run("group") }, "Group"), h("button", { cls: "pbtn sm", onclick: () => A.run("autolayout") }, "Auto layout"), h("button", { cls: "pbtn sm", onclick: () => A.run("match-w") }, "Same width"), h("button", { cls: "pbtn sm", onclick: () => A.run("match-h") }, "Same height"))]));
  const same = k => its.every(i => JSON.stringify(i[k]) === JSON.stringify(its[0][k])) ? its[0][k] : "mixed";
  pane.append(section("Layer", [row(num("Opacity", same("opacity") === "mixed" ? "mixed" : Math.round((its[0].opacity ?? 1) * 100), (v, l) => { its.forEach(i => { A.touch(i, "opacity"); i.opacity = S.clamp(v, 0, 100) / 100; }); l ? S.canvas.render() : A.commit("Opacity"); }, { unit: "%", dec: 0, min: 0, max: 100 }))]));
  const shapes = its.filter(i => !["text", "icon", "line", "group"].includes(i.type));
  if (shapes.length) pane.append(section("Fill (all)", [row(colorField(shapes[0].fills?.[0]?.color || "#2BB3C0", c => { shapes.forEach(i => A.setProp(i, "fills", [{ kind: "solid", color: c }], false)); A.commit("~Fill"); }))]));
  const texts = its.filter(i => i.text);
  if (texts.length) pane.append(section("Text (all)", [row(colorField(texts[0].text.color, c => { texts.forEach(i => A.setProp(i, "text.color", c, false)); A.commit("~Text colour"); })), row(num("Size", texts[0].text.size, v => { texts.forEach(i => A.setProp(i, "text.size", v, false)); A.commit("~Text size"); }, { min: 1 }), sel(allFonts().map(f => [f, f]), texts[0].text.font, v => { texts.forEach(i => A.setProp(i, "text.font", v, false)); A.commit("Font"); }))]));
  statusSection(pane, its);
}

function statusSection(pane, its) {
  const it = its[0], st = its.every(i => i.status === it.status) ? it.status : "";
  const parts = [row(seg([["new", "New"], ["changed", "Changed"], ["keep", "Keep"], ["remove", "Remove"]], st, v => { its.forEach(i => i.status = v); A.commit("Status " + v); }))];
  if (its.length === 1) {
    const ta = h("textarea", { rows: 3, placeholder: "Note for Claude, e.g. make it glow when a song is playing" }); ta.value = it.note?.text || "";
    ta.onchange = () => { const v = ta.value.trim(); if (v) it.note = Object.assign(it.note || {}, { text: v }); else delete it.note; A.commit("Note"); };
    ta.onkeydown = e => e.stopPropagation();
    parts.push(ta);
    if (it.changedFrom && Object.keys(it.changedFrom).length) parts.push(h("div", { cls: "hint", style: { marginTop: "6px" } }, "Changed from the app: " + Object.keys(it.changedFrom).map(k => ({ x: "position", y: "position", w: "size", h: "size", fills: "fill", text: "text", effects: "effects", radius: "corners", stroke: "border", rot: "rotation", hidden: "visibility" }[k] || k)).filter((v, i, a) => a.indexOf(v) === i).join(", ") + ". ",
      h("a", { href: "#", style: { color: "var(--acc)" }, onclick: e => { e.preventDefault(); for (const [k, v] of Object.entries(it.changedFrom)) it[k] = S.clone(v); it.changedFrom = {}; it.status = "keep"; A.commit("Put back as it was"); } }, "Put it back")));
  }
  pane.append(section("Status for Claude", parts, { hint: "what Claude should do" }));
}

function itemProps(pane, it) {
  const v = S.view(it);
  const set = (path, val, live) => { A.setProp(it, path, val, false); if (live) S.canvas.render(); else A.commit("~" + path); };
  const T = S.TYPES[it.type] || { label: it.type };
  /* header */
  const nm = h("input", { value: it.name, style: { flex: 1, height: "26px", padding: "0 7px", fontWeight: 600 } });
  nm.onchange = () => { it.name = nm.value.trim() || it.name; it.nameByHand = true; A.commit("Rename"); }; nm.onkeydown = e => { e.stopPropagation(); if (e.key === "Enter") nm.blur(); };
  const partLabel = it.part ? (it.part.startsWith("macawp3:") ? "MacawP3 part · " + it.part.slice(8) : it.part.startsWith("new:") ? "new part" : it.part) : it.partRef ? "My part" : "";
  pane.append(section(T.label, [row(nm), partLabel ? h("div", { cls: "hint" }, partLabel) : null, alignRow()], { right: h("i", {}, it.locked ? "locked" : "") }));
  /* states */
  if (["button", "icon", "cover", "toggle", "checkbox", "slider", "rect", "ellipse", "frame", "text", "image"].includes(it.type)) {
    const has = s => it.states && it.states[s];
    pane.append(section("Looks when", [row(seg(S.STATES.map(s => [s, (s[0].toUpperCase() + s.slice(1)) + (has(s) ? " •" : ""), s === "normal" ? "How it normally looks" : "Edits now only change how it looks when " + s]), it.viewState || "normal", s => { it.viewState = s; A.refresh(); }, { style: { fontSize: "11px" } })),
      it.viewState && it.viewState !== "normal" ? h("div", { cls: "hint" }, `Editing the "${it.viewState}" look. Changes below only apply ${it.viewState === "pressed" ? "while it's pressed" : it.viewState === "disabled" ? "when it can't be used" : "while a song is " + it.viewState}. `, has(it.viewState) ? h("a", { href: "#", style: { color: "var(--acc)" }, onclick: e => { e.preventDefault(); delete it.states[it.viewState]; A.commit("Clear state"); } }, "Clear this look") : null) : null]));
  }
  /* position and size */
  const ratio = it.keepRatio;
  pane.append(section("Position and size", [
    row(num("X", it.x, (val, l) => { A.touch(it, "x"); it.x = val; l ? S.canvas.render() : (A.fitParents(it.id), A.commit("~x")); }), num("Y", it.y, (val, l) => { A.touch(it, "y"); it.y = val; l ? S.canvas.render() : (A.fitParents(it.id), A.commit("~y")); })),
    row(num("W", v.w, (val, l) => { const k = val / it.w; A.setProp(it, "w", Math.max(0, val), false); if (ratio) A.setProp(it, "h", S.round(it.h * k, 2), false); if (it.type === "text") it.text.sizing = "fixed"; l ? S.canvas.render() : A.commit("~w"); }, { min: 0 }),
      num("H", v.h, (val, l) => { const k = val / it.h; A.setProp(it, "h", Math.max(0, val), false); if (ratio) A.setProp(it, "w", S.round(it.w * k, 2), false); l ? S.canvas.render() : A.commit("~h"); }, { min: 0 }),
      ib(ratio ? "link" : "unlink", "Keep width and height in proportion", () => { it.keepRatio = !it.keepRatio; A.commit("Ratio"); }, { on: ratio })),
    row(num("°", it.rot || 0, (val, l) => { A.touch(it, "rot"); it.rot = val; l ? S.canvas.render() : A.commit("~rot"); }, { title: "Rotation" }),
      !["line", "path", "text", "icon", "group", "ellipse", "toggle"].includes(it.type) ? num("◜", Array.isArray(v.radius) ? "mixed" : v.radius, (val, l) => set("radius", Math.max(0, val), l), { title: "Corner rounding", min: 0 }) : h("div", { style: { flex: 1 } })),
    !["line", "path", "text", "icon", "group", "ellipse", "toggle"].includes(it.type) ? row(h("span", { cls: "hint", style: { flex: 1 } }, "Each corner:"), ...[0, 1, 2, 3].map(i => num("", Array.isArray(v.radius) ? v.radius[i] : v.radius, val => { const r = Array.isArray(it.radius) ? it.radius.slice() : [it.radius, it.radius, it.radius, it.radius].map(x => +x || 0); r[i] = Math.max(0, val); set("radius", r); }, { title: ["Top left", "Top right", "Bottom right", "Bottom left"][i] }))) : null,
    it.type === "text" ? row(lbl("Width"), seg([["hug", "Fit the words"], ["fixed", "Fixed, wraps"]], it.text.sizing || "fixed", s => { set("text.sizing", s); if (s === "hug") { const el = document.querySelector(`[data-id="${it.id}"] .tx`); if (el) { it.w = Math.ceil(el.scrollWidth) + 1; it.h = Math.ceil(el.scrollHeight); } A.commit("Text width"); } })) : null,
    (() => { const f = S.findIn(A.doc, it.id); return f && f.parent && f.parent.layout ? row(tog(!!it.fillCross, val => { it.fillCross = val; A.commit("Fill the row"); }, "Stretch across the auto layout"), tog(!!it.absolute, val => { it.absolute = val; A.commit("Ignore auto layout"); }, "Ignore auto layout")) : null; })()
  ]));
  /* pin */
  const pin = it.pin || { h: "left", v: "top" };
  pane.append(section("Pin to", [
    row(seg([["left", "Left"], ["center", "Centre"], ["right", "Right"], ["stretch", "Stretch"]], pin.h, val => { it.pin = Object.assign({}, pin, { h: val }); A.commit("Pin"); })),
    row(seg([["top", "Top"], ["center", "Centre"], ["bottom", "Bottom"], ["stretch", "Stretch"]], pin.v, val => { it.pin = Object.assign({}, pin, { v: val }); A.commit("Pin"); }))
  ], { hint: "on a bigger or smaller phone" }));
  /* auto layout */
  if (it.type === "frame" || it.type === "group") {
    const L = it.layout;
    pane.append(section("Auto layout", L ? [
      row(seg([["row", "i:arrow-right", "In a row"], ["col", "i:arrow-down", "In a column"]], L.dir, val => { L.dir = val; A.touch(it, "layout"); A.commit("Auto layout"); }), num("Gap", L.gap, (val, l) => { L.gap = val; A.touch(it, "layout"); l ? S.canvas.render() : A.commit("~gap"); }, { min: 0 }), num("Pad", L.pad, (val, l) => { L.pad = val; A.touch(it, "layout"); l ? S.canvas.render() : A.commit("~pad"); }, { min: 0 })),
      row(lbl("Line up"), seg([["start", L.dir === "row" ? "Top" : "Left"], ["center", "Middle"], ["end", L.dir === "row" ? "Bottom" : "Right"]], L.align, val => { L.align = val; A.touch(it, "layout"); A.commit("Auto layout"); })),
      row(lbl("Spread"), seg([["start", "Start"], ["center", "Centre"], ["end", "End"], ["between", "Even"]], L.justify || "start", val => { L.justify = val; A.touch(it, "layout"); A.commit("Auto layout"); })),
      tog(!!L.hug, val => { L.hug = val; A.touch(it, "layout"); A.commit("Hug"); }, "Shrink to fit the contents"),
      row(h("button", { cls: "pbtn sm", onclick: () => { A.touch(it, "layout"); delete it.layout; A.commit("Remove auto layout"); } }, "Remove auto layout"))
    ] : [h("div", { cls: "hint" }, "Lines the things inside up in a row or column, with even gaps. Add one and the others make room."), row(h("button", { cls: "pbtn sm", onclick: () => A.run("autolayout") }, "+ Add auto layout (Shift+A)"))], { hint: "" }));
    if (it.type === "frame") pane.append(section("Frame", [tog(it.clip !== false, val => { it.clip = val; A.commit("Clip"); }, "Hide what sticks out")]));
  }
  /* fill */
  if (!["group", "line", "icon", "slider", "progress", "toggle", "checkbox"].includes(it.type)) fillSection(pane, it, v);
  /* border */
  if (!["group", "icon", "slider", "progress", "toggle", "checkbox"].includes(it.type)) strokeSection(pane, it, v);
  /* effects */
  if (it.type !== "line") effectsSection(pane, it, v);
  /* text */
  if (it.text) textSection(pane, it, v);
  /* icon */
  if (it.icon) {
    const I = v.icon;
    const nameBtn = h("button", { cls: "pbtn sm", style: { flex: 1, justifyContent: "flex-start" }, onclick: () => S.dlg.iconPicker(n => set("icon.name", n), I.name) }, I.name ? h("span", { html: S.iconSVG(I.name, 14, "currentColor") }) : null, I.name || "Pick an icon…");
    pane.append(section("Icon", [
      row(nameBtn, I.name && it.type !== "icon" ? ib("x", "No icon", () => set("icon.name", "")) : null),
      row(colorField(I.color, c => set("icon.color", c))),
      row(it.type !== "icon" ? num("Size", I.size, (val, l) => set("icon.size", val, l), { min: 4 }) : null, num("Line", I.stroke || 2, (val, l) => set("icon.stroke", val, l), { min: 0.5, step: 0.25, dec: 2, title: "Line thickness" })),
      tog(!!I.filled, val => set("icon.filled", val), "Filled in"),
      it.type !== "icon" ? row(lbl("Where"), seg([["left", "Left"], ["right", "Right"], ["only", "Icon only"]], I.pos || "left", val => set("icon.pos", val))) : null
    ]));
  }
  /* sliders, toggles */
  if (it.slider) pane.append(section(it.type === "progress" ? "Progress" : "Slider", [
    row(num("Value", Math.round(v.slider.value * 100), (val, l) => set("slider.value", S.clamp(val, 0, 100) / 100, l), { unit: "%", dec: 0, min: 0, max: 100 }), num("Thick", v.slider.thickness, (val, l) => set("slider.thickness", val, l), { min: 1 })),
    it.type === "slider" ? row(num("Knob", v.slider.knobSize ?? 14, (val, l) => set("slider.knobSize", Math.max(0, val), l), { min: 0, title: "Knob size (0 = no knob)" })) : null,
    row(lbl("Track"), colorField(v.slider.track, c => set("slider.track", c))), row(lbl("Filled"), colorField(v.slider.fill, c => set("slider.fill", c))),
    it.type === "slider" ? row(lbl("Knob"), colorField(v.slider.knob, c => set("slider.knob", c))) : null
  ]));
  if (it.toggle) pane.append(section(it.type === "checkbox" ? "Checkbox" : "Toggle", [
    tog(v.toggle.on, val => set("toggle.on", val), "On"), row(lbl("On colour"), colorField(v.toggle.onColor, c => set("toggle.onColor", c))), row(lbl("Off colour"), colorField(v.toggle.offColor, c => set("toggle.offColor", c))), row(lbl(it.type === "checkbox" ? "Tick" : "Knob"), colorField(v.toggle.knob, c => set("toggle.knob", c)))
  ]));
  if (it.type === "image") pane.append(section("Image", [
    row(h("button", { cls: "pbtn sm", onclick: () => { const inp = $("file-img"); inp.value = ""; inp.onchange = () => { const f = inp.files[0]; if (!f) return; const r = new FileReader(); r.onload = () => { set("image.src", r.result); A.assetAdd({ name: f.name, src: r.result, w: 0, h: 0 }); }; r.readAsDataURL(f); }; inp.click(); } }, "Replace image…")),
    row(lbl("Fit"), seg([["cover", "Fill"], ["contain", "Fit"], ["fill", "Stretch"]], it.image.fit || "cover", val => set("image.fit", val))),
    it.reference ? h("div", { cls: "hint" }, "This is a tracing image. Claude is told it's only a reference.") : null
  ]));
  if (it.type === "cover") pane.append(section("Album cover", [h("div", { cls: "hint" }, "Stands in for the playing song's artwork. Claude fills it with the real cover."), tog(it.cover?.sample !== false, val => { it.cover = { sample: val }; A.commit("Cover"); }, "Uses the playing song's art")]));
  /* animation */
  const an = it.anim || { kind: "none" };
  const demo = h("div", { cls: "anim-demo" });
  if (an.kind && an.kind !== "none") demo.style.animation = `anim-${{ pulse: "pulse", spin: "spin", fade: "fade", slide: "slide", scale: "scale", bounce: "pulse" }[an.kind]} ${an.dur || 1}s ease-in-out infinite`;
  pane.append(section("Animation", [
    row(sel([["none", "None"], ["fade", "Fade"], ["slide", "Slide"], ["scale", "Grow in"], ["pulse", "Pulse"], ["bounce", "Bounce"], ["spin", "Spin"], ["glow", "Glow on and off"], ["custom", "Something else (describe it)"]], an.kind, val => { it.anim = Object.assign({}, an, { kind: val }); A.commit("Animation"); })),
    an.kind !== "none" ? row(num("Secs", an.dur || 1, val => { it.anim = Object.assign({}, an, { dur: val }); A.commit("~anim"); }, { min: 0.05, step: 0.05, dec: 2 }), sel([["tap", "When tapped"], ["playing", "While playing"], ["open", "When the screen opens"], ["always", "All the time"], ["hover", "When the mouse is over it"]], an.when || "tap", val => { it.anim = Object.assign({}, an, { when: val }); A.commit("Animation"); })) : null,
    an.kind !== "none" ? (() => { const t = h("input", { value: an.note || "", placeholder: "In words, e.g. bounces a little then settles", style: { flex: 1, height: "26px", padding: "0 7px" } }); t.onchange = () => { it.anim = Object.assign({}, an, { note: t.value }); A.commit("Animation note"); }; t.onkeydown = e => e.stopPropagation(); return row(t); })() : null,
    an.kind !== "none" ? demo : null
  ], { hint: "described to Claude" }));
  /* layer */
  pane.append(section("Layer", [
    row(num("Opacity", Math.round((v.opacity ?? 1) * 100), (val, l) => set("opacity", S.clamp(val, 0, 100) / 100, l), { unit: "%", dec: 0, min: 0, max: 100 })),
    row(tog(!!it.hidden, val => { A.touch(it, "hidden"); it.hidden = val; A.commit(val ? "Hide" : "Show"); }, "Hidden"), tog(!!it.locked, val => { it.locked = val; A.commit(val ? "Lock" : "Unlock"); }, "Locked"))
  ]));
  statusSection(pane, [it]);
  if (it.partRef) pane.append(section("My part", [row(h("button", { cls: "pbtn sm", onclick: () => A.run("updatepart") }, "Update the part from this"), h("button", { cls: "pbtn sm", onclick: () => A.syncPartCopies(it.partRef) }, "Reset to the part"))]));
  if (it.part && it.part.startsWith("macawp3:")) pane.append(section("MacawP3", [row(h("button", { cls: "pbtn sm", onclick: () => S.dlg.swapPart() }, "Swap for another part…"))]));
}

function fillSection(pane, it, v) {
  const fills = v.fills || [];
  const setF = (fs, live) => { A.setProp(it, "fills", fs, false); live ? S.canvas.render() : A.commit("~fill"); };
  const rows = fills.map((f, i) => {
    const up = (patch, live) => { const fs = S.clone(fills); Object.assign(fs[i], patch); setF(fs, live); };
    /* the fill type is a small button with a menu, so the colour field gets the room */
    const KINDS = [["solid", "Solid colour", "square"], ["linear", "Gradient", "blend"], ["radial", "Round gradient", "circle-dot"], ["cover", "From the album cover", "disc-3"], ["image", "Image", "image"]];
    const cur = KINDS.find(k => k[0] === f.kind) || KINDS[0];
    const kind = ib(cur[2], "Fill type: " + cur[1] + " (click to change)", e => S.dlg.menuAt(e.clientX, e.clientY + 8, KINDS.map(k => [k[1], () => up({ kind: k[0], color2: f.color2 || "#123440", angle: f.angle ?? 135 }), { check: k[0] === f.kind }])));
    const parts = [row(kind, f.kind === "solid" || f.kind === "linear" || f.kind === "radial" ? colorField(f.color, c => up({ color: c })) : f.kind === "cover" ? h("span", { cls: "hint", style: { flex: 1 } }, "the song's colours") : h("button", { cls: "pbtn sm", style: { flex: 1 }, onclick: () => { const inp = $("file-img"); inp.value = ""; inp.onchange = () => { const fl = inp.files[0]; if (!fl) return; const r = new FileReader(); r.onload = () => up({ image: r.result }); r.readAsDataURL(fl); }; inp.click(); } }, f.image ? "Change image" : "Choose image"),
      ib(f.on === false ? "eye-off" : "eye", "Show / hide this fill", () => up({ on: f.on === false })), ib("minus", "Remove", () => { const fs = S.clone(fills); fs.splice(i, 1); setF(fs); }))];
    if (f.kind === "linear" || f.kind === "radial") parts.push(row(lbl("to"), colorField(f.color2 || "#000", c => up({ color2: c })), f.kind === "linear" ? num("°", f.angle ?? 180, (a, l) => up({ angle: a }, l), { title: "Direction" }) : null));
    if (f.kind !== "solid") parts.push(row(num("Opacity", Math.round((f.opacity ?? 1) * 100), (o, l) => up({ opacity: S.clamp(o, 0, 100) / 100 }, l), { unit: "%", dec: 0 })));
    return h("div", { style: { marginBottom: "6px" } }, ...parts);
  });
  pane.append(section("Fill", rows.length ? rows : [h("div", { cls: "hint" }, "No fill")], { right: h("span", { cls: "add", title: "Add fill", onclick: () => setF(fills.concat({ kind: "solid", color: fills.length ? "rgba(255,255,255,0.20)" : "#2BB3C0" })) }, "+") }));
}
function strokeSection(pane, it, v) {
  const s = v.stroke;
  const setS = (st, live) => { A.setProp(it, "stroke", st, false); live ? S.canvas.render() : A.commit("~stroke"); };
  if (!s) return pane.append(section(it.type === "line" || it.type === "path" ? "Line" : "Border", [h("div", { cls: "hint" }, "None")], { right: h("span", { cls: "add", onclick: () => setS({ color: "rgba(255,255,255,0.3)", width: 1, style: "solid" }) }, "+") }));
  const up = (p, l) => setS(Object.assign({}, s, p), l);
  pane.append(section(it.type === "line" || it.type === "path" ? "Line" : "Border", [
    row(colorField(s.color, c => up({ color: c })), ib(s.on === false ? "eye-off" : "eye", "Show / hide", () => up({ on: s.on === false })), it.type !== "line" ? ib("minus", "Remove", () => setS(null)) : null),
    row(num("Width", s.width, (w, l) => up({ width: Math.max(0, w) }, l), { min: 0, step: 0.5, dec: 1 }), sel([["solid", "Solid"], ["dashed", "Dashed"], ["dotted", "Dotted"]], s.style || "solid", st => up({ style: st }))),
    it.type !== "line" && it.type !== "path" ? row(seg([["inside", "Inside"], ["outside", "Outside"]], s.pos || "inside", p => up({ pos: p }))) : null
  ]));
}
function effectsSection(pane, it, v) {
  const effs = v.effects || [];
  const setE = (es, live) => { A.setProp(it, "effects", es, false); live ? S.canvas.render() : A.commit("~effects"); };
  const rows = effs.map((e, i) => {
    const up = (p, l) => { const es = S.clone(effs); Object.assign(es[i], p); setE(es, l); };
    const head = row(sel([["shadow", "Drop shadow"], ["inner", "Inner shadow"], ["glow", "Glow"], ["blur", "Blur"], ["glass", "Glass blur"]], e.kind, k => up({ kind: k })), ib(e.on === false ? "eye-off" : "eye", "Switch off to compare", () => up({ on: e.on === false })), ib("minus", "Remove", () => { const es = S.clone(effs); es.splice(i, 1); setE(es); }));
    const body = [];
    if (e.kind === "glass") body.push(row(seg([["clear", "Clear"], ["frosted", "Frosted"], ["liquid", "Liquid"], ["tinted", "Tinted"]], e.glass || "liquid", g => up({ glass: g }))), row(num("Blur", e.blur ?? "", (b, l) => up({ blur: b }, l), { min: 0, title: "Blur amount (empty = the preset's)" })));
    else if (e.kind === "blur") body.push(row(num("Blur", e.blur ?? 4, (b, l) => up({ blur: b }, l), { min: 0 })));
    else {
      body.push(row(e.color === "cover" ? h("div", { cls: "fld ro", style: { flex: 1 } }, "Album colour") : colorField(e.color || "#000", c => up({ color: c })), h("button", { cls: "ib" + (e.color === "cover" ? " on" : ""), title: "Take the colour from the album cover (like the app's glow)", onclick: () => up({ color: e.color === "cover" ? "#F2C14E" : "cover" }) }, S.icon("disc-3", 14))));
      body.push(row(num("X", e.x || 0, (x, l) => up({ x }, l)), num("Y", e.y || 0, (y, l) => up({ y }, l)), num("Blur", e.blur || 0, (b, l) => up({ blur: Math.max(0, b) }, l), { min: 0 }), num("Grow", e.spread || 0, (s, l) => up({ spread: s }, l), { title: "Spread" })));
      if (e.color === "cover") body.push(row(num("Strength", Math.round((e.opacity ?? 0.45) * 100), (o, l) => up({ opacity: S.clamp(o, 0, 100) / 100 }, l), { unit: "%", dec: 0 })));
    }
    return h("div", { style: { marginBottom: "8px" } }, head, ...body);
  });
  pane.append(section("Effects", rows.length ? rows : [h("div", { cls: "hint" }, "Shadow, glow, blur, or the app's Liquid Glass.")], { right: h("span", { cls: "add", title: "Add effect", onclick: e => S.dlg.menuAt(e.clientX, e.clientY, [["Drop shadow", () => setE(effs.concat({ kind: "shadow", color: "rgba(0,0,0,0.35)", x: 0, y: 6, blur: 18, spread: 0, on: true }))], ["Glow", () => setE(effs.concat({ kind: "glow", color: "#F2C14E", x: 0, y: 0, blur: 24, spread: 2, on: true }))], ["Album-colour glow", () => setE(effs.concat({ kind: "glow", color: "cover", x: 0, y: 12, blur: 40, spread: 0, opacity: 0.45, on: true }))], ["Inner shadow", () => setE(effs.concat({ kind: "inner", color: "rgba(0,0,0,0.3)", x: 0, y: 2, blur: 6, spread: 0, on: true }))], ["Blur", () => setE(effs.concat({ kind: "blur", blur: 6, on: true }))], ["Glass blur (Liquid Glass)", () => setE(effs.concat({ kind: "glass", glass: "liquid", on: true }))]]) }, "+") }));
}
function textSection(pane, it, v) {
  const T = v.text, set = (k, val, l) => { A.setProp(it, "text." + k, val, false); l ? S.canvas.render() : A.commit("~text." + k); };
  const ts = T.style && A.doc.textStyles.find(s => s.id === T.style);
  const content = h("textarea", { rows: 2 }); content.value = T.content ?? ""; content.onkeydown = e => e.stopPropagation();
  content.oninput = () => { A.nameFromText(it, it.text.content, content.value); A.setProp(it, "text.content", content.value, false); S.canvas.render(); };
  content.onchange = () => { if (it.type === "text" && it.text.sizing === "hug") { const el = document.querySelector(`[data-id="${it.id}"] .tx`); if (el) { it.w = Math.ceil(el.scrollWidth) + 1; it.h = Math.ceil(el.scrollHeight); } } A.commit("Edit text"); };
  pane.append(section("Text", [
    content,
    row(lbl("Style"), sel([["", "No style"], ...A.doc.textStyles.map(s => [s.id, `${s.name} · ${s.size}`])], T.style || "", val => set("style", val || undefined))),
    ts ? h("div", { cls: "hint" }, `Uses "${ts.name}". Changing the style changes every text that uses it.`) : row(sel(allFonts().map(f => [f, f]), T.font || "Inter", f => set("font", f), { style: { fontFamily: T.font } })),
    ts ? null : row(sel([[300, "Light"], [400, "Regular"], [500, "Medium"], [600, "Semibold"], [700, "Bold"], [800, "Extra bold"], [900, "Black"]], T.weight, w => set("weight", +w)), num("Size", T.size, (s, l) => set("size", Math.max(1, s), l), { min: 1 })),
    ts ? null : row(num("↕", T.lh || "", (s, l) => set("lh", s, l), { title: "Line height (empty = automatic)", min: 0 }), num("↔", T.ls || 0, (s, l) => set("ls", s, l), { title: "Letter spacing", step: 0.1, dec: 1 })),
    row(colorField(T.color, c => set("color", c))),
    row(seg([["left", "i:align-left"], ["center", "i:align-center"], ["right", "i:align-right"]], T.align || "left", a => set("align", a)), seg([["top", "i:arrow-up-to-line"], ["middle", "i:fold-vertical"], ["bottom", "i:arrow-down-to-line"]], T.valign || "top", a => set("valign", a))),
    row(seg([["", "Aa"], ["uppercase", "AA"], ["lowercase", "aa"], ["capitalize", "Aa Bb"]], T.case || "", c => set("case", c)), ib("italic", "Italic", () => set("italic", !T.italic), { on: T.italic }), ib("underline", "Underline", () => set("deco", T.deco === "underline" ? "" : "underline"), { on: T.deco === "underline" }), ib("strikethrough", "Strike through", () => set("deco", T.deco === "line-through" ? "" : "line-through"), { on: T.deco === "line-through" })),
    it.type === "text" ? row(lbl("Too long"), sel([["wrap", "Wrap to more lines"], ["ellipsis", "Cut with …"], ["shrink", "Shrink to fit"]], T.overflow || "wrap", o => set("overflow", o))) : null,
    row(lbl("Words"), sel([["fixed", "Fixed words (as typed)"], ["song", "The song's title"], ["artist", "The artist"], ["album", "The album"], ["time", "A time (1:24)"], ["count", "A number / count"]], T.sample || "fixed", s => set("sample", s))),
    T.sample && T.sample !== "fixed" ? h("div", { cls: "hint" }, "Claude will fill this from the playing song instead of using the words you typed.") : null
  ]));
}

/* notes and tap links */
function rightNotes(pane) {
  A.noteFilter = A.noteFilter || "all";
  pane.append(h("div", { cls: "sec" }, seg([["all", "All"], ["screen", "This screen"], ["open", "Open"], ["done", "Done"]], A.noteFilter, f => { A.noteFilter = f; P.renderRight(); })));
  const notes = S.canvas.noteOrder().map((n, i) => Object.assign(n, { num: i + 1 })).filter(n => A.noteFilter === "all" || (A.noteFilter === "screen" && n.sc.id === A.activeScreen) || (A.noteFilter === "open" && !n.done) || (A.noteFilter === "done" && n.done));
  if (!notes.length) pane.append(h("div", { cls: "empty" }, "No notes here. Press N, then click anything to pin a note for Claude."));
  for (const n of notes) {
    const ck = h("label", { cls: "chk", title: "Done (Claude built it)" }, h("input", { type: "checkbox", checked: !!n.done, onchange: e => { if (n.kind === "item") n.it.note.done = e.target.checked; else n.sc.noteDone = e.target.checked; A.commit("Note done"); } }), h("i"));
    const card = h("div", { cls: "sec", style: { cursor: "pointer", opacity: n.done ? 0.55 : 1 } },
      h("div", { cls: "row", style: { marginBottom: "4px" } }, h("span", { style: { width: "20px", height: "20px", borderRadius: "50% 50% 50% 0", transform: "rotate(-45deg)", background: n.done ? "#6f7480" : "var(--warn)", color: "#3a3200", display: "grid", placeItems: "center", fontWeight: 700, fontSize: "11px", flex: "none" } }, h("span", { style: { transform: "rotate(45deg)" } }, n.num)), h("b", {}, n.kind === "item" ? n.it.name : "Whole screen"), h("span", { style: { marginLeft: "auto", color: "var(--dim)" } }, n.sc.name), ck),
      h("div", { style: { color: "var(--ink2)", whiteSpace: "pre-wrap" } }, n.note));
    card.onclick = e => { if (e.target.closest(".chk")) return; if (n.kind === "item") { A.select(n.id); S.canvas.zoomSel(); } else { A.selectScreen(n.id); S.canvas.zoomTo(n.sc); } A.openNote = n.id; S.canvas.overlay(); };
    pane.append(card);
  }
  /* tap links */
  const links = A.doc.links;
  pane.append(section("Tap links", [
    links.length ? null : h("div", { cls: "hint" }, "Press K, then drag from a button to the screen it should open."),
    ...links.map((l, i) => {
      const f = S.findIn(A.doc, l.from), to = S.screenOf(A.doc, l.to); if (!f) return null;
      const up = (k, val) => { l[k] = val; A.commit("Tap link"); };
      return h("div", { style: { padding: "6px", borderRadius: "6px", marginBottom: "6px", background: A.selLink === l.id ? "var(--acc2)" : "var(--panel2)", border: "1px solid var(--line)" }, onclick: () => { A.selLink = l.id; S.canvas.overlay(); } },
        h("div", { cls: "row" }, h("span", { style: { color: ["#4c8dff", "#9b7bff", "#3ecf8e", "#ff9f43", "#ff4d8d", "#2bb3c0"][i % 6] } }, "●"), h("b", {}, f.item.name), S.icon("arrow-right", 12), h("span", {}, to ? to.name : "?"), h("span", { style: { marginLeft: "auto" } }, ib("trash-2", "Delete link", () => { A.doc.links = links.filter(x => x !== l); A.commit("Delete link"); }))),
        row(sel([["tap", "Tap"], ["longpress", "Long press"], ["swipeleft", "Swipe left"], ["swiperight", "Swipe right"], ["swipeup", "Swipe up"], ["swipedown", "Swipe down"], ["hover", "Mouse over (desktop)"]], l.on, val => up("on", val)),
          sel([["instant", "Instant"], ["slide", "Slide in"], ["slideup", "Slide up"], ["fade", "Fade"], ["zoom", "Zoom from it"], ["sheet", "Bottom sheet"], ["popup", "Pop-up"], ["back", "Go back"]], l.motion, val => up("motion", val))),
        row(lbl("Opens"), sel(A.doc.screens.map(s => [s.id, s.name]), l.to, val => up("to", val))));
    })
  ]));
}
function rightCode(pane) {
  const its = A.selItems();
  let o;
  if (its.length) o = its.map(it => S.exporter.itemJSON(it, S.findIn(A.doc, it.id).screen));
  else if (A.screen()) { const sc = A.screen(); o = S.exporter.screenJSON(sc, { includeKeep: true, short: true }); }
  pane.append(h("div", { cls: "sec" }, h("div", { cls: "hint", style: { marginBottom: "8px" } }, "Exactly what the design file tells Claude about " + (its.length ? "what you picked." : "this screen (items shortened).")),
    h("div", { cls: "code", style: { whiteSpace: "pre-wrap", wordBreak: "break-word", maxHeight: "none" } }, o ? JSON.stringify(o.length === 1 ? o[0] : o, null, 2) : "Nothing selected"),
    h("button", { cls: "pbtn sm", style: { marginTop: "8px" }, onclick: () => { S.host.copyText(JSON.stringify(o, null, 2)); S.toast("Copied"); } }, "Copy")));
}

P.init = () => {
  $("left-tabs").addEventListener("click", e => { const t = e.target.closest("span"); if (t) { A.leftTab = t.dataset.t; P.renderLeft(); } });
  $("right-tabs").addEventListener("click", e => { const t = e.target.closest("span"); if (t) { A.rightTab = t.dataset.t; P.renderRight(); } });
};
})();
