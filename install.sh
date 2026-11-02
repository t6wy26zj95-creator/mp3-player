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

mkdir -p "$DIR/app" "$DIR/data" "$DIR/finder" "$DIR/data/finder"
chmod 700 "$DIR/data/finder"                                              # everyone's song-search logins live here
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
if ! grep -q '^FINDER_URL=' .env && [ -n "$(grep '^TG_API_ID=' .env | cut -d= -f2-)" ]; then
  # song search (the + on grey songs in the player) uses the api_id / api_hash this server already has
  echo "FINDER_URL=http://finder:8090" >> .env
  if grep -q '^COMPOSE_PROFILES=..*' .env; then grep -Eq '^COMPOSE_PROFILES=(.*,)?finder(,.*)?$' .env || sed -i 's/^COMPOSE_PROFILES=\(.*\)$/COMPOSE_PROFILES=\1,finder/' .env
  else sed -i '/^COMPOSE_PROFILES=/d' .env; echo "COMPOSE_PROFILES=finder" >> .env; fi
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
  # song search (on when the server has api_id/api_hash: COMPOSE_PROFILES has "finder"): each person's own Telegram
  # account, logged in from the player, uses the music bot's inline search for the + on grey songs
  finder:
    build: ./finder
    container_name: macaw-finder
    restart: unless-stopped
    profiles: ["finder"]
    env_file: .env
    volumes:
      - ./data/finder:/session
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
let db = { owner: null, users: {}, invites: {}, appKeys: {}, offset: 0, version: 1, secret: crypto.randomBytes(24).toString("hex"), tracks: [] };
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
  const w = waitBy.get(m.from.id);
  if (w && audioOf(m)) { waitBy.delete(m.from.id); w.res(await addAudio(m, w.uid)); return; }   // the song search just sent this for someone's +
  const text = (m.text || "").trim(), uid = m.from.id;
  const start = /^\/start(?:\s+([\w-]+))?/.exec(text);
  if (start && !db.owner) { db.owner = uid; save(true); console.log("owner is now Telegram user", uid); setCommands(); }
  if (start && start[1] && start[1].startsWith("app_")) return linkApp(m, start[1].slice(4));
  if (start && !isMember(uid) && start[1]) return joinWithInvite(m, start[1]);
  if (!isMember(uid)) { if (text || audioOf(m)) await reply(m, "This is a private music bot. To use it you need an invite link from its owner."); return; }
  if (start) return welcome(m);
  if (/^\/remove\b/.test(text)) return removeCmd(m);
  if (/^\/stats\b/.test(text)) return stats(m);
  if (/^\/invite\b/.test(text)) return uid === db.owner ? invite(m) : reply(m, "Only the bot's owner can invite people.");
  if (/^\/users\b/.test(text)) return uid === db.owner ? usersList(m.chat.id) : reply(m, "Only the bot's owner can see that.");
  if (!audioOf(m)) { if (text && !text.startsWith("/")) await reply(m, "Send or forward audio files here and they appear in your player."); return; }
  await addAudio(m, uid);
}
async function addAudio(m, uid) {                                         // one audio message -> uid's library; returns the song (null if it can't be taken)
  const a = audioOf(m);
  const uniq = a.file_unique_id, id = trackKey(uid, uniq);
  if (byId(id)) { await react(m, "👌"); return byId(id); }                 // already in this person's library
  if (a.file_size && a.file_size > MAX_DOWNLOAD) {
    await react(m, "🤷");
    await reply(m, `That file is ${Math.round(a.file_size / 1048576)} MB. ${LOCAL ? "The limit is 2000 MB." : "Bots can only download files up to 20 MB from Telegram, so send an MP3 or M4A version of it."}`);
    return null;
  }
  const name = a.file_name || "";
  let ext = ((name.match(/\.[a-z0-9]{2,5}$/i) || [])[0] || "").toLowerCase();
  if (!MIME[ext]) ext = EXT_OF[a.mime_type] || ".mp3";
  const mime = (a.mime_type || "").startsWith("audio/") ? a.mime_type : MIME[ext];
  const t = { id, uid, uniq, fileId: a.file_id, title: a.title || name.replace(/\.[^.]+$/, "") || "Unknown", artist: a.performer || "", album: "", albumArtist: "",
    num: 0, disc: 0, year: 0, isrc: "", duration: a.duration || 0, size: a.file_size || 0, mime, ext,
    thumbId: (a.thumbnail || a.thumb || {}).file_id || null, cover: null, added: Date.now(), used: Date.now(), rev: 1 };
  const twin = db.tracks.find(x => x.uniq === uniq && x.rev > 1);         // someone already has this exact song: reuse what we know, nothing to download
  if (twin) { for (const k of META) t[k] = twin[k]; t.rev = 2; db.tracks.push(t); bump(); await react(m, "👌"); return t; }
  db.tracks.push(t); bump();
  await react(m, "✍");                                                     // ✍ = reading it, 👌 = in your library
  enqueue(async () => {
    try { await readTags(t); t.rev++; bump(); await react(m, "👌"); }
    catch (e) { console.error("ingest", t.title, e.message); await react(m, "🤷"); }   // stays in the library under Telegram's title; the file is fetched again when played
  });
  return t;
}
/* ---------- song search (optional: FINDER_URL, on when the server has api_id/api_hash) ----------
   The + on a grey song in the player. Bots can't use another bot's inline search, so each person logs their own Telegram
   account in once (player: Settings > Song search; the "finder" container keeps the login). Then + makes that account
   type "@musicbot Artist Title" in its chat with this bot, pick the best result and send it. Whatever audio that account
   sends next goes into the library of the person who pressed + (usually the same person; it may also be a spare account
   that isn't a member). One search at a time per person. Without a login the player opens the chat with the search typed in. */
