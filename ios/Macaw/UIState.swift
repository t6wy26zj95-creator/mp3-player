import SwiftUI

/// What's open on screen: the drawer tab and where you are in it, the big player, Settings, menus.
@MainActor @Observable
final class UIState {
    static let shared = UIState()

    var tab: DrawerTab?                 // nil = drawer closed
    var libraryPath: [Route] = []       // Library remembers where you were (open album, scroll) for the session
    var artistsPath: [Route] = []
    var expanded = false                // the big player
    var lyricsScroll: CGFloat = 0       // the big player scrolled up to show the lyrics bubble (0 = at the top)
    var lyricsMax: CGFloat = 0          // how far it scrolls: the bubble plus room under it
    var lyricsOpen = false
    var navDir = 0                      // which way the drawer last moved: 1 into a page, -1 back, 0 a tab switch              // the full lyrics fill the panel
    var settingsOpen = false
    var importing = false
    var menu: MenuState?
    var prompt: Prompt?
    var confirm: Confirm?
    var coverPickFor: String?           // tile key whose cover you're choosing
    var classic = false                 // set from the saved settings at start (Boot)
    var minimalLight = false
    var editing = false                 // Library: rearranging tiles (they jiggle; Done replaces the tabs)
    var tileDragging = false
    /// A phone on its side (web: orientation landscape, height under 500/560).
    var land = false
    /// The room the drawer's lists may take (web --room), set by RootView.
    var room: CGFloat = 400
    /// web --xs on its side: the big player's cover, as tall as the screen allows.
    var landArt: CGFloat = 200
    /// web html.cf-land: on its side with the Library open as Cover Flow, only the tabs and the row of covers show.
    var landFlow: Bool { land && coverFlow && tab == .library && libraryPath.isEmpty && !expanded }
    var coverFlow = false               // Settings > Cover Flow: albums in one row instead of the grid
    var dimGlass = false                // Settings > Dim glass: a light shade behind the clear glass
    // Settings > Glass lab (temporary, to tune Apple's glass on the phone itself): % of black behind the glass, % of grey
    // taken out of it, % of Apple's own black tint, and regular (frosted) instead of clear glass
    var glassBehind: Double = 0
    var glassSub: Double = 4
    var glassTint: Double = 14
    var glassRegular = false
    var glassLight = false              // the glass drawn in light mode (it adapts its own shading to the colour scheme)
    var glassPeek = false               // a glass slider is held: Settings fades so the panel shows
    var blur: Double = 0
    var wallpaper: UIImage?
    var wallpaperVersion = 0
    /// web wallTone (--scrim): how much darker the Classic panel and Settings get over a bright wallpaper
    var scrim: Double = 0

    struct MenuState: Identifiable {
        let id = UUID()
        var kind: Kind
        var anchor: CGRect
        enum Kind { case song(Track, inPlaylist: String?), tile(Tile) }
    }

    struct Confirm: Identifiable {
        let id = UUID()
        var text: String
        var ok: () -> Void
    }

    struct Prompt: Identifiable {
        let id = UUID()
        var title: String
        var text: String
        var button: String
        var done: (String) -> Void
    }

    func open(_ t: DrawerTab) {
        if expanded { XPMotion.shared.close { self.open(t) }; return }   // the big player folds back first
        navDir = 0
        withAnimation(Theme.ease) {
            tab = tab == t ? nil : t
        }
        Haptics.select()
    }

    func push(_ r: Route) {
        navDir = 1
        withAnimation(Theme.ease) {
            if tab == .artists { artistsPath.append(r) } else { libraryPath.append(r) }
        }
    }
    func back() {
        navDir = -1
        withAnimation(Theme.ease) {
            if tab == .artists { _ = artistsPath.popLast() } else { _ = libraryPath.popLast() }
        }
    }
    /// Opens one of your albums in the Library (web: a hidden album tapped in Settings).
    func openAlbum(_ name: String) {
        if expanded { XPMotion.shared.close { self.openAlbum(name) }; return }
        navDir = 1
        withAnimation(Theme.ease) { tab = .library; libraryPath = [.album(name)] }
    }
    /// Opens an artist's page (from the artist name under a song).
    func showArtist(_ name: String) {
        if expanded { XPMotion.shared.close { self.showArtist(name) }; return }
        withAnimation(Theme.ease) {
            tab = .artists
            if artistsPath.last != .artist(name) { artistsPath = [.artist(name)] }
        }
    }

    func setClassic(_ on: Bool) { classic = on; Store.shared["oldPanel"] = on ? "1" : "" }
    func setCoverFlow(_ on: Bool) { coverFlow = on; Store.shared["libView"] = on ? "flow" : "grid" }
    func setDimGlass(_ on: Bool) { dimGlass = on; Store.shared["glassDim"] = on ? "1" : "" }
    func setGlassLab(behind: Double? = nil, sub: Double? = nil, tint: Double? = nil, regular: Bool? = nil, light: Bool? = nil) {
        if let light { glassLight = light; Store.shared["glassLight"] = light ? "1" : "" }
        if let behind { glassBehind = behind; Store.shared["glassBehind"] = String(Int(behind)) }
        if let sub { glassSub = sub; Store.shared["glassSub"] = String(Int(sub)) }
        if let tint { glassTint = tint; Store.shared["glassTint"] = String(Int(tint)) }
        if let regular { glassRegular = regular; Store.shared["glassRegular"] = regular ? "1" : "" }
    }
    func setMinimalLight(_ on: Bool) { minimalLight = on; Store.shared["lightMin"] = on ? "1" : "" }
    func setBlur(_ v: Double) { blur = v; Store.shared["wallpaperBlur"] = String(Int(v)) }

    func reloadWallpaper() {
        Task {
            let img = await Wallpaper.load()
            let scr = UIScreen.main.bounds.size
            let sc = await Task.detached(priority: .utility) { img.map { UIState.tone($0, scr) } ?? 0 }.value
            withAnimation(Theme.easeN) { wallpaper = img; wallpaperVersion += 1; scrim = sc }
        }
    }

    /// web wallTone: the bright parts of the wallpaper as you see it (the 85th percentile of a 40-wide copy, cover-fitted
    /// to the screen), and the tint that keeps white text readable over them
    nonisolated static func tone(_ im: UIImage, _ scr: CGSize) -> Double {
        let W = 40, H = max(20, Int((40 * scr.height / max(1, scr.width)).rounded()))
        guard let cg = im.cgImage else { return 0 }
        var px = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height), k = max(CGFloat(W) / iw, CGFloat(H) / ih)
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: (CGFloat(W) - iw * k) / 2, y: (CGFloat(H) - ih * k) / 2, width: iw * k, height: ih * k))
        var ls: [Double] = []
        ls.reserveCapacity(W * H)
        for i in stride(from: 0, to: px.count, by: 4) {
            ls.append((0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])) / 255 * 0.94)
        }
        ls.sort()
        let hi = ls[Int(Double(ls.count) * 0.85)]
        return max(0, min(0.72, 1 - 0.34 / max(hi, 0.01)))
    }
}
