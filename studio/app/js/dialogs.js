/* Menus, pop-ups and windows: the menu bar, right-click menus, colour picker, icon picker, command search, shortcuts,
   settings, new screen, history, and the Home screen. */
"use strict";
(() => {
const D = S.dlg = {};
const h = S.h, $ = id => document.getElementById(id);

/* ---------- pop-up plumbing ---------- */
let openPop = null;
D.closePop = () => { if (openPop) { openPop.remove(); openPop = null; } document.querySelectorAll(".menubar>span.on").forEach(s => s.classList.remove("on")); };
D.place = (el, x, y) => {
  document.body.append(el);
  const r = el.getBoundingClientRect();
  el.style.left = Math.max(4, Math.min(x, innerWidth - r.width - 6)) + "px";
  el.style.top = Math.max(4, Math.min(y, innerHeight - r.height - 6)) + "px";
};
document.addEventListener("pointerdown", e => { if (openPop && !openPop.contains(e.target) && !e.target.closest(".menubar") && !e.target.closest(".pop.sub")) D.closePop(); }, true);
D.modal = (title, sub, body, foot, o = {}) => {
  const close = () => { scrim.remove(); document.removeEventListener("keydown", esc, true); o.onClose && o.onClose(); };
  const esc = e => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
  const dlg = h("div", { cls: "dlg", style: { width: (o.width || 560) + "px" } },
    h("div", { cls: "dlg-h" }, h("div", {}, h("h2", {}, title), sub ? h("p", {}, sub) : null), h("button", { cls: "ib x", onclick: close }, S.icon("x", 16))),
    h("div", { cls: "dlg-b" }, body), foot ? h("div", { cls: "dlg-f" }, foot) : null);
  const scrim = h("div", { cls: "scrim" }, dlg);
  scrim.addEventListener("pointerdown", e => { if (e.target === scrim && !o.sticky) close(); });
  document.addEventListener("keydown", esc, true);
  document.body.append(scrim);
  return { close, dlg, scrim };
};
D.prompt = (title, label, value = "") => new Promise(res => {
  const inp = h("input", { value, style: { width: "100%", height: "32px", padding: "0 10px", fontSize: "13px" } });
  let done = false;
  const m = D.modal(title, label, inp, [h("button", { cls: "pbtn", onclick: () => m.close() }, "Cancel"), h("button", { cls: "pbtn p", onclick: () => { done = true; m.close(); res(inp.value.trim()); } }, "OK")], { width: 400, onClose: () => { if (!done) res(null); } });
  inp.addEventListener("keydown", e => { e.stopPropagation(); if (e.key === "Enter") { done = true; m.close(); res(inp.value.trim()); } if (e.key === "Escape") m.close(); });
  setTimeout(() => { inp.focus(); inp.select(); }, 0);
});

/* ---------- menus ---------- */
const menuItems = ids => ids.map(id => {
  if (id === "-") return h("div", { cls: "msep" });
  if (Array.isArray(id)) { const [label, fn, o = {}] = id; return h("div", { cls: "mi" + (o.dis ? " dis" : ""), onclick: () => { D.closePop(); fn(); } }, h("span", { cls: "chkm" }, o.check ? "✓" : ""), label, o.key ? h("kbd", {}, o.key) : null); }
  const a = A.actions[id]; if (!a) return null;
  const en = !a.en || a.en(), ck = a.check && a.check();
  return h("div", { cls: "mi" + (en ? "" : " dis"), onclick: () => { D.closePop(); A.run(id); } }, h("span", { cls: "chkm" }, ck ? "✓" : ""), a.label, A.keyOf(id) ? h("kbd", {}, A.keyOf(id)) : null);
}).filter(Boolean);
D.menuAt = (x, y, items) => { D.closePop(); const m = h("div", { cls: "pop menu" }, menuItems(items)); openPop = m; D.place(m, x, y); };
D.buildMenubar = () => {
  const mb = $("menubar"); mb.innerHTML = "";
  for (const name of Object.keys(A.MENUS)) {
    const s = h("span", {}, name);
    const open = () => { D.closePop(); s.classList.add("on"); const r = s.getBoundingClientRect(); const m = h("div", { cls: "pop menu" }, menuItems(A.MENUS[name])); openPop = m; D.place(m, r.left, r.bottom + 2); };
    s.onclick = () => { if (s.classList.contains("on")) D.closePop(); else open(); };
    s.onmouseenter = () => { if (document.querySelector(".menubar>span.on") && !s.classList.contains("on")) open(); };
    mb.append(s);
  }
};
D.contextMenu = (x, y) => {
  const its = A.selItems();
  if (!its.length && A.selScreen) return D.screenMenu(x, y, A.screen());
  if (!its.length) return D.menuAt(x, y, ["paste", "-", "addscreen", "copymacaw", "-", "zoomfit", "zoom100", "-", "t-rulers", "t-snap"]);
  D.closePop();
  const m = h("div", { cls: "pop menu" }, menuItems(["cut", "copy", "paste", "dup", "del", "-", "front", "back", "group", "ungroup", "autolayout", "-", "note"]));
  const markRow = h("div", { cls: "mi" }, h("span", { cls: "chkm" }), "Mark as…", h("kbd", {}, "›"));
  markRow.onmouseenter = () => { document.querySelectorAll(".pop.sub").forEach(x => x.remove()); const r = markRow.getBoundingClientRect(); const sm = h("div", { cls: "pop menu sub" }, ["new", "changed", "keep", "remove"].map(st => h("div", { cls: "mi", onclick: () => { D.closePop(); document.querySelectorAll(".pop.sub").forEach(x => x.remove()); A.setStatus(st); } }, h("span", { cls: "tag " + st }, st), { new: "New idea", changed: "Changed", keep: "Keep as is", remove: "Remove from app" }[st]))); D.place(sm, r.right + 2, r.top - 5); sm.addEventListener("pointerdown", e => e.stopPropagation()); };
  m.append(markRow, ...menuItems(["link", "swappart", "savepart", "updatepart", "-", "copystyle", "pastestyle", "lock", "hide"]));
  m.addEventListener("mouseover", e => { if (!e.target.closest(".mi") || e.target.closest(".mi") === markRow) return; document.querySelectorAll(".pop.sub").forEach(x => x.remove()); });
  openPop = m; D.place(m, x, y);
  const killSub = new MutationObserver(() => { if (!document.body.contains(m)) { document.querySelectorAll(".pop.sub").forEach(x => x.remove()); killSub.disconnect(); } }); killSub.observe(document.body, { childList: true });
};
D.screenMenu = (x, y, sc) => D.menuAt(x, y, [
  ["Rename…", () => D.prompt("Rename screen", "Name", sc.name).then(n => { if (n) { sc.name = n; A.commit("Rename screen"); } })],
  ["Duplicate (for a version B)", () => A.duplicateScreen(sc.id)], ["Delete", () => A.deleteScreen(sc.id)], "-",
  ...["new", "changed", "keep", "remove"].map(st => ["Mark as " + st, () => { sc.status = st; sc.statusByHand = true; A.commit("Screen status"); }, { check: sc.status === st }]), "-",
  ["Put in a section…", () => D.prompt("Section", "Group screens under a heading (empty = none)", sc.section || "").then(n => { if (n != null) { sc.section = n; A.commit("Section"); } })],
  ["Note for Claude…", () => { A.selectScreen(sc.id); A.openNote = sc.id; S.canvas.overlay(); }],
  ["Zoom to it", () => S.canvas.zoomTo(sc)], ["Preview it", () => S.modes.preview(sc.id)], ["Compare with the real app", () => S.modes.compare(sc.id)], "-", ["Export picture…", () => S.exporter.exportPictureDialog(sc.id)]
]);

/* ---------- colour picker ---------- */
D.colorPicker = (anchor, color, onChange, o = {}) => {
  D.closePop();
  let c = S.parseColor(S.resolveColor(A.doc, color) || "#FFFFFF"), hsv = S.rgb2hsv(c);
  const svBox = h("div", { cls: "cp-sv" }), svDot = h("i"); svBox.append(svDot);
  const hue = h("div", { cls: "cp-bar cp-hue" }, h("i")), alpha = h("div", { cls: "cp-bar" }, h("i"));
  const hex = h("input", { style: { flex: "1 1 0", minWidth: "0", height: "26px", padding: "0 7px" } }), aIn = h("input", { style: { flex: "0 0 52px", width: "52px", height: "26px", padding: "0 7px" } });
  const prev = h("span", { cls: "sw", style: { width: "26px", height: "26px" } }, h("i"));
  const out = () => S.rgba(S.hex(c), c.a);
  const draw = (emit = true) => {
    const base = S.hex(S.hsv2rgb(hsv.h, 1, 1));
    svBox.style.background = `linear-gradient(to top,#000,transparent),linear-gradient(to right,#fff,${base})`;
    svDot.style.left = hsv.s * 100 + "%"; svDot.style.top = (1 - hsv.v) * 100 + "%";
    hue.firstChild.style.left = hsv.h / 360 * 100 + "%";
    alpha.style.background = `linear-gradient(to right,transparent,${S.hex(c)}),repeating-conic-gradient(#888 0 25%,#bbb 0 50%) 0/8px 8px`; alpha.firstChild.style.left = c.a * 100 + "%";
    if (document.activeElement !== hex) hex.value = S.hex(c); if (document.activeElement !== aIn) aIn.value = Math.round(c.a * 100) + "%";
    prev.firstChild.style.background = out();
    if (emit) live(out());
  };
  let lastEmit = 0, pendingCommit = false;
  const live = col => { onChange(col); };   // the caller commits with "~" labels, so dragging is one undo step
  const drag = (el, fn) => el.addEventListener("pointerdown", e => { const mv = ev => { const r = el.getBoundingClientRect(); fn(S.clamp((ev.clientX - r.left) / r.width, 0, 1), S.clamp((ev.clientY - r.top) / r.height, 0, 1)); draw(); }; mv(e); el.setPointerCapture(e.pointerId); el.onpointermove = mv; el.onpointerup = () => { el.onpointermove = null; A.recentColor(out()); }; });
  drag(svBox, (x, y) => { hsv.s = x; hsv.v = 1 - y; Object.assign(c, S.hsv2rgb(hsv.h, hsv.s, hsv.v)); });
  drag(hue, x => { hsv.h = x * 360; Object.assign(c, S.hsv2rgb(hsv.h, hsv.s, hsv.v)); });
  drag(alpha, x => { c.a = S.round(x, 2); });
  hex.addEventListener("change", () => { let v = hex.value.trim(); if (/^[0-9a-f]{3,8}$/i.test(v)) v = "#" + v; const p = S.parseColor(v); c = Object.assign(p, { a: v.length === 9 ? p.a : c.a }); hsv = S.rgb2hsv(c); draw(); A.recentColor(out()); });
  aIn.addEventListener("change", () => { c.a = S.clamp(parseFloat(aIn.value) || 0, 0, 100) / 100; draw(); });
  [hex, aIn].forEach(i => i.addEventListener("keydown", e => { e.stopPropagation(); if (e.key === "Enter") i.blur(); }));
  const pickFrom = col => { c = S.parseColor(col); hsv = S.rgb2hsv(c); draw(); A.recentColor(out()); };
  const swRow = (cols, title) => h("div", { cls: "cp-sws" }, cols.map(([n, col]) => h("span", { cls: "sw", title: n + " " + col, onclick: () => pickFrom(col) }, h("i", { style: { background: col } }))));
  const eye = h("button", { cls: "ib box", title: "Pick a colour from anywhere on screen", onclick: async () => { if (!window.EyeDropper) return S.toast("Needs the Windows app"); try { const r = await new window.EyeDropper().open(); pickFrom(r.sRGBHex); } catch (e) {} } }, S.icon("pipette", 14));
  const styles = (A.doc.colorStyles || []);
  const pop = h("div", { cls: "pop cp" },
    svBox, hue, alpha, h("div", { cls: "row" }, eye, prev, hex, aIn),
    h("h5", {}, "MacawP3 colours"), swRow(S.MACAW.colors),
    styles.length ? h("h5", {}, "Colour styles (stay linked)") : null,
    styles.length ? h("div", { cls: "cp-sws" }, styles.map(st => h("span", { cls: "sw", title: st.name + " (linked)", onclick: () => { onChange({ style: st.id }); D.closePop(); } }, h("i", { style: { background: st.color } })))) : null,
    (A.settings.recentColors || []).length ? h("h5", {}, "Recent") : null, (A.settings.recentColors || []).length ? swRow(A.settings.recentColors.map(x => ["", x])) : null);
  pop.addEventListener("keydown", e => e.stopPropagation());
  openPop = pop; const r = anchor.getBoundingClientRect(); D.place(pop, r.left - 270, r.top - 40);
  draw(false);
};

/* ---------- icon picker ---------- */
D.iconPicker = (onPick, current = "") => {
  const names = Object.keys(window.ICONS || {});
  const q = h("input", { placeholder: `Search ${names.length} icons (play, heart, shuffle…)`, style: { width: "100%", height: "32px", padding: "0 10px", fontSize: "13px", marginBottom: "10px" } });
  const grid = h("div", { cls: "icgrid", style: { maxHeight: "52vh", overflow: "auto" } });
  const fav = ["play", "pause", "skip-back", "skip-forward", "shuffle", "repeat", "repeat-1", "heart", "list-music", "music", "disc-3", "mic-vocal", "volume-2", "settings", "search", "plus", "x", "chevron-left", "chevron-right", "ellipsis", "share", "download", "house", "library", "user", "timer", "list-plus", "radio", "headphones", "airplay"];
  const show = () => {
    const s = q.value.trim().toLowerCase(); grid.innerHTML = "";
    const list = s ? names.filter(n => n.includes(s) || (window.ICONS[n][1] || "").includes(s)).slice(0, 600) : fav.concat(names.filter(n => !fav.includes(n)).slice(0, 400));
    for (const n of list) grid.append(h("span", { title: n, cls: n === current ? "on" : "", html: S.iconSVG(n, 22, "currentColor"), onclick: () => { m.close(); onPick(n); } }));
    if (!list.length) grid.append(h("div", { cls: "empty" }, "No icon called that. Try another word."));
  };
  q.addEventListener("input", show); q.addEventListener("keydown", e => e.stopPropagation());
  const m = D.modal("Icons", "Free Lucide icons. Pick one, set its size and colour after.", h("div", {}, q, grid), null, { width: 640 });
  show(); setTimeout(() => q.focus(), 0);
};

/* ---------- command search ---------- */
D.palette = () => {
  const q = h("input", { placeholder: "Type an action, a screen, a layer or a colour…", style: { width: "100%", height: "36px", padding: "0 12px", fontSize: "14px", border: 0, background: "transparent" } });
  const list = h("div", { style: { maxHeight: "50vh", overflow: "auto", padding: "4px 0" } });
  let rows = [], idx = 0;
  const all = () => {
    const out = [];
    for (const id in A.actions) { const a = A.actions[id]; if (!a.en || a.en()) out.push({ label: a.label, kind: "Action", key: A.keyOf(id), run: () => A.run(id) }); }
    for (const sc of A.doc.screens) { out.push({ label: "Go to screen: " + sc.name, kind: "Screen", run: () => { A.selectScreen(sc.id); S.canvas.zoomTo(sc); } }); S.walk(sc.items, it => { out.push({ label: `Find layer: "${it.name}"`, kind: sc.name, run: () => { A.activeScreen = sc.id; A.select(it.id); S.canvas.zoomSel(); } }); }); }
    for (const [n, c] of S.MACAW.colors) out.push({ label: `Colour: MacawP3 ${n.toLowerCase()} ${c}`, kind: "Colour", run: () => applyColor(c) });
    for (const st of A.doc.colorStyles) out.push({ label: `Colour style: ${st.name}`, kind: "Colour", run: () => applyColor({ style: st.id }) });
    for (const p of S.PARTS) out.push({ label: "Add part: " + p.name, kind: "Part", run: () => { if (p.screen) A.addScreen(p.screen()); else S.canvas.insertCentered(S.panels.partItem(p)); } });
    return out;
  };
  const applyColor = c => { const its = A.selItems(); if (!its.length) return S.toast("Select something first"); for (const it of its) { if (it.type === "text") A.setProp(it, "text.color", c, false); else if (it.type === "icon") A.setProp(it, "icon.color", c, false); else A.setProp(it, "fills", [{ kind: "solid", color: c }], false); } A.commit("Colour"); };
  const items = all();
  const show = () => {
    const words = q.value.toLowerCase().split(/\s+/).filter(Boolean);
    rows = items.filter(r => words.every(w => r.label.toLowerCase().includes(w))).slice(0, 60); idx = 0; draw();
  };
  const draw = () => { list.innerHTML = ""; rows.forEach((r, i) => list.append(h("div", { cls: "mi" + (i === idx ? " on" : ""), style: { height: "32px" }, onclick: () => { m.close(); r.run(); } }, r.label, h("kbd", {}, r.key || r.kind)))); const on = list.children[idx]; on && on.scrollIntoView({ block: "nearest" }); };
  q.addEventListener("input", show);
  q.addEventListener("keydown", e => { e.stopPropagation(); if (e.key === "ArrowDown") { idx = Math.min(rows.length - 1, idx + 1); draw(); e.preventDefault(); } if (e.key === "ArrowUp") { idx = Math.max(0, idx - 1); draw(); e.preventDefault(); } if (e.key === "Enter" && rows[idx]) { m.close(); rows[idx].run(); } if (e.key === "Escape") m.close(); });
  const m = D.modal("Command search", "", h("div", {}, h("div", { style: { borderBottom: "1px solid var(--line)" } }, q), list), null, { width: 580 });
  m.dlg.querySelector(".dlg-h").remove(); m.dlg.querySelector(".dlg-b").style.padding = "6px";
  m.scrim.style.alignItems = "start"; m.scrim.style.paddingTop = "12vh";
  show(); setTimeout(() => q.focus(), 0);
};

/* ---------- shortcuts (click one to change it) ---------- */
D.shortcuts = () => {
  const body = h("div", { style: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: "2px 28px" } });
  const draw = () => {
    body.innerHTML = "";
    const ids = Object.keys(A.actions).filter(id => A.keyOf(id) || ["preview", "send", "note", "savepart"].includes(id));
    for (const id of ids) {
      const k = h("kbd", { cls: "key", style: { cursor: "pointer" }, title: "Click, then press the new keys" }, A.keyOf(id) || "none");
      k.onclick = () => {
        k.textContent = "press keys…";
        const grab = e => { e.preventDefault(); e.stopPropagation(); const ks = A.keyString(e); if (!ks) return; window.removeEventListener("keydown", grab, true); if (ks === "Escape") return draw(); A.settings.shortcuts = Object.assign({}, A.settings.shortcuts, { [id]: ks === "Backspace" ? "" : ks }); A.saveSettings(); draw(); };
        window.addEventListener("keydown", grab, true);
      };
      body.append(h("div", { cls: "row", style: { height: "26px", margin: 0, borderBottom: "1px solid var(--line)" } }, h("span", {}, A.actions[id].label), h("span", { style: { marginLeft: "auto" } }, k)));
    }
  };
  draw();
  D.modal("Keyboard shortcuts", "Click a shortcut, then press the keys you want (Backspace clears it). Hold Space and drag to move around; hold Alt to measure.", body,
    [h("button", { cls: "pbtn", onclick: () => { A.settings.shortcuts = {}; A.saveSettings(); draw(); } }, "Reset all")], { width: 760 });
};

/* ---------- settings ---------- */
D.settings = (page = "general") => {
  const st = A.settings, save = () => { A.saveSettings(); A.applySettings(); A.refresh(); };
  const nav = h("div", { style: { width: "190px", background: "var(--panel2)", padding: "12px 8px", borderRight: "1px solid var(--line)", flex: "none" } });
  const main = h("div", { style: { flex: 1, padding: "18px 22px", overflow: "auto", minHeight: "430px" } });
  const pages = { general: "General", canvas: "Canvas & snapping", shortcuts: "Shortcuts", send: "Send to Claude", claude: "Ask Claude", macaw: "MacawP3 link", updates: "Updates", backups: "Backups" };
  const field = (label, el, hint) => h("div", { style: { marginBottom: "14px" } }, h("div", { style: { fontWeight: 600, marginBottom: "5px" } }, label), el, hint ? h("div", { cls: "hint", style: { marginTop: "4px" } }, hint) : null);
  const inp = (val, set, o = {}) => { const i = h("input", Object.assign({ value: val ?? "", style: { width: o.w || "100%", height: "30px", padding: "0 9px" } }, o.attrs || {})); i.onchange = () => set(i.value); i.onkeydown = e => e.stopPropagation(); return i; };
  const toggle = (on, set, label) => { const b = h("button", { cls: "tog" + (on ? " on" : "") }); b.onclick = () => { on = !on; b.classList.toggle("on", on); set(on); save(); }; return h("label", { cls: "row", style: { gap: "10px", marginBottom: "10px", cursor: "pointer" } }, b, label); };
  const show = p => {
    page = p; nav.innerHTML = ""; main.innerHTML = "";
    for (const [k, l] of Object.entries(pages)) nav.append(h("div", { cls: "li" + (k === p ? " sel" : ""), style: { height: "32px", cursor: "pointer" }, onclick: () => show(k) }, l));
    main.append(h("h2", { style: { margin: "0 0 14px", fontSize: "17px" } }, pages[p]));
    if (p === "general") {
      main.append(field("Theme", h("div", { style: { width: "240px" } }, S.h("div", { cls: "seg" }, [["dark", "Dark"], ["light", "Light"]].map(([v, l]) => h("span", { cls: st.theme === v ? "on" : "", onclick: () => { st.theme = v; save(); show(p); } }, l))))));
      main.append(field("Interface size", h("div", { style: { width: "360px" } }, h("div", { cls: "seg" }, [0.9, 1, 1.1, 1.25, 1.5].map(z => h("span", { cls: (st.uiScale || 1) === z ? "on" : "", onclick: () => { st.uiScale = z; save(); show(p); } }, Math.round(z * 100) + "%"))))));
      main.append(toggle(st.openLast !== false, v => st.openLast = v, "Open the last design when the app starts"));
      main.append(field("New screens are", h("select", { cls: "plain", onchange: e => { st.defaultDevice = e.target.value; save(); } }, Object.entries(S.DEVICES).filter(([k]) => k !== "custom").map(([k, d]) => h("option", { value: k, selected: st.defaultDevice === k }, `${d.name} (${d.w} × ${d.h})`)))));
    }
    if (p === "canvas") {
      main.append(field("Grid size", h("div", { cls: "row" }, inp(st.grid, v => { st.grid = Math.max(1, parseInt(v) || 8); save(); }, { w: "80px" }), "px")));
      main.append(toggle(st.snap, v => st.snap = v, "Snap to edges and centres of other things"));
      main.append(toggle(st.gridSnap, v => st.gridSnap = v, "Snap to the grid"));
      main.append(toggle(st.guides, v => st.guides = v, "Show pink smart guides and gaps while dragging"));
      main.append(toggle(st.rulers, v => st.rulers = v, "Show rulers"));
      main.append(toggle(st.chrome, v => st.chrome = v, "Draw the phone's notch, status bar and home bar"));
      main.append(toggle(st.safe, v => st.safe = v, "Show safe areas (red bands where buttons shouldn't go)"));
      main.append(field("Arrow keys move by", h("div", { cls: "row" }, inp(st.nudge, v => { st.nudge = +v || 1; save(); }, { w: "60px" }), "px, with Shift", inp(st.bigNudge, v => { st.bigNudge = +v || 8; save(); }, { w: "60px" }), "px")));
    }
    if (p === "shortcuts") { main.append(h("p", { cls: "hint" }, "Every shortcut can be changed."), h("button", { cls: "pbtn", onclick: () => { m.close(); D.shortcuts(); } }, "Open the shortcut list")); }
    if (p === "claude") {
      main.append(h("div", { cls: "hint", style: { marginBottom: "14px", maxWidth: "460px" } }, "The chat at the bottom right talks to Claude with your own API key. It's billed by use on your Anthropic account: a question costs a few cents, a big redesign more."));
      const k = inp("", () => {}, { attrs: { type: "password", placeholder: "sk-ant-…" }, w: "360px" });
      const state = h("div", { cls: "hint", style: { marginTop: "6px" } });
      S.host.claudeHasKey().then(has => { state.textContent = has ? "A key is saved (kept encrypted on this PC)." : "No key yet."; });
      main.append(field("Claude API key", h("div", {}, h("div", { cls: "row" }, k,
        h("button", { cls: "pbtn p sm", onclick: async () => { if (!k.value.trim()) return; await S.host.claudeSetKey(k.value); k.value = ""; S.toast("Key saved"); S.chat.needKey = false; S.chat.render(); show(p); } }, "Save"),
        h("button", { cls: "pbtn sm danger", onclick: async () => { await S.host.claudeSetKey(""); S.toast("Key removed"); S.chat.render(); show(p); } }, "Remove")), state),
        h("span", {}, "Make one at ", h("a", { href: "#", style: { color: "var(--acc)" }, onclick: e => { e.preventDefault(); S.host.openExternal("https://console.anthropic.com/settings/keys"); } }, "console.anthropic.com"), ". Ctrl+J jumps to the chat.")));
    }
    if (p === "send") {
      const s = st.send = Object.assign({}, S.DEFAULT_SETTINGS.send, st.send);
      main.append(field("Send it by", h("div", { style: { width: "420px" } }, h("div", { cls: "seg" }, [["github", "GitHub (designs/ folder)"], ["folder", "Save to a folder"]].map(([v, l]) => h("span", { cls: s.delivery === v ? "on" : "", onclick: () => { s.delivery = v; save(); show(p); } }, l))))));
      main.append(field("GitHub access key", inp(s.token, v => { s.token = v.trim(); save(); }, { attrs: { type: "password", placeholder: "github_pat_…" } }),
        h("span", {}, "Needed to upload designs. Make a fine-grained token with only ", h("b", {}, "Contents: Read and write"), " on the mp3-player repo. ", h("a", { href: "#", style: { color: "var(--acc)" }, onclick: e => { e.preventDefault(); S.host.openExternal("https://github.com/settings/personal-access-tokens/new"); } }, "Make one on GitHub"), ". It's kept on this PC only.")));
      main.append(field("Repository", inp(s.repo, v => { s.repo = v.trim(); save(); })), field("Branch", inp(s.branch, v => { s.branch = v.trim() || "main"; save(); }, { w: "200px" }), "Designs go in its designs/ folder. That folder doesn't start an app release."));
      main.append(field("Picture size", h("div", { style: { width: "240px" } }, h("div", { cls: "seg" }, [1, 2, 3].map(z => h("span", { cls: s.scale === z ? "on" : "", onclick: () => { s.scale = z; save(); show(p); } }, z + "×"))))));
      main.append(toggle(s.includeKeep, v => s.includeKeep = v, "List every unchanged (\"keep\") item in full, not just by name"));
      main.append(h("button", { cls: "pbtn", onclick: async () => { try { const r = await S.host.githubTest(s); S.toast(r); } catch (e) { S.toast(e.message, true, 5000); } } }, "Test the GitHub connection"));
    }
    if (p === "macaw") {
      main.append(h("p", {}, "The MacawP3 parts and screens are built from the player's real sizes, colours and fonts (index.html in the mp3-player repo, October 2026)."));
      main.append(h("p", { cls: "hint" }, "When Claude changes how the app looks, the parts get updated in the next studio update, which installs itself. Each part carries the name of its piece in the app's code (for example #play-btn), so Claude knows exactly what to change."));
      main.append(h("button", { cls: "pbtn", onclick: () => S.host.openExternal("https://github.com/t6wy26zj95-creator/mp3-player") }, "Open the repo on GitHub"));
    }
    if (p === "updates") {
      const box = h("div", {}); main.append(h("p", {}, "Macaw Studio version ", h("b", {}, S.host.version)), box);
      const drawU = u => { box.innerHTML = ""; const msg = { idle: "", checking: "Checking…", none: "You have the newest version.", downloading: `Downloading version ${u.version} (${u.percent || 0}%)…`, ready: `Version ${u.version} is ready.`, available: `Version ${u.version} is out.`, error: "Couldn't check: " + (u.message || "") }[u.state] || ""; box.append(h("p", {}, msg));
        box.append(h("div", { cls: "row" }, h("button", { cls: "pbtn", onclick: async () => drawU(await S.host.checkUpdates()) }, "Check now"), u.state === "ready" ? h("button", { cls: "pbtn p", onclick: () => S.host.installUpdate() }, "Restart and update") : null)); };
      S.host.updateState().then(drawU); S.host.onUpdate(u => { if (page === "updates") drawU(u); });
      main.append(h("p", { cls: "hint" }, "The app checks when it starts and every few hours, downloads quietly, and installs when you close it."));
    }
    if (p === "backups") {
      main.append(h("p", { cls: "hint" }, "Every design keeps its last 20 saves. Pick one to open it as a copy."));
      const list = h("div", {}, "Loading…"); main.append(list);
      S.host.listBackups(A.doc ? A.doc.id : "").then(bs => { list.innerHTML = ""; if (!bs.length) list.append(h("div", { cls: "empty" }, "No backups yet.")); for (const b of bs) list.append(h("div", { cls: "li", style: { height: "32px" } }, S.icon("history", 13), h("span", { cls: "nm" }, b.name), h("span", { cls: "hint" }, new Date(b.mtime).toLocaleString()), h("button", { cls: "pbtn sm", onclick: async () => { const t = await S.host.readBackup(b.path); const d = JSON.parse(t); d.id = S.uid("d"); d.name = d.name + " (backup " + new Date(b.mtime).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }) + ")"; m.close(); A.open(d); A.save(); } }, "Open copy"))); });
    }
  };
  const m = D.modal("Settings", "", h("div", { style: { display: "flex", margin: "-16px -22px", minHeight: "460px" } }, nav, main), null, { width: 820 });
  m.dlg.querySelector(".dlg-h h2").textContent = "Settings";
  show(page);
};