const FINDER = (process.env.FINDER_URL || "").trim();
const waitBy = new Map(), findChains = new Map();                          // Telegram account id -> { uid, res } ; uid -> its searches in a row
async function finder(p, body) {
  const r = await fetch(FINDER + p, body ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : {});
  return { code: r.status, body: await r.json().catch(() => ({ error: "song search: HTTP " + r.status })) };
}
function findSong(uid, q) {
  const run = async () => {
    if (!FINDER) return { code: 501, body: { error: "song search is off on the server", manual: true } };
    let st; try { st = (await finder("/status?uid=" + uid)).body; } catch { return { code: 503, body: { error: "song search isn't running", manual: true } }; }
    if (!st.ready) return { code: 409, body: { error: "log in under Settings > Song search", manual: true } };
    const got = new Promise(res => waitBy.set(st.id, { uid, res }));
    let r; try { r = await finder("/find", { ...q, uid, target: BOT_NAME }); } catch { waitBy.delete(st.id); return { code: 502, body: { error: "song search didn't answer" } }; }
    if (r.code !== 200) { waitBy.delete(st.id); return r; }
    const t = await Promise.race([got, sleep(30000).then(() => null)]);   // the bot hears about the song a moment after it's sent
    waitBy.delete(st.id);
    if (!t) return { code: 504, body: { error: "the song was sent, but it didn't reach the bot" } };
    console.log("search", uid, q.artist, "-", q.title, "->", r.body.artist, "-", r.body.title);
    return { code: 200, body: { ok: true, id: t.id, title: t.title, artist: t.artist } };
  };
  const p = (findChains.get(uid) || Promise.resolve()).then(run, run);
  findChains.set(uid, p.catch(() => {})); return p;
}
const readBody = req => new Promise((ok, no) => {
  let b = ""; req.on("data", c => { b += c; if (b.length > 1e4) { no(new Error("too big")); req.destroy(); } }); req.on("end", () => ok(b)); req.on("error", no);
});
/* ---------- the iOS app (MacawP3) ----------
   The app can't sign in through Telegram like the Mini App does, so it links once: Settings > Link Telegram asks the
   server for a code (POST /api/link), opens t.me/<bot>?start=app_<code>, you press Start, and the app picks up a key
   for your library (GET /api/link/<code>). With that key (X-App-Key) it lists your songs and downloads them. */
