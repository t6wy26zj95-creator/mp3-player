/* MacawP3 for Windows and Mac: the player (index.html) in its own window.
   - The page is served at macaw://app/ (like the iOS app), so settings and playlists stay between launches, and it uses the
     same bridge as the iOS app (window.webkit.messageHandlers.macaw + window.MACAW_APP), so the song library and the
     Telegram link work the same way. Songs live in the Music\MacawP3 folder.
   - Two looks: "Floating glass" (Windows 10 2004+ and 11): no window frame, the Liquid Glass panel floats on the desktop
     and bends what is really behind it (a live capture of the screen, drawn through the glass by the GPU). "Window": a
     normal window with your wallpaper, like the web version.
   - Updates: every build on main is published to the "desktop" release on GitHub; the app checks it, downloads a new
     version in the background and offers Restart (it also installs itself the next time the app is closed). */
const { app, BrowserWindow, protocol, net, ipcMain, dialog, shell, screen, desktopCapturer, session, Menu } = require("electron");
const path = require("path"), fs = require("fs"), fsp = fs.promises, os = require("os"), crypto = require("crypto");
const { Readable } = require("stream");

const AUDIO = new Set(["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf", "m4b", "mp4", "ogg", "opus", "wma", "webm"]);
const MIME = { html: "text/html; charset=utf-8", js: "text/javascript; charset=utf-8", css: "text/css; charset=utf-8", json: "application/json",
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", svg: "image/svg+xml", ico: "image/x-icon",
  mp3: "audio/mpeg", m4a: "audio/mp4", m4b: "audio/mp4", mp4: "audio/mp4", aac: "audio/aac", wav: "audio/wav", flac: "audio/flac",
  aif: "audio/aiff", aiff: "audio/aiff", caf: "audio/x-caf", ogg: "audio/ogg", opus: "audio/ogg", webm: "audio/webm", wma: "audio/x-ms-wma" };
const ext = f => path.extname(f).slice(1).toLowerCase();
const BG = "#0b1d24";

if (!app.requestSingleInstanceLock()) { app.quit(); return; }
app.setAppUserModelId("app.macaw.player");                         // Windows: the taskbar, notifications and the media overlay name the app
protocol.registerSchemesAsPrivileged([{ scheme: "macaw", privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } }]);

/* ---------- where things are ---------- */
const WWW = fs.existsSync(path.join(__dirname, "www", "index.html")) ? path.join(__dirname, "www") : path.join(__dirname, "..");   // the repo's own index.html while developing
const LIB = process.env.MACAW_LIBRARY || path.join(app.getPath("music"), "MacawP3");
const ART = path.join(app.getPath("userData"), "Covers");
const CFG_FILE = path.join(app.getPath("userData"), "desktop.json");
let cfg = {}; try { cfg = JSON.parse(fs.readFileSync(CFG_FILE, "utf8")) || {}; } catch (e) {}
const saveCfg = () => { try { fs.writeFileSync(CFG_FILE, JSON.stringify(cfg)); } catch (e) {} };

/* Floating glass needs Windows to leave our own window out of the screen capture (WDA_EXCLUDEFROMCAPTURE, Windows 10
   version 2004 = build 19041 and later); otherwise the glass would show itself. Elsewhere the app is a normal window. */
const FLOAT_OK = process.platform === "win32" && +(os.release().split(".")[2] || 0) >= 19041 || process.env.MACAW_FORCE_FLOAT === "1";
const useFloat = () => FLOAT_OK && cfg.float !== false;

