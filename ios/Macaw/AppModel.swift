import Foundation
import SwiftUI

/// The song library and everything you arrange in it: playlists, hidden albums, tile order and covers.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    static let allKey = "@all"

    private(set) var tracks: [Track] = []
    private(set) var albums: [Album] = []
    private(set) var byPath: [String: Track] = [:]
    private(set) var byKey: [String: Track] = [:]
    private(set) var loaded = false
    var readingText: String?                         // "Reading your songs… 3 of 120"

    var playlists: [Playlist] = []
    var hidden: [String] = []
    var albumOrder: [String] = []
    var tileCovers: [String: String] = [:]
    var allNameSaved: String = ""
    var allName: String { allNameSaved.isEmpty ? "All Tracks" : allNameSaved }

    var toastText: String?
    private var toastTask: Task<Void, Never>?

    private var tagCache: [String: TagInfo] = [:]
    private let tagFile = Library.shared.supportFolder.appendingPathComponent("tags.json")
    private var scanning = false
    private var scanAgain = false

    private init() {
        if let d = try? Data(contentsOf: tagFile), let c = try? JSONDecoder().decode([String: TagInfo].self, from: d) { tagCache = c }
    }

    // MARK: saved arrangement

    func loadArrangement() {
        let s = Store.shared
        playlists = s.json("playlists", as: [Playlist].self) ?? []
        hidden = s.json("hiddenAlbums", as: [String].self) ?? []
        albumOrder = s.json("albumOrder", as: [String].self) ?? []
        tileCovers = s.json("tileCovers", as: [String: String].self) ?? [:]
        allNameSaved = s["allName"] ?? ""
    }

    /// A key changed on another device (pulled from your music server).
    func applySynced(_ key: String) {
        loadArrangement()
        if key == "playlists" { Player.shared.playlistsChanged() }
    }

    private func savePlaylists() { Store.shared.setJSON("playlists", playlists) }

    // MARK: the songs

    /// Looks at the folder again: new songs get their tags read, removed ones disappear.
    func scan() async {
        if scanning { scanAgain = true; return }
        scanning = true
        defer {
            scanning = false
            if scanAgain { scanAgain = false; Task { await scan() } }
        }
        let first = !loaded
        let entries = await Task.detached(priority: .userInitiated) { Library.shared.scan() }.value
        let tg = Telegram.shared
        let botOf = tg.botIdsByPath()
        var keep: [String: TagInfo] = [:]
        var out: [Track] = []
        let todo = entries.filter { tagCache[cacheKey($0)] == nil }.count
        var read = 0
        if todo > 3 && !first { toast("Adding \(todo) songs…") }
        for e in entries {
            let k = cacheKey(e)
            var info = tagCache[k]
            if info == nil {
                read += 1
                if first || todo > 3 { readingText = "Reading your songs… \(read) of \(todo)" }
                info = await Tags.read(Library.shared.songsFolder.appendingPathComponent(e.path), path: e.path)
            }
            guard var t = info else { continue }
            keep[k] = t
            let bot = botOf[e.path]
            if let bot, let a = tg.albums[bot], !a.isEmpty { t.album = a }          // a bot song keeps the album the server gave it
            if let bot, let d = tg.durations[bot], d > 0 { t.duration = d }
            out.append(Track(path: e.path, size: e.size, title: t.title, artist: t.artist, album: t.album, albumArtist: t.albumArtist,
                             num: t.num, disc: t.disc, year: t.year, duration: t.duration, botId: bot))
        }
        readingText = nil
        let added = first ? [] : out.filter { byPath[$0.path] == nil }
        tagCache = keep
        if let d = try? JSONEncoder().encode(keep) { try? d.write(to: tagFile, options: .atomic) }
        out.sort(by: AppModel.trackOrder)
        setTracks(out)
        loaded = true
        if added.count == 1 { toast("Added “\(added[0].title)”") } else if added.count > 1 { toast("Added \(added.count) songs") }
        Player.shared.libraryChanged()
    }

    private func cacheKey(_ e: Library.Entry) -> String { "\(e.path)|\(e.size)|\(e.modified)" }

    static func trackOrder(_ a: Track, _ b: Track) -> Bool {
        if a.album != b.album { return a.album.localizedCompare(b.album) == .orderedAscending }
        let da = a.disc == 0 ? 1 : a.disc, db = b.disc == 0 ? 1 : b.disc
        if da != db { return da < db }
        let na = a.num == 0 ? 1_000_000 : a.num, nb = b.num == 0 ? 1_000_000 : b.num
        if na != nb { return na < nb }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    private func setTracks(_ list: [Track]) {
        tracks = list
        byPath = Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        byKey = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [String: [Track]] = [:], order: [String] = []
        for t in list where !t.album.isEmpty {
            if groups[t.album] == nil { order.append(t.album) }
            groups[t.album, default: []].append(t)
        }
        albums = order.map { name in
            let ts = groups[name] ?? []
            return Album(name: name, artist: AppModel.albumArtist(ts), year: ts.map(\.year).max() ?? "", tracks: ts)
        }
    }

    /// The album's artist, picked the way the web player does: its album artist tag, or "Various Artists" when the songs
    /// are by more than two artists, or the artist most of its songs are by.
    static func albumArtist(_ ts: [Track]) -> String {
        func top(_ xs: [String]) -> String {
            var n: [String: Int] = [:]; xs.forEach { n[$0, default: 0] += 1 }
            return n.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? ""
        }
        let aa = ts.map(\.albumArtist).filter { !$0.isEmpty }
        if !aa.isEmpty { return top(aa) }
        let ar = ts.map(\.artist).filter { !$0.isEmpty }
        if Set(ar).count > 2 { return "Various Artists" }
        return top(ar)
    }

    func album(named name: String) -> Album? { albums.first { $0.name == name } }
    func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }
    func tracks(of p: Playlist) -> [Track] { p.keys.compactMap { byKey[$0] } }

    // MARK: Library tiles

    /// All Tracks, playlists and albums, in your order (new ones: All Tracks, then playlists, first).
    var tiles: [Tile] {
        let hiddenSet = Set(hidden)
        var items: [Tile] = [.all] + playlists.map { .playlist($0) }
        // as the web player: albums in the order of the song list (by album name); songs without an album get no tile
        let sortedAlbums = albums.filter { !hiddenSet.contains($0.name) && $0.name != "Unknown album" }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        items += sortedAlbums.map { .album($0) }
        let rank: (Tile) -> Int = { t in
            if let i = self.albumOrder.firstIndex(of: t.key) { return i }
            switch t { case .all: return -3; case .playlist: return -2; case .album: return 1_000_000 }
        }
        return items.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    /// Letters and digits only, lower case (web: sn), for matching names that are written differently.
    nonisolated static func sn(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }.map(Character.init))
    }
    static func sortName(_ s: String) -> String {
        let l = s.lowercased()
        return l.hasPrefix("the ") ? String(l.dropFirst(4)) : l
    }

    /// Saves where a tile was dropped when you rearranged the grid.
    func moveTile(_ key: String, before target: String) {
        var keys = tiles.map(\.key)
        guard let from = keys.firstIndex(of: key), key != target else { return }
        keys.remove(at: from)
        let to = keys.firstIndex(of: target) ?? keys.count
        keys.insert(key, at: to)
        albumOrder = keys
        Store.shared.setJSON("albumOrder", keys)
    }

    /// Saves the grid's order after you moved tiles (web saveOrder).
    func saveTileOrder(_ keys: [String]) {
        albumOrder = keys
        Store.shared.setJSON("albumOrder", keys)
    }

    func coverKey(_ tileKey: String) -> String { tileKey == AppModel.allKey || tileKey.hasPrefix("pl:") ? tileKey : "a:" + tileKey }

    func setTileCover(_ tileKey: String, jpeg: Data?) {
        let k = coverKey(tileKey)
        if let jpeg { tileCovers[k] = "data:image/jpeg;base64," + jpeg.base64EncodedString() } else { tileCovers[k] = nil }
        Store.shared.setJSON("tileCovers", tileCovers)
    }

    // MARK: changes

    func hideAlbum(_ name: String) {
        guard !hidden.contains(name) else { return }
        hidden.append(name); Store.shared.setJSON("hiddenAlbums", hidden)
        toast("Album hidden. Bring it back in Settings")
    }
    func unhideAlbum(_ name: String) {
        hidden.removeAll { $0 == name }; Store.shared.setJSON("hiddenAlbums", hidden)
    }

    func renameAll(_ name: String) {
        allNameSaved = name.trimmingCharacters(in: .whitespaces)
        Store.shared["allName"] = allNameSaved
    }

    @discardableResult
    func newPlaylist(_ name: String, keys: [String] = []) -> Playlist {
        let id = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1000...46655), radix: 36)
        let clean = name.trimmingCharacters(in: .whitespaces)
        let p = Playlist(id: id, name: clean.isEmpty ? "My playlist \(playlists.count + 1)" : clean, keys: keys)
        playlists.append(p); savePlaylists()
        return p
    }
    func renamePlaylist(_ id: String, _ name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty { playlists[i].name = clean; savePlaylists() }
    }
    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        tileCovers["pl:" + id] = nil; Store.shared.setJSON("tileCovers", tileCovers)
        savePlaylists(); toast("Playlist deleted")
    }
    func toggle(_ t: Track, in id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        if playlists[i].keys.contains(t.key) {
            playlists[i].keys.removeAll { $0 == t.key }; toast("Removed from “\(playlists[i].name)”")
        } else {
            playlists[i].keys.append(t.key); toast("Added to “\(playlists[i].name)”")
        }
        savePlaylists()
    }
    func remove(_ t: Track, from id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].keys.removeAll { $0 == t.key }; savePlaylists()
    }
    func movePlaylistSongs(_ id: String, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        var ts = tracks(of: playlists[i]).map(\.key)
        ts.move(fromOffsets: from, toOffset: to)
        let missing = playlists[i].keys.filter { byKey[$0] == nil }       // songs not on this phone keep their place at the end
        playlists[i].keys = ts + missing; savePlaylists()
    }

    func importFiles(_ urls: [URL]) {
        Task {
            _ = await Task.detached(priority: .userInitiated) { Library.shared.importFiles(urls) }.value
            await scan()
        }
    }

    // MARK: toast

    func toast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { toastText = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.toastText = nil }
        }
    }
}