const links = new Map();                                                  // code -> { exp, uid }: pending links, kept 10 minutes, in memory only
const LINK_MS = 10 * 60e3;
function newLink() {
  const now = Date.now();
  for (const [c, v] of links) if (v.exp < now) links.delete(c);
  if (links.size > 200) links.delete(links.keys().next().value);
  const code = crypto.randomBytes(12).toString("base64url");
  links.set(code, { exp: now + LINK_MS, uid: null });
  return code;
}
async function linkApp(m, code) {
  const l = links.get(code);
  if (!isMember(m.from.id)) return reply(m, "This is a private music bot. To use it you need an invite link from its owner.");
  if (!l || l.exp < Date.now()) return reply(m, "That link has expired. In the app, open Settings and tap Link Telegram again.");
  l.uid = m.from.id;
  await reply(m, "Your iPhone app is linked ✅\n\nSongs you send here now download into the app by themselves (while the app is open).");
}
const appUser = key => { const a = key && db.appKeys[key]; return a && isMember(a.uid) ? a.uid : null; };
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
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "X-Init-Data, X-App-Key, Range, Content-Type", "Access-Control-Allow-Methods": "GET, HEAD, POST, DELETE, OPTIONS",
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
  if (req.headers["x-app-key"]) {                                         // the iOS app, linked through the bot
    const uid = appUser(req.headers["x-app-key"]);
    if (uid == null) json(res, 403, { error: "this app isn't linked any more: link Telegram again" });
    return uid;
  }
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
    if (p === "/api/link" && req.method === "POST") {                   // the app starts linking
      if (!BOT_NAME) return json(res, 503, { error: "the bot is still starting, try again in a minute" });
      const code = newLink();
      return json(res, 200, { code, url: `https://t.me/${BOT_NAME}?start=app_${code}`, expires: LINK_MS / 1000 });
    }
    if (p === "/api/link" && req.method === "DELETE") {                 // the app unlinks itself
      const key = req.headers["x-app-key"];
      if (key && db.appKeys[key]) { delete db.appKeys[key]; save(true); }
      return json(res, 200, { ok: true });
    }
    let m = /^\/api\/link\/([\w-]+)$/.exec(p);
    if (m && req.method === "GET") {                                     // the app waits for you to press Start in the bot
      const l = links.get(m[1]);
      if (!l || l.exp < Date.now()) return json(res, 410, { error: "expired" });
      if (!l.uid) return json(res, 200, { pending: true });
      links.delete(m[1]);
      const key = crypto.randomBytes(24).toString("base64url");
      db.appKeys[key] = { uid: l.uid, created: Date.now() }; save(true);
      return json(res, 200, { key });
    }
    if (p.startsWith("/api/search") || p === "/api/fetch") {          // song search (see above)
      const uid = member(req, res); if (uid == null) return;
      if (p === "/api/search" && req.method === "GET") {
        if (!FINDER) return json(res, 200, { available: false, bot: BOT_NAME });
        try { const s = (await finder("/status?uid=" + uid)).body; return json(res, 200, { available: true, ready: !!s.ready, name: s.name || "", bot: BOT_NAME }); }
        catch { return json(res, 200, { available: false, error: "song search isn't running", bot: BOT_NAME }); }
      }
      if (req.method !== "POST") return json(res, 404, { error: "not found" });
      let q; try { q = JSON.parse(await readBody(req) || "{}"); } catch { return json(res, 400, { error: "bad request" }); }
      const s = v => String(v || "").slice(0, 200).trim();
      if (p === "/api/fetch") { const r = await findSong(uid, { bot: s(q.bot), artist: s(q.artist), title: s(q.title), album: s(q.album) }); return json(res, r.code, r.body); }
      if (!FINDER) return json(res, 501, { error: "song search is off on the server" });
      try {
        if (p === "/api/search/login") { const r = await finder("/login", { uid, step: s(q.step), value: s(q.value) }); return json(res, r.code, r.body); }
        if (p === "/api/search/logout") { const r = await finder("/logout", { uid }); return json(res, r.code, r.body); }
      } catch { return json(res, 503, { error: "song search isn't running" }); }
      return json(res, 404, { error: "not found" });
    }
    m = /^\/api\/track\/([\w-]+)$/.exec(p);
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

cat > finder/Dockerfile <<'MACAW_EOF'
FROM python:3.12-slim
RUN pip install --no-cache-dir "telethon>=1.34,<2" "aiohttp>=3.9,<4" "qrcode>=7.4,<9"
WORKDIR /app
COPY finder.py ./
CMD ["python", "-u", "finder.py"]
MACAW_EOF

