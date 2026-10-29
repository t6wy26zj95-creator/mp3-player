/* Ask Claude: a chat at the bottom of the right panel. Nick can ask questions about the design, or ask Claude to change it.
   Claude sees the design through tools (look at a screen, see a picture of it) and changes it with tools
   (change, add, delete items, add screens, select). Every change is a normal undo step.
   The talking happens in main.js (claude:turn) with the key Nick pasted in Settings; this file runs the tools. */
"use strict";
(() => {
const h = S.h, C = S.chat = {};
const chats = {};   // design id -> { hist: [API messages], log: [what the chat shows] }
let busy = null;    // the request being answered
let open = true, height = 340;

/* ---------- what Claude is told ---------- */
const SYSTEM = `You are Claude, built into Macaw Studio: a design tool Nick uses on Windows to design screens for MacawP3, his music player app (a web app that also ships as a Windows app and an iPhone app).
Nick uses this chat to ask questions about his design or about UI design in general, and to ask you to change the design for him.

How to work:
- Be brief and plain. Nick likes blunt, simple answers, no jargon. A few sentences is usually right.
- Before changing anything, look at the screen (look_at_screen) so you use real ids and positions. Use see_screen when how it looks matters.
- Do what Nick asks, then say in one or two sentences what you changed. Don't redesign things he didn't ask about. If a request is unclear or would change a lot, ask first.
- Nick can undo anything you do with Ctrl+Z, so small reversible changes don't need permission.
- After changing something, select it (select_items) so Nick sees it.

The design:
- A design has screens (phones, mostly iPhone 15 Pro, 393 x 852 points). Positions are in points from the screen's top-left corner. Items can sit inside frames and groups.
- Items copied from the real MacawP3 app have status "keep" (unchanged), "changed" (edited), or "remove". New items are "new". This tells the Claude that later builds the real app what Nick wants changed.
- MacawP3's look: dark teal wallpaper, a frosted glass "Player card" (radius 40), white text in Inter, round glass buttons, accent teal #2BB3C0, gold #F2C14E, album-colour glows. Keep new things in that style unless Nick asks otherwise.
- Colours are "#RRGGBB", "rgba(r,g,b,a)", or "cover" (the playing song's album colour).`;

const PROPS = {
  name: { type: "string" },
  x: { type: "number", description: "Left edge, from the screen's top-left" }, y: { type: "number", description: "Top edge, from the screen's top-left" },
  w: { type: "number" }, h: { type: "number" },
  rotate: { type: "number", description: "Degrees" }, opacity: { type: "number", description: "0 to 100" }, hidden: { type: "boolean" },
  radius: { type: "number", description: "Corner radius" },
  fill: { description: 'A colour, "none", or a gradient {"gradient": ["#color1", "#color2"], "angle": 135}' },
  border: { description: '{"color": "...", "width": 1} or "none"' },
  text: { type: "string", description: "The words (text, button, badge, text field)" },
  text_size: { type: "number" }, text_weight: { type: "number", description: "400 regular, 600 semibold, 700 bold" },
  text_color: { type: "string" }, text_align: { type: "string", enum: ["left", "center", "right"] }, font: { type: "string" },
  icon: { type: "string", description: "A Lucide icon name, e.g. play, pause, heart, shuffle, repeat, list-music, settings" }, icon_color: { type: "string" }, icon_size: { type: "number" },
  note: { type: "string", description: "A note for later (shown as a pin). Empty string removes it." },
  status: { type: "string", enum: ["new", "changed", "keep", "remove"] }
};
const partList = () => S.PARTS.filter(p => !p.screen).map(p => `${p.id} (${p.name})`).join(", ");
const TOOLS = () => [
  { name: "look_at_screen", description: "Get a screen as JSON: every item with its id, name, kind, box {x,y,w,h} from the screen's top-left, colours, text, status, notes and children. Also lists every screen in the design. Leave screen_id out for the screen Nick is looking at.",
    input_schema: { type: "object", properties: { screen_id: { type: "string" } } } },
  { name: "see_screen", description: "Get a picture of a screen as it looks now. Use it when looks matter (spacing, colours, balance).",
    input_schema: { type: "object", properties: { screen_id: { type: "string" } } } },
  { name: "change_items", description: "Change existing items. Give only the properties to change. x and y are from the screen's top-left even for items inside groups.",
    input_schema: { type: "object", properties: { changes: { type: "array", items: { type: "object", properties: Object.assign({ id: { type: "string" } }, PROPS), required: ["id"] } } }, required: ["changes"] } },
  { name: "add_items", description: `Add new items to a screen. type is one of: ${Object.keys(S.TYPES).filter(t => t !== "group" && t !== "path").join(", ")}, or "part" to add a ready-made MacawP3 piece (give part: one of ${partList()}). Sizes default sensibly; x/y are from the screen's top-left. Returns the new ids.`,
    input_schema: { type: "object", properties: { screen_id: { type: "string" }, inside_id: { type: "string", description: "A frame to put the items in (optional)" },
      items: { type: "array", items: { type: "object", properties: Object.assign({ type: { type: "string" }, part: { type: "string" } }, PROPS), required: ["type"] } } }, required: ["items"] } },
  { name: "delete_items", description: "Delete items by id. Real MacawP3 pieces are recorded as removed on purpose.",
    input_schema: { type: "object", properties: { ids: { type: "array", items: { type: "string" } } }, required: ["ids"] } },
  { name: "add_screen", description: `Add a screen. copy_of copies a real MacawP3 screen (${S.MACAW_SCREENS.map(s => s[0]).join(", ")}); otherwise a blank phone. device is one of ${Object.keys(S.DEVICES).filter(d => d !== "custom").join(", ")} (default iphone15pro).`,
    input_schema: { type: "object", properties: { copy_of: { type: "string" }, device: { type: "string" }, name: { type: "string" } } } },
  { name: "select_items", description: "Select items on the canvas so Nick sees them.",
    input_schema: { type: "object", properties: { ids: { type: "array", items: { type: "string" } } }, required: ["ids"] } }
].map(t => Object.assign(t, { eager_input_streaming: true }));

/* where Nick is right now, sent with each message */
function context() {
  const sc = A.screen();
  const sel = A.selItems().map(i => `"${i.name}" (${i.id}, ${i.type})`);
  return `<studio_context>
Design: "${A.doc.name}". Screens: ${A.doc.screens.map(s => `"${s.name}" (${s.id}, ${s.status})`).join(", ") || "none yet"}.
Nick is looking at: ${sc ? `"${sc.name}" (${sc.id})` : "no screen"}. Selected: ${sel.length ? sel.join(", ") : "nothing"}.
</studio_context>`;
}

/* ---------- the tools ---------- */
const err = m => { throw new Error(m); };
const screenFor = id => (id ? S.screenOf(A.doc, id) || err(`No screen with id ${id}`) : A.screen() || err("There are no screens yet. Use add_screen."));
const isColor = c => typeof c === "string" && (c === "cover" || /^#[0-9a-f]{3,8}$/i.test(c) || /^rgba?\(/i.test(c));
const color = (c, what) => (isColor(c) ? c : err(`${what}: "${c}" isn't a colour`));
function applyProps(it, p) {
  const set = (path, v) => A.setProp(it, path, v, false);
  const num = (k) => { if (p[k] == null) return null; const v = +p[k]; if (!isFinite(v)) err(`${k} must be a number`); return v; };
  if (p.name != null) { it.name = String(p.name).slice(0, 60); it.nameByHand = true; }
  if (p.x != null || p.y != null) {
    const abs = S.absPos(A.doc, it.id), ox = abs.x - it.x, oy = abs.y - it.y;
    if (p.x != null) set("x", S.round(num("x") - ox, 1)); if (p.y != null) set("y", S.round(num("y") - oy, 1));
  }
  if (p.w != null) set("w", Math.max(1, S.round(num("w"), 1))); if (p.h != null) set("h", Math.max(0, S.round(num("h"), 1)));
  if (p.rotate != null) set("rot", num("rotate"));
  if (p.opacity != null) set("opacity", S.clamp(num("opacity"), 0, 100) / 100);
  if (p.hidden != null) set("hidden", !!p.hidden);
  if (p.radius != null) set("radius", Math.max(0, num("radius")));
  if (p.fill != null) {
    const f = p.fill;
    if (f === "none") set("fills", []);
    else if (typeof f === "object" && Array.isArray(f.gradient)) set("fills", [{ kind: "linear", color: color(f.gradient[0], "fill"), color2: color(f.gradient[1] || f.gradient[0], "fill"), angle: +f.angle || 180 }]);
    else set("fills", [{ kind: "solid", color: color(f, "fill") }]);
  }
  if (p.border != null) {
    if (p.border === "none") set("stroke", null);
    else if (typeof p.border === "object") set("stroke", { color: color(p.border.color || "#FFFFFF", "border"), width: +p.border.width || 1, style: "solid" });
    else err('border must be {"color", "width"} or "none"');
  }
  const hasText = it.text || ["text", "button", "badge", "input"].includes(it.type);
  for (const [k, path] of [["text", "text.content"], ["text_size", "text.size"], ["text_weight", "text.weight"], ["text_color", "text.color"], ["text_align", "text.align"], ["font", "text.font"]]) {
    if (p[k] == null) continue;
    if (!hasText) err(`"${it.name}" has no text`);
    let v = p[k];
    if (k === "text_color") v = color(v, "text_color"); else if (k === "text_size" || k === "text_weight") v = num(k); else v = String(v);
    if (k === "text") { A.nameFromText(it, it.text && it.text.content, v); it.text = it.text || {}; it.text.sample = "fixed"; }
    set(path, v);
  }
  if (p.icon != null) { const n = String(p.icon); if (n && !(window.ICONS || {})[n]) err(`There's no icon called "${n}"`); set("icon.name", n); if (!it.icon.size) it.icon.size = it.type === "icon" ? Math.min(it.w, it.h) : 18; if (!it.icon.color) it.icon.color = "#FFFFFF"; }
  if (p.icon_color != null) set("icon.color", color(p.icon_color, "icon_color"));
  if (p.icon_size != null) set("icon.size", num("icon_size"));
  if (p.note != null) it.note = p.note ? { text: String(p.note), done: false } : undefined;
  if (p.status != null) { if (!["new", "changed", "keep", "remove"].includes(p.status)) err("status must be new, changed, keep or remove"); it.status = p.status; }
  A.fitParents(it.id);
}
const done = [];   // what this reply changed, shown in the chat
const TOOL = {
  look_at_screen(i) {
    const sc = screenFor(i.screen_id);
    return JSON.stringify({ screens: A.doc.screens.map(s => ({ id: s.id, name: s.name, status: s.status })), screen: S.exporter.screenJSON(sc, { includeKeep: true }) });
  },
  async see_screen(i) {
    const sc = screenFor(i.screen_id);
    const b = await S.exporter.png({ kind: "screen", screen: sc.id, scale: 1 });
    if (!b) return "Pictures only work in the Windows app. Use look_at_screen instead.";
    return [{ type: "image", source: { type: "base64", media_type: "image/png", data: b } }, { type: "text", text: `"${sc.name}", ${sc.w} x ${sc.h}` }];
  },
  change_items(i) {
    if (!Array.isArray(i.changes) || !i.changes.length) err("changes must be a list");
    const out = [];
    for (const c of i.changes) {
      const f = c && S.findIn(A.doc, c.id);
      if (!f) { out.push(`${c && c.id}: no item with that id`); continue; }
      try { applyProps(f.item, c); out.push(`${c.id}: changed`); } catch (e) { out.push(`${c.id}: ${e.message}`); }
    }
    const n = out.filter(s => s.endsWith(": changed")).length;
    if (n) { A.commit("Claude: change " + n + " item" + (n > 1 ? "s" : "")); done.push(`Changed ${n} item${n > 1 ? "s" : ""}`); }
    return out.join("\n");
  },
  add_items(i) {
    const sc = screenFor(i.screen_id);
    const into = i.inside_id ? S.findIn(A.doc, i.inside_id) || err(`No item with id ${i.inside_id}`) : null;
    if (into && !into.item.children) err(`"${into.item.name}" can't hold other items (use a frame)`);
    if (!Array.isArray(i.items) || !i.items.length) err("items must be a list");
    const ids = [], out = [];
    for (const d of i.items) {
      try {
        let it;
        if (d.type === "part") { const p = S.PARTS.find(x => x.id === d.part && !x.screen) || err(`No part called ${d.part}`); it = S.panels.partItem(p); }
        else if (S.TYPES[d.type] && d.type !== "group" && d.type !== "path") it = S.newItem(d.type, { status: "new" });
        else err(`Unknown type ${d.type}`);
        it.status = it.status || "new"; it.x = 0; it.y = 0;
        it.name = A.uniqueName(it.name, sc);
        (into ? into.item.children : sc.items).push(it);
        applyProps(it, Object.assign({ x: d.x ?? 20, y: d.y ?? 120 }, d, { type: undefined }));
        ids.push(it.id); out.push(`${it.id}: added "${it.name}"`);
      } catch (e) { out.push(`${d && d.type}: ${e.message}`); }
    }
    if (ids.length) { A.activeScreen = sc.id; A.commit("Claude: add " + ids.length + " item" + (ids.length > 1 ? "s" : "")); done.push(`Added ${ids.length} item${ids.length > 1 ? "s" : ""}`); }
    return out.join("\n");
  },
  delete_items(i) {
    const ids = (i.ids || []).filter(id => S.findIn(A.doc, id));
    if (!ids.length) return "None of those ids exist.";
    const keep = A.sel; A.sel = ids; A.deleteSel(); A.sel = keep.filter(id => S.findIn(A.doc, id));
    A.hist[A.hi].label = "Claude: delete " + ids.length;
    done.push(`Deleted ${ids.length} item${ids.length > 1 ? "s" : ""}`);
    return `Deleted ${ids.length}.`;
  },
  add_screen(i) {
    let sc;
    if (i.copy_of) { const mk = S.SCREEN_MAKERS[i.copy_of] || err(`No MacawP3 screen called ${i.copy_of}`); sc = mk(); }
    else { const dev = i.device && S.DEVICES[i.device] ? i.device : "iphone15pro"; sc = S.newScreen(dev, { name: i.name || "New screen", status: "new" }); }
    if (i.name) sc.name = String(i.name);
    A.addScreen(sc, "Claude: add screen");
    done.push(`Added the screen "${sc.name}"`);
    return `Added "${sc.name}" with id ${sc.id}.`;
  },
  select_items(i) {
    const ids = (i.ids || []).filter(id => S.findIn(A.doc, id));
    if (!ids.length) return "None of those ids exist.";
    A.activeScreen = S.findIn(A.doc, ids[0]).screen.id; A.select(ids); S.canvas.zoomSel && S.canvas.zoomSel();
    return "Selected.";
  }
};
const validate = (name, input) => {
  if (!input || typeof input !== "object" || Array.isArray(input)) return "The input must be an object.";
  const t = TOOLS().find(x => x.name === name); if (!t) return `There's no tool called ${name}.`;
  for (const r of t.input_schema.required || []) if (input[r] == null) return `Missing ${r}.`;
  for (const [k, s] of Object.entries(t.input_schema.properties)) if (input[k] != null && s.type === "array" && !Array.isArray(input[k])) return `${k} must be a list.`;
  return null;
};

/* ---------- the conversation ---------- */
const chat = () => { const id = A.doc ? A.doc.id : "none"; return chats[id] = chats[id] || { hist: [], log: [] }; };

C.send = async text => {
  text = (text || "").trim(); if (!text || busy || !A.doc) return;
  if (!(await S.host.claudeHasKey())) { C.needKey = true; C.render(); return; }
  const c = chat(), myId = S.uid("q");
  busy = { id: myId, c };
  c.hist.push({ role: "user", content: [{ type: "text", text: context() }, { type: "text", text }] });
  c.log.push({ who: "me", text });
  let bubble = { who: "claude", text: "", acts: [] }; c.log.push(bubble);
  busy.bubble = bubble; C.render();
  let said = "";   // the text of every finished turn (the stream only shows it live)
  try {
    for (let round = 0; round < 30; round++) {
      done.length = 0;
      const r = await S.host.claudeTurn(myId, { system: SYSTEM, tools: TOOLS(), messages: c.hist });
      if (r.error) {
        if (r.error === "STOPPED") bubble.note = "Stopped.";
        else if (r.error === "NO_KEY") { C.needKey = true; c.log.pop(); }
        else if (r.error === "GARBLED") bubble.note = "Claude's reply didn't come through whole. Ask again.";
        else bubble.note = r.error;
        break;
      }
      const m = r.message;
      c.hist.push({ role: "assistant", content: m.content });   // kept exactly as sent back (thinking blocks included)
      const words = m.content.filter(b => b.type === "text").map(b => b.text).join("").trim();
      if (words) said += (said ? "\n\n" : "") + words;
      bubble.text = said;
      if (m.stop_reason === "refusal") { bubble.note = "Claude declined that one."; break; }
      if (m.stop_reason === "max_tokens") { bubble.note = "The answer got too long and was cut off. Ask for less at once."; if (m.content.some(b => b.type === "tool_use")) c.hist.push({ role: "user", content: m.content.filter(b => b.type === "tool_use").map(b => ({ type: "tool_result", tool_use_id: b.id, is_error: true, content: "Cut off before it finished. Not run." })) }); break; }
      const calls = m.content.filter(b => b.type === "tool_use");
      if (m.stop_reason !== "tool_use" || !calls.length) break;
      const results = [];
      for (const b of calls) {
        const bad = validate(b.name, b.input);
        if (bad) { results.push({ type: "tool_result", tool_use_id: b.id, is_error: true, content: JSON.stringify({ INVALID_INPUT: bad }) }); continue; }
        try { results.push({ type: "tool_result", tool_use_id: b.id, content: await TOOL[b.name](b.input) }); }
        catch (e) { results.push({ type: "tool_result", tool_use_id: b.id, is_error: true, content: e.message }); }
      }
      bubble.acts.push(...done);
      c.hist.push({ role: "user", content: results });
      if (busy.stopped) { bubble.note = "Stopped."; break; }
      if (said) bubble.text = said + "\n\n";
      C.render();
    }
  } catch (e) { bubble.note = "Something went wrong: " + e.message; }
  busy = null; C.render();
};
C.stop = () => { if (busy) { busy.stopped = true; S.host.claudeStop(busy.id); } };
C.clear = () => { if (busy) return; const c = chat(); c.hist = []; c.log = []; C.render(); };
S.host.onClaudeDelta((id, t) => { if (busy && busy.id === id) { busy.bubble.text += t; C.renderLast(); } });

/* ---------- the panel ---------- */
let el, list, input;
const md = s => {   // tiny markdown: **bold**, `code`, bullet lists, paragraphs
  const esc = t => t.replace(/[&<>]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[ch]));
  const inline = t => esc(t).replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>").replace(/`([^`]+)`/g, "<code>$1</code>");
  const out = []; let para = [], list = null;
  const flushP = () => { if (para.length) out.push("<p>" + para.map(inline).join("<br>") + "</p>"); para = []; };
  const flushL = () => { if (list) out.push("<ul>" + list.map(l => "<li>" + inline(l) + "</li>").join("") + "</ul>"); list = null; };
  for (const line of s.split("\n")) {
    const b = /^\s*(?:[-*\u2022]|\d+\.)\s+(.*)$/.exec(line);
    if (b) { flushP(); (list = list || []).push(b[1]); }
    else if (!line.trim()) { flushP(); flushL(); }
    else { flushL(); para.push(line); }
  }
  flushP(); flushL();
  return out.join("");
};
function bubbleEl(b) {
  if (b.who === "me") return h("div", { cls: "cm me" }, b.text);
  const d = h("div", { cls: "cm cl" });
  const body = h("div", { cls: "cm-text" }); body.innerHTML = b.text ? md(b.text) : ""; d.append(body);
  if (!b.text && busy && busy.bubble === b && !b.acts.length) d.append(h("div", { cls: "cm-think" }, h("i"), h("i"), h("i")));
  if (b.acts.length) d.append(h("div", { cls: "cm-acts" }, ...b.acts.map(a => h("span", {}, S.icon("check", 11), a))));
  if (b.note) d.append(h("div", { cls: "cm-note" }, b.note));
  return d;
}
C.renderLast = () => { if (!list) return; const c = chat(), last = list.lastElementChild; if (last && c.log.length) { last.replaceWith(bubbleEl(c.log[c.log.length - 1])); list.scrollTop = list.scrollHeight; } };
C.render = async () => {
  if (!el) return;
  el.classList.toggle("closed", !open); el.style.height = open ? height + "px" : "";
  const c = chat();
  el.querySelector(".chat-clear").style.visibility = c.log.length && !busy ? "visible" : "hidden";
  if (!open) return;
  list.innerHTML = "";
  if (C.needKey && !(await S.host.claudeHasKey())) {
    const k = h("input", { type: "password", placeholder: "sk-ant-…" }); k.onkeydown = e => { e.stopPropagation(); if (e.key === "Enter") go(); };
    const go = async () => { if (!k.value.trim()) return; await S.host.claudeSetKey(k.value); C.needKey = false; S.toast("Key saved"); C.render(); };
    list.append(h("div", { cls: "chat-empty" }, h("b", {}, "Paste a Claude API key to start"),
      h("div", {}, "Get one at ", h("a", { href: "#", onclick: e => { e.preventDefault(); S.host.openExternal("https://console.anthropic.com/settings/keys"); } }, "console.anthropic.com"), ". It's billed by use: a question costs a few cents, a big redesign more."),
      h("div", { cls: "row", style: { marginTop: "8px" } }, h("div", { cls: "fld" }, k), h("button", { cls: "pbtn c sm", onclick: go }, "Save")),
      h("div", { cls: "hint" }, "Kept encrypted on this PC. Change it in Settings > Ask Claude.")));
  } else if (!c.log.length) {
    list.append(h("div", { cls: "chat-empty" }, h("b", {}, "Ask Claude anything"),
      h("div", {}, "Questions about your design, or things to change. Claude sees your screens and what you have selected."),
      ...["Make the play button bigger", "Does this screen look balanced?", "Add a shuffle button next to play"].map(t => h("div", { cls: "chat-idea", onclick: () => { input.value = t; input.focus(); } }, t)),
      h("div", { cls: "hint" }, "Ctrl+Z undoes anything Claude changes.")));
  } else for (const b of c.log) list.append(bubbleEl(b));
  list.scrollTop = list.scrollHeight;
  el.querySelector(".chat-send").replaceWith(busy ? h("button", { cls: "pbtn sm chat-send", title: "Stop", onclick: C.stop }, S.icon("square", 12)) : h("button", { cls: "pbtn c sm chat-send", title: "Send (Enter)", onclick: () => { const t = input.value; input.value = ""; grow(); C.send(t); } }, S.icon("arrow-up", 14)));
};
const grow = () => { input.style.height = "auto"; input.style.height = Math.min(140, input.scrollHeight) + "px"; };
C.init = () => {
  try { const s = JSON.parse(localStorage.getItem("ms.chat") || "{}"); if (s.open === false) open = false; if (s.height) height = s.height; } catch (e) {}
  const remember = () => { try { localStorage.setItem("ms.chat", JSON.stringify({ open, height })); } catch (e) {} };
  input = h("textarea", { rows: 1, placeholder: "Ask Claude…" });
  input.onkeydown = e => { e.stopPropagation(); if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); const t = input.value; input.value = ""; grow(); C.send(t); } };
  input.oninput = grow;
  list = h("div", { cls: "chat-list scroll" });
  const grip = h("div", { cls: "chat-grip", title: "Drag to resize" });
  grip.onpointerdown = e => {
    e.preventDefault(); const y0 = e.clientY, h0 = height, max = document.getElementById("right").clientHeight - 140;
    const mv = ev => { height = S.clamp(h0 + (y0 - ev.clientY), 160, Math.max(200, max)); el.style.height = height + "px"; };
    const up = () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); remember(); };
    window.addEventListener("pointermove", mv); window.addEventListener("pointerup", up);
  };
  const head = h("div", { cls: "chat-head", onclick: e => { if (e.target.closest(".chat-clear")) return; open = !open; remember(); C.render(); if (open) input.focus(); } },
    h("span", { cls: "chat-logo" }, S.icon("sparkles", 13)), h("b", {}, "Ask Claude"),
    h("span", { cls: "chat-clear", title: "Start a new chat", onclick: () => C.clear() }, S.icon("rotate-ccw", 12), "New chat"),
    h("span", { cls: "chat-chev" }, S.icon("chevron-down", 14)));
  el = h("div", { id: "chat" }, grip, head, list, h("div", { cls: "chat-input" }, input, h("button", { cls: "chat-send" })));
  document.getElementById("right").append(el);
  C.render();
};
C.focus = () => { if (!open) { open = true; C.render(); } input.focus(); };
})();
