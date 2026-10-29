/* Macaw Studio for Windows: a design tool for MacawP3 ideas.
   - The editor (app/) runs in one window, served at studio://app/.
   - Designs are .macaw files (JSON) in Documents\Macaw Designs. Each save also keeps a backup (last 20) in the app's data.
   - Pictures for Send to Claude are drawn by app/render.html in a hidden window and captured as PNG.
   - Send to Claude uploads to the mp3-player repo's designs/ folder with GitHub's API (a key the user pastes in Settings).
   - Updates: every build on main is published to the "studio" release on GitHub; the app updates itself from there. */
const { app, BrowserWindow, protocol, net, ipcMain, dialog, shell, clipboard, nativeImage, session, desktopCapturer, Menu, safeStorage } = require("electron");
const path = require("path"), fs = require("fs"), fsp = fs.promises;

if (!app.requestSingleInstanceLock()) { app.quit(); return; }
app.setAppUserModelId("app.macaw.studio");
protocol.registerSchemesAsPrivileged([{ scheme: "studio", privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } }]);

const APP_DIR = path.join(__dirname, "app");
const DESIGNS = process.env.MACAW_STUDIO_DESIGNS || path.join(app.getPath("documents"), "Macaw Designs");
const SENT = path.join(DESIGNS, "Sent");
const BACKUPS = path.join(app.getPath("userData"), "Backups");
const SETTINGS = path.join(app.getPath("userData"), "settings.json");
const PKG = require("./package.json");
const MIME = { html: "text/html; charset=utf-8", js: "text/javascript; charset=utf-8", css: "text/css; charset=utf-8", json: "application/json", png: "image/png", svg: "image/svg+xml", txt: "text/plain" };
const DARK = { color: "#232428", symbolColor: "#e8e9ec" }, LIGHT = { color: "#fafafb", symbolColor: "#1d1f23" };
let win = null, theme = "dark", flushed = false;