cat > finder/finder.py <<'MACAW_EOF'
# Macaw song search ("finder").
# Bots can't use another bot's inline search, so each person logs their own Telegram account in once (player Settings >
# Song search). Then the + on a grey song does what they'd do by hand, in THEIR chat with the Macaw bot: types
# "@musicbot Artist Title", picks the result that matches best and sends it. The bot gets it like any song they send.
# Only the Macaw server talks to this (internal Docker network, port 8090); it passes the player user's id as "uid".
# Logins are kept in /session (one file per person). Uses the server's api_id / api_hash (TG_API_ID, TG_API_HASH).
import asyncio, difflib, os, re, unicodedata
from aiohttp import web
from telethon import TelegramClient, errors
from telethon.tl.types import DocumentAttributeAudio, DocumentAttributeFilename

API_ID = int(os.environ.get("TG_API_ID") or 0)
API_HASH = os.environ.get("TG_API_HASH") or ""
DIR = "/session"
DEVICE = "Macaw song search"
WAIT_AUDIO = 75                      # seconds to wait when the music bot sends a placeholder first and the song later

clients, pending, locks = {}, {}, {}  # uid -> logged-in client; uid -> login in progress; uid -> one search at a time
def spath(uid): return os.path.join(DIR, f"u{int(uid)}")
def new_client(uid): return TelegramClient(spath(uid), API_ID, API_HASH, device_model=DEVICE, system_version="server", app_version="1.0")
def ok(**k): return web.json_response(k)
def err(msg, code=400, **k): return web.json_response({"error": msg, **k}, status=code)

async def client_of(uid):
    c = clients.get(uid)
    if c is None:
        if not os.path.exists(spath(uid) + ".session"): return None
        c = new_client(uid)
    try:
        if not c.is_connected(): await c.connect()
        if await c.is_user_authorized(): clients[uid] = c; return c
    except Exception as e: print(f"[{uid}] connect: {e}", flush=True)
    clients.pop(uid, None)
    return None

def forget(uid):
    clients.pop(uid, None)
    for ext in (".session", ".session-journal"):
        try: os.remove(spath(uid) + ext)
        except FileNotFoundError: pass

# ---------- login ----------
# By code: phone -> code (Telegram says where it sent it: the Telegram app, SMS, a call, email) -> 2FA password if any.
# By QR: the player shows a QR code, you scan it in Telegram on your phone (Settings > Devices > Link Desktop Device).
VIA = {"SentCodeTypeApp": "app", "SentCodeTypeSms": "sms", "SentCodeTypeFirebaseSms": "sms", "SentCodeTypeSmsWord": "sms",
       "SentCodeTypeSmsPhrase": "sms", "SentCodeTypeCall": "call", "SentCodeTypeFlashCall": "call", "SentCodeTypeMissedCall": "call",
       "SentCodeTypeEmailCode": "email", "SentCodeTypeSetUpEmailRequired": "setup_email", "SentCodeTypeFragmentSms": "fragment"}
def via_of(sent):
    name = type(getattr(sent, "type", None)).__name__
    return VIA.get(name, name)

def qr_svg(url):
    import io, qrcode, qrcode.image.svg
    buf = io.BytesIO()
    qrcode.make(url, image_factory=qrcode.image.svg.SvgPathImage, box_size=10, border=2).save(buf)
    return buf.getvalue().decode()

async def qr_loop(uid, p):                                # waits for the scan; the QR code changes every ~30 s
    qr = p["qr"]
    for _ in range(20):
        try:
            await qr.wait(25)
            p["state"] = "done"; return
        except asyncio.TimeoutError:
            if pending.get(uid) is not p: return
            await qr.recreate(); p["svg"] = qr_svg(qr.url)
        except errors.SessionPasswordNeededError:
            p["state"] = "password"; return
        except Exception as e:
            p["state"] = "error"; p["error"] = str(e); return
    p["state"] = "error"; p["error"] = "The QR code expired. Start again"

async def finish(uid, c):
    pending.pop(uid, None); clients[uid] = c
    me = await c.get_me()
    print(f"[{uid}] logged in as {me.id}", flush=True)
    return ok(done=True, name=me.first_name or me.username or str(me.id), id=me.id)

async def fresh(uid):                                     # drop any login in progress and any old login for this person
    old = pending.pop(uid, None)
    if old:
        t = old.get("task")
        if t: t.cancel()
        await old["c"].disconnect()
    c = clients.pop(uid, None)
    if c: await c.disconnect()
    forget(uid)
    c = new_client(uid); await c.connect()
    return c

