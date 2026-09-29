#!/usr/bin/env bash
# Macaw player server: your Telegram music bot (you + invited friends, separate libraries) + the streaming API for the player.
# Runs in Docker next to your VPN and doesn't touch it. Run it again any time to update; library and settings are kept.
set -euo pipefail
DIR=/opt/macaw-player
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Please run this as root."; exit 1; }

say "Checking Docker"
command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
if ! docker compose version >/dev/null 2>&1; then
  apt-get update -qq || true
  apt-get install -y -qq docker-compose-v2 >/dev/null 2>&1 || apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || {
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; }
fi
docker compose version

mkdir -p "$DIR/app" "$DIR/data"
cd "$DIR"
if [ ! -f .env ]; then
  say "Settings (asked only the first time)"
  read -rp "Domain [macawp3.duckdns.org]: " DOMAIN </dev/tty
  DOMAIN=${DOMAIN:-macawp3.duckdns.org}
  while :; do
    read -rp "Bot token from @BotFather: " BOT_TOKEN </dev/tty
    BOT_TOKEN=$(printf '%s' "$BOT_TOKEN" | tr -d ' \r')
    if curl -fsS --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" >/dev/null 2>&1; then echo "Token works."; break; fi
    echo "Telegram doesn't accept that token. Copy it again from @BotFather (/mybots > your bot > API Token)."
  done
  read -rp "Player link, e.g. https://yourname.github.io/player/ : " PLAYER_URL </dev/tty
  (umask 077; printf 'DOMAIN=%s\nBOT_TOKEN=%s\nPLAYER_URL=%s\nCACHE_GB=8\n' "$DOMAIN" "$BOT_TOKEN" "$PLAYER_URL" > .env)
fi
DOMAIN=$(grep '^DOMAIN=' .env | cut -d= -f2-)
if ! grep -q '^TG_API_ID=' .env; then
  say "Big files (optional, asked once)"
  echo "Songs over 20 MB need Telegram API keys (api_id and api_hash from my.telegram.org)."
  echo "Press Enter to skip. (To be asked again later: sed -i '/^TG_API_ID=/d' $DIR/.env and run this installer again.)"
  while :; do
    read -rp "api_id (a number): " TG_API_ID </dev/tty
    TG_API_ID=$(printf '%s' "$TG_API_ID" | tr -d ' \r')
    [ -z "$TG_API_ID" ] && break
    if ! printf '%s' "$TG_API_ID" | grep -Eq '^[0-9]{3,12}$'; then echo "That doesn't look like an api_id (only digits). Try again or press Enter to skip."; continue; fi
    read -rp "api_hash (32 letters and digits): " TG_API_HASH </dev/tty
    TG_API_HASH=$(printf '%s' "$TG_API_HASH" | tr -d ' \r')
    if printf '%s' "$TG_API_HASH" | grep -Eq '^[0-9a-fA-F]{32}$'; then break; fi
    echo "That api_hash doesn't look right (it should be 32 characters, 0-9 and a-f). Let's try again."
  done
  if [ -n "$TG_API_ID" ]; then
    (umask 077; printf 'TG_API_ID=%s\nTG_API_HASH=%s\nLOCAL_BOT_API=1\nTG_API_BASE=http://bot-api:8081\nCOMPOSE_PROFILES=bigfiles\n' "$TG_API_ID" "$TG_API_HASH" >> .env)
    echo "Big files on: the bot switches to your own Telegram Bot API server (songs up to 2000 MB)."
  else
    echo "TG_API_ID=" >> .env; echo "Skipped."
  fi
fi

