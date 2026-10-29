# Macaw Studio

A Windows design tool for MacawP3. Nick draws screens here (or copies the real MacawP3 screens and changes them), adds notes, then presses **Send to Claude**. That uploads a folder to `designs/` in this repo with:

- `design.json`: every item with exact position, size, colours, fonts, notes, tap links, and what changed from the real app. The source of truth.
- `README.md`: a plain summary plus every note, in order.
- `screens/*.png` (and `*.notes.png` with numbered note pins), `before-after/*.png`, `flow.png`.
- the editable `.macaw` file.

## Download

https://github.com/t6wy26zj95-creator/mp3-player/releases/download/studio/MacawStudio-Setup.exe

Every push to `main` that touches `studio/` builds a new version (`.github/workflows/studio.yml`). Installed copies update themselves.

## How it's built

- Electron. `main.js` is the Windows side (files, backups, pictures, GitHub upload, updates). `preload.js` gives the page `window.studioHost`.
- `app/` is the editor: plain JavaScript, no build step. Open `app/index.html` in a browser to try it without Electron (designs then live in the browser's storage, and pictures/GitHub upload are off).
- `app/render.html` draws the PNGs in a hidden window.
- Designs live in `Documents\Macaw Designs` as `.macaw` files (JSON). Backups (last 20 per design) are in the app's data folder.
- The MacawP3 parts and screens are in `app/js/parts.js`, copied from the real player's look. When the player's look changes a lot, update them there.
- Icons: Lucide (ISC license, `app/vendor/LICENSE-lucide.txt`).

Run locally: `cd studio && npm install && npm start`.