async def login(req):
    j = await req.json(); uid = int(j.get("uid") or 0); step = j.get("step"); v = str(j.get("value") or "").strip()
    if not uid: return err("bad request")
    if step == "phone":
        phone = re.sub(r"[^\d+]", "", v)
        if not re.fullmatch(r"\+?\d{7,15}", phone): return err("That phone number doesn't look right. Write it with the country code, like +7 999 123 45 67")
        c = await fresh(uid)
        try: sent = await c.send_code_request(phone)
        except errors.FloodWaitError as e: await c.disconnect(); return err(f"Telegram asks to wait {e.seconds // 60 + 1} min before trying again")
        except (errors.PhoneNumberInvalidError, errors.PhoneNumberBannedError): await c.disconnect(); return err("Telegram doesn't accept that number")
        except Exception as e: await c.disconnect(); return err(f"Telegram said: {e}")
        via = via_of(sent)
        print(f"[{uid}] code sent via {via} ({type(sent.type).__name__})", flush=True)
        if via == "setup_email":
            await c.disconnect()
            return err("Telegram wants this account to have a login email before it sends codes here. Use the QR code instead")
        pending[uid] = {"c": c, "phone": phone, "hash": sent.phone_code_hash}
        return ok(next="code", via=via)
    if step == "qr":
        c = await fresh(uid)
        try: qr = await c.qr_login()
        except Exception as e: await c.disconnect(); return err(f"Telegram said: {e}")
        p = {"c": c, "qr": qr, "state": "wait", "svg": qr_svg(qr.url)}
        pending[uid] = p
        p["task"] = asyncio.create_task(qr_loop(uid, p))
        return ok(next="qr", svg=p["svg"])
    p = pending.get(uid)
    if not p: return err("Start again", restart=True)
    c = p["c"]
    if step == "qrwait":
        if "qr" not in p: return err("Start again", restart=True)
        if p["state"] == "done": return await finish(uid, c)
        if p["state"] == "password": return ok(next="password")
        if p["state"] == "error": pending.pop(uid, None); return err(p.get("error") or "Something went wrong. Start again", restart=True)
        return ok(next="qr", svg=p["svg"])
    try:
        if step == "resend":
            if "phone" not in p: return err("Start again", restart=True)
            from telethon.tl.functions.auth import ResendCodeRequest
            sent = await c(ResendCodeRequest(p["phone"], p["hash"]))
            p["hash"] = sent.phone_code_hash
            via = via_of(sent); print(f"[{uid}] code re-sent via {via}", flush=True)
            return ok(next="code", via=via)
        if step == "code":
            try: await c.sign_in(p["phone"], re.sub(r"\D", "", v), phone_code_hash=p["hash"])
            except errors.SessionPasswordNeededError: return ok(next="password")
        elif step == "password": await c.sign_in(password=v)
        else: return err("bad request")
    except errors.PhoneCodeInvalidError: return err("Wrong code. Check it and try again")
    except errors.PhoneCodeExpiredError: pending.pop(uid, None); await c.disconnect(); return err("The code expired. Start again", restart=True)
    except errors.PasswordHashInvalidError: return err("Wrong password")
    except errors.FloodWaitError as e: return err(f"Telegram asks to wait {e.seconds // 60 + 1} min")
    except Exception as e: return err(f"Telegram said: {e}")
    return await finish(uid, c)

async def logout(req):
    uid = int((await req.json()).get("uid") or 0)
    c = await client_of(uid)
    if c:
        try: await c.log_out()
        except Exception: pass
    forget(uid)
    return ok(ok=True)

async def status(req):
    uid = int(req.query.get("uid") or 0)
    c = await client_of(uid)
    if not c: return ok(ready=False)
    try: me = await c.get_me()
    except Exception as e: return ok(ready=False, error=str(e))
    return ok(ready=True, id=me.id, name=me.first_name or me.username or str(me.id))

# ---------- picking the best result ----------
JUNK = re.compile(r"\b(remix|live|cover|karaoke|instrumental|sped ?up|slowed|nightcore|reverb|8d|acoustic|demo|edit|version|mashup|minus|минус)\b", re.I)

