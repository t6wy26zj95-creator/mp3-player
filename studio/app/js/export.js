/* Send to Claude: the design file (design.json), a plain-language README.md, and pictures of every screen. */
"use strict";
(() => {
const X = S.exporter = {};
const h = S.h;
const r1 = v => S.round(+v || 0, 1);

/* colours as Claude reads them: "#F2C14E", "rgba(...)", or "#2BB3C0 (colour style Bright teal)" */
const col = c => {
  if (c == null) return undefined;
  if (c === "cover") return "album cover colour";
  if (typeof c === "object" && c.style) { const st = (A.doc.colorStyles || []).find(s => s.id === c.style); return st ? `${S.hexA(st.color)} (colour style "${st.name}")` : undefined; }
  return S.hexA(c);
};
const fillOut = f => {
  if (!f || f.on === false) return null;
  if (f.kind === "solid") return col(f.color) + (f.opacity != null && f.opacity < 1 ? ` at ${Math.round(f.opacity * 100)}%` : "");
  if (f.kind === "linear") return { gradient: [col(f.color), col(f.color2)], angle: f.angle ?? 180 };
  if (f.kind === "radial") return { roundGradient: [col(f.color), col(f.color2)] };
  if (f.kind === "cover") return "the playing song's album cover colours";
  if (f.kind === "image") return "an image (see the screen picture)";
};
const effOut = e => {
  if (e.on === false) return null;
  if (e.kind === "glass") return { glass: e.glass || "liquid", note: "the app's Liquid Glass / frosted panel", blur: e.blur };
  if (e.kind === "blur") return { blur: e.blur };
  const o = { [e.kind === "inner" ? "innerShadow" : e.kind]: col(e.color), x: e.x || 0, y: e.y || 0, blur: e.blur || 0 };
  if (e.spread) o.spread = e.spread; if (e.color === "cover" && e.opacity != null) o.strength = Math.round(e.opacity * 100) + "%";
  return o;
};
const clean = o => { for (const k of Object.keys(o)) { const v = o[k]; if (v === undefined || v === null || v === "" || (Array.isArray(v) && !v.length) || (typeof v === "object" && !Array.isArray(v) && !Object.keys(v).length)) delete o[k]; } return o; };
const textOut = (T) => {
  if (!T) return undefined;
  const ts = T.style && (A.doc.textStyles || []).find(s => s.id === T.style);
  const f = ts ? Object.assign({}, T, ts) : T;
  return clean({ words: T.content, fillFrom: T.sample && T.sample !== "fixed" ? { song: "the playing song's title", artist: "the artist's name", album: "the album name", time: "a time like 1:24", count: "a number" }[T.sample] : undefined,
    style: ts ? ts.name : undefined, font: f.font, size: f.size, weight: f.weight, color: col(T.color), align: T.align !== "left" ? T.align : undefined, valign: T.valign && T.valign !== "top" ? T.valign : undefined,
    lineHeight: f.lh || undefined, letterSpacing: f.ls || undefined, case: T.case || undefined, italic: T.italic || undefined, decoration: T.deco || undefined,
    tooLong: T.overflow && T.overflow !== "wrap" ? { ellipsis: "cut with …", shrink: "shrink to fit" }[T.overflow] : undefined, width: T.sizing === "hug" ? "fits the words" : undefined });
};
const linkWords = { tap: "tap", longpress: "long press", swipeleft: "swipe left", swiperight: "swipe right", swipeup: "swipe up", swipedown: "swipe down", hover: "mouse over" };
const motionWords = { instant: "instantly", slide: "slides in from the right", slideup: "slides up", fade: "fades in", zoom: "zooms out of the tapped item", sheet: "opens as a bottom sheet", popup: "opens as a pop-up", back: "goes back" };

/* one item, with its box measured from the screen's top-left corner */
X.itemJSON = (it, sc, ox = null, oy = null) => {
  if (ox == null) { const p = S.absPos(A.doc, it.id); ox = p.x - it.x; oy = p.y - it.y; }
  const x = it.x + ox, y = it.y + oy;
  const o = {
    name: it.name, kind: it.type === "rect" ? "box" : it.type === "ellipse" ? "circle" : it.type === "path" ? "drawing" : it.type, id: it.id,
    part: it.part && it.part.startsWith("macawp3:") ? it.part.slice(8) : undefined, myPart: it.partRef ? ((A.settings.myParts || []).find(p => p.id === it.partRef) || {}).name : undefined,
    status: it.status, swappedFrom: it.swappedFrom,
    box: { x: r1(x), y: r1(y), w: r1(it.w), h: r1(it.h) },
    rotate: it.rot ? r1(it.rot) : undefined, flip: it.flipX || it.flipY ? [it.flipX ? "across" : null, it.flipY ? "down" : null].filter(Boolean).join(" and ") : undefined,
    pin: it.pin && (it.pin.h !== "left" || it.pin.v !== "top") ? [it.pin.h, it.pin.v] : undefined,
    opacity: it.opacity != null && it.opacity < 1 ? Math.round(it.opacity * 100) + "%" : undefined,
    hidden: it.hidden || undefined, reference: it.reference ? "tracing image only, not part of the design" : undefined,
    fill: (it.fills || []).map(fillOut).filter(Boolean),
    border: it.stroke && it.stroke.on !== false && it.stroke.width ? clean({ color: col(it.stroke.color), width: it.stroke.width, style: it.stroke.style !== "solid" ? it.stroke.style : undefined, outside: it.stroke.pos === "outside" || undefined }) : undefined,
    radius: it.type === "ellipse" ? undefined : Array.isArray(it.radius) ? it.radius : it.radius || undefined,
    effects: (it.effects || []).map(effOut).filter(Boolean),
    text: it.text ? textOut(it.text) : undefined,
    icon: it.icon && it.icon.name ? clean({ name: it.icon.name, set: "lucide", size: it.icon.size, color: col(it.icon.color), filled: it.icon.filled || undefined, where: it.type !== "icon" && it.icon.pos !== "left" ? it.icon.pos : undefined }) : undefined,
    value: it.slider ? Math.round(it.slider.value * 100) + "%" : it.toggle ? (it.toggle.on ? "on" : "off") : undefined,
    colors: it.slider ? clean({ track: col(it.slider.track), filled: col(it.slider.fill), knob: it.slider.knobSize === 0 ? "none" : col(it.slider.knob) }) : it.toggle ? clean({ on: col(it.toggle.onColor), off: col(it.toggle.offColor), knob: col(it.toggle.knob) }) : undefined,
    image: it.type === "image" ? (it.image && it.image.src ? "an image you added (see the picture)" : "empty image box") : it.type === "cover" ? "the playing song's album art" : undefined,
    autoLayout: it.layout ? clean({ direction: it.layout.dir === "col" ? "column" : "row", gap: it.layout.gap, padding: it.layout.pad, lineUp: it.layout.align, spread: it.layout.justify !== "start" ? it.layout.justify : undefined, shrinkToFit: it.layout.hug || undefined }) : undefined,
    clipsContent: it.type === "frame" && it.clip !== false ? true : undefined,
    states: it.states && Object.keys(it.states).length ? Object.fromEntries(Object.entries(it.states).map(([k, v]) => [k, X.diffWords(it, v)])) : undefined,
    animation: it.anim && it.anim.kind !== "none" ? clean({ kind: it.anim.kind, seconds: it.anim.dur || 1, when: { tap: "when tapped", playing: "while a song plays", open: "when the screen opens", always: "all the time", hover: "on mouse over" }[it.anim.when || "tap"], description: it.anim.note }) : undefined,
    changedFrom: it.changedFrom && Object.keys(it.changedFrom).length ? X.diffWords(it.changedFrom, null, true) : undefined,
    note: it.note && it.note.text ? it.note.text + (it.note.done ? " (done)" : "") : undefined,
    opens: A.doc.links.filter(l => l.from === it.id).map(l => { const to = S.screenOf(A.doc, l.to); return `${linkWords[l.on] || l.on} → "${to ? to.name : "?"}", ${motionWords[l.motion] || l.motion}`; }),
    children: it.children && it.children.length ? it.children.map(c => X.itemJSON(c, sc, x, y)) : undefined
  };
  return clean(o);
};
/* what a state or an older look changes, in readable form */
X.diffWords = (base, over, isOld = false) => {
  const src = isOld ? base : over, o = {};
  for (const [k, v] of Object.entries(src || {})) {
    if (k === "fills") o.fill = (v || []).map(fillOut).filter(Boolean);
    else if (k === "effects") o.effects = (v || []).map(effOut).filter(Boolean);
    else if (k === "text") o.text = textOut(v);
    else if (k === "icon") o.icon = v && v.name ? { name: v.name, color: col(v.color), size: v.size } : "none";
    else if (k === "stroke") o.border = v ? { color: col(v.color), width: v.width } : "none";
    else if (["x", "y", "w", "h", "rot", "radius", "opacity", "hidden"].includes(k)) o[{ w: "width", h: "height", rot: "rotate" }[k] || k] = v;
    else if (k === "slider") o.value = v && Math.round(v.value * 100) + "%";
    else if (k === "toggle") o.value = v && (v.on ? "on" : "off");
  }
  return o;
};
/* does anything inside need Claude's attention? */
const interesting = it => it.status !== "keep" || (it.note && it.note.text) || A.doc.links.some(l => l.from === it.id) || (it.children || []).some(interesting);
X.screenJSON = (sc, o = {}) => {
  const short = it => {   // unchanged app pieces: just name, part and place, unless something inside them changed
    const j = X.itemJSON(it, sc);
    const trim = (it2, j2) => {
      if (!o.includeKeep && it2.status === "keep" && !interesting(it2)) return clean({ name: j2.name, kind: j2.kind, part: j2.part, status: "keep", box: j2.box });
      if (j2.children) j2.children = it2.children.map((c, i) => trim(c, j2.children[i]));
      return j2;
    };
    return trim(it, j);
  };
  const d = S.DEVICES[sc.device] || S.DEVICES.custom;
  return clean({
    screen: sc.name, id: sc.id, device: d.name, size: [sc.w, sc.h], status: sc.status, section: sc.section || undefined,
    basedOn: sc.basedOn ? "MacawP3 " + sc.basedOn + " screen" : undefined,
    background: sc.bg.kind === "macaw" ? `MacawP3 wallpaper (${sc.tone})` : sc.bg.kind === "color" ? col(sc.bg.color) : "an image",
    note: sc.note || undefined,
    items: sc.items.map(short).reverse(),   // front first
    removed: (sc.removed || []).map(r => clean({ name: r.name, part: r.part ? r.part.replace("macawp3:", "") : undefined, wasAt: r.box })),
    picture: o.picture
  });
};
X.slug = s => String(s).replace(/[\\/:*?"<>|#%]+/g, "").replace(/\s+/g, " ").trim().slice(0, 60) || "design";
X.fileSlug = s => X.slug(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "screen";
X.designJSON = (screens, o = {}) => {
  const ids = new Set(screens.map(s => s.id)), allItems = new Set(); for (const s of screens) S.walk(s.items, it => allItems.add(it.id));
  return clean({
    app: "Macaw Studio", format: 1, design: A.doc.name, sent: new Date().toISOString(), from: "Nick",
    message: o.message || undefined,
    howToRead: "Sizes are in points (iPhone 15 Pro is 393 × 852). box = x, y, width, height from the screen's top-left corner. status: new = a new idea to build, changed = an existing MacawP3 piece to change (changedFrom shows how it was), keep = leave as it is, remove = take it out of the app. part = the matching element in index.html. Items are listed front to back. Notes are Nick's words.",
    screens: screens.map(s => X.screenJSON(s, { includeKeep: o.includeKeep, picture: o.pictures ? `screens/${X.fileSlug(s.name)}.png` : undefined })),
    links: A.doc.links.filter(l => allItems.has(l.from)).map(l => { const f = S.findIn(A.doc, l.from), to = S.screenOf(A.doc, l.to); return { from: f.item.name, onScreen: f.screen.name, opens: to ? to.name : "?", on: linkWords[l.on] || l.on, motion: motionWords[l.motion] || l.motion }; }),
    notes: S.canvas.noteOrder().filter(n => ids.has(n.sc.id)).map((n, i) => clean({ number: i + 1, on: n.kind === "item" ? n.it.name : "the whole screen", screen: n.sc.name, note: n.note, done: n.done || undefined })),
    colorStyles: (A.doc.colorStyles || []).map(c => ({ name: c.name, color: S.hexA(c.color) })),
    textStyles: (A.doc.textStyles || []).map(t => clean({ name: t.name, font: t.font, size: t.size, weight: t.weight, lineHeight: t.lh || undefined, letterSpacing: t.ls || undefined }))
  });
};

/* README: the same thing in plain words, for a quick read */
const describeChange = it => {
  const out = [], cf = it.changedFrom || {};
  const was = (k, now, then) => out.push(`${k}: ${then} → ${now}`);
  if (cf.fills) was("fill", JSON.stringify((it.fills || []).map(fillOut)), JSON.stringify((cf.fills || []).map(fillOut)));
  if (cf.w || cf.h) was("size", `${r1(it.w)} × ${r1(it.h)}`, `${r1(cf.w ?? it.w)} × ${r1(cf.h ?? it.h)}`);
  if (cf.x != null || cf.y != null) was("position", `${r1(it.x)}, ${r1(it.y)}`, `${r1(cf.x ?? it.x)}, ${r1(cf.y ?? it.y)}`);
  if (cf.text) { const a = cf.text, b = it.text; if (a.content !== b.content) was("words", `"${b.content}"`, `"${a.content}"`); if (a.size !== b.size) was("text size", b.size, a.size); if (JSON.stringify(a.color) !== JSON.stringify(b.color)) was("text colour", col(b.color), col(a.color)); if (a.weight !== b.weight) was("weight", b.weight, a.weight); if (a.font !== b.font) was("font", b.font, a.font); }
  if (cf.effects) out.push("effects now: " + (JSON.stringify((it.effects || []).map(effOut).filter(Boolean)) || "none"));
  if (cf.radius != null) was("corners", JSON.stringify(it.radius), JSON.stringify(cf.radius));
  if (cf.stroke !== undefined) out.push("border now: " + (it.stroke ? `${col(it.stroke.color)} ${it.stroke.width}px` : "none"));
  if (cf.icon) was("icon", it.icon.name || "none", cf.icon.name || "none");
  if (cf.hidden !== undefined) out.push(it.hidden ? "hidden" : "shown");
  if (cf.rot !== undefined) was("rotation", it.rot + "°", (cf.rot || 0) + "°");
  if (cf.layout !== undefined) out.push("auto layout: " + (it.layout ? `${it.layout.dir === "col" ? "column" : "row"}, gap ${it.layout.gap}` : "removed"));
  return out;
};
X.readme = (screens, o = {}) => {
  const L = [], ids = new Set(screens.map(s => s.id));
  L.push(`# Design: ${A.doc.name}`, "", `Sent from Macaw Studio on ${new Date().toLocaleString()}.`, "");
  if (o.message) L.push("## Nick's message", "", o.message, "");
  L.push("## Screens", "");
  for (const sc of screens) {
    const d = S.DEVICES[sc.device] || S.DEVICES.custom;
    L.push(`### ${sc.name} (${sc.status})`, "", `${d.name}, ${sc.w} × ${sc.h}${sc.basedOn ? `, copied from the MacawP3 ${sc.basedOn} screen` : ""}. Picture: \`screens/${X.fileSlug(sc.name)}.png\`${o.notesPics ? ` (with note pins: \`screens/${X.fileSlug(sc.name)}.notes.png\`)` : ""}.`, "");
    if (sc.note) L.push(`Note for the whole screen: ${sc.note}`, "");
    const nw = [], ch = [], rm = [];
    const visit = (list, path) => { for (const it of list) {
      const p = S.absPos(A.doc, it.id); const where = `at ${r1(p.x)}, ${r1(p.y)}, ${r1(it.w)} × ${r1(it.h)}`;
      const part = it.part && it.part.startsWith("macawp3:") ? ` (\`${it.part.slice(8)}\`)` : "";
      const note = it.note && it.note.text ? ` Note: "${it.note.text}"` : "";
      const links = A.doc.links.filter(l => l.from === it.id).map(l => ` Tapping it: ${linkWords[l.on]} opens "${S.screenOf(A.doc, l.to)?.name}", ${motionWords[l.motion]}.`).join("");
      const states = it.states && Object.keys(it.states).length ? ` Has looks for: ${Object.keys(it.states).join(", ")}.` : "";
      const anim = it.anim && it.anim.kind !== "none" ? ` Animation: ${it.anim.kind}, ${it.anim.dur || 1}s, ${it.anim.when || "tap"}${it.anim.note ? " (" + it.anim.note + ")" : ""}.` : "";
      if (it.status === "new" && !it.reference) nw.push(`- **${it.name}** (${S.TYPES[it.type]?.label || it.type}${it.text && it.text.content ? `, "${String(it.text.content).slice(0, 60)}"` : ""}) ${where}.${note}${links}${states}${anim}`);
      else if (it.status === "changed") { const c = describeChange(it); ch.push(`- **${it.name}**${part}: ${c.length ? c.join("; ") : "see design.json"}.${note}${links}${states}${anim}`); }
      else if (it.status === "remove") rm.push(`- **${it.name}**${part}`);
      else if (note || links || states || anim) ch.push(`- **${it.name}**${part} (unchanged look):${note}${links}${states}${anim}`);
      if (it.children && it.status !== "new") visit(it.children);
    } };
    visit(sc.items.slice().reverse());
    for (const r of sc.removed || []) rm.push(`- **${r.name}**${r.part ? ` (\`${r.part.replace("macawp3:", "")}\`)` : ""}, was at ${r.box.x}, ${r.box.y}`);
    if (ch.length) L.push("Changed:", "", ...ch, "");
    if (nw.length) L.push("New:", "", ...nw, "");
    if (rm.length) L.push("Take out of the app:", "", ...rm, "");
    if (!ch.length && !nw.length && !rm.length) L.push("No changes marked on this screen.", "");
  }
  const links = A.doc.links.filter(l => { const f = S.findIn(A.doc, l.from); return f && ids.has(f.screen.id); });
  if (links.length) { L.push("## Tap links", ""); for (const l of links) { const f = S.findIn(A.doc, l.from), to = S.screenOf(A.doc, l.to); L.push(`- ${f.item.name} on "${f.screen.name}": ${linkWords[l.on]} opens "${to ? to.name : "?"}", ${motionWords[l.motion]}.`); } L.push(""); if (o.flow) L.push("All screens with their arrows: `flow.png`.", ""); }
  const notes = S.canvas.noteOrder().filter(n => ids.has(n.sc.id));
  if (notes.length) { L.push("## All notes", ""); notes.forEach((n, i) => L.push(`${i + 1}. ${n.kind === "item" ? n.it.name : "Whole screen"} (${n.sc.name})${n.done ? " [done]" : ""}: ${n.note}`)); L.push(""); }
  L.push("## Files", "", "- `design.json`: every item with exact sizes, colours, fonts, notes and links. The source of truth.", "- `screens/`: a picture of each screen" + (o.notesPics ? ", plus one with numbered note pins" : "") + ".");
  if (o.before) L.push("- `before-after/`: the original MacawP3 screen next to the new design.");
  L.push(`- \`${X.fileSlug(A.doc.name)}.macaw\`: the editable design. Open it in Macaw Studio.`, "");
  return L.join("\n");
};

/* ---------- pictures ---------- */
const docForRender = () => JSON.parse(JSON.stringify(A.doc, (k, v) => k === "versions" ? undefined : v));
X.png = async job => { const r = await S.host.renderPNG(Object.assign({ doc: docForRender(), scale: 2 }, job)); return r; };

/* ---------- Send to Claude ---------- */
X.sendDialog = () => {
  if (!A.doc || !A.doc.screens.length) return S.toast("Draw a screen first");
  const st = A.settings.send = Object.assign({}, S.DEFAULT_SETTINGS.send, A.settings.send);
  const picked = new Set(A.doc.screens.filter(s => s.status !== "keep" || interesting({ status: s.status, children: s.items })).map(s => s.id));
  if (!picked.size) A.doc.screens.forEach(s => picked.add(s.id));
  const inc = { pictures: true, notesPics: true, before: true, flow: A.doc.links.length > 0, mac: true, includeKeep: !!st.includeKeep };
  let delivery = st.delivery;
  const msg = h("textarea", { rows: 5, placeholder: "What should Claude do? e.g. Redo the big player like this, and add the new Queue screen." }); msg.value = A.doc.message || "";
  msg.onkeydown = e => e.stopPropagation(); msg.oninput = () => { A.doc.message = msg.value; refreshPreview(); };
  const prev = h("div", { cls: "code", style: { height: "430px", fontSize: "11px" } });
  const refreshPreview = S.debounce(() => { const scs = A.doc.screens.filter(s => picked.has(s.id)); prev.textContent = JSON.stringify(X.designJSON(scs, { message: msg.value.trim(), includeKeep: inc.includeKeep, pictures: inc.pictures }), null, 2); sendBtn.textContent = `Send ${scs.length} screen${scs.length === 1 ? "" : "s"}`; }, 150);
  const ck = (on, label, set) => h("label", { cls: "chk", style: { marginBottom: "7px" } }, h("input", { type: "checkbox", checked: on, onchange: e => { set(e.target.checked); refreshPreview(); } }), h("i"), label);
  const left = h("div", { style: { width: "300px", flex: "none" } },
    h("div", { cls: "section-h", style: { padding: "0 0 8px" } }, "Screens"),
    ...A.doc.screens.map(s => h("div", { cls: "row" }, ck(picked.has(s.id), s.name, v => v ? picked.add(s.id) : picked.delete(s.id)), h("span", { cls: "tag " + s.status, style: { marginLeft: "auto" } }, s.status))),
    h("div", { cls: "msep", style: { margin: "10px 0" } }),
    ck(inc.pictures, "Pictures of each screen (PNG)", v => inc.pictures = v),
    ck(inc.notesPics, "Pictures with the note pins drawn on", v => inc.notesPics = v),
    ck(inc.before, "Before / after (for copied MacawP3 screens)", v => inc.before = v),
    ck(inc.flow, "Flow picture (screens + tap arrows)", v => inc.flow = v),
    ck(inc.mac, "The editable .macaw design", v => inc.mac = v),
    ck(inc.includeKeep, "List unchanged items in full", v => inc.includeKeep = v),
    h("div", { cls: "section-h", style: { padding: "10px 0 6px" } }, "Message to Claude"), msg,
    h("div", { cls: "section-h", style: { padding: "12px 0 6px" } }, "Send it by"),
    h("div", { cls: "seg" }, [["github", "GitHub"], ["folder", "A folder on this PC"]].map(([v, l]) => h("span", { cls: delivery === v ? "on" : "", onclick: e => { delivery = v; e.target.parentNode.querySelectorAll("span").forEach(s => s.classList.toggle("on", s === e.target)); hint.textContent = hintText(); } }, l))),
    (() => { return h("div", {}); })());
  const hintText = () => delivery === "github" ? (st.token ? `Goes to ${st.repo} › designs/ on ${st.branch}. That folder doesn't start an app release.` : "Needs a GitHub access key first: Settings > Send to Claude.") : "Saved in Documents\\Macaw Designs\\Sent. Then drag the folder into the chat with Claude.";
  const hint = h("div", { cls: "hint", style: { marginTop: "6px" } }, hintText()); left.append(hint);
  const sendBtn = h("button", { cls: "pbtn c", onclick: () => go() }, "Send");
  const m = S.dlg.modal("✦ Send to Claude", "Packs your design so Claude can read every size, colour and note exactly.",
    h("div", { style: { display: "flex", gap: "20px" } }, left, h("div", { style: { flex: 1, minWidth: 0 } }, h("div", { cls: "section-h", style: { padding: "0 0 8px" } }, "Preview of design.json"), prev)),
    [h("button", { cls: "pbtn", onclick: () => S.dlg.settings("send") }, "Settings…"), h("span", { style: { flex: 1 } }), h("button", { cls: "pbtn", onclick: () => m.close() }, "Cancel"), sendBtn], { width: 960 });
  refreshPreview();
  const go = async () => {
    const scs = A.doc.screens.filter(s => picked.has(s.id)); if (!scs.length) return S.toast("Pick at least one screen");
    if (delivery === "github" && !st.token) { S.toast("Add a GitHub access key first", true); return S.dlg.settings("send"); }
    st.delivery = delivery; A.saveSettings(); A.doc.message = msg.value.trim(); A.markDirty();
    sendBtn.disabled = true;
    try {
      const files = await X.buildFiles(scs, Object.assign({}, inc, { message: msg.value.trim() }), t => { sendBtn.textContent = t; });
      const dir = `designs/${new Date().toISOString().slice(0, 10)} ${X.slug(A.doc.name)}`;
      let where;
      if (delivery === "github") { sendBtn.textContent = "Uploading…"; where = await S.host.githubPush({ token: st.token, repo: st.repo, branch: st.branch, dir, files, message: `Design: ${A.doc.name} (${scs.length} screen${scs.length > 1 ? "s" : ""}) from Macaw Studio` }); }
      else where = await S.host.writeFolder(dir.replace("designs/", ""), files);
      m.close(); X.sentDialog(delivery, where, dir, scs);
    } catch (e) { S.toast("Sending failed: " + e.message, true, 7000); sendBtn.disabled = false; refreshPreview(); }
  };
};
X.buildFiles = async (scs, inc, progress = () => {}) => {
  const files = [];
  const o = { message: inc.message, includeKeep: inc.includeKeep, pictures: inc.pictures, notesPics: inc.notesPics, before: inc.before, flow: inc.flow };
  files.push({ path: "design.json", text: JSON.stringify(X.designJSON(scs, o), null, 2) });
  let missing = false;
  if (inc.pictures) for (const [i, sc] of scs.entries()) {
    progress(`Drawing ${i + 1} of ${scs.length}…`);
    const a = await X.png({ kind: "screen", screen: sc.id }); if (a) files.push({ path: `screens/${X.fileSlug(sc.name)}.png`, base64: a }); else missing = true;
    if (inc.notesPics && S.canvas.noteOrder().some(n => n.sc.id === sc.id)) { const b = await X.png({ kind: "screen", screen: sc.id, notes: true }); if (b) files.push({ path: `screens/${X.fileSlug(sc.name)}.notes.png`, base64: b }); }
    if (inc.before && sc.basedOn && S.SCREEN_MAKERS[sc.basedOn]) { const c = await X.png({ kind: "before", screen: sc.id, original: S.SCREEN_MAKERS[sc.basedOn]() }); if (c) files.push({ path: `before-after/${X.fileSlug(sc.name)}.png`, base64: c }); }
  }
  if (inc.flow && A.doc.links.length) { progress("Drawing the flow…"); const f = await X.png({ kind: "flow", screens: scs.map(s => s.id), scale: 1 }); if (f) files.push({ path: "flow.png", base64: f }); }
  o.notesPics = files.some(f => f.path.endsWith(".notes.png")); o.before = files.some(f => f.path.startsWith("before-after/")); o.flow = files.some(f => f.path === "flow.png");
  files.push({ path: "README.md", text: X.readme(scs, o) + (missing ? "\n(Pictures couldn't be drawn in this copy of the studio.)\n" : "") });
  if (inc.mac) files.push({ path: `${X.fileSlug(A.doc.name)}.macaw`, text: JSON.stringify(Object.assign({}, A.doc, { versions: [] })) });
  return files;
};
X.sentDialog = (delivery, where, dir, scs) => {
  const chat = delivery === "github" ? `I sent you a design from Macaw Studio: ${dir}/ in the mp3-player repo. Read README.md and design.json there, look at the pictures, and build it.` : `I'm attaching a design from Macaw Studio (${scs.length} screen${scs.length > 1 ? "s" : ""}). Read README.md and design.json, look at the pictures, and build it.`;
  S.host.copyText(chat);
  S.dlg.modal("Sent ✓", delivery === "github" ? "It's in the repo. The message for Claude is copied, paste it in the chat." : "Saved. Drag the folder into the chat with Claude, then paste the copied message.",
    h("div", {}, h("div", { cls: "code", style: { whiteSpace: "pre-wrap" } }, chat)),
    [delivery === "github" ? h("button", { cls: "pbtn", onclick: () => S.host.openExternal(where) }, "Open on GitHub") : h("button", { cls: "pbtn", onclick: () => S.host.showInFolder(where) }, "Open the folder"), h("button", { cls: "pbtn p", onclick: () => { S.host.copyText(chat); S.toast("Copied"); } }, "Copy message again")], { width: 560 });
};

/* ---------- export a picture ---------- */
X.exportPictureDialog = (sid) => {
  if (!A.doc.screens.length) return;
  let which = sid || A.activeScreen || A.doc.screens[0].id, scale = 2, kind = "screen", notes = false;
  const body = h("div", {});
  const draw = () => {
    body.innerHTML = "";
    body.append(h("div", { cls: "row" }, h("span", { cls: "lbl" }, "What"), h("div", { cls: "fld" }, h("select", { onchange: e => { which = e.target.value; } }, [["all", "All screens on one sheet"], ...A.doc.screens.map(s => [s.id, s.name])].map(([v, l]) => h("option", { value: v, selected: v === which }, l))))));
    const its = A.selItems();
    if (its.length === 1) body.append(h("label", { cls: "chk", style: { margin: "6px 0 10px 68px" } }, h("input", { type: "checkbox", checked: kind === "item", onchange: e => { kind = e.target.checked ? "item" : "screen"; } }), h("i"), `Only "${its[0].name}"`));
    body.append(h("div", { cls: "row" }, h("span", { cls: "lbl" }, "Size"), h("div", { cls: "seg" }, [1, 2, 3].map(z => h("span", { cls: z === scale ? "on" : "", onclick: () => { scale = z; draw(); } }, z + "×")))));
    body.append(h("label", { cls: "chk", style: { margin: "6px 0 0 68px" } }, h("input", { type: "checkbox", checked: notes, onchange: e => notes = e.target.checked }), h("i"), "Draw the note pins"));
  };
  draw();
  const m = S.dlg.modal("Export picture", "Saves a PNG.", body, [h("button", { cls: "pbtn", onclick: () => m.close() }, "Cancel"), h("button", { cls: "pbtn p", onclick: async () => {
    const its = A.selItems();
    const job = kind === "item" && its[0] ? { kind: "item", item: its[0].id, scale } : which === "all" ? { kind: "flow", screens: A.doc.screens.map(s => s.id), scale, notes } : { kind: "screen", screen: which, scale, notes };
    const b = await X.png(job); if (!b) return S.toast("Pictures need the Windows app", true);
    const name = (kind === "item" ? its[0].name : which === "all" ? A.doc.name : S.screenOf(A.doc, which).name) + ".png";
    m.close(); const p = await S.host.saveFileDialog(name, b); if (p) S.toast("Saved " + p);
  } }, "Export")], { width: 420 });
};
})();
