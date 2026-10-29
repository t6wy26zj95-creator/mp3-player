/* Preview (click through your tap links like a rough app) and Compare (your design next to a screenshot of the real app). */
"use strict";
(() => {
const M = S.modes = {};
const h = S.h;
let el = null, timer = null;
const close = () => { if (el) { el.remove(); el = null; } clearInterval(timer); document.removeEventListener("keydown", keys, true); document.body.classList.remove("nohot"); A.refresh(); };
const keys = e => { if (e.key === "Escape" && !document.querySelector(".scrim")) { e.preventDefault(); e.stopPropagation(); close(); } if (el && el.onkey) el.onkey(e); };
const shell = (title, sub) => {
  close();
  el = h("div", { id: "mode" });
  const side = h("div", { cls: "mside" }), stage = h("div", { cls: "mstage" });
  el.append(side, stage); document.getElementById("app").append(el);
  side.append(h("div", { cls: "row", style: { marginBottom: "12px" } }, h("b", { style: { fontSize: "15px" } }, title), h("button", { cls: "pbtn sm", style: { marginLeft: "auto" }, onclick: close }, "Done (Esc)")), sub ? h("div", { cls: "hint", style: { marginBottom: "12px" } }, sub) : null);
  document.addEventListener("keydown", keys, true);
  return { side, stage };
};

/* a screen laid out for another phone size, following each item's "Pin to" setting */
M.adapt = (sc, w, hh) => {
  const c = S.clone(sc), dx = w - sc.w, dy = hh - sc.h;
  for (const it of c.items) {
    const p = it.pin || { h: "left", v: "top" };
    if (p.h === "right") it.x += dx; else if (p.h === "center") it.x += dx / 2; else if (p.h === "stretch") it.w += dx;
    if (p.v === "bottom") it.y += dy; else if (p.v === "center") it.y += dy / 2; else if (p.v === "stretch") it.h += dy;
  }
  c.w = w; c.h = hh; return c;
};

/* ---------- Preview ---------- */
M.preview = (startId) => {
  S.dlg.closePop();
  if (!A.doc.screens.length) return S.toast("Draw a screen first");
  const { side, stage } = shell("Preview", "Click the blue spots to follow your tap links. Swipes and long presses work too.");
  let cur = startId || A.activeScreen || A.doc.screens[0].id, back = [], size = null, showHot = true, showNotes = false, tone = null;
  const list = h("div", {});
  const devSel = h("select", { cls: "plain", style: { width: "100%" }, onchange: e => { size = e.target.value || null; draw(); } }, h("option", { value: "" }, "As designed"), Object.entries(S.DEVICES).filter(([k]) => k !== "custom").map(([k, d]) => h("option", { value: k }, `${d.name} (${d.w} × ${d.h})`)));
  const tg = (label, on, fn) => { const b = h("button", { cls: "tog" + (on ? " on" : "") }); b.onclick = () => { on = !on; b.classList.toggle("on", on); fn(on); }; return h("label", { cls: "row", style: { gap: "8px", cursor: "pointer", marginBottom: "8px" } }, b, label); };
  const recBtn = h("button", { cls: "pbtn sm", onclick: () => record() }, S.icon("circle-dot", 13), "Record a clip");
  side.append(h("div", { cls: "section-h", style: { padding: "0 0 6px" } }, "Screens"), list,
    h("div", { cls: "section-h", style: { padding: "14px 0 6px" } }, "Show on"), devSel, h("div", { cls: "hint", style: { margin: "4px 0 12px" } }, "Other sizes move things by their \"Pin to\" setting."),
    tg("Show clickable spots", true, v => { showHot = v; document.body.classList.toggle("nohot", !v); }), tg("Show notes", false, v => { showNotes = v; draw(); }), tg("Light wallpaper", false, v => { tone = v ? "light" : null; draw(); }),
    h("div", { cls: "row", style: { marginTop: "8px" } }, h("button", { cls: "pbtn sm", onclick: () => { if (back.length) { cur = back.pop(); draw("back"); } } }, S.icon("arrow-left", 13), "Back"), recBtn));
  const draw = (motion) => {
    list.innerHTML = "";
    for (const s of A.doc.screens) list.append(h("div", { cls: "li" + (s.id === cur ? " sel" : ""), style: { cursor: "pointer" }, onclick: () => { back.push(cur); cur = s.id; draw("fade"); } }, h("span", { cls: "nm" }, s.name), h("span", { cls: "hint" }, A.doc.links.filter(l => S.findIn(A.doc, l.from)?.screen.id === s.id).length || "")));
    let sc = S.screenOf(A.doc, cur); if (!sc) return;
    if (size) { const d = S.DEVICES[size]; sc = Object.assign(M.adapt(sc, d.w, d.h), { device: size }); }
    if (tone) sc = Object.assign(S.clone(sc), { tone });
    const d = S.DEVICES[sc.device] || S.DEVICES.custom;
    const r = stage.getBoundingClientRect(); const k = Math.min(1, (r.height - 60) / sc.h, (r.width - 60) / sc.w);
    const scr = S.renderScreen(A.doc, sc, { chrome: sc.chrome !== false });
    const frame = h("div", { cls: d.radius >= 40 ? "phone-frame" : "", style: { width: sc.w + "px", height: sc.h + "px", borderRadius: d.radius + "px", transform: `scale(${k})`, position: "relative", overflow: "hidden", boxShadow: d.radius >= 40 ? "" : "0 20px 60px rgba(0,0,0,.5)" } }, scr);
    /* hot spots */
    const pos = id => { let x = 0, y = 0; const f = S.findIn({ screens: [sc] }, id); if (!f) return null; for (const a of S.ancestors({ screens: [sc] }, id)) { x += a.x; y += a.y; } return { x: x + f.item.x, y: y + f.item.y, w: f.item.w, h: f.item.h }; };
    for (const l of A.doc.links) {
      const b = pos(l.from); if (!b) continue;
      const hot = h("div", { cls: "hot", title: `${l.on} → ${S.screenOf(A.doc, l.to)?.name}`, style: { left: b.x + "px", top: b.y + "px", width: Math.max(b.w, 20) + "px", height: Math.max(b.h, 20) + "px" } });
      const goTo = () => { if (l.motion === "back") { if (back.length) { cur = back.pop(); draw("back"); } return; } back.push(cur); cur = l.to; draw(l.motion); };
      if (l.on === "tap") hot.onclick = goTo;
      if (l.on === "hover") hot.onmouseenter = goTo;
      if (l.on === "longpress") { let t; hot.onpointerdown = () => { t = setTimeout(goTo, 500); }; hot.onpointerup = hot.onpointerleave = () => clearTimeout(t); }
      if (l.on.startsWith("swipe")) { let s0; hot.onpointerdown = e => { s0 = [e.clientX, e.clientY]; hot.setPointerCapture(e.pointerId); }; hot.onpointerup = e => { if (!s0) return; const dx = e.clientX - s0[0], dy = e.clientY - s0[1]; const dir = Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? "left" : "right") : (dy < 0 ? "up" : "down"); if (Math.hypot(dx, dy) > 40 && l.on === "swipe" + dir) goTo(); s0 = null; }; }
      scr.append(hot);
    }
    if (showNotes) S.canvas.noteOrder().filter(n => n.sc.id === cur && n.kind === "item").forEach((n, i) => { const b = pos(n.id); if (b) scr.append(h("div", { style: { position: "absolute", left: b.x + b.w + "px", top: b.y + "px", zIndex: 100001, background: "#fff6c7", color: "#3a3200", padding: "5px 8px", borderRadius: "6px", fontSize: "11px", maxWidth: "180px", boxShadow: "0 4px 12px rgba(0,0,0,.4)" } }, n.note)); });
    const anim = { slide: "sl-in", slideup: "sl-up", sheet: "sl-up", fade: "fd-in", zoom: "zm-in", popup: "zm-in", back: "fd-in" }[motion];
    if (anim) scr.style.animation = `${anim} .35s cubic-bezier(.22,1,.36,1)`;
    const hold = h("div", { style: { width: sc.w * k + "px", height: sc.h * k + "px", position: "relative" } }, h("div", { style: { position: "absolute", left: 0, top: 0, transformOrigin: "0 0" } }, frame));
    frame.style.transformOrigin = "0 0";
    stage.innerHTML = ""; stage.append(hold);
  };
  el.onkey = e => { if (e.key === "Backspace" && back.length) { cur = back.pop(); draw("back"); } };
  let rec = null;
  const record = async () => {
    if (rec) { rec.stop(); return; }
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 30 }, audio: false });
      const chunks = []; rec = new MediaRecorder(stream, { mimeType: "video/webm" });
      rec.ondataavailable = e => chunks.push(e.data);
      rec.onstop = async () => { stream.getTracks().forEach(t => t.stop()); rec = null; recBtn.lastChild.textContent = "Record a clip"; const b = new Blob(chunks, { type: "video/webm" }); const buf = new Uint8Array(await b.arrayBuffer()); let s = ""; for (let i = 0; i < buf.length; i += 32768) s += String.fromCharCode.apply(null, buf.subarray(i, i + 32768)); const p = await S.host.saveFileDialog(A.doc.name + " preview.webm", btoa(s)); if (p) S.toast("Saved the clip"); };
      rec.start(); recBtn.lastChild.textContent = "Stop recording"; S.toast("Recording. Click through, then press Stop.");
    } catch (e) { S.toast("Recording needs the Windows app", true); }
  };
  setTimeout(() => draw(), 0);
};

