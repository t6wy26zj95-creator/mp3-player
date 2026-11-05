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
    var coverPickFor: String?           // tile key whose cover you're choosing
    var classic = false                 // set from the saved settings at start (Boot)
    var minimalLight = false
    var editing = false                 // Library: rearranging tiles (they jiggle; Done replaces the tabs)
    var tileDragging = false
    var coverFlow = false               // Settings > Cover Flow: albums in one row instead of the grid
    var dimGlass = false                // Settings > Dim glass: a light shade behind the clear glass
    // Settings > Glass lab (temporary, to tune Apple's glass on the phone itself): % of black behind the glass, % of grey
    // taken out of it, % of Apple's own black tint, and regular (frosted) instead of clear glass
    var glassBehind: Double = 30
    var glassSub: Double = 0
    var glassTint: Double = 0
    var glassRegular = false
    var glassPeek = false               // a glass slider is held: Settings fades so the panel shows
    var blur: Double = 0
    var wallpaper: UIImage?
    var wallpaperVersion = 0

    struct MenuState: Identifiable {
        let id = UUID()
        var kind: Kind
        var anchor: CGRect
        enum Kind { case song(Track, inPlaylist: String?), tile(Tile) }
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
    func setGlassLab(behind: Double? = nil, sub: Double? = nil, tint: Double? = nil, regular: Bool? = nil) {
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
            withAnimation(Theme.easeN) { wallpaper = img; wallpaperVersion += 1 }
        }
    }
}
