/* The bridge between the player page and the app. It looks to the page exactly like the iOS app's bridge
   (window.MACAW_APP + window.webkit.messageHandlers.macaw), so the song library and the Telegram link work unchanged;
   MACAW_APP.desktop and window.MACAW_DESK add the desktop parts (window buttons, the glass, updates). */
const { contextBridge, ipcRenderer, webUtils } = require("electron");

const info = ipcRenderer.sendSync("desk:info");
contextBridge.exposeInMainWorld("MACAW_APP", { ...info, desktop: true, base: "macaw://app/lib/" });
contextBridge.exposeInMainWorld("webkit", { messageHandlers: { macaw: { postMessage: m => ipcRenderer.send("macaw", m) } } });
contextBridge.exposeInMainWorld("MACAW_DESK", {
  send: (cmd, arg) => ipcRenderer.send("desk", String(cmd), arg),
  display: () => ipcRenderer.invoke("desk:display"),
  update: () => ipcRenderer.invoke("desk:update"),
  on: (ch, cb) => { if (["display", "update", "near"].includes(ch)) ipcRenderer.on("desk:" + ch, (e, d) => cb(d)); }
});

/* songs (or whole folders) dropped anywhere on the window go into the library */
window.addEventListener("dragover", e => { if (e.dataTransfer && [...e.dataTransfer.types].includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; } }, true);
window.addEventListener("drop", e => {
  const files = e.dataTransfer ? [...e.dataTransfer.files] : []; if (!files.length) return;
  e.preventDefault(); e.stopPropagation();
  const paths = files.map(f => { try { return webUtils.getPathForFile(f); } catch (x) { return ""; } }).filter(Boolean);
  if (paths.length) ipcRenderer.send("macaw", { cmd: "importPaths", paths });
}, true);
