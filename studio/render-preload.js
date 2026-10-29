/* For the hidden picture window: receive a drawing job, say when it's drawn. */
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("renderHost", {
  onJob: cb => ipcRenderer.on("render:job", (e, job) => cb(job)),
  ready: size => ipcRenderer.send("render:ready", size)
});
