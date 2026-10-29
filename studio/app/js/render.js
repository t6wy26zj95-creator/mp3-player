/* The hidden picture window. It gets a job from main.js, draws it at 1x, and says how big it is.
   main.js then zooms the window to the export scale and takes the picture. */
"use strict";
(() => {
const h = S.h, out = document.getElementById("out");
document.getElementById("render-css").textContent = S.RENDER_CSS;
const px = v => v + "px";
const place = (el, x, y) => { el.style.position = "absolute"; el.style.left = px(x); el.style.top = px(y); return el; };

/* every note on a screen, in the order the Notes tab shows them */
function notesOf(doc, sc) {
  const out = [];
  if (sc.note) out.push({ text: sc.note, done: !!sc.noteDone, box: null, name: "Whole screen" });
  S.walk(sc.items, it => { if (it.note && it.note.text) { const b = S.absPos(doc, it.id); out.push({ text: it.note.text, done: !!it.note.done, box: b, name: it.name }); } });
  return out;
}
function pins(doc, sc, host, ox, oy, startAt = 1) {
  const ns = notesOf(doc, sc);
  ns.forEach((n, i) => {
    const num = startAt + i;
    if (n.box) { host.append(h("div", { cls: "pinbox", style: { left: px(ox + n.box.x - 2), top: px(oy + n.box.y - 2), width: px(n.box.w + 4), height: px(n.box.h + 4) } })); host.append(h("div", { cls: "pin", style: { left: px(ox + n.box.x + n.box.w), top: px(oy + n.box.y) } }, String(num))); }
    else host.append(h("div", { cls: "pin", style: { left: px(ox + 16), top: px(oy + 16) } }, String(num)));
  });
  return ns;
}
function legend(ns, x, hgt, startAt = 1) {
  return h("div", { cls: "legend", style: { left: px(x), minHeight: px(hgt) } }, h("h3", {}, "Notes"),
    ...ns.map((n, i) => h("div", { cls: "n" + (n.done ? " done" : "") }, h("b", {}, String(startAt + i)), h("span", {}, (n.box ? n.name + ": " : "") + n.text))));
}

const draw = {
  screen(doc, job) {
    const sc = S.screenOf(doc, job.screen);
    const scr = S.renderScreen(doc, sc, { chrome: true });
    if (!job.notes) { out.append(scr); return { w: sc.w, h: sc.h }; }
    const pad = 24, sheet = h("div", { cls: "sheet" });
    sheet.append(place(scr, pad, pad));
    const ns = pins(doc, sc, sheet, pad, pad);
    const W = sc.w + pad * 2 + 300, H = sc.h + pad * 2;
    sheet.append(legend(ns, sc.w + pad * 2, H));
    Object.assign(sheet.style, { width: px(W), height: px(H) });
    out.append(sheet);
    return { w: W, h: Math.max(H, sheet.scrollHeight) };
  },
  item(doc, job) {
    const f = S.findIn(doc, job.item);
    const it = S.clone(f.item); it.x = 0; it.y = 0;
    const el = S.renderItem(doc, it, {});
    const wrap = h("div", { cls: "scr", style: { width: px(it.w), height: px(it.h), overflow: "visible", background: "transparent" } }, el);
    out.append(wrap);
    return { w: Math.ceil(it.w), h: Math.ceil(it.h) };
  },
  before(doc, job) {
    const sc = S.screenOf(doc, job.screen), orig = job.original;
    orig.device = orig.device || sc.device; orig.w = orig.w || sc.w; orig.h = orig.h || sc.h;
    const pad = 28, top = 44, gap = 56;
    const W = pad * 2 + orig.w + gap + sc.w, H = top + Math.max(orig.h, sc.h) + pad;
    const sheet = h("div", { cls: "sheet", style: { width: px(W), height: px(H) } });
    sheet.append(place(h("div", { cls: "lab" }, "Before: MacawP3 today"), pad, 14), place(h("div", { cls: "lab" }, "After: " + sc.name), pad + orig.w + gap, 14));
    sheet.append(place(S.renderScreen(doc, orig, { chrome: true }), pad, top), place(S.renderScreen(doc, sc, { chrome: true }), pad + orig.w + gap, top));
    out.append(sheet);
    return { w: W, h: H };
  },
  flow(doc, job) {
    const scs = (job.screens || doc.screens.map(s => s.id)).map(id => S.screenOf(doc, id)).filter(Boolean);
    const pad = 40, top = 34;
    const x0 = Math.min(...scs.map(s => s.x)), y0 = Math.min(...scs.map(s => s.y));
    const pos = sc => ({ x: pad + sc.x - x0, y: pad + top + sc.y - y0 });
    let W = 0, H = 0;
    for (const sc of scs) { const p = pos(sc); W = Math.max(W, p.x + sc.w + pad); H = Math.max(H, p.y + sc.h + pad); }
    const sheet = h("div", { cls: "sheet" });
    let n = 1; const allNotes = [];
    for (const sc of scs) {
      const p = pos(sc);
      sheet.append(place(h("div", { cls: "lab" }, sc.name), p.x, p.y - 26), place(S.renderScreen(doc, sc, { chrome: true }), p.x, p.y));
      if (job.notes) { const ns = pins(doc, sc, sheet, p.x, p.y, n); ns.forEach(x => x.name = sc.name + " / " + x.name); allNotes.push(...ns); n += ns.length; }
    }
    /* tap links: an arrow from the item to the screen it opens */
    const ids = new Set(scs.map(s => s.id));
    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg"); svg.setAttribute("class", "arrows"); svg.setAttribute("width", W); svg.setAttribute("height", H);
    svg.innerHTML = `<defs><marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#FF4D8D"/></marker></defs>`;
    for (const l of doc.links || []) {
      const b = S.absPos(doc, l.from), to = S.screenOf(doc, l.to);
      if (!b || !to || !ids.has(b.screen.id) || !ids.has(to.id) || b.screen.id === to.id) continue;
      const ps = pos(b.screen), pt = pos(to);
      const sx = ps.x + b.x + b.w / 2, sy = ps.y + b.y + b.h / 2;
      const right = pt.x > sx, tx = right ? pt.x - 6 : pt.x + to.w + 6, ty = pt.y + Math.min(to.h / 2, 120);
      const mx = (sx + tx) / 2;
      const path = document.createElementNS(svgNS, "path");
      path.setAttribute("d", `M${sx} ${sy} C${mx} ${sy} ${mx} ${ty} ${tx} ${ty}`);
      Object.entries({ fill: "none", stroke: "#FF4D8D", "stroke-width": 3, "marker-end": "url(#ah)" }).forEach(([k, v]) => path.setAttribute(k, v));
      const dot = document.createElementNS(svgNS, "circle");
      Object.entries({ cx: sx, cy: sy, r: 5, fill: "#FF4D8D" }).forEach(([k, v]) => dot.setAttribute(k, v));
      svg.append(path, dot);
    }
    sheet.append(svg);
    if (job.notes && allNotes.length) { sheet.append(legend(allNotes, W, H)); W += 300; }
    Object.assign(sheet.style, { width: px(W), height: px(H) });
    out.append(sheet);
    return { w: W, h: Math.max(H, sheet.scrollHeight) };
  },
  async compare(doc, job) {
    const sc = S.screenOf(doc, job.screen), c = sc.compare || { image: "", marks: [] };
    const img = new Image(); img.src = c.image;
    await img.decode().catch(() => {});
    const iw = sc.w, ih = img.naturalWidth ? Math.round(img.naturalHeight * sc.w / img.naturalWidth) : sc.h;
    const pad = 28, top = 44, gap = 56;
    const W = pad * 2 + sc.w + gap + iw, H = top + Math.max(sc.h, ih) + pad;
    const sheet = h("div", { cls: "sheet", style: { width: px(W), height: px(H) } });
    sheet.append(place(h("div", { cls: "lab" }, "Design: " + sc.name), pad, 14), place(h("div", { cls: "lab" }, "Real app (differences boxed)"), pad + sc.w + gap, 14));
    sheet.append(place(S.renderScreen(doc, sc, { chrome: true }), pad, top));
    const real = place(h("div", { style: { width: px(iw), height: px(ih), overflow: "hidden", borderRadius: "24px" } }), pad + sc.w + gap, top);
    img.style.cssText = `width:${iw}px;height:${ih}px;display:block`; real.append(img);
    c.marks.forEach((m, i) => real.append(h("div", { cls: "mark", style: { left: px(m.x), top: px(m.y), width: px(m.w), height: px(m.h) } }, h("b", {}, `${i + 1}. ${m.text || ""}`))));
    real.style.overflow = "visible";
    sheet.append(real);
    out.append(sheet);
    return { w: W, h: H };
  }
};

/* wait for pictures (img tags and CSS backgrounds) and fonts */
async function settle() {
  const urls = new Set();
  out.querySelectorAll("img").forEach(i => urls.add(i.src));
  out.querySelectorAll("*").forEach(el => { const m = (el.style.background + " " + el.style.backgroundImage).match(/url\("?([^")]+)"?\)/g); if (m) m.forEach(u => urls.add(u.replace(/^url\("?|"?\)$/g, ""))); });
  await Promise.all([...urls].map(u => { const i = new Image(); i.src = u; return i.decode().catch(() => {}); }));
  if (document.fonts) await document.fonts.ready;
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
}

async function run(job) {
  out.innerHTML = "";
  let size = { w: 10, h: 10 };
  try { size = await draw[job.kind](job.doc, job); await settle(); }
  catch (e) { out.innerHTML = ""; out.append(h("div", { style: { padding: "20px", color: "#fff", background: "#400", font: "14px sans-serif", width: "400px" } }, "Could not draw this: " + e.message)); size = { w: 440, h: 60 }; }
  return { w: Math.ceil(size.w), h: Math.ceil(size.h) };
}
window.renderJob = run;   // for testing in a browser
if (window.renderHost) window.renderHost.onJob(async job => window.renderHost.ready(await run(job)));
})();