/* ---------- history ---------- */
D.history = () => {
  const list = h("div", { style: { maxHeight: "60vh", overflow: "auto" } });
  A.hist.forEach((st, i) => list.append(h("div", { cls: "li" + (i === A.hi ? " sel" : ""), style: { height: "28px", cursor: "pointer", opacity: i > A.hi ? 0.5 : 1 }, onclick: () => { A.jumpHistory(i); m.close(); } }, h("span", { cls: "nm" }, (i + 1) + ". " + st.label.replace("~", "")), h("span", { cls: "hint" }, st.t ? new Date(st.t).toLocaleTimeString() : ""))));
  const m = D.modal("History", "Click a step to jump back (or forward) to it.", list, null, { width: 440 });
  setTimeout(() => { const s = list.querySelector(".sel"); s && s.scrollIntoView({ block: "center" }); }, 0);
};

/* ---------- new screen ---------- */
D.newScreen = (tab = "blank") => {
  let device = A.settings.defaultDevice || "iphone15pro", picks = new Set(["library"]);
  const body = h("div", {});
  const draw = () => {
    body.innerHTML = "";
    body.append(h("div", { style: { width: "320px", marginBottom: "16px" } }, h("div", { cls: "seg" }, [["blank", "Blank screen"], ["macaw", "Copy MacawP3 screens"]].map(([v, l]) => h("span", { cls: tab === v ? "on" : "", onclick: () => { tab = v; draw(); } }, l)))));
    if (tab === "blank") {
      for (const [k, d] of Object.entries(S.DEVICES)) body.append(h("div", { cls: "li dev-li" + (k === device ? " sel" : ""), style: { cursor: "pointer" }, onclick: () => { device = k; draw(); }, ondblclick: () => go() }, h("span", { cls: "ic" }, S.icon(k === "desktop" ? "monitor" : k === "ipad" ? "tablet" : k === "telegram" ? "send" : "smartphone", 14)), h("span", { cls: "nm" }, d.name), h("span", { cls: "hint" }, k === "custom" ? "type a size after" : `${d.w} × ${d.h}`)));
    } else {
      const g = h("div", { cls: "pick-screens" });
      for (const [k, n] of S.MACAW_SCREENS) { const pic = h("div", { cls: "pic" }); pic.append(S.panels.thumb(S.SCREEN_MAKERS[k](), 126, 196)); g.append(h("div", { cls: "ps" + (picks.has(k) ? " on" : ""), onclick: () => { picks.has(k) ? picks.delete(k) : picks.add(k); draw(); } }, pic, h("div", {}, n))); }
      body.append(h("p", { cls: "hint", style: { marginTop: 0 } }, "Each comes in as separate pieces you can move, change or delete. Anything you change is marked \"changed\" for Claude."), g);
    }
  };
  const go = () => {
    m.close();
    if (tab === "blank") { const sc = S.newScreen(device, { name: "Screen " + (A.doc.screens.length + 1) }); A.addScreen(sc, "New screen"); }
    else { let last; for (const k of picks) { last = A.addScreen(S.SCREEN_MAKERS[k](), "Copy " + k); } setTimeout(() => S.canvas.zoomFit(), 30); }
  };
  draw();
  const m = D.modal("New screen", "", body, [h("button", { cls: "pbtn", onclick: () => m.close() }, "Cancel"), h("button", { cls: "pbtn p", onclick: go }, "Add")], { width: tab === "macaw" ? 520 : 480 });
};

