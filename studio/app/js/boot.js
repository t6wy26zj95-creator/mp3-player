/* Start-up: settings, menus, buttons, and the first design. */
"use strict";
(async () => {
const $ = id => document.getElementById(id);
document.getElementById("render-css").textContent = S.RENDER_CSS;
A.settings = Object.assign({}, S.DEFAULT_SETTINGS, await S.host.getSettings().catch(() => ({})));
A.settings.send = Object.assign({}, S.DEFAULT_SETTINGS.send, A.settings.send);
A.applySettings();
S.dlg.buildMenubar();
S.canvas.init(); S.panels.init();
const btn = (id, icon, label, fn) => { const b = $(id); b.innerHTML = ""; b.append(S.icon(icon, 15)); if (label) b.append(label); b.onclick = fn; };
btn("b-undo", "undo-2", "", () => A.undo()); btn("b-redo", "redo-2", "", () => A.redo());
btn("b-preview", "play", "Preview", () => S.modes.preview()); btn("b-compare", "arrow-left-right", "Compare", () => S.modes.compare());
btn("b-send", "sparkles", "Send to Claude", () => S.exporter.sendDialog());
$("b-zoom").onclick = e => S.dlg.menuAt(e.clientX - 60, e.clientY + 16, ["zoomin", "zoomout", "zoomfit", "zoomsel", "-", "zoom50", "zoom100", "zoom200"]);
$("doc-title").onclick = () => A.rename();
$("st-snap").onclick = () => A.run("t-snap"); $("st-grid").onclick = () => A.run("t-gridSnap"); $("st-guides").onclick = () => A.run("t-guides"); $("st-rulers").onclick = () => A.run("t-rulers");
$("st-zoom").onclick = () => S.canvas.zoomSet(1);
window.addEventListener("keydown", e => { if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === "v" || e.key === "V")) return; A.handleKey(e); });
S.host.onMenu && S.host.onMenu(id => A.run(id));
S.host.onUpdate(u => { if (u && u.state === "ready") S.toast(`Update ${u.version} is ready. It installs when you close the app.`, false, 6000); });
S.host.onFlush(async () => { try { if (A.dirty) await A.save(); } catch (e) {} S.host.flushed(); });
window.addEventListener("beforeunload", () => { if (A.dirty) A.save(); });
if (A.settings.fontsLoaded && window.queryLocalFonts) S.panels.loadFonts().catch(() => {});
/* open the last design, or show Home */
let opened = false;
if (A.settings.openLast !== false && A.settings.lastOpen) { try { A.open(JSON.parse(await S.host.readFile(A.settings.lastOpen)), A.settings.lastOpen); opened = true; } catch (e) {} }
if (!opened) { A.doc = S.newDoc(); A.resetHistory(); A.refresh(); S.home.open(); }
})();