/* ---------- small file helpers ---------- */
const inside = (dir, p) => { const r = path.resolve(p); return r === path.resolve(dir) || r.startsWith(path.resolve(dir) + path.sep); };
async function writeAtomic(file, data) {   // write to a temp file, then swap it in, so a crash never leaves half a design
  await fsp.mkdir(path.dirname(file), { recursive: true });
  const tmp = file + ".tmp-" + process.pid;
  await fsp.writeFile(tmp, data);
  await fsp.rename(tmp, file);
}
const safeName = s => String(s || "Untitled design").replace(/[\\/:*?"<>|]+/g, "").replace(/\s+/g, " ").trim().slice(0, 80) || "Untitled design";
async function freePath(dir, base, ext) { let p = path.join(dir, base + ext); for (let k = 2; ; k++) { try { await fsp.access(p); p = path.join(dir, `${base} ${k}${ext}`); } catch (e) { return p; } } }

/* ---------- settings ---------- */
ipcMain.handle("settings:get", async () => { try { return JSON.parse(await fsp.readFile(SETTINGS, "utf8")); } catch (e) { return {}; } });
ipcMain.handle("settings:set", async (e, s) => { await writeAtomic(SETTINGS, JSON.stringify(s, null, 1)); });

/* ---------- designs ---------- */
ipcMain.handle("designs:list", async () => {
  await fsp.mkdir(DESIGNS, { recursive: true });
  const out = [];
  for (const n of await fsp.readdir(DESIGNS)) {
    if (!n.toLowerCase().endsWith(".macaw")) continue;
    const p = path.join(DESIGNS, n);
    try { const st = await fsp.stat(p); out.push({ path: p, name: n.replace(/\.macaw$/i, ""), mtime: st.mtimeMs, size: st.size }); } catch (e) {}
  }
  return out;
});
ipcMain.handle("designs:read", async (e, p) => {
  if (!inside(DESIGNS, p) && !inside(BACKUPS, p)) throw new Error("That file isn't in Macaw Designs");
  return fsp.readFile(p, "utf8");
});
ipcMain.handle("designs:newPath", async (e, name) => { await fsp.mkdir(DESIGNS, { recursive: true }); return freePath(DESIGNS, safeName(name), ".macaw"); });
ipcMain.handle("designs:write", async (e, p, text) => {
  if (!p || !inside(DESIGNS, p)) p = await freePath(DESIGNS, safeName(JSON.parse(text).name), ".macaw");
  await writeAtomic(p, text);
  return p;
});
ipcMain.handle("designs:rename", async (e, p, name) => {
  if (!inside(DESIGNS, p)) return p;
  const want = path.join(DESIGNS, safeName(name) + ".macaw");
  if (path.resolve(want) === path.resolve(p)) return p;
  const to = await freePath(DESIGNS, safeName(name), ".macaw");
  try { await fsp.rename(p, to); return to; } catch (x) { return p; }
});
ipcMain.handle("designs:trash", async (e, p) => { if (inside(DESIGNS, p)) await shell.trashItem(p); });
ipcMain.handle("designs:open", async () => {
  const r = await dialog.showOpenDialog(win, { title: "Open a design", filters: [{ name: "Macaw Studio design", extensions: ["macaw", "json"] }], properties: ["openFile"] });
  if (r.canceled || !r.filePaths[0]) return null;
  const p = r.filePaths[0];
  return { path: p, text: await fsp.readFile(p, "utf8"), inDesigns: inside(DESIGNS, p) };
});
ipcMain.handle("designs:saveCopy", async (e, name, text) => {
  const r = await dialog.showSaveDialog(win, { title: "Save a copy", defaultPath: path.join(app.getPath("documents"), safeName(name) + ".macaw"), filters: [{ name: "Macaw Studio design", extensions: ["macaw"] }] });
  if (r.canceled || !r.filePath) return null;
  await writeAtomic(r.filePath, text); return r.filePath;
});
/* backups: one every 2 minutes at most, the last 20 per design */
const lastBackup = {};
ipcMain.handle("backup:save", async (e, id, name, text) => {
  if (!/^[\w-]+$/.test(id)) return;
  if (Date.now() - (lastBackup[id] || 0) < 120e3) return;
  lastBackup[id] = Date.now();
  const dir = path.join(BACKUPS, id);
  await writeAtomic(path.join(dir, `${Date.now()} ${safeName(name)}.macaw`), text);
  const all = (await fsp.readdir(dir)).filter(n => n.endsWith(".macaw")).sort();
  for (const old of all.slice(0, Math.max(0, all.length - 20))) await fsp.unlink(path.join(dir, old)).catch(() => {});
});
ipcMain.handle("backup:list", async (e, id) => {
  const out = [];
  const dirs = id && /^[\w-]+$/.test(id) ? [id] : await fsp.readdir(BACKUPS).catch(() => []);
  for (const d of dirs) for (const n of await fsp.readdir(path.join(BACKUPS, d)).catch(() => [])) {
    if (!n.endsWith(".macaw")) continue;
    const m = /^(\d+) (.*)\.macaw$/.exec(n); out.push({ path: path.join(BACKUPS, d, n), name: m ? m[2] : n, mtime: m ? +m[1] : 0 });
  }
  return out.sort((a, b) => b.mtime - a.mtime).slice(0, 60);
});
ipcMain.handle("backup:read", async (e, p) => { if (!inside(BACKUPS, p)) throw new Error("not a backup"); return fsp.readFile(p, "utf8"); });

/* ---------- pictures ---------- */
let renderWin = null, renderQueue = Promise.resolve();
function getRenderWin() {
  if (renderWin && !renderWin.isDestroyed()) return Promise.resolve(renderWin);
  renderWin = new BrowserWindow({ show: false, width: 800, height: 900, frame: false, transparent: true, backgroundColor: "#00000000",
    webPreferences: { offscreen: true, preload: path.join(__dirname, "render-preload.js"), contextIsolation: true, sandbox: true } });
  renderWin.webContents.setFrameRate(10);
  return renderWin.loadURL("studio://app/render.html").then(() => renderWin);
}
ipcMain.handle("render:png", (e, job) => {
  const run = async () => {
    const w = await getRenderWin();
    const scale = Math.max(0.25, Math.min(4, +job.scale || 2));
    w.webContents.setZoomFactor(1);
    const size = await new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error("drawing took too long")), 20000);
      ipcMain.once("render:ready", (ev, s) => { clearTimeout(t); res(s); });
      w.webContents.send("render:job", job);
    });
    const W = Math.ceil(size.w * scale), H = Math.ceil(size.h * scale);
    w.setContentSize(W, H); w.webContents.setZoomFactor(scale);
    await new Promise(r => setTimeout(r, 350));
    w.webContents.invalidate();
    await new Promise(r => setTimeout(r, 150));
    const img = await w.webContents.capturePage({ x: 0, y: 0, width: W, height: H });
    return img.toPNG().toString("base64");
  };
  const p = renderQueue.then(run, run);
  renderQueue = p.catch(() => {});
  return p;
});
ipcMain.handle("file:saveAs", async (e, name, base64) => {
  const ext = path.extname(name).slice(1) || "png";
  const r = await dialog.showSaveDialog(win, { title: "Save", defaultPath: path.join(app.getPath("pictures"), safeName(name.replace(/\.[^.]+$/, "")) + "." + ext), filters: [{ name: ext.toUpperCase(), extensions: [ext] }] });
  if (r.canceled || !r.filePath) return null;
  await fsp.writeFile(r.filePath, Buffer.from(base64, "base64")); return r.filePath;
});