D.swapPart = () => {
  const it = A.selItems()[0]; if (!it) return;
  const grid = h("div", { cls: "pgrid", style: { gridTemplateColumns: "repeat(4,1fr)", padding: 0 } });
  for (const p of S.PARTS.filter(p => !p.screen).concat(S.BASIC.map(b => Object.assign({ basic: true }, b)))) {
    const c = h("div", { cls: "pcard", title: p.name }, h("div", { cls: "th" }), h("div", { cls: "nm" }, p.name));
    try { const x = p.make(); const k = Math.min(1, 100 / x.w, 64 / Math.max(1, x.h)); const el = S.renderItem(A.doc, Object.assign(x, { x: 0, y: 0 })); el.style.position = "relative"; el.style.transform = `scale(${k})`; el.style.transformOrigin = "0 0"; c.firstChild.append(h("div", { style: { width: x.w * k + "px", height: x.h * k + "px" } }, el)); } catch (e) {}
    c.onclick = () => {
      m.close();
      const f = S.findIn(A.doc, it.id), n = p.basic ? p.make() : S.panels.partItem(p);
      n.x = S.round(it.x + (it.w - n.w) / 2); n.y = S.round(it.y + (it.h - n.h) / 2); n.status = it.status === "keep" ? "changed" : it.status; n.note = it.note;
      n.swappedFrom = it.part || it.name;
      f.list.splice(f.index, 1, n); A.doc.links.forEach(l => { if (l.from === it.id) l.from = n.id; }); A.sel = [n.id]; A.commit("Swap part");
    };
    grid.append(c);
  }
  const m = D.modal("Swap part", `Put another part where "${it.name}" is. Its notes and tap links move over.`, grid, null, { width: 640 });
};
D.textStyle = ts => {
  const body = h("div", {});
  const f = (label, el) => h("div", { cls: "row", style: { marginBottom: "10px" } }, h("span", { cls: "lbl", style: { width: "110px" } }, label), el);
  const i = (k, type = "text") => { const e = h("input", { value: ts[k], type, style: { flex: 1, height: "28px", padding: "0 8px" } }); e.onchange = () => { ts[k] = type === "number" ? +e.value : e.value; A.commit("~Text style"); }; e.onkeydown = ev => ev.stopPropagation(); return e; };
  body.append(f("Name", i("name")), f("Font", i("font")), f("Size", i("size", "number")), f("Weight", i("weight", "number")), f("Line height", i("lh", "number")), f("Letter spacing", i("ls", "number")));
  D.modal("Text style", "Every text using this style updates.", body, null, { width: 420 });
};
D.about = () => D.modal("Macaw Studio", "Version " + S.host.version, h("div", {}, h("p", {}, "A drawing board for MacawP3 ideas. Design screens, explain them with notes and tap links, then Send to Claude."), h("p", { cls: "hint" }, "Icons: Lucide (ISC licence). Font: Inter.")), null, { width: 420 });
D.helpGuide = () => D.modal("How it works", "", h("div", { style: { lineHeight: 1.6 } },
  h("ol", { style: { paddingLeft: "18px", margin: 0 } },
    h("li", {}, h("b", {}, "Start: "), "File > New design. Pick a blank phone, or copy real MacawP3 screens."),
    h("li", {}, h("b", {}, "Change it: "), "drag things to move them, drag the white squares to stretch, Delete to remove. Pick tools at the bottom (R box, T text, B button, C icon, I image). Ctrl+Z undoes anything."),
    h("li", {}, h("b", {}, "Settings: "), "the right panel has every setting of what you selected. Double-click text to type. Double-click a group to go inside it; Esc to come back out."),
    h("li", {}, h("b", {}, "Explain it: "), "press N and click something to pin a note. Press K and drag from a button to a screen to say what tapping it opens. Mark things New / Changed / Keep / Remove (right-click > Mark as)."),
    h("li", {}, h("b", {}, "Try it: "), "Preview (Ctrl+Enter) lets you click through your tap links."),
    h("li", {}, h("b", {}, "Send to Claude: "), "the orange button. It uploads pictures plus a file with every size, colour and note to the repo's designs/ folder. Then tell Claude \"check the new design\"."),
    h("li", {}, h("b", {}, "Check what Claude built: "), "Compare puts a screenshot of the real app next to your design.")),
  h("p", { cls: "hint" }, "Ctrl+K finds any action. ? shows every shortcut.")), null, { width: 620 });