def norm(s):
    s = unicodedata.normalize("NFKC", str(s or "")).casefold()
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", s)                                      # (Live), [Remastered 2004]...
    s = re.sub(r"\s[-–—]\s.*\b(remaster\w*|version|mono|stereo|edit|mix|bonus|deluxe|single)\b.*$", " ", s)   # " - 2004 Remaster"
    s = re.sub(r"\b(feat|ft|featuring)\b.*$", " ", s)
    return re.sub(r"[^\w]+", " ", s).strip()

def sim(a, b, artist=False):
    a, b = norm(a), norm(b)
    if artist: a, b = re.sub(r"^the ", "", a), re.sub(r"^the ", "", b)       # "The Sundays" = "Sundays"
    if not a or not b: return 0.0
    if a == b: return 1.0
    r = difflib.SequenceMatcher(None, a, b).ratio()
    short, long_ = sorted((a, b), key=len)
    if short in long_ and len(short) / len(long_) >= 0.75: r = max(r, 0.9)      # only when almost the whole title matches
    return r

def describe(r):
    """(title, artist, album, is_audio, is_album) of one inline result, from its audio tags or the text the bot shows."""
    title, desc = r.title or "", r.description or ""
    artist = album = ""
    doc, is_audio = r.document, False
    if doc is not None:
        is_audio = (doc.mime_type or "").startswith("audio/")
        for a in doc.attributes:
            if isinstance(a, DocumentAttributeAudio) and not a.voice:
                is_audio = True; title = a.title or title; artist = a.performer or artist
            elif isinstance(a, DocumentAttributeFilename) and not title:
                title = re.sub(r"\.[a-z0-9]{2,5}$", "", a.file_name, flags=re.I)
    m = re.search(r"(?:artist|исполнитель)\s*:\s*(.+)", desc, re.I)
    if m: artist = artist or m.group(1).strip()
    m = re.search(r"(?:album|альбом)\s*:\s*(.+)", desc, re.I)
    if m: album = m.group(1).strip()
    if not artist and desc: artist = desc.splitlines()[0].strip()
    if not artist and " - " in title: artist, title = [x.strip() for x in title.split(" - ", 1)]
    is_album = bool(re.search(r"\((album|ep|playlist|альбом)\)\s*$", r.title or "", re.I))
    return title, artist, album, is_audio, is_album

def score(r, want_artist, want_title, want_album):
    """0 = not this song. Title must match almost exactly, and the artist too when both are known."""
    title, artist, album, is_audio, is_album = describe(r)
    ts = sim(title, want_title)
    ars = sim(artist, want_artist, artist=True) if artist and want_artist else 0.5
    if is_album or ts < 0.85 or (artist and want_artist and ars < 0.8): return 0, title, artist
    s = 60 * ts + 35 * ars
    if want_album and album and sim(album, want_album) > 0.8: s += 5
    if is_audio: s += 3
    for w in set(x.lower() for x in JUNK.findall(title + " " + (r.title or ""))):
        if w not in want_title.lower(): s -= 15
    return s, title, artist

def is_audio_msg(m):
    return bool(m and m.media and (m.audio or (m.document and (m.document.mime_type or "").startswith("audio/"))))