/* ---------- Send to Claude ---------- */
const cleanRel = p => { const parts = String(p).split("/").filter(Boolean); if (!parts.length || parts.some(x => x === "." || x === "..")) throw new Error("bad file name " + p); return parts; };
ipcMain.handle("send:folder", async (e, name, files) => {
  const dir = await freePath(SENT, safeName(name), "");
  for (const f of files) { const parts = cleanRel(f.path); await writeAtomic(path.join(dir, ...parts), f.base64 != null ? Buffer.from(f.base64, "base64") : f.text); }
  return dir;
});
async function gh(token, method, url, body) {
  const r = await net.fetch("https://api.github.com" + url, { method, headers: { Authorization: "Bearer " + token, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "MacawStudio", "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text(); let j = null; try { j = text ? JSON.parse(text) : null; } catch (x) {}
  if (!r.ok) { const msg = j && j.message || text.slice(0, 200); const err = new Error(r.status === 401 ? "GitHub didn't accept the access key (check Settings > Send to Claude)" : r.status === 403 ? "The access key can't write to this repo (it needs Contents: Read and write)" : r.status === 404 ? "GitHub can't find that repo or branch (or the key can't see it)" : `GitHub said: ${msg}`); err.status = r.status; throw err; }
  return j;
}
ipcMain.handle("send:github", async (e, o) => {
  const { token, repo, dir } = o, branch = o.branch || "main";
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo || "")) throw new Error("The repo should look like owner/name");
  const prefix = cleanRel(dir).join("/");
  const blobs = [];
  for (const f of o.files) {
    const parts = cleanRel(f.path);
    const b = await gh(token, "POST", `/repos/${repo}/git/blobs`, f.base64 != null ? { content: f.base64, encoding: "base64" } : { content: Buffer.from(f.text, "utf8").toString("base64"), encoding: "base64" });
    blobs.push({ path: prefix + "/" + parts.join("/"), mode: "100644", type: "blob", sha: b.sha });
  }
  for (let attempt = 0; attempt < 3; attempt++) {
    const ref = await gh(token, "GET", `/repos/${repo}/git/ref/heads/${encodeURIComponent(branch)}`);
    const head = await gh(token, "GET", `/repos/${repo}/git/commits/${ref.object.sha}`);
    /* files left over from an earlier send of this design are removed, so the folder matches what was sent */
    const tree = await gh(token, "GET", `/repos/${repo}/git/trees/${head.tree.sha}?recursive=1`).catch(() => ({ tree: [] }));
    const keep = new Set(blobs.map(b => b.path));
    const gone = (tree.tree || []).filter(t => t.type === "blob" && t.path.startsWith(prefix + "/") && !keep.has(t.path)).map(t => ({ path: t.path, mode: "100644", type: "blob", sha: null }));
    const nt = await gh(token, "POST", `/repos/${repo}/git/trees`, { base_tree: head.tree.sha, tree: blobs.concat(gone) });
    const c = await gh(token, "POST", `/repos/${repo}/git/commits`, { message: o.message || "Design from Macaw Studio", tree: nt.sha, parents: [ref.object.sha] });
    try { await gh(token, "PATCH", `/repos/${repo}/git/refs/heads/${encodeURIComponent(branch)}`, { sha: c.sha }); return `https://github.com/${repo}/tree/${encodeURIComponent(branch)}/${prefix.split("/").map(encodeURIComponent).join("/")}`; }
    catch (err) { if (err.status !== 422 || attempt === 2) throw err; }   // someone pushed meanwhile: try again on top of it
  }
});
ipcMain.handle("send:githubTest", async (e, s) => {
  const r = await gh(s.token, "GET", `/repos/${s.repo}`);
  if (!r.permissions || !r.permissions.push) throw new Error("Connected, but this key can only read the repo. It needs Contents: Read and write.");
  await gh(s.token, "GET", `/repos/${s.repo}/git/ref/heads/${encodeURIComponent(s.branch || "main")}`);
  return `Connected to ${r.full_name}. Designs will go to designs/ on ${s.branch || "main"}.`;
});

/* ---------- Ask Claude (the chat in the right panel) ----------
   The API key is kept encrypted by Windows (safeStorage) in the app's data folder. The editor page never gets it back. */
const KEYFILE = path.join(app.getPath("userData"), "claude-key.bin");
async function readKey() {
  try { const b = await fsp.readFile(KEYFILE); return safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(b) : b.toString("utf8"); } catch (e) { return ""; }
}
ipcMain.handle("claude:setKey", async (e, key) => {
  key = String(key || "").trim();
  if (!key) { await fsp.unlink(KEYFILE).catch(() => {}); return false; }
  await writeAtomic(KEYFILE, safeStorage.isEncryptionAvailable() ? safeStorage.encryptString(key) : Buffer.from(key, "utf8"));
  return true;
});
ipcMain.handle("claude:hasKey", async () => !!(await readKey()));
const chats = new Map();
ipcMain.handle("claude:turn", async (e, id, req) => {
  const key = await readKey();
  if (!key) return { error: "NO_KEY" };
  const Anthropic = require("@anthropic-ai/sdk");
  const client = new Anthropic({ apiKey: key });
  let stream;
  try {
    stream = client.beta.messages.stream({
      model: "claude-opus-5-5", max_tokens: 32000,
      thinking: { type: "adaptive" }, output_config: { effort: "medium" },
      cache_control: { type: "ephemeral" },
      betas: ["server-side-fallback-2026-07-01"], fallbacks: "default",   // if a request is declined, the API retries it on a suitable model by itself
      system: req.system, tools: req.tools, messages: req.messages
    });
    chats.set(id, stream);
    stream.on("text", t => { if (!e.sender.isDestroyed()) e.sender.send("claude:delta", id, t); });
    return { message: await stream.finalMessage() };
  } catch (err) {
    if (err instanceof Anthropic.APIUserAbortError) return { error: "STOPPED" };
    if (err instanceof Anthropic.AuthenticationError) return { error: "Claude didn't accept the API key. Check it in Settings > Ask Claude." };
    if (err instanceof Anthropic.PermissionDeniedError) return { error: "This API key isn't allowed to use Claude Opus 5.5." };
    if (err instanceof Anthropic.RateLimitError) return { error: "Too many requests right now (or the account is out of credit). Try again in a minute." };
    if (err instanceof Anthropic.BadRequestError) return { error: "Claude couldn't take that request: " + err.message };
    if (err instanceof Anthropic.APIConnectionError) return { error: "Can't reach Claude. Check the internet connection." };
    if (err instanceof Anthropic.APIError) return { error: `Claude had a problem (${err.status || "no status"}). Try again.` };
    return { error: "GARBLED", detail: String(err && err.message || err).slice(0, 300) };   // e.g. a tool call that didn't come through whole
  } finally { chats.delete(id); }
});
ipcMain.on("claude:stop", (e, id) => { const s = chats.get(id); if (s) s.abort(); });

/* ---------- little things ---------- */
ipcMain.handle("shell:show", async (e, p) => { if (inside(DESIGNS, p)) { const st = await fsp.stat(p).catch(() => null); if (st && st.isDirectory()) shell.openPath(p); else shell.showItemInFolder(p); } });
ipcMain.handle("shell:open", (e, url) => { if (/^https:\/\//.test(url)) shell.openExternal(url); });
ipcMain.handle("clip:write", (e, t) => clipboard.writeText(String(t)));
ipcMain.handle("clip:read", () => { const img = clipboard.readImage(); return { text: clipboard.readText(), image: img.isEmpty() ? null : img.toDataURL() }; });
ipcMain.on("ui:zoom", (e, z) => { if (win) win.webContents.setZoomFactor(Math.max(0.6, Math.min(2, +z || 1))); });
ipcMain.on("ui:theme", (e, t) => { theme = t === "light" ? "light" : "dark"; if (win && process.platform === "win32") try { win.setTitleBarOverlay(Object.assign({ height: 40 }, theme === "light" ? LIGHT : DARK)); } catch (x) {} });
ipcMain.on("ui:flushed", () => { flushed = true; if (win) win.close(); });

/* ---------- updates ---------- */
const FEED = `https://github.com/t6wy26zj95-creator/mp3-player/releases/download/${PKG.studioChannel === "preview" ? "studio-preview" : "studio"}`;
let updater = null, upd = { state: "idle" }, busy = false;
const updState = s => { upd = s; if (win && !win.isDestroyed()) win.webContents.send("studio:update", s); return s; };
ipcMain.handle("update:state", () => upd);
ipcMain.handle("update:check", () => checkUpdates(true));
ipcMain.handle("update:install", () => { if (updater && upd.state === "ready") { flushed = true; setImmediate(() => updater.quitAndInstall(true, true)); } });
function setupUpdates() {
  if (!app.isPackaged || process.platform !== "win32") return;
  try { updater = require("electron-updater").autoUpdater; } catch (e) { return; }
  updater.autoDownload = true; updater.autoInstallOnAppQuit = true; updater.logger = null;
  updater.setFeedURL({ provider: "generic", url: FEED });
  updater.on("download-progress", p => updState({ state: "downloading", version: upd.version, percent: Math.round(p.percent || 0) }));
  updater.on("update-downloaded", i => updState({ state: "ready", version: i.version }));
  updater.on("error", () => { if (upd.state === "downloading") updState({ state: "error", message: "the download stopped, it will try again later" }); });
  setTimeout(() => checkUpdates(false), 5000);
  setInterval(() => checkUpdates(false), 3 * 3600e3);
}
async function checkUpdates(byHand) {
  if (!updater) return updState({ state: "none", version: app.getVersion() });
  if (busy || upd.state === "downloading" || upd.state === "ready") return upd;
  busy = true; if (byHand) updState({ state: "checking" });
  try {
    const r = await updater.checkForUpdates();
    if (r && r.updateInfo && r.isUpdateAvailable !== false && r.updateInfo.version !== app.getVersion()) return updState({ state: "downloading", version: r.updateInfo.version, percent: 0 });
    return updState({ state: "none", version: app.getVersion() });
  } catch (e) { return updState(byHand ? { state: "error", message: String(e && e.message || e).split("\n")[0].slice(0, 120) } : { state: "idle" }); }
  finally { busy = false; }
}

/* ---------- the window ---------- */
function createWindow() {
  const o = { width: 1440, height: 900, minWidth: 1100, minHeight: 680, backgroundColor: "#18191c", title: "Macaw Studio", show: false,
    icon: path.join(__dirname, "build", "icon.png"),
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, sandbox: true, spellcheck: false, additionalArguments: ["--studio-version=" + app.getVersion()] } };
  if (process.platform === "win32") Object.assign(o, { titleBarStyle: "hidden", titleBarOverlay: Object.assign({ height: 40 }, DARK) });
  else if (process.platform === "darwin") Object.assign(o, { titleBarStyle: "hiddenInset" });
  win = new BrowserWindow(o);
  win.once("ready-to-show", () => { win.maximize(); win.show(); });
  win.loadURL("studio://app/index.html");
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https:\/\//.test(url)) shell.openExternal(url); return { action: "deny" }; });
  win.webContents.on("will-navigate", (e, url) => { if (!url.startsWith("studio://app/")) e.preventDefault(); });
  win.on("close", e => {   // let the editor save first (it has 2 seconds)
    if (flushed) return;
    e.preventDefault(); win.webContents.send("studio:flush");
    setTimeout(() => { flushed = true; if (win && !win.isDestroyed()) win.close(); }, 2000);
  });
  win.on("closed", () => { win = null; if (renderWin && !renderWin.isDestroyed()) renderWin.destroy(); });
}

app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
app.on("window-all-closed", () => app.quit());
app.whenReady().then(() => {
  Menu.setApplicationMenu(process.platform === "darwin" ? Menu.buildFromTemplate([{ role: "appMenu" }, { role: "editMenu" }, { role: "windowMenu" }]) : null);
  protocol.handle("studio", async req => {
    const u = new URL(req.url);
    const rel = decodeURIComponent(u.pathname).replace(/^\/+/, "") || "index.html";
    const file = path.join(APP_DIR, rel);
    if (!inside(APP_DIR, file)) return new Response("no", { status: 403 });
    try { const data = await fsp.readFile(file); return new Response(data, { headers: { "Content-Type": MIME[path.extname(file).slice(1)] || "application/octet-stream" } }); }
    catch (e) { return new Response("not found", { status: 404 }); }
  });
  const ses = session.defaultSession;
  ses.setPermissionRequestHandler((wc, perm, cb) => cb(["local-fonts", "clipboard-read", "clipboard-sanitized-write", "media", "display-capture"].includes(perm)));
  ses.setPermissionCheckHandler((wc, perm) => ["local-fonts", "clipboard-read", "clipboard-sanitized-write", "media", "display-capture"].includes(perm));
  ses.setDisplayMediaRequestHandler(async (req, cb) => {   // "Record a clip" records this window
    try { const id = win.getMediaSourceId(); const srcs = await desktopCapturer.getSources({ types: ["window"] }); cb({ video: srcs.find(s => s.id === id) || srcs[0] }); } catch (e) { cb({}); }
  });
  createWindow();
  setupUpdates();
});
