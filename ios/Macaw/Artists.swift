import SwiftUI

/// Artists: a grid of your artists (photo from Deezer, or their initial), then an artist's page with your albums.
struct ArtistsDrawer: View {
    private var ui: UIState { .shared }
    var body: some View {
        Group {
            switch ui.artistsPath.last {
            case .artist(let name): ArtistPage(name: name)
            case .album(let name): AlbumPage(name: name, back: "Back")
            default: ArtistGrid()
            }
        }
        // the slide between pages is done by DrawerView
    }
}

enum Artists {
    /// Your artists: an album's artist for album songs, the song's artist otherwise.
    @MainActor static func all() -> [String] {
        let m = AppModel.shared, hidden = Set(m.hidden)
        var seen = Set<String>(), out: [String] = []
        for a in m.albums where !hidden.contains(a.name) && !a.artist.isEmpty && a.artist != "Various Artists" {
            if seen.insert(a.artist.lowercased()).inserted { out.append(a.artist) }
        }
        for t in m.tracks where !t.artist.isEmpty && t.album.isEmpty {
            if seen.insert(t.artist.lowercased()).inserted { out.append(t.artist) }
        }
        return out.sorted { AppModel.sortName($0).localizedCompare(AppModel.sortName($1)) == .orderedAscending }
    }

    @MainActor static func albums(of name: String) -> [Album] {
        let l = name.lowercased()
        return AppModel.shared.albums.filter { $0.artist.lowercased() == l || $0.tracks.contains { $0.artist.lowercased() == l } }
            .sorted { (Int($0.year) ?? 9999) < (Int($1.year) ?? 9999) }
    }
    @MainActor static func songs(of name: String) -> [Track] {
        let l = name.lowercased()
        return AppModel.shared.tracks.filter { $0.artist.lowercased() == l || $0.albumArtist.lowercased() == l }
    }
}

/// Artist photos from Deezer, remembered for a week (web: artistCache).
@MainActor
final class ArtistPhotos {
    static let shared = ArtistPhotos()
    private var urls: [String: String] = [:]
    private var times: [String: Double] = [:]
    private var busy = Set<String>()
    private init() {
        if let d = UserDefaults.standard.data(forKey: "artistPhotos"), let v = try? JSONDecoder().decode([String: String].self, from: d) { urls = v }
        if let d = UserDefaults.standard.data(forKey: "artistPhotoTimes"), let v = try? JSONDecoder().decode([String: Double].self, from: d) { times = v }
    }
    func url(_ name: String) async -> URL? {
        let k = name.lowercased()
        if let u = urls[k], Date().timeIntervalSince1970 - (times[k] ?? 0) < 7 * 86400 { return u.isEmpty ? nil : URL(string: u) }
        guard !busy.contains(k) else { return nil }
        busy.insert(k); defer { busy.remove(k) }
        var q = URLComponents(string: "https://api.deezer.com/search/artist")!
        q.queryItems = [.init(name: "limit", value: "5"), .init(name: "q", value: name)]
        guard case let (data, _)? = try? await URLSession.shared.data(from: q.url!),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = j["data"] as? [[String: Any]] else { return nil }
        let hit = list.first { ($0["name"] as? String)?.lowercased() == k } ?? list.first
        var u = hit?["picture_xl"] as? String ?? ""
        if u.contains("/artist//") { u = "" }                         // Deezer's empty placeholder
        urls[k] = u; times[k] = Date().timeIntervalSince1970
        if let d = try? JSONEncoder().encode(urls) { UserDefaults.standard.set(d, forKey: "artistPhotos") }
        if let d = try? JSONEncoder().encode(times) { UserDefaults.standard.set(d, forKey: "artistPhotoTimes") }
        return u.isEmpty ? nil : URL(string: u)
    }
}

struct ArtistPhoto: View {
    var name: String
    var size: CGFloat
    @State private var url: URL?
    var body: some View {
        ZStack {
            Circle().fill(Color.w(0.05))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size / 3, weight: .bold)).foregroundStyle(Color.w(0.45))
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: Theme.easeN)) { phase in
                    if let img = phase.image { img.resizable().scaledToFill().transition(.opacity) } else { Color.clear }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: name) { url = await ArtistPhotos.shared.url(name) }
    }
}

struct ArtistGrid: View {
    private var ui: UIState { .shared }
    var body: some View {
        // the same grid as Library (web .albums-grid), round covers with the same glass edge (web .artist-card)
        let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 3)
        LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
            ForEach(Artists.all(), id: \.self) { name in
                Button { Haptics.light(); ui.push(.artist(name)) } label: {
                    VStack(spacing: 8) {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay { GeometryReader { g in ArtistPhoto(name: name, size: g.size.width) } }
                            .overlay { TileGlass(shape: Circle()) }
                            .shadow(color: .black.opacity(0.3), radius: 7.5, y: 8)
                        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
                    }
                }
                .buttonStyle(TileStyle())
            }
        }
        .padding(10)
    }
}

struct ArtistPage: View {
    var name: String
    private var ui: UIState { .shared }
    private var player: Player { .shared }
    var body: some View {
        let albums = Artists.albums(of: name), songs = Artists.songs(of: name)
        VStack(alignment: .leading, spacing: 0) {
            BackButton(title: ui.tab == .artists && ui.artistsPath.count <= 1 ? "Back to Artists" : "Back")
            HStack(spacing: 14) {
                ArtistPhoto(name: name, size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    Text("\(albums.count) album\(albums.count == 1 ? "" : "s") · \(songs.count) song\(songs.count == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Color.w(0.55))
                }
                Spacer()
                Button { Haptics.light(); player.playAll(songs, name: name) } label: {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).offset(x: 1)
                }
                .buttonStyle(RoundButtonStyle(size: 36))
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
            if !albums.isEmpty {
                SectionLabel(text: "Albums")
                let cols = [GridItem(.adaptive(minimum: 90, maximum: 90), spacing: 14, alignment: .top)]
                LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
                    ForEach(albums) { a in
                        Button { Haptics.light(); ui.push(.album(a.name)) } label: {
                            VStack(spacing: 6) {
                                CoverImage(path: a.coverPath, px: 300, placeholder: AnyView(IconTile(system: "music.note")))
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(a.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1).frame(width: 90)
                                if !a.year.isEmpty { Text(a.year).font(.system(size: 10)).foregroundStyle(Color.w(0.45)) }
                            }
                        }
                        .buttonStyle(TileStyle())
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}
