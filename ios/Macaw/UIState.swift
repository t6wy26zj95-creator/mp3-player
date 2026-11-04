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
    var lyricsOpen = false              // the full lyrics fill the panel
    var settingsOpen = false
    var importing = false
    var menu: MenuState?
    var prompt: Prompt?
    var coverPickFor: String?           // tile key whose cover you're choosing
    var classic = false                 // set from the saved settings at start (Boot)
    var minimalLight = false
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
        withAnimation(Theme.ease) {
            if expanded { expanded = false }
            tab = tab == t ? nil : t
        }
        Haptics.select()
    }

    func push(_ r: Route) {
        withAnimation(Theme.easeN) {
            if tab == .artists { artistsPath.append(r) } else { libraryPath.append(r) }
        }
    }
    func back() {
        withAnimation(Theme.easeN) {
            if tab == .artists { _ = artistsPath.popLast() } else { _ = libraryPath.popLast() }
        }
    }
    /// Opens an artist's page (from the artist name under a song).
    func showArtist(_ name: String) {
        withAnimation(Theme.ease) {
            expanded = false
            tab = .artists
            if artistsPath.last != .artist(name) { artistsPath = [.artist(name)] }
        }
    }

    func setClassic(_ on: Bool) { classic = on; Store.shared["oldPanel"] = on ? "1" : "" }
    func setMinimalLight(_ on: Bool) { minimalLight = on; Store.shared["lightMin"] = on ? "1" : "" }
    func setBlur(_ v: Double) { blur = v; Store.shared["wallpaperBlur"] = String(Int(v)) }

    func reloadWallpaper() {
        Task {
            let img = await Wallpaper.load()
            withAnimation(Theme.easeN) { wallpaper = img; wallpaperVersion += 1 }
        }
    }
}
