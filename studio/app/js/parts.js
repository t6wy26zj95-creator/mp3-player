/* MacawP3 parts and whole screens, built from the player's real sizes and colours (index.html, October 2026).
   Each part says which bit of the real app it is (part: "macawp3:..."), so Claude knows which code to change. */
"use strict";
(() => {
const N = S.newItem;
const W = "#FFFFFF", DIM = "rgba(255,255,255,0.55)", GLASS = "rgba(255,255,255,0.10)", GB = "rgba(255,255,255,0.15)";
const txt = (content, o = {}) => N("text", Object.assign({ status: "keep", text: Object.assign({ content, font: "Inter", size: 13, weight: 400, lh: 0, ls: 0, align: "left", valign: "top", color: W, sizing: "fixed", overflow: "ellipsis", sample: "fixed" }, o.t || {}) }, o, { t: undefined }));
const grp = (name, x, y, w, h, children, o = {}) => N("group", Object.assign({ name, x, y, w, h, children, status: "keep" }, o));
const keep = (it, part) => { S.walk([it], i => { i.status = "keep"; }); if (part) it.part = part; return it; };
const roundBtn = (name, icon, x, y, size, part, filled = true) => keep(N("button", { name, x, y, w: size, h: size, radius: size / 2,
  fills: [{ kind: "solid", color: GLASS }], stroke: { color: GB, width: 1, style: "solid" },
  effects: [{ kind: "shadow", color: "rgba(0,0,0,0.2)", x: 0, y: 2, blur: 5, spread: 0, on: true }],
  text: { content: "", font: "Inter", size: 13, weight: 600, align: "center", valign: "middle", color: W, sample: "fixed" },
  icon: { name: icon, size: Math.round(size * 0.41), color: W, pos: "only", filled, stroke: 2 } }), part);
const cover = (name, x, y, s, r, colors, part) => keep(N("cover", { name, x, y, w: s, h: s, radius: r, fills: [{ kind: "linear", color: colors[0], color2: colors[1], angle: 135 }] }), part);
const glassCard = (name, x, y, w, h, r, part, children = []) => keep(N("frame", { name, x, y, w, h, radius: r, clip: true, fills: [],
  effects: [{ kind: "glass", glass: "liquid", on: true }], children }), part);
const COVERS = [["#E8A04C", "#5A1F4A"], ["#4CC9E8", "#3A4AB5"], ["#9BE84C", "#1F6B4A"], ["#E84C9B", "#5A1F8A"], ["#E8D84C", "#B5783A"], ["#4CE8B0", "#1F4A6B"], ["#7A8CFF", "#2A1F5A"], ["#FF8A5C", "#7A2A1F"], ["#C04CE8", "#3A1F6B"]];
const SONGS = [["Midnight Drive", "Aurora Fields"], ["Slow Bloom", "Aurora Fields"], ["Glass Ocean", "Kairo"], ["Fernweh", "Ash Lane"], ["Pink Static", "Mira Vale"], ["Gold Hour", "The Sundays"], ["Low Tide", "Okan"], ["Northbound", "Velvet Sky"], ["Celeste", "Nova"]];

/* ---------- small parts (each made at 0,0) ---------- */
const P = {};
P.playerControls = () => grp("Controls", 0, 0, 114, 34, [
  roundBtn("Previous", "skip-back", 0, 0, 34, "macawp3:#prev-btn"), roundBtn("Play / Pause", "play", 40, 0, 34, "macawp3:#play-btn"), roundBtn("Next", "skip-forward", 80, 0, 34, "macawp3:#next-btn")
], { part: "macawp3:.controls-cluster" });
P.scrubber = (w = 200) => grp("Scrubber", 0, 0, w, 16, [
  txt("0:00", { name: "Current time", x: 0, y: 0, w: 30, h: 16, t: { size: 11, color: "rgba(255,255,255,0.7)" } }),
  keep(N("slider", { name: "Seek bar", x: 36, y: 0, w: w - 72, h: 16, slider: { value: 0, track: "rgba(255,255,255,0.20)", fill: W, knob: W, knobSize: 14, thickness: 4 } }), "macawp3:#seek-bar"),
  txt("0:40", { name: "Length", x: w - 30, y: 0, w: 30, h: 16, t: { size: 11, color: "rgba(255,255,255,0.7)", align: "right" } })
], { part: "macawp3:.scrubber" });
P.songInfo = () => grp("Song info", 0, 0, 220, 42, [
  txt("Midnight Drive", { name: "Song title", x: 0, y: 0, w: 220, h: 22, t: { size: 17, weight: 600, sample: "song" }, part: "macawp3:.track-title" }),
  txt("Aurora Fields ›", { name: "Artist", x: 0, y: 24, w: 220, h: 18, t: { size: 13, color: DIM, sample: "artist" }, part: "macawp3:.track-artist" })
]);
P.tabs = (active = "Library", w = 313) => {
  const names = ["+ Songs", "Queue", "Library", "Artists"], cw = w / 4, kids = [];
  names.forEach((n, i) => {
    if (n === active) kids.push(keep(N("rect", { name: "Active tab pill", x: i * cw + 2, y: 2, w: cw - 4, h: 30, radius: 15, fills: [{ kind: "solid", color: "rgba(255,255,255,0.12)" }],
      stroke: { color: "rgba(255,255,255,0.2)", width: 1, style: "solid" }, effects: [{ kind: "glass", glass: "liquid", on: true }] }), "macawp3:.tab-pill"));
    kids.push(keep(N("button", { name: n + " tab", x: i * cw, y: 0, w: cw, h: 34, radius: 0, pad: 0, fills: [], stroke: null,
      text: { content: n, font: "Inter", size: 11, weight: 600, ls: 0.5, align: i === 0 ? "left" : "center", valign: "middle", color: n === active || i === 0 ? W : "rgba(255,255,255,0.40)", case: "uppercase", sample: "fixed" },
      icon: { name: "", size: 14, color: W, pos: "left" } }), i === 0 ? "macawp3:#btn-add" : "macawp3:#btn-" + { Queue: "queue", Library: "playlist", Artists: "artists" }[n]));
  });
  return grp("Tab buttons", 0, 0, w, 34, kids, { part: "macawp3:.tab-buttons" });
};
P.albumTile = (i = 0, s = 96) => grp("Album card", 0, 0, s, s + 22, [
  i < 0 ? keep(N("frame", { name: "All Tracks tile", x: 0, y: 0, w: s, h: s, radius: 14, fills: [{ kind: "solid", color: "rgba(255,255,255,0.06)" }], stroke: { color: GB, width: 1, style: "solid" }, children: [
    keep(N("icon", { name: "Folder icon", x: s / 2 - 18, y: s / 2 - 18, w: 36, h: 36, icon: { name: "folder", color: "rgba(255,255,255,0.55)", stroke: 2, filled: true } }))] }))
    : cover("Cover", 0, 0, s, 14, COVERS[i % COVERS.length]),
  txt(i < 0 ? "All Tracks" : SONGS[i % SONGS.length][0], { name: "Album name", x: 0, y: s + 7, w: s, h: 15, t: { size: 11, weight: 600, align: "center", color: "rgba(255,255,255,0.8)" }, part: "macawp3:.album-card-title" })
], { part: "macawp3:.album-card" });
P.songRow = (i = 0, w = 313) => grp("Song row", 0, 0, w, 52, [
  cover("Cover", 0, 6, 40, 8, COVERS[i % COVERS.length]),
  txt(SONGS[i % SONGS.length][0], { name: "Song title", x: 52, y: 8, w: w - 90, h: 18, t: { size: 13, weight: 500, sample: "song" }, part: "macawp3:.item-title" }),
  txt(SONGS[i % SONGS.length][1], { name: "Artist", x: 52, y: 27, w: w - 90, h: 16, t: { size: 11, color: DIM, sample: "artist" }, part: "macawp3:.item-artist" }),
  keep(N("icon", { name: "Drag handle", x: w - 22, y: 16, w: 20, h: 20, icon: { name: "grip-vertical", color: "rgba(255,255,255,0.35)", stroke: 2 } }))
], { part: "macawp3:.queue-item" });
P.artistRow = (i = 0, w = 313) => grp("Artist row", 0, 0, w, 56, [
  keep(N("cover", { name: "Artist photo", x: 0, y: 4, w: 48, h: 48, radius: 24, fills: [{ kind: "linear", color: COVERS[i % 9][0], color2: COVERS[i % 9][1], angle: 135 }], effects: [] })),
  txt(SONGS[i % 9][1], { name: "Artist name", x: 62, y: 10, w: w - 90, h: 18, t: { size: 15, weight: 600 } }),
  txt((i % 4 + 1) + " albums · " + (i * 3 % 17 + 4) + " songs", { name: "Counts", x: 62, y: 31, w: w - 90, h: 16, t: { size: 12, color: DIM } }),
  keep(N("icon", { name: "Chevron", x: w - 20, y: 18, w: 18, h: 18, icon: { name: "chevron-right", color: "rgba(255,255,255,0.35)", stroke: 2 } }))
], { part: "macawp3:.artist-row" });
P.miniPlayer = (w = 361) => keep(N("frame", { name: "Mini player", x: 0, y: 0, w, h: 62, radius: 31, clip: true, effects: [{ kind: "glass", glass: "liquid", on: true }], children: [
  cover("Cover", 10, 10, 42, 10, COVERS[0]),
  txt("Midnight Drive", { name: "Song title", x: 62, y: 13, w: w - 140, h: 18, t: { size: 13, weight: 600, sample: "song" } }),
  txt("Aurora Fields", { name: "Artist", x: 62, y: 32, w: w - 140, h: 16, t: { size: 12, color: DIM, sample: "artist" } }),
  roundBtn("Play / Pause", "play", w - 52, 14, 34, "macawp3:#play-btn")
] }), "new:mini-player");
P.glassCard = () => glassCard("Glass card", 0, 0, 240, 160, 28, "macawp3:.glass-panel");
P.gear = () => keep(roundBtn("Settings button", "settings", 0, 0, 44, "macawp3:#settings-btn"));
P.toggle = (on = false) => keep(N("toggle", { name: "Toggle", w: 46, h: 28, toggle: { on, onColor: "#3E8E86", offColor: "rgba(255,255,255,0.10)", knob: W } }), "macawp3:.switch");
P.setRow = (title = "Cover Flow", sub = "Albums in one row that you flip through", w = 335, tog = true) => grp("Settings row", 0, 0, w, sub ? 64 : 50, [
  txt(title, { name: "Row title", x: 14, y: sub ? 12 : 15, w: w - 90, h: 20, t: { size: 15, weight: 500 } }),
  sub ? txt(sub, { name: "Row hint", x: 14, y: 34, w: w - 90, h: 16, t: { size: 12, color: DIM } }) : null,
  tog ? Object.assign(P.toggle(false), { x: w - 60, y: sub ? 18 : 11 }) : keep(N("icon", { name: "Chevron", x: w - 32, y: 16, w: 18, h: 18, icon: { name: "chevron-right", color: "rgba(255,255,255,0.35)" } }))
].filter(Boolean), { part: "macawp3:.set-row" });
P.setGroup = (title, rows, w = 335) => {
  let y = 0; const kids = [];
  rows.forEach((r, i) => { const g = P.setRow(r[0], r[1], w, r[2] !== false); g.y = y; kids.push(g); y += g.h; if (i < rows.length - 1) kids.push(keep(N("line", { name: "Divider", x: 14, y, w: w - 14, h: 0, stroke: { color: "rgba(255,255,255,0.08)", width: 1, style: "solid" } }))); });
  const box = keep(N("frame", { name: title + " group", x: 0, y: 22, w, h: y, radius: 16, clip: true, fills: [{ kind: "solid", color: "rgba(255,255,255,0.06)" }], stroke: { color: "rgba(255,255,255,0.10)", width: 1, style: "solid" }, children: kids }), "macawp3:.set-group");
  return grp(title + " section", 0, 0, w, y + 22, [txt(title, { name: "Section title", x: 6, y: 0, w: w - 12, h: 16, t: { size: 11, weight: 600, ls: 0.5, case: "uppercase", color: DIM }, part: "macawp3:.set-h" }), box]);
};
P.volume = (w = 220) => grp("Volume slider", 0, 0, w, 20, [
  keep(N("icon", { name: "Quiet", x: 0, y: 2, w: 16, h: 16, icon: { name: "volume", color: DIM } })),
  keep(N("slider", { name: "Volume", x: 24, y: 0, w: w - 48, h: 20, slider: { value: 0.7, track: "rgba(255,255,255,0.20)", fill: W, knob: W, knobSize: 14, thickness: 4 } })),
  keep(N("icon", { name: "Loud", x: w - 16, y: 2, w: 16, h: 16, icon: { name: "volume-2", color: DIM } }))
]);
P.lyrics = (w = 313) => grp("Lyrics block", 0, 0, w, 150, [
  txt("Driving through the city lights", { name: "Line (past)", x: 0, y: 0, w, h: 26, t: { size: 20, weight: 700, color: "rgba(255,255,255,0.35)", overflow: "wrap" } }),
  txt("Midnight on the radio", { name: "Line (now)", x: 0, y: 40, w, h: 26, t: { size: 22, weight: 700, overflow: "wrap" } }),
  txt("Every song a place we know", { name: "Line (next)", x: 0, y: 82, w, h: 26, t: { size: 20, weight: 700, color: "rgba(255,255,255,0.35)", overflow: "wrap" } })
], { part: "macawp3:.xp-lyrics" });
P.backBtn = () => keep(N("button", { name: "Back button", w: 88, h: 34, radius: 17, fills: [{ kind: "solid", color: GLASS }], stroke: { color: GB, width: 1, style: "solid" },
  text: { content: "Back", font: "Inter", size: 13, weight: 600, align: "center", valign: "middle", color: W, sample: "fixed" }, icon: { name: "chevron-left", size: 16, color: W, pos: "left" } }), "macawp3:.back-btn");
P.sectionHeader = (t = "Albums") => txt(t, { name: "Section header", w: 200, h: 18, t: { size: 13, weight: 700, ls: 0.3, color: "rgba(255,255,255,0.85)" }, part: "macawp3:.artist-sec" });
P.playlistCard = () => grp("Playlist card", 0, 0, 150, 190, [
  keep(N("frame", { name: "Mosaic", x: 0, y: 0, w: 150, h: 150, radius: 14, clip: true, children: [0, 1, 2, 3].map(i => cover("Cover " + (i + 1), (i % 2) * 75, Math.floor(i / 2) * 75, 75, 0, COVERS[i + 2])) })),
  txt("Late night", { name: "Playlist name", x: 0, y: 158, w: 150, h: 16, t: { size: 13, weight: 600 } }),
  txt("12 songs", { name: "Song count", x: 0, y: 175, w: 150, h: 15, t: { size: 11, color: DIM } })
], { part: "macawp3:.pl-card" });
P.bigCover = () => cover("Album cover", 0, 0, 280, 18, COVERS[0], "macawp3:#xp-art");
P.bigControls = () => grp("Big controls", 0, 0, 313, 54, [
  roundBtn("Shuffle", "shuffle", 0, 11, 34, "macawp3:.xp-tog"), roundBtn("Previous", "skip-back", 62, 4, 46, "macawp3:#xp-prev"),
  roundBtn("Play / Pause", "play", 129.5, 0, 54, "macawp3:#xp-play"), roundBtn("Next", "skip-forward", 205, 4, 46, "macawp3:#xp-next"), roundBtn("Repeat", "repeat", 279, 11, 34, "macawp3:.xp-tog")
], { part: "macawp3:.xp-ctrls" });

/* ---------- whole screens ---------- */
const sc = (name, items, o = {}) => Object.assign(S.newScreen("iphone15pro", { name, status: "keep", items }), o);
const put = (it, x, y) => Object.assign(it, { x, y });
const playerTop = (active) => [
  cover("Cover", 24, 24, 66, 14, COVERS[0], "macawp3:#cover"),
  put(P.songInfo(), 104, 34),
  put(P.playerControls(), 24, 108),
  put(P.scrubber(193), 144, 117),
  put(P.tabs(active), 24, 158)
];
const SCREENS = {};
SCREENS.library = () => {
  const tiles = []; for (let i = 0; i < 9; i++) tiles.push(put(P.albumTile(i === 0 ? -1 : i - 1, 92), 24 + (i % 3) * 112.5, 222 + Math.floor(i / 3) * 132));
  return sc("Library", [
    glassCard("Player card", 16, 71, 361, 670, 40, "macawp3:.player-wrapper", [...playerTop("Library"),
      keep(N("line", { name: "Divider", x: 24, y: 204, w: 313, h: 0, stroke: { color: "rgba(255,255,255,0.10)", width: 1, style: "solid" } })), ...tiles]),
    put(P.gear(), 325, 760)
  ], { basedOn: "library" });
};
SCREENS.queue = () => {
  const rows = []; for (let i = 0; i < 8; i++) rows.push(put(P.songRow(i + 1), 24, 214 + i * 56));
  return sc("Queue", [glassCard("Player card", 16, 71, 361, 670, 40, "macawp3:.player-wrapper", [...playerTop("Queue"),
    keep(N("line", { name: "Divider", x: 24, y: 204, w: 313, h: 0, stroke: { color: "rgba(255,255,255,0.10)", width: 1, style: "solid" } })), ...rows]), put(P.gear(), 325, 760)], { basedOn: "queue" });
};
SCREENS.artists = () => {
  const rows = []; for (let i = 0; i < 7; i++) rows.push(put(P.artistRow(i), 24, 214 + i * 62));
  return sc("Artists", [glassCard("Player card", 16, 71, 361, 670, 40, "macawp3:.player-wrapper", [...playerTop("Artists"),
    keep(N("line", { name: "Divider", x: 24, y: 204, w: 313, h: 0, stroke: { color: "rgba(255,255,255,0.10)", width: 1, style: "solid" } })), ...rows]), put(P.gear(), 325, 760)], { basedOn: "artists" });
};
SCREENS.bigplayer = () => sc("Big player", [
  keep(N("rect", { name: "Handle", x: 172, y: 66, w: 48, h: 5, radius: 3, fills: [{ kind: "solid", color: "rgba(255,255,255,0.35)" }] }), "macawp3:.xp-handle"),
  put(Object.assign(P.bigCover(), { w: 313, h: 313 }), 40, 92),
  txt("Midnight Drive", { name: "Song title", x: 40, y: 430, w: 313, h: 26, t: { size: 20, weight: 600, align: "center", sample: "song" }, part: "macawp3:.xp-title" }),
  txt("Aurora Fields · Night Roads", { name: "Artist and album", x: 40, y: 460, w: 313, h: 18, t: { size: 13.5, align: "center", color: DIM, sample: "artist" }, part: "macawp3:.xp-sub" }),
  keep(N("slider", { name: "Seek bar", x: 40, y: 500, w: 313, h: 16, slider: { value: 0.35, track: "rgba(255,255,255,0.20)", fill: W, knob: W, knobSize: 0, thickness: 4 } }), "macawp3:.xp-scrub"),
  txt("1:24", { name: "Current time", x: 40, y: 524, w: 60, h: 14, t: { size: 11, color: "rgba(255,255,255,0.6)" } }),
  txt("-2:13", { name: "Time left", x: 293, y: 524, w: 60, h: 14, t: { size: 11, color: "rgba(255,255,255,0.6)", align: "right" } }),
  put(P.bigControls(), 40, 556),
  txt("Queue", { name: "Queue label", x: 22, y: 700, w: 120, h: 16, t: { size: 12, weight: 600, color: DIM }, part: "macawp3:.xp-next-h" }),
  txt("See all", { name: "See all", x: 271, y: 700, w: 100, h: 16, t: { size: 12, weight: 600, color: DIM, align: "right" }, part: "macawp3:#xp-see-all" }),
  ...[0, 1].map(i => keep(N("frame", { name: "Queue card", x: 20 + i * 146, y: 726, w: 138, h: 52, radius: 14, fills: [{ kind: "solid", color: "rgba(255,255,255,0.08)" }], children: [
    cover("Cover", 6, 6, 40, 9, COVERS[i + 2]), txt(SONGS[i + 2][0], { name: "Title", x: 54, y: 9, w: 78, h: 16, t: { size: 12, weight: 600 } }), txt(SONGS[i + 2][1], { name: "Artist", x: 54, y: 27, w: 78, h: 15, t: { size: 11, color: DIM } })] }), "macawp3:.xp-card"))
], { basedOn: "bigplayer" });
SCREENS.settings = () => sc("Settings", [
  glassCard("Settings sheet", 16, 71, 361, 740, 32, "macawp3:#settings", [
    txt("Settings", { name: "Title", x: 20, y: 22, w: 200, h: 28, t: { size: 20, weight: 700 } }),
    roundBtn("Close", "x", 309, 18, 34, "macawp3:.set-close"),
    put(P.setGroup("Library", [["Cover Flow", "Albums in one row that you flip through, instead of the grid"], ["Hidden albums", "", false]], 321), 20, 76),
    put(P.setGroup("Sound effect", [["None", "Your songs as they are", false], ["Gramophone", "", false], ["Old radio", "", false], ["Vinyl", "", false]], 321), 20, 238),
    put(P.setGroup("Appearance", [["Classic panel", "Plain frosted glass instead of Liquid Glass"]], 321), 20, 488)
  ])
], { basedOn: "settings" });
SCREENS.lyrics = () => sc("Lyrics", [
  cover("Cover", 24, 76, 48, 10, COVERS[0]),
  txt("Midnight Drive", { name: "Song title", x: 84, y: 80, w: 250, h: 20, t: { size: 15, weight: 600, sample: "song" } }),
  txt("Aurora Fields", { name: "Artist", x: 84, y: 101, w: 250, h: 16, t: { size: 12, color: DIM, sample: "artist" } }),
  put(Object.assign(P.lyrics(345), { h: 360 }), 24, 180),
  put(P.scrubber(345), 24, 740)
], { basedOn: "lyrics" });

/* ---------- the catalog shown in the Parts tab ---------- */
S.PARTS = [
  { id: "scr-library", name: "Library (player + grid)", group: "Screens", screen: SCREENS.library },
  { id: "scr-queue", name: "Queue", group: "Screens", screen: SCREENS.queue },
  { id: "scr-artists", name: "Artists", group: "Screens", screen: SCREENS.artists },
  { id: "scr-big", name: "Big player", group: "Screens", screen: SCREENS.bigplayer },
  { id: "scr-settings", name: "Settings", group: "Screens", screen: SCREENS.settings },
  { id: "scr-lyrics", name: "Lyrics", group: "Screens", screen: SCREENS.lyrics },
  { id: "p-cover", name: "Album cover", group: "Player", make: () => cover("Album cover", 0, 0, 160, 14, COVERS[0], "macawp3:#cover") },
  { id: "p-bigcover", name: "Big album cover", group: "Player", make: P.bigCover },
  { id: "p-play", name: "Play / Pause", group: "Player", make: () => roundBtn("Play / Pause", "play", 0, 0, 54, "macawp3:#play-btn") },
  { id: "p-controls", name: "Prev / Play / Next", group: "Player", make: P.playerControls },
  { id: "p-bigcontrols", name: "Big player controls", group: "Player", make: P.bigControls },
  { id: "p-scrub", name: "Scrubber", group: "Player", make: () => P.scrubber(260) },
  { id: "p-info", name: "Song title + artist", group: "Player", make: P.songInfo },
  { id: "p-volume", name: "Volume slider", group: "Player", make: () => P.volume(220) },
  { id: "p-lyrics", name: "Lyrics block", group: "Player", make: P.lyrics },
  { id: "p-tabs", name: "Tab buttons", group: "Navigation", make: () => P.tabs("Library") },
  { id: "p-mini", name: "Mini player", group: "Navigation", make: () => P.miniPlayer(361) },
  { id: "p-back", name: "Back button", group: "Navigation", make: P.backBtn },
  { id: "p-gear", name: "Settings button", group: "Navigation", make: P.gear },
  { id: "p-songrow", name: "Song row", group: "Lists", make: () => P.songRow(0) },
  { id: "p-album", name: "Album card", group: "Lists", make: () => P.albumTile(0) },
  { id: "p-artist", name: "Artist row", group: "Lists", make: () => P.artistRow(0) },
  { id: "p-playlist", name: "Playlist card", group: "Lists", make: P.playlistCard },
  { id: "p-sechead", name: "Section header", group: "Lists", make: () => P.sectionHeader() },
  { id: "p-setgroup", name: "Settings group", group: "Settings", make: () => P.setGroup("Library", [["Cover Flow", "Albums in one row that you flip through"], ["Hidden albums", "", false]]) },
  { id: "p-setrow", name: "Settings row", group: "Settings", make: () => P.setRow() },
  { id: "p-toggle", name: "Toggle", group: "Settings", make: () => P.toggle(true) },
  { id: "p-glass", name: "Glass card", group: "Surfaces", make: P.glassCard },
  { id: "p-glow", name: "Album-colour glow", group: "Surfaces", make: () => keep(N("ellipse", { name: "Album glow", w: 220, h: 220, fills: [{ kind: "radial", color: "rgba(232,140,76,0.55)", color2: "rgba(232,140,76,0)" }], effects: [{ kind: "blur", blur: 30, on: true }] }), "macawp3:.art-bloom") }
];
S.BASIC = [
  { id: "b-btn", name: "Filled button", make: () => N("button", { name: "Button", fills: [{ kind: "solid", color: "#2BB3C0" }], stroke: null, text: { content: "Continue", font: "Inter", size: 15, weight: 600, align: "center", valign: "middle", color: "#0A1A20", sample: "fixed" } }) },
  { id: "b-btn2", name: "Outline button", make: () => N("button", { name: "Button", fills: [], stroke: { color: "#FFFFFF", width: 1.5, style: "solid" }, text: { content: "Cancel", font: "Inter", size: 15, weight: 600, align: "center", valign: "middle", color: "#FFFFFF", sample: "fixed" } }) },
  { id: "b-glassbtn", name: "Glass button", make: () => N("button", { name: "Glass button", effects: [{ kind: "glass", glass: "liquid", on: true }] }) },
  { id: "b-iconbtn", name: "Round icon button", make: () => roundBtn("Icon button", "heart", 0, 0, 44, "", false) },
  { id: "b-textbtn", name: "Text button", make: () => N("button", { name: "Text button", w: 100, h: 32, fills: [], stroke: null, text: { content: "See all", font: "Inter", size: 13, weight: 600, align: "center", valign: "middle", color: "#2BB3C0", sample: "fixed" } }) },
  { id: "b-card", name: "Card", make: () => N("frame", { name: "Card", w: 300, h: 160, radius: 20, fills: [{ kind: "solid", color: "rgba(255,255,255,0.08)" }], stroke: { color: "rgba(255,255,255,0.12)", width: 1, style: "solid" }, children: [] }) },
  { id: "b-input", name: "Search field", make: () => N("input", { name: "Search field" }) },
  { id: "b-toggle", name: "Toggle", make: () => N("toggle") },
  { id: "b-check", name: "Checkbox", make: () => N("checkbox") },
  { id: "b-slider", name: "Slider", make: () => N("slider") },
  { id: "b-progress", name: "Progress ring", make: () => N("progress") },
  { id: "b-badge", name: "Badge", make: () => N("badge") },
  { id: "b-divider", name: "Divider", make: () => N("line", { name: "Divider", w: 300, stroke: { color: "rgba(255,255,255,0.12)", width: 1, style: "solid" } }) },
  { id: "b-ph", name: "Placeholder", make: () => N("placeholder") },
  { id: "b-tabbar", name: "Bottom tab bar", make: () => { const ic = ["house", "search", "library", "user"], lab = ["Home", "Search", "Library", "Me"];
    return N("frame", { name: "Tab bar", w: 361, h: 64, radius: 32, effects: [{ kind: "glass", glass: "liquid", on: true }], children: ic.map((n, i) => N("button", { name: lab[i] + " tab", x: 8 + i * 86, y: 6, w: 86, h: 52, radius: 26, fills: i === 0 ? [{ kind: "solid", color: "rgba(255,255,255,0.12)" }] : [], stroke: null,
      text: { content: "", font: "Inter", size: 10, weight: 600, align: "center", valign: "middle", color: i === 0 ? "#FFFFFF" : "rgba(255,255,255,0.5)", sample: "fixed" }, icon: { name: n, size: 22, color: i === 0 ? "#FFFFFF" : "rgba(255,255,255,0.5)", pos: "only" } })) }); } },
  { id: "b-sheet", name: "Bottom sheet", make: () => N("frame", { name: "Bottom sheet", w: 393, h: 360, radius: 28, effects: [{ kind: "glass", glass: "frosted", on: true }], children: [N("rect", { name: "Grabber", x: 176, y: 8, w: 40, h: 5, radius: 3, fills: [{ kind: "solid", color: "rgba(255,255,255,0.4)" }] })] }) },
  { id: "b-list", name: "List row", make: () => P.setRow("List row", "Second line", 335, false) },
  { id: "b-title", name: "Screen title", make: () => N("text", { name: "Screen title", w: 300, h: 36, text: { content: "Library", font: "Inter", size: 30, weight: 700, color: "#FFFFFF", align: "left", valign: "top", sizing: "hug", sample: "fixed" } }) }
];
S.SCREEN_MAKERS = SCREENS;
S.MACAW_SCREENS = [["library", "Library"], ["queue", "Queue"], ["artists", "Artists"], ["bigplayer", "Big player"], ["settings", "Settings"], ["lyrics", "Lyrics"]];
})();
