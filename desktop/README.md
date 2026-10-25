# MacawP3 desktop app

The player (`../index.html`) as a Windows and Mac app, made with Electron.

- `main.js`: the window, the song library (Music\MacawP3), the screen capture behind Floating glass, and updates.
- `preload.js`: the bridge to the page. It looks like the iOS app's bridge, so the library and the Telegram link work
  the same way; `window.MACAW_DESK` adds the desktop parts.
- Floating glass (Windows 10 2004+ and 11): a frameless, see-through window. The app leaves itself out of screen
  captures, captures the screen under it, and the Liquid Glass shader in index.html draws that capture through the
  panel (search for `FLOAT` and `DESK` there). Settings > App turns it off (then it's a normal window with the wallpaper).
- Builds and updates: `.github/workflows/desktop.yml`. Main goes to the `desktop` release, other branches to
  `desktop-preview`; the app updates itself from there.

Try it locally: `cd desktop && npm install && mkdir -p www && cp ../index.html www/ && npm start`
(without `www/` it serves the repo's index.html directly).