async def find(req):
    j = await req.json()
    uid = int(j.get("uid") or 0)
    bot, target = str(j.get("bot") or "").lstrip("@"), str(j.get("target") or "").lstrip("@")
    artist, title, album = j.get("artist") or "", j.get("title") or "", j.get("album") or ""
    if not re.fullmatch(r"[A-Za-z0-9_]{4,32}", bot) or not target or not title: return err("bad request")
    client = await client_of(uid)
    if not client: return err("log in under Settings > Song search", 409, manual=True)
    clean = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip() or title
    async with locks.setdefault(uid, asyncio.Lock()):
        # Music bots' search is quirky: "the sundays your eyes" may not list the song at all while "the sundays your ey" puts
        # it first. So try a few phrasings, like a person would, and stop as soon as one gives an exact match.
        # Music bots also limit how often you may search ("Too many requests"), so at most 4 tries, with a pause between.
        # Telegram also keeps a bot's answer to the exact same text for a while (an empty "Too many requests" answer too),
        # so the tries are all different texts, lowercase ones included, the way someone typing would send them.
        low = f"{artist} {clean}".lower()
        queries = [f"{artist} {clean}"]
        if len(clean) > 5: queries.append(f"{artist} {clean[:-2]}".lower())   # cut short: oddly, often what makes the song show up
        queries += [low, f"{clean} {artist}".lower(), clean.lower()]
        if len(clean) > 6: queries.append(f"{artist} {clean[:-3]}".lower())
        queries = [q.strip() for q in dict.fromkeys(queries) if q.strip()][:5]
        pool, seen, problem, answered, limited = [], set(), None, False, ""
        for n, q in enumerate(queries):
            if n: await asyncio.sleep(1.5)
            got = None
            for i in range(4):                                 # music bots are often slow to answer the first time: ask again
                try: got = await client.inline_query(bot, q, entity=target); problem = None; break
                except errors.FloodWaitError as e:
                    problem = e
                    if e.seconds > 30: break
                    await asyncio.sleep(e.seconds + 1)
                except Exception as e:
                    problem = e; print(f"[{uid}] @{bot} '{q}' try {i + 1}: {type(e).__name__}: {e}", flush=True)
                    await asyncio.sleep(2 + 2 * i)
            if got is None: continue
            answered = True
            pm = getattr(getattr(got, "switch_pm", None), "text", "") or ""
            if not got and pm:                                 # a button instead of songs ("Too many requests"), maybe an old kept answer
                print(f"[{uid}] @{bot} '{q}': no results, button '{pm}'", flush=True)
                limited = pm; continue                         # a different text gets a fresh answer
            for r in got:
                key = (r.title, r.description, r.id if hasattr(r, "id") else None)
                if key not in seen: seen.add(key); pool.append(r)
            top_now = max((score(r, artist, title, album)[0] for r in got), default=0)
            print(f"[{uid}] '{q}': {len(got)} results, best {top_now:.0f}", flush=True)
            if top_now >= 80: break
        if not pool:
            if limited: return err(f"@{bot} says “{limited}”. Wait a few minutes (or open @{bot} and press its button), then try again", 429)
            if problem and not answered: return err(f"@{bot} didn't answer ({type(problem).__name__}). Try again in a minute", 502)
            return err(f"@{bot} found nothing", 404)
        ranked = sorted(((score(r, artist, title, album), r) for r in pool), key=lambda x: -x[0][0])
        (best, got_title, got_artist), r = ranked[0]
        top = [{"title": t, "artist": a, "score": round(s)} for (s, t, a), _ in ranked[:5]]
        print(f"[{uid}] {artist} - {title}: best {got_artist} - {got_title} ({best:.0f})", flush=True)
        if best < 55: return err("no exact match in @" + bot, 404, candidates=top)
        try: msg = await r.click(target)
        except Exception as e: return err(f"couldn't send the result: {e}", 502)
        if not is_audio_msg(msg):                          # some music bots send a placeholder first and put the song in later
            for _ in range(WAIT_AUDIO // 3):
                await asyncio.sleep(3)
                m = await client.get_messages(target, ids=msg.id)
                if is_audio_msg(m):
                    await client.send_file(target, m.media)         # again as a new message, so the Macaw bot surely sees it
                    try: await client.delete_messages(target, msg.id)
                    except Exception: pass
                    break
            else: return err(f"@{bot} didn't send a song", 504)
        return ok(ok=True, title=got_title, artist=got_artist, score=round(best), candidates=top)

async def main():
    os.makedirs(DIR, exist_ok=True)
    if not API_ID or not API_HASH: print("song search: TG_API_ID / TG_API_HASH are missing in /opt/macaw-player/.env, so it's off", flush=True)
    app = web.Application()
    app.router.add_get("/status", status); app.router.add_post("/login", login); app.router.add_post("/logout", logout); app.router.add_post("/find", find)
    runner = web.AppRunner(app); await runner.setup(); await web.TCPSite(runner, "0.0.0.0", 8090).start()
    print("song search: ready", flush=True)
    await asyncio.Event().wait()

asyncio.run(main())
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
if grep -q '^FINDER_URL=' .env; then echo "Song search is on: in the player, Settings > Song search > Log in (each person with their own account)."
else echo "Song search is off: it needs api_id/api_hash (the 'Big files' question). Without it, + opens the bot chat with the search typed in."; fi
