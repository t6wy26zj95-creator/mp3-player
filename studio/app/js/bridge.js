/* The link to the Windows app (preload.js puts window.studioHost there). Opened as a plain web page (for testing),
   a stand-in keeps designs and settings in the browser's storage. */
"use strict";
(() => {
const H = window.studioHost;
const LS = {
  get: k => { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
};
const web = {
  isApp: false, version: "dev", platform: "web",
  getSettings: async () => LS.get("ms.settings") || {},
  setSettings: async s => LS.set("ms.settings", s),
  listDesigns: async () => Object.values(LS.get("ms.files") || {}).map(f => ({ path: f.path, name: f.name, mtime: f.mtime, size: f.text.length, thumb: f.thumb || "" })),
  readFile: async p => { const f = (LS.get("ms.files") || {})[p]; if (!f) throw new Error("not found"); return f.text; },
  writeDesign: async (p, text, thumb) => { const all = LS.get("ms.files") || {}; const name = JSON.parse(text).name; p = p || "web:" + name + "-" + Date.now(); all[p] = { path: p, name, text, mtime: Date.now(), thumb }; LS.set("ms.files", all); return p; },
  newDesignPath: async name => "web:" + name + "-" + Date.now(),
  renameDesign: async (p, name) => p,
  trashDesign: async p => { const all = LS.get("ms.files") || {}; delete all[p]; LS.set("ms.files", all); },
  openDialog: async () => null,
  saveCopyDialog: async (name, text) => { const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([text])); a.download = name + ".macaw"; a.click(); return null; },
  backup: async () => {}, listBackups: async () => [], readBackup: async () => "",
  renderPNG: async () => null,
  writeFolder: async (name, files) => { console.log("writeFolder", name, files.map(f => f.path)); return "web:" + name; },
  githubPush: async () => { throw new Error("GitHub upload only works in the Windows app"); },
  showInFolder: async () => {}, openExternal: async u => window.open(u, "_blank"),
  copyText: async t => { try { await navigator.clipboard.writeText(t); } catch (e) {} },
  saveFileDialog: async (name, base64) => { const a = document.createElement("a"); a.href = "data:application/octet-stream;base64," + base64; a.download = name; a.click(); return name; },
  updateState: async () => ({ state: "none" }), checkUpdates: async () => ({ state: "none" }), installUpdate: async () => {}, onUpdate: () => {},
  setZoom: z => { document.body.style.zoom = z; }, setTheme: () => {}, onMenu: () => {}, readClipboard: async () => ({ text: await navigator.clipboard.readText().catch(() => ""), image: null }),
  githubTest: async () => { throw new Error("GitHub upload only works in the Windows app"); },
  onFlush: () => {}, flushed: () => {},
  claudeSetKey: async () => false, claudeHasKey: async () => false, claudeTurn: async () => ({ error: "The chat only works in the Windows app." }), claudeStop: () => {}, onClaudeDelta: () => {}
};
S.host = H ? Object.assign({}, web, H, { isApp: true }) : web;
})();
