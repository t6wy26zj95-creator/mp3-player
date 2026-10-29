/* The bridge between the editor page and Windows: window.studioHost (used by app/js/bridge.js). */
const { contextBridge, ipcRenderer } = require("electron");
const inv = (ch, ...a) => ipcRenderer.invoke(ch, ...a);
const VERSION = (process.argv.find(a => a.startsWith("--studio-version=")) || "").split("=")[1] || "";
contextBridge.exposeInMainWorld("studioHost", {
  version: VERSION, platform: process.platform,
  getSettings: () => inv("settings:get"), setSettings: s => inv("settings:set", s),
  listDesigns: () => inv("designs:list"), readFile: p => inv("designs:read", p),
  writeDesign: (p, text) => inv("designs:write", p, text), newDesignPath: name => inv("designs:newPath", name),
  renameDesign: (p, name) => inv("designs:rename", p, name), trashDesign: p => inv("designs:trash", p),
  openDialog: () => inv("designs:open"), saveCopyDialog: (name, text) => inv("designs:saveCopy", name, text),
  backup: (id, name, text) => inv("backup:save", id, name, text), listBackups: id => inv("backup:list", id), readBackup: p => inv("backup:read", p),
  renderPNG: job => inv("render:png", job), saveFileDialog: (name, base64) => inv("file:saveAs", name, base64),
  writeFolder: (name, files) => inv("send:folder", name, files), githubPush: o => inv("send:github", o), githubTest: s => inv("send:githubTest", s),
  showInFolder: p => inv("shell:show", p), openExternal: u => inv("shell:open", u),
  copyText: t => inv("clip:write", t), readClipboard: () => inv("clip:read"),
  updateState: () => inv("update:state"), checkUpdates: () => inv("update:check"), installUpdate: () => inv("update:install"),
  onUpdate: cb => ipcRenderer.on("studio:update", (e, s) => cb(s)),
  setZoom: z => ipcRenderer.send("ui:zoom", z), setTheme: t => ipcRenderer.send("ui:theme", t),
  claudeSetKey: k => inv("claude:setKey", k), claudeHasKey: () => inv("claude:hasKey"),
  claudeTurn: (id, req) => inv("claude:turn", id, req), claudeStop: id => ipcRenderer.send("claude:stop", id),
  onClaudeDelta: cb => ipcRenderer.on("claude:delta", (e, id, t) => cb(id, t)),
  onFlush: cb => ipcRenderer.on("studio:flush", () => cb()), flushed: () => ipcRenderer.send("ui:flushed")
});