/* ---------- the song library (the same as the iOS app's, see ios/Macaw/Library.swift) ---------- */
function inLib(rel) {                                                // the file for a path the page asked for, or null if it's outside the folder
  if (typeof rel !== "string" || !rel) return null;
  const parts = rel.split("/"); if (parts.some(p => !p || p === "." || p === "..")) return null;
  const full = path.resolve(LIB, ...parts);
  return full.startsWith(path.resolve(LIB) + path.sep) ? full : null;
}
async function listLib() {
  const out = [];
  async function walk(dir) {
    let items; try { items = await fsp.readdir(dir, { withFileTypes: true }); } catch (e) { return; }
    for (const it of items) {
      if (it.name.startsWith(".")) continue;
      const full = path.join(dir, it.name);
      if (it.isDirectory()) await walk(full);
      else if (it.isFile() && AUDIO.has(ext(it.name))) {
        try { const st = await fsp.stat(full); out.push({ n: path.relative(LIB, full).split(path.sep).join("/"), s: st.size, m: Math.floor(st.mtimeMs) }); } catch (e) {}
      }
    }
  }
  await fsp.mkdir(LIB, { recursive: true }).catch(() => {});
  await walk(LIB);
  return out.sort((a, b) => (a.n < b.n ? -1 : a.n > b.n ? 1 : 0));
}
const artFile = rel => path.join(ART, crypto.createHash("sha256").update(rel).digest("hex"));
async function freeName(dest) {                                      // "Song.mp3", or "Song 2.mp3" if that's taken
  const dir = path.dirname(dest), e = path.extname(dest), stem = path.basename(dest, e);
  for (let k = 2; ; k++) { try { await fsp.access(dest); dest = path.join(dir, `${stem} ${k}${e}`); } catch (x) { return dest; } }
}
async function importPaths(paths) {                                  // copies songs (and songs inside folders) into the library
  let added = 0;
  const one = async src => {
    let st; try { st = await fsp.stat(src); } catch (e) { return; }
    if (st.isDirectory()) { for (const n of await fsp.readdir(src).catch(() => [])) await one(path.join(src, n)); return; }
    if (!AUDIO.has(ext(src))) return;
    if (path.resolve(src).startsWith(path.resolve(LIB) + path.sep)) return;   // already in the library
    let dest = path.join(LIB, path.basename(src));
    try { if ((await fsp.stat(dest)).size === st.size) return; } catch (e) {}   // the same song is already there
    dest = await freeName(dest);
    try { await fsp.copyFile(src, dest); added++; } catch (e) { console.warn("copy", src, e.message); }
  };
  await fsp.mkdir(LIB, { recursive: true }).catch(() => {});
  for (const p of paths) await one(p);
  return added;
}