/* ---------- Compare ---------- */
M.compare = (sid) => {
  S.dlg.closePop();
  if (!A.doc.screens.length) return S.toast("Draw a screen first");
  const { side, stage } = shell("Compare", "Put a screenshot of the real app next to your design. Drag a box on the screenshot to mark a difference.");
  let sc = S.screenOf(A.doc, sid || A.activeScreen) || A.doc.screens[0], view = "side", strength = 50, blinkOn = false;
  const cmp = () => (sc.compare = sc.compare || { image: "", marks: [] });
  const panel = h("div", {}); side.append(panel);
  const loadImg = src => { cmp().image = src; cmp().date = Date.now(); A.commit("Compare picture"); draw(); };
  const drawSide = () => {
    panel.innerHTML = "";
    panel.append(h("div", { cls: "section-h", style: { padding: "0 0 6px" } }, "Screen"), h("select", { cls: "plain", style: { width: "100%", marginBottom: "12px" }, onchange: e => { sc = S.screenOf(A.doc, e.target.value); draw(); } }, A.doc.screens.map(s => h("option", { value: s.id, selected: s === sc }, s.name))));
    panel.append(h("div", { cls: "section-h", style: { padding: "0 0 6px" } }, "Real app picture"),
      h("div", { cls: "row" }, h("button", { cls: "pbtn sm", onclick: () => { const inp = document.getElementById("file-img"); inp.value = ""; inp.onchange = () => { const f = inp.files[0]; if (!f) return; const r = new FileReader(); r.onload = () => loadImg(r.result); r.readAsDataURL(f); }; inp.click(); } }, "Load picture…"),
        h("button", { cls: "pbtn sm", onclick: async () => { try { const d = await S.host.readClipboard(); if (d && d.image) loadImg(d.image); else S.toast("No picture on the clipboard"); } catch (e) { S.toast("Use Load picture"); } } }, "Paste")),
      h("div", { cls: "hint", style: { marginBottom: "12px" } }, cmp().image ? "Loaded " + (cmp().date ? new Date(cmp().date).toLocaleString() : "") : "Use a screenshot Claude sent, or one from your phone."));
    panel.append(h("div", { cls: "section-h", style: { padding: "0 0 6px" } }, "View"), h("div", { cls: "seg", style: { marginBottom: "8px" } }, [["side", "Side by side"], ["overlay", "Overlay"], ["slider", "Slider"], ["blink", "Blink"]].map(([v, l]) => h("span", { cls: view === v ? "on" : "", onclick: () => { view = v; draw(); } }, l))));
    if (view === "overlay") { const r = h("input", { type: "range", min: 0, max: 100, value: strength, style: { width: "100%" }, oninput: e => { strength = +e.target.value; const im = stage.querySelector(".cmp-real"); if (im) im.style.opacity = strength / 100; } }); panel.append(h("div", { cls: "hint" }, "See-through strength"), r); }
    const marks = cmp().marks;
    panel.append(h("div", { cls: "section-h", style: { padding: "14px 0 6px" } }, `Differences (${marks.length})`),
      ...marks.map((mk, i) => h("div", { cls: "li" }, h("span", { style: { color: "var(--guide)" } }, "●"), h("span", { cls: "nm", title: mk.text }, mk.text || "(no words)"), h("div", { cls: "act" }, h("span", { onclick: () => { marks.splice(i, 1); A.commit("Remove mark"); draw(); } }, S.icon("x", 12))))),
      h("div", { cls: "hint" }, "Drag a box on the real picture to mark one."),
      h("button", { cls: "pbtn c", style: { marginTop: "14px" }, disabled: !cmp().image, onclick: () => S.exporter.sendFixes(sc) }, "✦ Send fixes to Claude"));
  };
  const draw = () => {
    drawSide(); clearInterval(timer);
    const r = stage.getBoundingClientRect();
    const both = view === "side";
    const k = Math.min(1, (r.height - 70) / sc.h, (r.width - 80) / (sc.w * (both ? 2 : 1) + (both ? 60 : 0)));
    const design = S.renderScreen(A.doc, sc, { chrome: sc.chrome !== false });
    const real = cmp().image ? h("img", { cls: "cmp-real", src: cmp().image, draggable: "false", style: { width: sc.w + "px", height: "auto", display: "block" } }) : h("div", { cls: "cmp-real", style: { width: sc.w + "px", height: sc.h + "px", display: "grid", placeItems: "center", color: "var(--dim)", border: "2px dashed var(--line2)", borderRadius: "20px", boxSizing: "border-box" } }, "Load a picture of the real app");
    const realBox = h("div", { style: { position: "relative", width: sc.w + "px" } }, real);
    for (const mk of cmp().marks) realBox.append(h("div", { cls: "cmp-mark", style: { left: mk.x + "px", top: mk.y + "px", width: mk.w + "px", height: mk.h + "px" } }, h("span", {}, mk.text)));
    /* drag to mark */
    realBox.addEventListener("pointerdown", e => {
      if (!cmp().image) return; e.preventDefault();
      const br = realBox.getBoundingClientRect(), kk = br.width / sc.w;
      const x0 = (e.clientX - br.left) / kk, y0 = (e.clientY - br.top) / kk;
      const box = h("div", { cls: "cmp-mark" }); realBox.append(box);
      const mv = ev => { const x = (ev.clientX - br.left) / kk, y = (ev.clientY - br.top) / kk; Object.assign(box.style, { left: Math.min(x, x0) + "px", top: Math.min(y, y0) + "px", width: Math.abs(x - x0) + "px", height: Math.abs(y - y0) + "px" }); };
      const up = async ev => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); const x = (ev.clientX - br.left) / kk, y = (ev.clientY - br.top) / kk; if (Math.abs(x - x0) < 6 || Math.abs(y - y0) < 6) return box.remove(); const t = await S.dlg.prompt("What's different here?", "A few words for Claude", ""); if (t == null) return box.remove(); cmp().marks.push({ x: S.round(Math.min(x, x0)), y: S.round(Math.min(y, y0)), w: S.round(Math.abs(x - x0)), h: S.round(Math.abs(y - y0)), text: t }); A.commit("Mark difference"); draw(); };
      window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
    });
    const lab = t => h("div", { style: { position: "absolute", bottom: "100%", left: 0, marginBottom: "8px", color: "var(--mute)", fontWeight: 600, whiteSpace: "nowrap", fontSize: 12 / k + "px" } }, t);
    let content;
    if (view === "side") content = h("div", { style: { display: "flex", gap: "60px", alignItems: "flex-start" } }, h("div", { style: { position: "relative" } }, lab("Your design"), design), h("div", { style: { position: "relative" } }, lab("Real app"), realBox));
    else {
      const wrap = h("div", { style: { position: "relative", width: sc.w + "px", height: sc.h + "px" } }, design);
      Object.assign(realBox.style, { position: "absolute", left: 0, top: 0 });
      wrap.append(realBox);
      if (view === "overlay") real.style.opacity = strength / 100;
      if (view === "slider") {
        let pos = 0.5; realBox.style.clipPath = `inset(0 0 0 ${pos * 100}%)`;
        const handle = h("div", { style: { position: "absolute", top: "-10px", bottom: "-10px", left: pos * 100 + "%", width: "4px", marginLeft: "-2px", background: "var(--guide)", cursor: "ew-resize", zIndex: 10, borderRadius: "2px" } });
        handle.onpointerdown = e => { e.stopPropagation(); handle.setPointerCapture(e.pointerId); handle.onpointermove = ev => { const br = wrap.getBoundingClientRect(); pos = S.clamp((ev.clientX - br.left) / br.width, 0, 1); handle.style.left = pos * 100 + "%"; realBox.style.clipPath = `inset(0 0 0 ${pos * 100}%)`; }; handle.onpointerup = () => handle.onpointermove = null; };
        wrap.append(handle);
      }
      if (view === "blink") { timer = setInterval(() => { blinkOn = !blinkOn; realBox.style.visibility = blinkOn ? "visible" : "hidden"; }, 500); }
      content = h("div", { style: { position: "relative" } }, lab(view === "blink" ? "Switching every half second" : view === "slider" ? "Drag the pink line" : "Real app on top of your design"), wrap);
    }
    content.style.transform = `scale(${k})`; content.style.transformOrigin = "0 0";
    const holder = h("div", { style: { width: (view === "side" ? sc.w * 2 + 60 : sc.w) * k + "px", height: sc.h * k + "px", marginTop: "20px" } }, content);
    stage.innerHTML = ""; stage.append(holder);
  };
  setTimeout(draw, 0);
};

