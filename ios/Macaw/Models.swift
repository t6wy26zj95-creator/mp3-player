import Foundation

/// One song file in the app's folder.
struct Track: Identifiable, Hashable {
    var id: String { path }
    let path: String            // inside Documents, e.g. "Telegram/Artist - Title.mp3"
    let size: Int
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var num: Int
    var disc: Int
    var year: String
    var duration: Double
    var botId: String?          // the song's id on your music server, when it came from the Telegram bot
    var ed: String = ""         // the album as the file names it ("Faith (Deluxe Edition)"); album is the name it's shown under
    var isrc: String = ""       // the recording's ID code (ID3 TSRC, or the server's), "" when unknown

    /// The same key the web player uses for a song (playlists store these), so playlists carry over.
    var key: String { "r:" + (botId ?? "n:" + path) }
    var shownArtist: String { artist.isEmpty ? "Unknown artist" : artist }
    var albumName: String { album.isEmpty ? "Unknown album" : album }
    var albumArtistName: String { albumArtist.isEmpty ? shownArtist : albumArtist }
    var url: URL { Library.shared.songsFolder.appendingPathComponent(path) }
}

struct Album: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let artist: String
    let year: String
    let tracks: [Track]
    var coverPath: String? { tracks.first(where: { Library.shared.hasArt($0.path) })?.path }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var keys: [String]
}

/// A Library tile: All Tracks, a playlist or an album. key = what the web player calls it ("@all", "pl:<id>", album name).
enum Tile: Identifiable, Hashable {
    case all
    case playlist(Playlist)
    case album(Album)
    var id: String { key }
    var key: String {
        switch self {
        case .all: return AppModel.allKey
        case .playlist(let p): return "pl:" + p.id
        case .album(let a): return a.name
        }
    }
}

enum RepeatMode: String, Codable { case all, one, off }

/// Where something in the drawer is: the Library grid, an album, a playlist, an artist page...
enum Route: Hashable {
    case album(String)
    case playlist(String)
    case allTracks
    case artist(String)
    case catalog(CatRef)        // an album on an artist's page that isn't (all) yours: its tracklist from Deezer
}

enum DrawerTab: String { case queue, library, artists }

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s.rounded(.down))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}