/* ---------- macaw://app/ ---------- */
async function serveFile(file, req, extra) {
  let st; try { st = await fsp.stat(file); } catch (e) { return new Response("Not found", { status: 404 }); }
  const size = st.size, h = { "Content-Type": MIME[ext(file)] || "application/octet-stream", "Accept-Ranges": "bytes", ...extra };
  const m = /^bytes=(\d*)-(\d*)/.exec(req.headers.get("range") || "");
  if (m && size) {
    let s, e;
    if (m[1] === "") { s = Math.max(0, size - (+m[2] || 0)); e = size - 1; } else { s = +m[1]; e = m[2] === "" ? size - 1 : Math.min(+m[2], size - 1); }
    if (s <= e && s < size) {
      h["Content-Range"] = `bytes ${s}-${e}/${size}`; h["Content-Length"] = String(e - s + 1);
      return new Response(Readable.toWeb(fs.createReadStream(file, { start: s, end: e })), { status: 206, headers: h });
    }
  }
  h["Content-Length"] = String(size);
  return new Response(req.method === "HEAD" ? null : Readable.toWeb(fs.createReadStream(file)), { status: 200, headers: h });
}
async function handle(req) {
  const u = new URL(req.url); let p;
  try { p = decodeURIComponent(u.pathname); } catch (e) { return new Response("Bad request", { status: 400 }); }
  if (p === "/lib/list") return new Response(JSON.stringify(await listLib()), { headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
  if (p.startsWith("/lib/song/")) { const f = inLib(p.slice(10)); return f ? serveFile(f, req) : new Response("Not found", { status: 404 }); }
  if (p.startsWith("/lib/art/")) {
    const rel = p.slice(9); if (!inLib(rel)) return new Response("Not found", { status: 404 });
    try { const b = await fsp.readFile(artFile(rel)); return new Response(b, { headers: { "Content-Type": b[0] === 0x89 ? "image/png" : "image/jpeg", "Cache-Control": "max-age=31536000" } }); }
    catch (e) { return new Response("Not found", { status: 404 }); }
  }
  let rel = p.replace(/^\/+/, "") || "index.html";
  if (rel.split("/").includes("..")) return new Response("Not found", { status: 404 });
  const file = path.join(WWW, ...rel.split("/"));
  if (rel === "index.html") {                                        // the tag reader comes with the app, so songs added offline still get their names and covers
    let html = await fsp.readFile(file, "utf8");
    if (fs.existsSync(path.join(WWW, "jsmediatags.min.js"))) html = html.replace(/https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/jsmediatags\/[\d.]+\/jsmediatags\.min\.js/, "jsmediatags.min.js");
    return new Response(html, { headers: { "Content-Type": MIME.html, "Cache-Control": "no-cache" } });
  }
  return serveFile(file, req, { "Cache-Control": "no-cache" });
}

/* ---------- the window ---------- */
let win = null, floatOn = false, quitting = false;
const send = (ch, d) => { if (win && !win.isDestroyed()) win.webContents.send(ch, d); };
const callPage = (fn, ...args) => { if (win && !win.isDestroyed()) win.webContents.executeJavaScript(`window.${fn} && window.${fn}.apply(null, ${JSON.stringify(args)})`).catch(() => {}); };

function onScreen(b) { return b && screen.getAllDisplays().some(d => { const a = d.workArea; return b.x < a.x + a.width - 60 && b.x + b.width > a.x + 60 && b.y >= a.y - 10 && b.y < a.y + a.height - 60; }); }
function createWindow() {
  floatOn = useFloat();
  const wa = screen.getPrimaryDisplay().workArea, key = floatOn ? "floatBounds" : "winBounds", saved = cfg[key];
  const icon = path.join(__dirname, "build", "icon.png");
  const o = {
    show: false, title: "MacawP3", backgroundColor: floatOn ? "#00000000" : BG, icon: fs.existsSync(icon) ? icon : undefined, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, sandbox: true, backgroundThrottling: false,
      autoplayPolicy: "no-user-gesture-required", spellcheck: false }
  };
  if (floatOn) {
    /* the panel is at most 580 px wide, with 16 px of air each side for its shadow; tall enough for the big player and the lists */
    const w = 612, h = Math.min(960, wa.height - 16);
    Object.assign(o, { width: w, height: h, x: wa.x + wa.width - w - 24, y: wa.y + 8, frame: false, transparent: true, resizable: false,
      maximizable: false, fullscreenable: false, hasShadow: false, thickFrame: false });
    if (saved && onScreen({ ...saved, width: w, height: h })) { o.x = saved.x; o.y = Math.max(saved.y, screen.getDisplayMatching({ ...saved, width: w, height: h }).workArea.y); }
  } else {
    Object.assign(o, { width: 1100, height: Math.min(860, wa.height - 40), minWidth: 380, minHeight: 520, titleBarStyle: "hidden" });
    if (process.platform === "darwin") o.trafficLightPosition = { x: 14, y: 12 };
    else o.titleBarOverlay = { color: "#00000000", symbolColor: "#ffffff", height: 34 };
    if (saved && onScreen(saved)) Object.assign(o, { x: saved.x, y: saved.y, width: saved.width, height: saved.height });
  }
  const w = win = new BrowserWindow(o);
  if (floatOn) w.setContentProtection(true);                       // leaves this window out of the screen capture the glass bends (and out of screenshots)
  const fl = floatOn;
  if (!fl && cfg.winMax) w.maximize();
  w.once("ready-to-show", () => w.show());
  const remember = () => { if (w.isDestroyed() || w.isMinimized()) return; if (!fl) { cfg.winMax = w.isMaximized(); if (cfg.winMax) return saveCfg(); } cfg[key] = w.getBounds(); saveCfg(); };
  w.on("moved", remember); w.on("resized", remember); w.on("close", remember);
  let dispId = null, mvT = 0;
  const checkDisplay = () => {                                       // moved onto another screen: the glass captures that one instead
    if (w.isDestroyed()) return;
    const d = screen.getDisplayMatching(w.getBounds()); if (d.id === dispId) return;
    dispId = d.id; send("desk:display", null);
  };
  w.on("move", () => { clearTimeout(mvT); mvT = setTimeout(checkDisplay, 120); });
  w.webContents.on("did-finish-load", () => { dispId = screen.getDisplayMatching(w.getBounds()).id; });
  w.webContents.setWindowOpenHandler(({ url }) => { openOut(url); return { action: "deny" }; });
  w.webContents.on("will-navigate", (e, url) => { if (!url.startsWith("macaw://")) { e.preventDefault(); openOut(url); } });
  w.webContents.on("render-process-gone", () => { if (!quitting) setTimeout(() => !w.isDestroyed() && w.reload(), 500); });
  w.on("closed", () => { if (win === w) win = null; });
  w.loadURL("macaw://app/index.html");
}
function openOut(url) { try { if (["https:", "http:", "tg:", "mailto:"].includes(new URL(url).protocol)) shell.openExternal(url); } catch (e) {} }

/* ---------- messages from the page (the same commands as the iOS app, see ios/Macaw/PlayerViewController.swift) ---------- */
let dlBusy = 0; const dlQueue = [];
function download(id, url, name) {
  dlQueue.push({ id, url, name }); pump();
}
async function pump() {
  if (dlBusy >= 2 || !dlQueue.length) return;
  const { id, url, name } = dlQueue.shift(); dlBusy++;
  let rel = "";
  try {
    const parts = String(name).split(/[\\/]/).filter(p => p && p !== "." && p !== ".."), clean = parts.length ? parts : ["Telegram", "Song.mp3"];
    const ac = new AbortController(), t = setTimeout(() => ac.abort(), 600000);
    const r = await net.fetch(url, { signal: ac.signal });
    if (!r.ok) throw new Error("HTTP " + r.status);
    let dest = path.join(LIB, ...clean); await fsp.mkdir(path.dirname(dest), { recursive: true }); dest = await freeName(dest);
    const tmp = dest + ".part";
    await fsp.writeFile(tmp, Readable.fromWeb(r.body)); clearTimeout(t);
    await fsp.rename(tmp, dest);
    rel = path.relative(LIB, dest).split(path.sep).join("/");
  } catch (e) { console.warn("download", e.message); }
  dlBusy--; callPage("natDownloaded", id, rel, !!rel); pump();
}
ipcMain.on("macaw", async (e, m) => {
  if (!m || typeof m !== "object") return;
  switch (m.cmd) {
    case "import": {
      const r = await dialog.showOpenDialog(win, { title: "Add songs", properties: ["openFile", "multiSelections"], filters: [{ name: "Music", extensions: [...AUDIO] }] });
      if (!r.canceled && r.filePaths.length) { await importPaths(r.filePaths); callPage("natSync"); }
      break;
    }
    case "importPaths":                                              // songs (or folders) dropped on the window
      if (Array.isArray(m.paths)) { const n = await importPaths(m.paths.filter(p => typeof p === "string")); if (n) callPage("natSync"); }
      break;
    case "art": {
      if (!inLib(m.n) || typeof m.b64 !== "string") return;
      await fsp.mkdir(ART, { recursive: true }).catch(() => {});
      fsp.writeFile(artFile(m.n), Buffer.from(m.b64, "base64")).catch(() => {});
      break;
    }
    case "download": if (typeof m.id === "string" && /^https?:/.test(m.url || "") && typeof m.name === "string") download(m.id, m.url, m.name); break;
    case "delete": { const f = String(m.n || "").startsWith("Telegram/") && inLib(m.n); if (f) { fsp.unlink(f).catch(() => {}); fsp.unlink(artFile(m.n)).catch(() => {}); } break; }
    case "open": if (/^(https|tg):/i.test(m.url || "")) shell.openExternal(m.url); break;
  }
});
/* songs copied into (or deleted from) the folder outside the app show up by themselves */
let watchT = 0;
function watchLib() {
  try { fs.mkdirSync(LIB, { recursive: true }); fs.watch(LIB, { recursive: true }, (ev, f) => { if (f && (f.endsWith(".part") || !AUDIO.has(ext(f)) && path.extname(f))) return; clearTimeout(watchT); watchT = setTimeout(() => callPage("natSync"), 800); }); }
  catch (e) { console.warn("watch", e.message); }
}

/* ---------- desktop-only: window buttons, the glass's screen capture, looks, updates ---------- */
ipcMain.on("desk:info", e => {
  e.returnValue = { version: app.getVersion(), platform: process.platform, float: floatOn, floatOK: FLOAT_OK, folder: LIB, packaged: app.isPackaged };
});
ipcMain.handle("desk:display", async () => {                         // the screen under the window, and its capture source
  if (!win) return null;
  const d = screen.getDisplayMatching(win.getBounds());
  const srcs = await desktopCapturer.getSources({ types: ["screen"], thumbnailSize: { width: 0, height: 0 } });
  const s = srcs.find(x => x.display_id === String(d.id)) || srcs[0];
  return s ? { id: s.id, x: d.bounds.x, y: d.bounds.y, w: d.bounds.width, h: d.bounds.height, scale: d.scaleFactor } : null;
});
ipcMain.on("desk", (e, cmd, arg) => {
  if (!win) return;
  switch (cmd) {
    case "min": win.minimize(); break;
    case "close": win.close(); break;
    case "ignore": if (floatOn) win.setIgnoreMouseEvents(!!arg, { forward: true }); break;   // clicks on the empty, see-through parts go to whatever is behind
    case "look": {                                                   // Settings: Floating glass on/off. The window is made again (a frameless see-through window can't become a normal one)
      if (!FLOAT_OK || !!arg === floatOn) return;
      cfg.float = !!arg; saveCfg();
      const old = win; win = null; createWindow(); old.destroy();
      break;
    }
    case "folder": fsp.mkdir(LIB, { recursive: true }).finally(() => shell.openPath(LIB)); break;
    case "update-check": checkUpdates(true); break;
    case "update-install": installUpdate(); break;
  }
});

/* updates. Builds of main are published to the GitHub release "desktop", test builds (a pull request) to "desktop-preview".
   The app looks in "desktop" first; a test build also looks in "desktop-preview", so the next test build arrives as an
   update too, and once the change is merged the real build takes over by itself. Windows downloads the new version in
   the background and installs it on Restart (or the next time the app is closed). A Mac without a paid Apple signature
   can't replace itself, so there the app only says a new version is out and opens the download. */
const REL = "https://github.com/t6wy26zj95-creator/mp3-player/releases/download/";
const PKG = (() => { try { return require("./package.json"); } catch (e) { return {}; } })();
const FEEDS = [REL + "desktop"].concat(PKG.macawChannel === "preview" ? [REL + "desktop-preview"] : []);
const MAC = process.platform === "darwin";
let updater = null, upd = { state: "idle" }, updBusy = false, macURL = "";
const updState = s => { upd = s; send("desk:update", s); };
ipcMain.handle("desk:update", () => upd);
const newer = (a, b) => { const x = String(a).split(".").map(Number), y = String(b).split(".").map(Number); for (let i = 0; i < 3; i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); } return false; };
function setupUpdates() {
  if (!app.isPackaged) return;
  if (!MAC) {
    try { updater = require("electron-updater").autoUpdater; } catch (e) { return; }
    updater.autoDownload = true; updater.autoInstallOnAppQuit = true; updater.logger = null;
    updater.on("download-progress", p => updState({ state: "downloading", version: upd.version, percent: Math.round(p.percent || 0) }));
    updater.on("update-downloaded", i => updState({ state: "ready", version: i.version }));
    updater.on("error", err => { if (upd.state === "downloading") updState({ state: "error", message: "the download stopped, it will try again later" }); });
  }
  setTimeout(() => checkUpdates(false), 4000);
  setInterval(() => checkUpdates(false), 3 * 3600e3);
}
async function checkUpdates(byHand) {
  if (!app.isPackaged) { if (byHand) updState({ state: "none", version: app.getVersion() }); return; }
  if (updBusy || upd.state === "downloading" || upd.state === "ready") return send("desk:update", upd);
  updBusy = true; if (byHand) updState({ state: "checking" });
  let ok = false, why = "";
  try {
    for (const url of FEEDS) {
      if (MAC) {                                                     // the Windows build's latest.yml says which version is current; the Mac build has the same number
        try {
          const r = await net.fetch(url + "/latest.yml", { cache: "no-store" }); if (!r.ok) { why = r.status === 404 ? "" : "HTTP " + r.status; continue; }
          ok = true; const v = (/^version:\s*([\d.]+)/m.exec(await r.text()) || [])[1];
          if (v && newer(v, app.getVersion())) { macURL = url + "/MacawP3-mac.zip"; return updState({ state: "available", version: v }); }
        } catch (e) { why = e.message; }
        continue;
      }
      updater.setFeedURL({ provider: "generic", url });
      try {
        const r = await updater.checkForUpdates(); ok = true;
        if (r && r.updateInfo && (r.isUpdateAvailable ?? newer(r.updateInfo.version, app.getVersion()))) return updState({ state: "downloading", version: r.updateInfo.version, percent: 0 });   // autoDownload: on its way
      } catch (e) { if (!/404/.test(String(e && e.message))) why = String(e && e.message || e).split("\n")[0].slice(0, 120); }
    }
    updState(ok || !why ? { state: "none", version: app.getVersion() } : byHand ? { state: "error", message: why } : { state: "idle" });
  } finally { updBusy = false; }
}
function installUpdate() {
  if (MAC) { if (macURL) shell.openExternal(macURL); return; }
  if (updater && upd.state === "ready") { quitting = true; setImmediate(() => updater.quitAndInstall(true, true)); }   // silent install, then the app starts again
}

/* ---------- start ---------- */
app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); } });
app.on("before-quit", () => { quitting = true; });
app.on("window-all-closed", () => app.quit());
app.on("activate", () => { if (!win) createWindow(); });
app.whenReady().then(() => {
  Menu.setApplicationMenu(process.platform === "darwin" ? Menu.buildFromTemplate([{ role: "appMenu" }, { role: "editMenu" }, { role: "windowMenu" }]) : null);
  protocol.handle("macaw", req => handle(req).catch(e => new Response(String(e), { status: 500 })));
  const ours = u => String(u || "").startsWith("macaw://app");
  session.defaultSession.setPermissionRequestHandler((wc, perm, cb, d) => cb(ours(d && d.requestingUrl || wc.getURL()) && ["media", "display-capture", "fullscreen", "clipboard-sanitized-write"].includes(perm)));
  session.defaultSession.setPermissionCheckHandler((wc, perm, origin) => ours(origin) && ["media", "display-capture", "fullscreen", "clipboard-sanitized-write"].includes(perm));
  createWindow(); watchLib(); setupUpdates();
});