/* the fixes from Compare go to Claude like a design */
S.exporter.sendFixes = async sc => {
  const st = A.settings.send = Object.assign({}, S.DEFAULT_SETTINGS.send, A.settings.send);
  const c = sc.compare; if (!c || !c.image) return;
  const msg = await S.dlg.prompt("Send fixes to Claude", "Anything to add? (optional)", ""); if (msg == null) return;
  try {
    const files = [];
    const lines = [`# Fixes for "${sc.name}"`, "", "Nick compared the design with a screenshot of the real app and marked what's different.", ""];
    if (msg) lines.push("Nick says: " + msg, "");
    c.marks.forEach((m, i) => lines.push(`${i + 1}. ${m.text || "(no words)"} — box ${m.x}, ${m.y}, ${m.w} × ${m.h} on the screenshot (scaled to ${sc.w} wide)`));
    lines.push("", "Files: `compare.png` (design left, real app right, differences boxed), `design.json` (the design for this screen).");
    files.push({ path: "FIXES.md", text: lines.join("\n") });
    files.push({ path: "fixes.json", text: JSON.stringify({ screen: sc.name, message: msg || undefined, differences: c.marks.map(m => ({ says: m.text, box: { x: m.x, y: m.y, w: m.w, h: m.h } })) }, null, 2) });
    files.push({ path: "design.json", text: JSON.stringify(S.exporter.designJSON([sc], {}), null, 2) });
    const png = await S.exporter.png({ kind: "compare", screen: sc.id, scale: 1 });
    if (png) files.push({ path: "compare.png", base64: png });
    const dir = `designs/${new Date().toISOString().slice(0, 10)} ${S.exporter.slug(A.doc.name)} fixes`;
    const where = st.delivery === "github" && st.token ? await S.host.githubPush({ token: st.token, repo: st.repo, branch: st.branch, dir, files, message: `Design fixes: ${sc.name} from Macaw Studio` }) : await S.host.writeFolder(dir.replace("designs/", ""), files);
    S.exporter.sentDialog(st.delivery === "github" && st.token ? "github" : "folder", where, dir, [sc]);
  } catch (e) { S.toast("Sending failed: " + e.message, true, 6000); }
};
})();