/* ---------- Home ---------- */
const HM = S.home = {};
HM.el = null;
HM.close = () => { if (HM.el) HM.el.classList.add("hide"); };
HM.open = async (view = "home") => {
  D.closePop();
  if (!HM.el) { HM.el = h("div", { id: "home" }); document.getElementById("app").append(HM.el); }
  HM.el.classList.remove("hide");
  const files = await S.host.listDesigns().catch(() => []);
  const st = A.settings, starred = new Set(st.starred || []);
  let side = view;
  const draw = () => {
    HM.el.innerHTML = "";
    const nav = h("div", { cls: "side" });
    for (const [k, l, ic] of [["home", "Home", "house"], ["new", "New design", "plus"], ["recent", "All designs", "clock"], ["starred", "Starred", "star"], ["parts", "My parts", "puzzle"]]) nav.append(h("div", { cls: "li" + (side === k ? " sel" : ""), onclick: () => { side = k; draw(); } }, h("span", { cls: "ic" }, S.icon(ic, 14)), l));
    nav.append(h("div", { style: { flex: 1 } }));
    const upd = h("div", {}); nav.append(upd);
    S.host.updateState().then(u => { if (u && u.state === "ready") upd.append(h("div", { cls: "sec", style: { background: "var(--panel2)", borderRadius: "10px", border: "1px solid var(--line)" } }, h("b", {}, "Update ready"), h("div", { cls: "hint", style: { margin: "4px 0 8px" } }, `Version ${u.version} installs when you close the app.`), h("button", { cls: "pbtn sm", onclick: () => S.host.installUpdate() }, "Restart now"))); });
    if (A.doc && A.doc.screens.length) nav.append(h("button", { cls: "pbtn", style: { marginTop: "8px" }, onclick: HM.close }, S.icon("arrow-left", 14), "Back to " + A.doc.name));
    const main = h("div", { cls: "main" });
    if (side === "home" || side === "new") main.append(newDesign());
    if (side === "home" || side === "recent" || side === "starred") {
      const list = files.filter(f => side !== "starred" || starred.has(f.path)).sort((a, b) => b.mtime - a.mtime);
      main.append(h("h2", { style: { fontSize: "16px", margin: "8px 0 12px" } }, side === "starred" ? "Starred" : side === "recent" ? "All designs" : "Recent designs"));
      if (!list.length) main.append(h("div", { cls: "empty", style: { textAlign: "left", padding: 0 } }, side === "starred" ? "Star a design to keep it here." : "No designs yet. Start one above."));
      const grid = h("div", { cls: "recent" });
      for (const f of (side === "home" ? list.slice(0, 12) : list)) {
        const pic = h("div", { cls: "pic" });
        S.host.readFile(f.path).then(t => { try { const d = JSON.parse(t); const sc = d.screens[0]; if (sc) { const old = A.doc; A.doc = A.doc || d; pic.append(S.panels.thumb(sc, 220, 130)); A.doc = old; } } catch (e) {} }).catch(() => {});
        const star = h("span", { cls: "star" + (starred.has(f.path) ? " on" : ""), title: "Star", onclick: e => { e.stopPropagation(); starred.has(f.path) ? starred.delete(f.path) : starred.add(f.path); st.starred = [...starred]; A.saveSettings(); draw(); } }, S.icon("star", 16));
        const card = h("div", { cls: "rcard", onclick: () => A.openPath(f.path) }, pic, star, h("div", { cls: "meta" }, h("b", {}, f.name), h("span", {}, new Date(f.mtime).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }))));
        card.oncontextmenu = e => { e.preventDefault(); D.menuAt(e.clientX, e.clientY, [["Open", () => A.openPath(f.path)], ["Show in folder", () => S.host.showInFolder(f.path)], ["Delete (to the Recycle Bin)", async () => { if (!confirm(`Delete "${f.name}"?`)) return; await S.host.trashDesign(f.path); HM.open(side); }]]); };
        grid.append(card);
      }
      main.append(grid);
    }
    if (side === "parts") {
      main.append(h("h1", {}, "My parts"), h("p", { cls: "hint" }, "Parts you saved with Arrange > Save as my part. They're in every design's Parts tab."));
      const grid = h("div", { cls: "pgrid", style: { gridTemplateColumns: "repeat(auto-fill,minmax(160px,1fr))", padding: "12px 0" } });
      for (const p of st.myParts || []) { const c = h("div", { cls: "pcard" }, h("div", { cls: "th" }), h("div", { cls: "nm" }, p.name)); try { const el = S.renderItem(A.doc || S.newDoc(), Object.assign(S.clone(p.item), { x: 0, y: 0 })); const k = Math.min(1, 140 / p.item.w, 64 / p.item.h); el.style.position = "relative"; el.style.transform = `scale(${k})`; el.style.transformOrigin = "0 0"; c.firstChild.append(h("div", { style: { width: p.item.w * k + "px", height: p.item.h * k + "px" } }, el)); } catch (e) {} grid.append(c); }
      if (!(st.myParts || []).length) main.append(h("div", { cls: "empty", style: { textAlign: "left", padding: 0 } }, "None yet."));
      main.append(grid);
    }
    HM.el.append(nav, main);
  };
  const newDesign = () => {
    let dev = st.defaultDevice || "iphone15pro", picks = new Set(["library", "bigplayer"]), mode = "macaw";
    const wrap = h("div", {});
    const drawN = () => {
      wrap.innerHTML = "";
      wrap.append(h("h1", {}, "New design"), h("div", { cls: "hint", style: { fontSize: "13px" } }, "Pick where to start. You can add more screens later."));
      const cards = h("div", { cls: "startcards" });
      const sc = (k, title, d, icon) => h("div", { cls: "startcard", style: mode === k ? { borderColor: "var(--acc)", boxShadow: "0 0 0 1px var(--acc)" } : {}, onclick: () => { if (k === "image") return startImage(); if (k === "file") return A.openFile(); mode = k; drawN(); } }, h("div", { cls: "pic", style: k === "macaw" ? { background: "radial-gradient(120% 90% at 60% 60%,#1d4e5c,#0a1a20)" } : {} }, S.icon(icon, 34, 1.5)), h("b", {}, title), h("div", { cls: "d" }, d));
      cards.append(sc("blank", "Blank phone", "An empty screen with the MacawP3 background", "smartphone"), sc("macaw", "Copy MacawP3 screens", "Library, Queue, Artists, Big player, Settings, Lyrics", "copy"), sc("image", "Open an image", "A sketch or screenshot to trace over", "image"), sc("file", "Open a design file", "A .macaw file, yours or one from Claude", "file-up"));
      wrap.append(cards);
      const cols = h("div", { style: { display: "flex", gap: "30px", flexWrap: "wrap", marginBottom: "30px" } });
      const devs = h("div", { style: { width: "380px" } }, h("div", { cls: "section-h", style: { padding: "0 0 8px" } }, "Screen size"));
      for (const [k, d] of Object.entries(S.DEVICES).filter(([k]) => k !== "custom")) devs.append(h("div", { cls: "li dev-li" + (dev === k ? " sel" : ""), style: { cursor: "pointer" }, onclick: () => { dev = k; drawN(); } }, h("span", { cls: "ic" }, S.icon(k === "desktop" ? "monitor" : k === "ipad" ? "tablet" : k === "telegram" ? "send" : "smartphone", 14)), h("span", { cls: "nm" }, d.name), h("span", { cls: "hint" }, `${d.w} × ${d.h}`)));
      cols.append(devs);
      if (mode === "macaw") {
        const g = h("div", { cls: "pick-screens" });
        for (const [k, n] of S.MACAW_SCREENS) { const pic = h("div", { cls: "pic" }); const d0 = A.doc; if (!A.doc) A.doc = S.newDoc(); pic.append(S.panels.thumb(S.SCREEN_MAKERS[k](), 126, 196)); A.doc = d0; g.append(h("div", { cls: "ps" + (picks.has(k) ? " on" : ""), onclick: () => { picks.has(k) ? picks.delete(k) : picks.add(k); drawN(); } }, pic, h("div", {}, n))); }
        cols.append(h("div", {}, h("div", { cls: "section-h", style: { padding: "0 0 8px" } }, "Screens to copy (iPhone 15 Pro size)"), g));
      }
      wrap.append(cols);
      const nameIn = h("input", { value: "Untitled design", style: { width: "260px", height: "32px", padding: "0 10px" } }); nameIn.onkeydown = e => e.stopPropagation();
      wrap.append(h("div", { cls: "row", style: { gap: "10px", marginBottom: "30px" } }, h("span", {}, "Name"), nameIn, h("button", { cls: "pbtn p", onclick: () => create(nameIn.value.trim() || "Untitled design") }, mode === "macaw" ? `Create with ${picks.size} screen${picks.size === 1 ? "" : "s"}` : "Create")));
      const create = name => {
        const d = S.newDoc(name); A.open(d, null);
        if (mode === "macaw" && picks.size) { let x = 0; for (const [k] of S.MACAW_SCREENS.filter(([k]) => picks.has(k))) { const s = S.SCREEN_MAKERS[k](); s.x = x; s.y = 0; x += s.w + 120; A.stampOrig(s.items); d.screens.push(s); } }
        else { const s = S.newScreen(dev, { name: "Screen 1" }); d.screens.push(s); }
        A.activeScreen = d.screens[0].id; A.resetHistory(); A.save(); A.refresh(); setTimeout(() => S.canvas.zoomFit(), 50);
      };
      const startImage = () => { const d = S.newDoc("Traced design"); A.open(d, null); A.save(); S.canvas.traceImage(); };
    };
    drawN();
    return wrap;
  };
  draw();
};
})();