say "Writing files"
cat > docker-compose.yml <<'MACAW_EOF'
name: macaw
services:
  app:
    build: ./app
    container_name: macaw-app
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/data
      - botapi:/var/lib/telegram-bot-api
  caddy:
    image: caddy:2
    container_name: macaw-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - DOMAIN=${DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - app
  # big-file mode only (turned on by COMPOSE_PROFILES=bigfiles in .env): Telegram's own Bot API server, no 20 MB limit
  bot-api:
    image: aiogram/telegram-bot-api:latest
    container_name: macaw-bot-api
    restart: unless-stopped
    profiles: ["bigfiles"]
    environment:
      - TELEGRAM_API_ID=${TG_API_ID:-}
      - TELEGRAM_API_HASH=${TG_API_HASH:-}
      - TELEGRAM_LOCAL=1
    volumes:
      - botapi:/var/lib/telegram-bot-api
volumes:
  caddy_data: {}
  caddy_config: {}
  botapi: {}
MACAW_EOF

cat > Caddyfile <<'MACAW_EOF'
{$DOMAIN} {
	reverse_proxy app:8080 {
		flush_interval -1
	}
}
MACAW_EOF

cat > app/package.json <<'MACAW_EOF'
{
  "name": "macaw-player-server",
  "private": true,
  "type": "module",
  "main": "server.js"
}
MACAW_EOF

cat > app/Dockerfile <<'MACAW_EOF'
FROM node:22-alpine
WORKDIR /app
COPY package.json server.js tags.js ./
ENV DATA_DIR=/data
CMD ["node", "server.js"]
MACAW_EOF

cat > app/tags.js <<'MACAW_EOF'
// Minimal music tag reader: ID3v2.2/2.3/2.4 and ID3v1 (MP3 and friends), FLAC Vorbis comments + picture, MP4/M4A ilst.
// Returns { title, artist, album, albumArtist, track, disc, year, isrc, picture: { mime, data } | null }. No dependencies.
import fs from "node:fs";

const latin1 = b => b.toString("latin1");
function decodeText(enc, b) {                                            // ID3 text: 0 latin1, 1 UTF-16 with BOM, 2 UTF-16BE, 3 UTF-8
  let s;
  if (enc === 1 || enc === 2) {
    let le = enc === 1, i = 0;
    if (b.length >= 2 && b[0] === 0xff && b[1] === 0xfe) { le = true; i = 2; }
    else if (b.length >= 2 && b[0] === 0xfe && b[1] === 0xff) { le = false; i = 2; }
    else if (enc === 2) le = false;
    const u = Buffer.from(b.subarray(i, i + ((b.length - i) & ~1)));
    if (!le) u.swap16();
    s = u.toString("utf16le");
  } else s = enc === 3 ? b.toString("utf8") : latin1(b);
  return s.split("\0").filter(Boolean)[0] || "";                           // several values: keep the first
}
const syncsafe = (b, o) => (b[o] & 0x7f) << 21 | (b[o + 1] & 0x7f) << 14 | (b[o + 2] & 0x7f) << 7 | (b[o + 3] & 0x7f);
function unsync(b) {                                                     // remove the 0x00 inserted after every 0xFF
  const out = Buffer.alloc(b.length); let j = 0;
  for (let i = 0; i < b.length; i++) { out[j++] = b[i]; if (b[i] === 0xff && b[i + 1] === 0) i++; }
  return out.subarray(0, j);
}
const num = s => { const n = parseInt(String(s || ""), 10); return n > 0 ? n : 0; };
const year = s => { const m = /(\d{4})/.exec(String(s || "")); return m ? +m[1] : 0; };

function id3v2(buf, r) {
  if (buf.length < 10 || latin1(buf.subarray(0, 3)) !== "ID3") return false;
  const v = buf[3], flags = buf[5], size = syncsafe(buf, 6);
  let tag = buf.subarray(10, 10 + size);
  if (v < 4 && flags & 0x80) tag = unsync(tag);
  let o = 0;
  if (flags & 0x40) o = v === 4 ? syncsafe(tag, 0) : tag.readUInt32BE(0) + 4;   // skip the extended header
  const MAP = v === 2 ? { TT2: "title", TP1: "artist", TAL: "album", TP2: "albumArtist", TRK: "track", TPA: "disc", TYE: "year", TRC: "isrc" }
                      : { TIT2: "title", TPE1: "artist", TALB: "album", TPE2: "albumArtist", TRCK: "track", TPOS: "disc", TYER: "year", TDRC: "year", TSRC: "isrc" };
  const hl = v === 2 ? 6 : 10;
  while (o + hl <= tag.length) {
    const id = latin1(tag.subarray(o, o + (v === 2 ? 3 : 4)));
    if (!/^[A-Z0-9]{3,4}$/.test(id)) break;                              // padding
    const fsize = v === 2 ? tag.readUIntBE(o + 3, 3) : v === 4 ? syncsafe(tag, o + 4) : tag.readUInt32BE(o + 4);
    const fflags = v === 2 ? 0 : tag.readUInt16BE(o + 8);
    let d = tag.subarray(o + hl, o + hl + fsize);
    o += hl + fsize;
    if (!fsize || d.length < fsize) continue;
    if (v === 4 && fflags & 0x02) d = unsync(d);
    if (v === 4 && fflags & 0x01) d = d.subarray(4);                     // data length indicator
    if (v === 3 && fflags & 0x00c0) continue;                            // compressed / encrypted: skip
    const key = MAP[id];
    if (key && !r[key]) r[key] = decodeText(d[0], d.subarray(1)).trim();
    else if ((id === "APIC" || id === "PIC") && !r.picture) {
      const enc = d[0]; let i = 1, mime;
      if (id === "PIC") { const f = latin1(d.subarray(1, 4)).toLowerCase(); mime = f === "png" ? "image/png" : "image/jpeg"; i = 4; }
      else { const e = d.indexOf(0, 1); mime = latin1(d.subarray(1, e)) || "image/jpeg"; i = e + 1; }
      const ptype = d[i]; i++;
      if (enc === 1 || enc === 2) { while (i + 1 < d.length && !(d[i] === 0 && d[i + 1] === 0)) i += 2; i += 2; }   // UTF-16 description ends with 00 00
      else { const e = d.indexOf(0, i); i = e < 0 ? d.length : e + 1; }
      if (i < d.length) r.picture = { mime: mime.includes("/") ? mime : "image/" + mime.toLowerCase(), data: Buffer.from(d.subarray(i)), front: ptype === 3 };
    }
  }
  return true;
}
function id3v1(buf, r) {
  if (buf.length < 128) return;
  const t = buf.subarray(buf.length - 128);
  if (latin1(t.subarray(0, 3)) !== "TAG") return;
  const f = (a, b) => latin1(t.subarray(a, b)).replace(/\0.*$/s, "").trim();
  r.title = r.title || f(3, 33); r.artist = r.artist || f(33, 63); r.album = r.album || f(63, 93); r.year = r.year || f(93, 97);
  if (!r.track && t[125] === 0 && t[126]) r.track = String(t[126]);
}
function flac(buf, r) {
  if (latin1(buf.subarray(0, 4)) !== "fLaC") return false;
  let o = 4, last = false;
  while (!last && o + 4 <= buf.length) {
    last = !!(buf[o] & 0x80); const type = buf[o] & 0x7f, len = buf.readUIntBE(o + 1, 3), b = buf.subarray(o + 4, o + 4 + len);
    o += 4 + len;
    if (type === 4) {                                                    // Vorbis comments (little endian lengths)
      let i = 4 + b.readUInt32LE(0); const n = b.readUInt32LE(i); i += 4;
      for (let k = 0; k < n && i + 4 <= b.length; k++) {
        const l = b.readUInt32LE(i), s = b.subarray(i + 4, i + 4 + l).toString("utf8"); i += 4 + l;
        const e = s.indexOf("="); if (e < 0) continue;
        const key = s.slice(0, e).toUpperCase(), val = s.slice(e + 1).trim();
        const map = { TITLE: "title", ARTIST: "artist", ALBUM: "album", ALBUMARTIST: "albumArtist", "ALBUM ARTIST": "albumArtist", TRACKNUMBER: "track", DISCNUMBER: "disc", DATE: "year", YEAR: "year", ISRC: "isrc" };
        if (map[key] && !r[map[key]]) r[map[key]] = val;
      }
    } else if (type === 6 && (!r.picture || !r.picture.front)) {          // picture block
      let i = 0; const ptype = b.readUInt32BE(i); i += 4;
      const ml = b.readUInt32BE(i); const mime = latin1(b.subarray(i + 4, i + 4 + ml)); i += 4 + ml;
      const dl = b.readUInt32BE(i); i += 4 + dl + 16;
      const len2 = b.readUInt32BE(i); i += 4;
      r.picture = { mime: mime || "image/jpeg", data: Buffer.from(b.subarray(i, i + len2)), front: ptype === 3 };
    }
  }
  return true;
}
function mp4(buf, r) {
  if (latin1(buf.subarray(4, 8)) !== "ftyp") return false;
  const atoms = (s, e) => { const out = []; let o = s;
    while (o + 8 <= e) { let size = buf.readUInt32BE(o), h = 8; const type = latin1(buf.subarray(o + 4, o + 8));
      if (size === 1) { size = Number(buf.readBigUInt64BE(o + 8)); h = 16; } else if (size === 0) size = e - o;
      if (size < h || o + size > e) break; out.push({ type, s: o + h, e: o + size }); o += size; }
    return out; };
  const find = (list, t) => list.find(a => a.type === t);
  const moov = find(atoms(0, buf.length), "moov"); if (!moov) return true;
  const udta = find(atoms(moov.s, moov.e), "udta"); if (!udta) return true;
  const meta = find(atoms(udta.s, udta.e), "meta"); if (!meta) return true;
  const ilst = find(atoms(meta.s + 4, meta.e), "ilst"); if (!ilst) return true;
  const MAP = { "©nam": "title", "©ART": "artist", "©alb": "album", aART: "albumArtist", "©day": "year" };
  for (const it of atoms(ilst.s, ilst.e)) {
    const data = find(atoms(it.s, it.e), "data"); if (!data) continue;
    const kind = buf.readUInt32BE(data.s) & 0xffffff, v = buf.subarray(data.s + 8, data.e);
    if (MAP[it.type]) r[MAP[it.type]] = r[MAP[it.type]] || v.toString("utf8").trim();
    else if ((it.type === "trkn" || it.type === "disk") && v.length >= 4) r[it.type === "trkn" ? "track" : "disc"] = String(v.readUInt16BE(2));
    else if (it.type === "covr" && !r.picture) r.picture = { mime: kind === 14 ? "image/png" : "image/jpeg", data: Buffer.from(v), front: true };
  }
  return true;
}
export function readTags(file) {
  const buf = fs.readFileSync(file), r = {};
  if (!flac(buf, r) && !mp4(buf, r)) { id3v2(buf, r); id3v1(buf, r); }
  return { title: r.title || "", artist: r.artist || "", album: r.album || "", albumArtist: r.albumArtist || "", track: num(r.track), disc: num(r.disc),
    year: year(r.year), isrc: r.isrc || "", picture: r.picture && r.picture.data.length > 100 ? { mime: r.picture.mime, data: r.picture.data } : null };
}
MACAW_EOF

cat > app/server.js <<'MACAW_EOF'
// Macaw player server
//  - the Telegram bot: every audio file someone sends or forwards to it goes into THEIR library
//  - a small HTTPS API (behind Caddy) that the player inside Telegram uses to list and stream those songs
// Who can use it: the owner (first account to send /start) and friends the owner invites with /invite (one-time links).
// Libraries are separate. If two people send the same song, the file is stored on the server only once.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { readTags as parseTags } from "./tags.js";

const TOKEN = (process.env.BOT_TOKEN || "").trim();
if (!TOKEN) { console.error("BOT_TOKEN is missing (edit /opt/macaw-player/.env)"); process.exit(1); }
const CLOUD = process.env.CLOUD_API_BASE || "https://api.telegram.org";
const LOCAL = process.env.LOCAL_BOT_API === "1";                        // big-file mode: our own Telegram Bot API server (needs api_id/api_hash)
const TG_BASE = process.env.TG_API_BASE || CLOUD;
const API = `${TG_BASE}/bot${TOKEN}`, FILES = `${TG_BASE}/file/bot${TOKEN}`;
const DATA = process.env.DATA_DIR || "/data";
const AUDIO = path.join(DATA, "audio"), COVERS = path.join(DATA, "covers"), DB_FILE = path.join(DATA, "library.json");
const CACHE_GB = parseFloat(process.env.CACHE_GB);
const CACHE_BYTES = (Number.isFinite(CACHE_GB) && CACHE_GB >= 0 ? CACHE_GB : 8) * 1e9;   // songs kept on the server (0 = keep nothing, just pass songs through)
const PLAYER_URL = (process.env.PLAYER_URL || "").trim();
const PORT = +process.env.PORT || 8080;
const MAX_DOWNLOAD = (LOCAL ? 2000 : 20) * 1024 * 1024;                   // Telegram's public servers let bots download up to 20 MB; our own Bot API server has no such limit
const INVITE_DAYS = 7;
const AUDIO_EXT = /\.(mp3|m4a|mp4|aac|flac|wav|ogg|oga|opus|aiff?)$/i;
const MIME = { ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".mp4": "audio/mp4", ".aac": "audio/aac", ".flac": "audio/flac", ".wav": "audio/wav",
  ".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/ogg", ".aif": "audio/aiff", ".aiff": "audio/aiff" };
const EXT_OF = { "audio/mpeg": ".mp3", "audio/mp3": ".mp3", "audio/mp4": ".m4a", "audio/x-m4a": ".m4a", "audio/aac": ".aac", "audio/flac": ".flac", "audio/x-flac": ".flac",
  "audio/wav": ".wav", "audio/x-wav": ".wav", "audio/ogg": ".ogg" };
const sleep = ms => new Promise(r => setTimeout(r, ms));
fs.mkdirSync(AUDIO, { recursive: true }); fs.mkdirSync(COVERS, { recursive: true });

/* ---------- data: one JSON file ---------- */
let db = { owner: null, users: {}, invites: {}, offset: 0, version: 1, secret: crypto.randomBytes(24).toString("hex"), tracks: [] };
try { db = { ...db, ...JSON.parse(fs.readFileSync(DB_FILE, "utf8")) }; } catch {}
let saveT = null;
function save(now) {
  clearTimeout(saveT);
  const write = () => { const tmp = DB_FILE + ".tmp"; fs.writeFileSync(tmp, JSON.stringify(db)); fs.renameSync(tmp, DB_FILE); };
  if (now) write(); else saveT = setTimeout(write, 500);
}
save(true);
const bump = () => { db.version++; save(); };                            // players re-read their library whenever the version changes
const byId = id => db.tracks.find(t => t.id === id);
const trackKey = (uid, uniq) => uid.toString(36) + "-" + uniq;           // one entry per person per song
const audioFile = t => path.join(AUDIO, t.uniq + t.ext);                  // files are shared: same song from two people = one file
const coverFile = t => path.join(COVERS, t.uniq);
const isMember = id => id === db.owner || !!db.users[id];
const nameOf = u => [u.first_name, u.last_name].filter(Boolean).join(" ") || u.username || String(u.id);
const songsOf = uid => db.tracks.filter(t => t.uid === uid).length;
function dropTracks(list) {                                              // remove entries; delete a file only when nobody else has that song
  db.tracks = db.tracks.filter(t => !list.includes(t));
  for (const t of list) if (!db.tracks.some(x => x.uniq === t.uniq)) for (const f of [audioFile(t), coverFile(t)]) { try { fs.unlinkSync(f); } catch {} }
  bump();
}

/* ---------- Telegram ---------- */
let BOT_NAME = "";
async function tg(method, params = {}) {
  const r = await fetch(`${API}/${method}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(params) });
  const j = await r.json().catch(() => ({ ok: false, description: "HTTP " + r.status }));
  if (!j.ok) { const e = new Error(`${method}: ${j.description}`); e.retry = j.parameters && j.parameters.retry_after; throw e; }
  return j.result;
}
const react = (m, emoji) => tg("setMessageReaction", { chat_id: m.chat.id, message_id: m.message_id, reaction: emoji ? [{ type: "emoji", emoji }] : [] }).catch(() => {});
const say = (chat, text, extra = {}) => tg("sendMessage", { chat_id: chat, text, ...extra }).catch(e => console.error(e.message));
const reply = (m, text, extra = {}) => say(m.chat.id, text, { reply_parameters: { message_id: m.message_id, allow_sending_without_reply: true }, ...extra });
const openButton = () => (PLAYER_URL ? { reply_markup: { inline_keyboard: [[{ text: "▶︎  Open player", web_app: { url: PLAYER_URL } }]] } } : {});

async function download(filePath, dest) {
  if (filePath.startsWith("/")) {                                         // big-file mode: the Bot API server already saved the file on the shared disk
    if (!fs.existsSync(filePath)) throw new Error("file not on disk yet");
    const tmp = dest + ".part";
    fs.copyFileSync(filePath, tmp); fs.renameSync(tmp, dest);
    try { fs.unlinkSync(filePath); } catch {}                             // don't keep a second copy
    return;
  }
  const r = await fetch(`${FILES}/${filePath}`);
  if (!r.ok || !r.body) throw new Error("download failed: HTTP " + r.status);
  const tmp = dest + ".part";
  await pipeline(Readable.fromWeb(r.body), fs.createWriteStream(tmp));
  fs.renameSync(tmp, dest);
}
const inflight = new Map();
function ensureAudio(t) {                                                 // the song on disk: fetched from Telegram once, again only if the cache dropped it
  const f = audioFile(t);
  if (fs.existsSync(f)) return Promise.resolve(f);
  if (inflight.has(t.uniq)) return inflight.get(t.uniq);
  const p = (async () => {
    for (let i = 0; ; i++) {
      try { const info = await tg("getFile", { file_id: t.fileId }); await download(info.file_path, f); break; }
      catch (e) { if (i >= 2) throw e; await sleep(1500); }                 // one or two retries: a big file can take a moment on the Bot API server
    }
    trimCache(t.uniq);
    return f;
  })().finally(() => inflight.delete(t.uniq));
  inflight.set(t.uniq, p);
  return p;
}
function trimCache(keep) {                                                // least recently played songs leave the server first
  const files = new Map();
  for (const t of db.tracks) {
    const f = audioFile(t), x = files.get(f);
    if (x) x.used = Math.max(x.used, t.used || 0);
    else if (fs.existsSync(f)) files.set(f, { f, uniq: t.uniq, used: t.used || 0, size: fs.statSync(f).size });
  }
  const list = [...files.values()].sort((a, b) => a.used - b.used);
  let total = list.reduce((s, x) => s + x.size, 0);
  for (const x of list) {
    if (total <= CACHE_BYTES) break;
    if (x.uniq === keep || inflight.has(x.uniq)) continue;
    try { fs.unlinkSync(x.f); total -= x.size; } catch {}
  }
}
const META = ["title", "artist", "album", "albumArtist", "num", "disc", "year", "isrc", "cover", "ext", "mime"];
async function readTags(t) {                                              // album, track number, year, cover... straight from the file's own tags
  const f = await ensureAudio(t);
  const s = v => (v == null ? "" : String(v).replace(/\0/g, "").trim());
  try {
    if (fs.statSync(f).size > 300e6) throw new Error("too big to read tags, keeping Telegram's");
    const c = parseTags(f);
    if (s(c.title)) t.title = s(c.title);
    if (s(c.artist)) t.artist = s(c.artist);
    t.album = s(c.album); t.albumArtist = s(c.albumArtist);
    t.num = c.track; t.disc = c.disc; t.year = c.year; t.isrc = s(c.isrc);
    if (c.picture) { fs.writeFileSync(coverFile(t), c.picture.data); t.cover = c.picture.mime; }
  } catch (e) { console.warn("tags", t.title, e.message); }
  if (!t.cover && t.thumbId) {                                            // no picture in the file: Telegram's small thumbnail, if it has one
    try { const info = await tg("getFile", { file_id: t.thumbId }); await download(info.file_path, coverFile(t)); t.cover = "image/jpeg"; } catch {}
  }
  if (CACHE_BYTES === 0) trimCache(null);                                 // pass-through mode: don't keep the file after reading its tags
}
let chain = Promise.resolve();                                            // one song at a time, so forwarding 50 files doesn't hammer anything
const enqueue = fn => { chain = chain.then(fn).catch(e => console.error(e.message)); return chain; };

function audioOf(m) {
  if (!m) return null;
  if (m.audio) return m.audio;
  const d = m.document;
  return d && ((d.mime_type || "").startsWith("audio/") || AUDIO_EXT.test(d.file_name || "")) ? d : null;
}
async function setCommands() {
  const base = [{ command: "start", description: "Open the player" }, { command: "remove", description: "Reply to a song to remove it" }, { command: "stats", description: "Library size" }];
  await tg("setMyCommands", { commands: base }).catch(() => {});
  if (db.owner) await tg("setMyCommands", { commands: [...base, { command: "invite", description: "Invite a friend" }, { command: "users", description: "Who has access" }],
    scope: { type: "chat", chat_id: db.owner } }).catch(() => {});
}
async function onMessage(m) {
  if (!m || !m.from || m.chat.type !== "private") return;
  const text = (m.text || "").trim(), uid = m.from.id;
  const start = /^\/start(?:\s+([\w-]+))?/.exec(text);
  if (start && !db.owner) { db.owner = uid; save(true); console.log("owner is now Telegram user", uid); setCommands(); }
  if (start && !isMember(uid) && start[1]) return joinWithInvite(m, start[1]);
  if (!isMember(uid)) { if (text || audioOf(m)) await reply(m, "This is a private music bot. To use it you need an invite link from its owner."); return; }
  if (start) return welcome(m);
  if (/^\/remove\b/.test(text)) return removeCmd(m);
  if (/^\/stats\b/.test(text)) return stats(m);
  if (/^\/invite\b/.test(text)) return uid === db.owner ? invite(m) : reply(m, "Only the bot's owner can invite people.");
  if (/^\/users\b/.test(text)) return uid === db.owner ? usersList(m.chat.id) : reply(m, "Only the bot's owner can see that.");
  const a = audioOf(m);
  if (!a) { if (text && !text.startsWith("/")) await reply(m, "Send or forward audio files here and they appear in your player."); return; }
  const uniq = a.file_unique_id, id = trackKey(uid, uniq);
  if (byId(id)) { await react(m, "👌"); return; }                           // already in this person's library
  if (a.file_size && a.file_size > MAX_DOWNLOAD) {
    await react(m, "🤷");
    await reply(m, `That file is ${Math.round(a.file_size / 1048576)} MB. ${LOCAL ? "The limit is 2000 MB." : "Bots can only download files up to 20 MB from Telegram, so send an MP3 or M4A version of it."}`);
    return;
  }
  const name = a.file_name || "";
  let ext = ((name.match(/\.[a-z0-9]{2,5}$/i) || [])[0] || "").toLowerCase();
  if (!MIME[ext]) ext = EXT_OF[a.mime_type] || ".mp3";
  const mime = (a.mime_type || "").startsWith("audio/") ? a.mime_type : MIME[ext];
  const t = { id, uid, uniq, fileId: a.file_id, title: a.title || name.replace(/\.[^.]+$/, "") || "Unknown", artist: a.performer || "", album: "", albumArtist: "",
    num: 0, disc: 0, year: 0, isrc: "", duration: a.duration || 0, size: a.file_size || 0, mime, ext,
    thumbId: (a.thumbnail || a.thumb || {}).file_id || null, cover: null, added: Date.now(), used: Date.now(), rev: 1 };
  const twin = db.tracks.find(x => x.uniq === uniq && x.rev > 1);         // someone already has this exact song: reuse what we know, nothing to download
  if (twin) { for (const k of META) t[k] = twin[k]; t.rev = 2; db.tracks.push(t); bump(); await react(m, "👌"); return; }
  db.tracks.push(t); bump();
  await react(m, "✍");                                                     // ✍ = reading it, 👌 = in your library
  enqueue(async () => {
    try { await readTags(t); t.rev++; bump(); await react(m, "👌"); }
    catch (e) { console.error("ingest", t.title, e.message); await react(m, "🤷"); }   // stays in the library under Telegram's title; the file is fetched again when played
  });
}
async function welcome(m) {
  const n = songsOf(m.from.id);
  await say(m.chat.id, `Your music library 🎧\n\nSend or forward audio files here and they show up in the player (${n} song${n === 1 ? "" : "s"} so far).\n\nTo take a song out, reply /remove to it.` +
    (m.from.id === db.owner ? "\n\nTo let a friend in, send /invite. /users shows who has access." : ""), openButton());
}
async function joinWithInvite(m, code) {
  const inv = db.invites[code];
  if (!inv || inv.exp < Date.now()) { if (inv) { delete db.invites[code]; save(); } return reply(m, "This invite link has expired or was already used. Ask for a new one."); }
  delete db.invites[code];
  db.users[m.from.id] = { name: nameOf(m.from), username: m.from.username || "", joined: Date.now() };
  save(true); console.log("new member", m.from.id, nameOf(m.from));
  await welcome(m);
  await say(db.owner, `${nameOf(m.from)}${m.from.username ? " (@" + m.from.username + ")" : ""} joined with your invite link.`);
}
async function invite(m) {
  for (const [c, v] of Object.entries(db.invites)) if (v.exp < Date.now()) delete db.invites[c];
  const code = crypto.randomBytes(9).toString("base64url");
  db.invites[code] = { exp: Date.now() + INVITE_DAYS * 864e5 };
  save(true);
  await reply(m, `Send this link to a friend. It works once, for ${INVITE_DAYS} days:\n\nhttps://t.me/${BOT_NAME}?start=${code}`, { link_preview_options: { is_disabled: true } });
}
function usersView() {
  const ids = Object.keys(db.users);
  const lines = [`You: ${songsOf(db.owner)} songs`, ...ids.map(id => `${db.users[id].name}${db.users[id].username ? " @" + db.users[id].username : ""}: ${songsOf(+id)} songs`)];
  return { text: (ids.length ? "People with access\n\n" : "Only you have access so far. Send /invite to let a friend in.\n\n") + lines.join("\n"),
    reply_markup: { inline_keyboard: ids.map(id => [{ text: "Remove " + db.users[id].name, callback_data: "rm:" + id }]) } };
}
const usersList = chat => say(chat, usersView().text, { reply_markup: usersView().reply_markup });
async function onCallback(q) {
  const done = text => tg("answerCallbackQuery", { callback_query_id: q.id, text }).catch(() => {});
  if (q.from.id !== db.owner || !q.message) return done("Only the owner can do that.");
  const [act, id] = String(q.data || "").split(":"), u = db.users[id];
  const edit = view => tg("editMessageText", { chat_id: q.message.chat.id, message_id: q.message.message_id, text: view.text, reply_markup: view.reply_markup }).catch(() => {});
  if (!u) { await edit(usersView()); return done("Already gone."); }
  if (act === "rm") {                                                     // ask first: removing someone also deletes their library
    await edit({ text: `Remove ${u.name}? Their library (${songsOf(+id)} songs) is deleted too.`,
      reply_markup: { inline_keyboard: [[{ text: "Yes, remove", callback_data: "rmy:" + id }, { text: "Cancel", callback_data: "rmn:" + id }]] } });
    return done();
  }
  if (act === "rmy") { delete db.users[id]; dropTracks(db.tracks.filter(t => t.uid === +id)); save(true); console.log("removed member", id); await edit(usersView()); return done(u.name + " removed"); }
  await edit(usersView()); return done();
}
async function removeCmd(m) {
  const a = audioOf(m.reply_to_message), t = a && byId(trackKey(m.from.id, a.file_unique_id));
  if (!t) return reply(m, "Reply /remove to one of the songs you sent me.");
  dropTracks([t]); await react(m.reply_to_message, null);
  await reply(m, `Removed “${t.title}”.`);
}
async function stats(m) {
  const mine = songsOf(m.from.id);
  let text = `${mine} song${mine === 1 ? "" : "s"} in your library.`;
  if (m.from.id === db.owner) {
    const seen = new Set(); let n = 0, bytes = 0;
    for (const t of db.tracks) { const f = audioFile(t); if (seen.has(f)) continue; seen.add(f); if (fs.existsSync(f)) { n++; bytes += fs.statSync(f).size; } }
    const others = Object.keys(db.users).map(id => `${db.users[id].name}: ${songsOf(+id)}`);
    text += (others.length ? `\n${others.join("\n")}` : "") + `\n\nServer cache: ${n} files, ${(bytes / 1e9).toFixed(2)} GB of ${CACHE_BYTES / 1e9} GB.`;
  }
  await reply(m, text);
}
async function switchToLocal() {                                         // once: the bot must log out of Telegram's public servers before our own server can run it
  if (!LOCAL || db.localReady) return;
  for (let i = 0; i < 3; i++) {
    try {
      const j = await (await fetch(`${CLOUD}/bot${TOKEN}/logOut`, { method: "POST" })).json();
      console.log("logOut from Telegram's public Bot API:", j.ok ? "done" : j.description);
      if (j.ok || /logged out|unauthorized/i.test(j.description || "")) { db.localReady = true; save(true); return; }
    } catch (e) { console.error("logOut attempt failed:", e.message); }
    await sleep(5000);
  }
  console.error("couldn't log the bot out of Telegram's public servers; will try again on the next start");
}
async function poll() {
  await switchToLocal();
  for (;;) {                                                              // keep trying until Telegram answers (bad token, no network...)
    try { const me = await tg("getMe"); BOT_NAME = me.username; console.log("bot @" + me.username + " is running"); break; }
    catch (e) { console.error("can't reach the bot:", e.message); await sleep(10000); }
  }
  await tg("deleteWebhook").catch(() => {});
  await setCommands();
  for (;;) {
    try {
      const ups = await tg("getUpdates", { offset: db.offset, timeout: 50, allowed_updates: ["message", "callback_query"] });
      for (const u of ups) {
        db.offset = u.update_id + 1;
        try { if (u.message) await onMessage(u.message); else if (u.callback_query) await onCallback(u.callback_query); } catch (e) { console.error("update", e.message); }
      }
      if (ups.length) save();
    } catch (e) { console.error("poll", e.message); await sleep(e.retry ? e.retry * 1000 : 5000); }
  }
}

/* ---------- API for the player ---------- */
function initUser(init) {                                                 // Telegram signs the data it hands the Mini App; only a valid signature from this bot passes
  if (!init) return null;
  const p = new URLSearchParams(init), hash = p.get("hash");
  if (!hash) return null;
  p.delete("hash");
  const check = [...p.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => `${k}=${v}`).join("\n");
  const key = crypto.createHmac("sha256", "WebAppData").update(TOKEN).digest();
  const h = crypto.createHmac("sha256", key).update(check).digest("hex");
  if (h.length !== hash.length || !crypto.timingSafeEqual(Buffer.from(h), Buffer.from(hash))) return null;
  if (!(Date.now() / 1000 - +p.get("auth_date") < 30 * 86400)) return null;
  try { return JSON.parse(p.get("user") || "null"); } catch { return null; }
}
const sign = s => crypto.createHmac("sha256", db.secret).update(s).digest("base64url").slice(0, 22);
function makeToken(uid) {                                                 // for <audio>/<img> URLs, which can't carry headers: tied to one person, same all day, valid ~8 days
  const exp = (Math.floor(Date.now() / 864e5) + 8) * 86400, u = uid.toString(36);
  return `${exp.toString(36)}.${u}.${sign(`s${exp}.${u}`)}`;
}
function tokenUser(tok) {
  const [a, u, b] = String(tok || "").split(".");
  const exp = parseInt(a, 36), uid = parseInt(u, 36);
  return b && exp > Date.now() / 1000 && b === sign(`s${exp}.${u}`) && isMember(uid) ? uid : null;
}
const pub = t => ({ id: t.id, title: t.title, artist: t.artist, album: t.album, albumArtist: t.albumArtist, num: t.num, disc: t.disc, year: t.year, isrc: t.isrc,
  duration: t.duration, size: t.size, mime: t.mime, cover: !!t.cover, rev: t.rev, added: t.added });
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "X-Init-Data, Range", "Access-Control-Allow-Methods": "GET, HEAD, DELETE, OPTIONS",
  "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges", "Access-Control-Max-Age": "86400" };
function json(res, code, obj) { res.writeHead(code, { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" }); res.end(JSON.stringify(obj)); }
function serveFile(req, res, file, type) {                                // with byte ranges: iPhones won't play audio without them
  const size = fs.statSync(file).size;
  const h = { ...CORS, "Content-Type": type, "Accept-Ranges": "bytes", "Cache-Control": "private, max-age=31536000, immutable" };
  const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || "");
  if (m && (m[1] || m[2])) {
    let start = m[1] ? +m[1] : size - +m[2];
    const end = m[1] && m[2] ? Math.min(+m[2], size - 1) : size - 1;
    if (start < 0) start = 0;
    if (start >= size || start > end) { res.writeHead(416, { ...h, "Content-Range": `bytes */${size}` }); return res.end(); }
    res.writeHead(206, { ...h, "Content-Range": `bytes ${start}-${end}/${size}`, "Content-Length": end - start + 1 });
    if (req.method === "HEAD") return res.end();
    return fs.createReadStream(file, { start, end }).pipe(res);
  }
  res.writeHead(200, { ...h, "Content-Length": size });
  if (req.method === "HEAD") return res.end();
  fs.createReadStream(file).pipe(res);
}
function member(req, res) {                                               // the signed-in Telegram user, if they're allowed in
  const u = initUser(req.headers["x-init-data"]);
  if (!u) { json(res, 401, { error: "not signed by Telegram" }); return null; }
  if (!db.owner) { json(res, 403, { error: "send /start to the bot first" }); return null; }
  if (!isMember(u.id)) { json(res, 403, { error: "you need an invite link from the bot's owner" }); return null; }
  return u.id;
}
http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x"), p = url.pathname;
  try {
    if (req.method === "OPTIONS") { res.writeHead(204, CORS); return res.end(); }
    if (p === "/" || p === "/health") { res.writeHead(200, { ...CORS, "Content-Type": "text/plain" }); return res.end("macaw player server: ok\n"); }
    if (p === "/api/library" && req.method === "GET") {
      const uid = member(req, res); if (uid == null) return;
      if (+url.searchParams.get("since") === db.version) return json(res, 200, { version: db.version, same: true });
      return json(res, 200, { version: db.version, token: makeToken(uid), tracks: db.tracks.filter(t => t.uid === uid).map(pub) });
    }
    let m = /^\/api\/track\/([\w-]+)$/.exec(p);
    if (m && req.method === "DELETE") {
      const uid = member(req, res); if (uid == null) return;
      const t = byId(m[1]); if (!t || t.uid !== uid) return json(res, 404, { error: "no such song" });
      dropTracks([t]); return json(res, 200, { ok: true, version: db.version });
    }
    m = /^\/api\/(audio|cover)\/([\w-]+)$/.exec(p);
    if (m && (req.method === "GET" || req.method === "HEAD")) {
      const uid = tokenUser(url.searchParams.get("t"));
      if (uid == null) return json(res, 403, { error: "bad or expired link" });
      const t = byId(m[2]); if (!t || t.uid !== uid) return json(res, 404, { error: "no such song" });   // only your own songs
      if (m[1] === "cover") return t.cover && fs.existsSync(coverFile(t)) ? serveFile(req, res, coverFile(t), t.cover) : json(res, 404, { error: "no cover" });
      let f;
      try { f = await ensureAudio(t); } catch (e) { console.error("fetch", t.title, e.message); return json(res, 502, { error: "couldn't get the song from Telegram" }); }
      t.used = Date.now(); save();
      return serveFile(req, res, f, t.mime);
    }
    json(res, 404, { error: "not found" });
  } catch (e) { console.error(e); if (!res.headersSent) json(res, 500, { error: "server error" }); else res.end(); }
}).listen(PORT, () => console.log("api listening on", PORT));

process.on("SIGTERM", () => { save(true); process.exit(0); });
poll();
MACAW_EOF

say "Checking the domain"
IP=$(curl -fsS4 --max-time 10 https://api.ipify.org 2>/dev/null || true)
DNS=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
if [ -n "$IP" ] && [ "$IP" != "$DNS" ]; then echo "Warning: $DOMAIN points to '${DNS:-nothing}', but this server is $IP. Fix it on duckdns.org, or HTTPS can't start."; else echo "$DOMAIN -> $IP"; fi
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; echo "Opened ports 80 and 443 in ufw."; fi

say "Starting (first time takes a minute)"
docker compose up -d --build
sleep 10
docker compose ps
if curl -fsS --max-time 30 "https://$DOMAIN/health" >/dev/null 2>&1; then echo "HTTPS works: https://$DOMAIN"
else echo "HTTPS isn't answering yet. The certificate can take a minute; if it stays like this, send the output of:  cd $DIR && docker compose logs --tail 40"; fi

say "Done"
echo "Open your bot in Telegram and send /start. The first account to do that becomes the owner."
echo "Then send /invite to the bot to get a one-time link for a friend."
