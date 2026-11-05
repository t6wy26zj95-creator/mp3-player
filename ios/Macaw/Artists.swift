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
    /// The main artist of a credit: "A feat. B", "A; B", "A / B", "A (with B)" → "A" (web: mainArtist).
    static func main(_ s: String) -> String {
        let pat = #"\s*(?:;|\s/\s|[(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s|\s(?:feat\.?|ft\.?|featuring)\s)\s*"#
        if let r = s.range(of: pat, options: [.regularExpression, .caseInsensitive]) {
            let m = s[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !m.isEmpty { return m }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Your artists, the one with the most songs first (web renderArtists).
    @MainActor static func all() -> [String] {
        var counts: [String: Int] = [:], shown: [String: String] = [:]
        for t in AppModel.shared.tracks {
            let a = main(t.artist)
            if a.isEmpty || a == "Unknown Artist" { continue }
            let k = a.lowercased()
            counts[k, default: 0] += 1
            if shown[k] == nil { shown[k] = a }
        }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : shown[$0]!.localizedCompare(shown[$1]!) == .orderedAscending }
            .map { shown[$0]! }
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
                            .softShadow(radius: 7.5, y: 8, opacity: 0.3, circle: true)
                        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
                    }
                }
                .buttonStyle(TileStyle())
            }
        }
        .padding(10)
    }
}

/// What the web player shows about an artist (web loadArtist): Last.fm (bio, tags, listeners, similar artists),
/// TheAudioDB (bio / picture when Last.fm has none), the picture from Deezer, and the artist's albums from Deezer's
/// catalogue. Remembered for a week.
@MainActor
@Observable
final class ArtistInfo {
    static let shared = ArtistInfo()
    struct CatAlbum: Codable, Hashable { var id: Int; var title: String; var year: String; var date: String; var cover: String? }
    struct Info: Codable {
        var name: String
        var photo: String?
        var bio = ""
        var tags: [String] = []
        var listeners = 0
        var similar: [String] = []
        var albums: [CatAlbum]? = nil                         // nil while loading
        var full = false
        var t: Double = Date().timeIntervalSince1970
    }
    private(set) var info: [String: Info] = [:]
    @ObservationIgnored private var busy = Set<String>()
    private static let lastfm = "dbe9aea2d4e59436f4b2015d1f0e027a"

    private init() {
        if let d = UserDefaults.standard.data(forKey: "artistInfo3"), let v = try? JSONDecoder().decode([String: Info].self, from: d) { info = v }
    }
    static func key(_ n: String) -> String { n.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespaces) }

    func get(_ name: String) -> Info? { info[Self.key(name)] }

    func load(_ name: String) async {
        let k = Self.key(name)
        if let c = info[k], c.full, Date().timeIntervalSince1970 - c.t < 7 * 86400 { return }
        guard !busy.contains(k) else { return }
        busy.insert(k); defer { busy.remove(k) }
        var d = Info(name: name, photo: info[k]?.photo)
        async let lfJ = json("https://ws.audioscrobbler.com/2.0/?method=artist.getinfo&api_key=\(Self.lastfm)&artist=\(enc(name))&autocorrect=1&format=json")
        async let adbJ = json("https://www.theaudiodb.com/api/v1/json/2/search.php?s=\(enc(name))")
        let (lf, adb) = await (lfJ, adbJ)
        var gotLF = false, gotADB = false
        if let a = lf?["artist"] as? [String: Any] {
            gotLF = true
            d.name = a["name"] as? String ?? name
            let summary = ((a["bio"] as? [String: Any])?["summary"] as? String) ?? ""
            d.bio = Self.plain(summary).replacingOccurrences(of: #"\s*Read more on Last\.fm.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            d.listeners = Int(((a["stats"] as? [String: Any])?["listeners"] as? String) ?? "") ?? 0
            d.tags = (((a["tags"] as? [String: Any])?["tag"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.prefix(4).map { $0 }
            d.similar = (((a["similar"] as? [String: Any])?["artist"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.prefix(6).map { $0 }
        }
        if let list = adb?["artists"] as? [[String: Any]], let a = list.first, Self.key(a["strArtist"] as? String ?? "") == k {
            gotADB = true
            if d.bio.isEmpty, let b = a["strBiographyEN"] as? String { d.bio = String(b.prefix(700)) }
            if d.tags.isEmpty, let g = a["strGenre"] as? String, !g.isEmpty { d.tags = [g] }
            if let p = (a["strArtistFanart"] as? String) ?? (a["strArtistThumb"] as? String), !p.isEmpty { d.photo = p }
        }
        if d.photo == nil, let u = await ArtistPhotos.shared.url(d.name) { d.photo = u.absoluteString }
        info[k] = d                                            // the page fills in what's there; the albums follow
        d.albums = await catalog(d.name) ?? []
        d.full = gotLF || gotADB
        info[k] = d
        if d.full, let data = try? JSONEncoder().encode(info) { UserDefaults.standard.set(data, forKey: "artistInfo3") }
    }

    /// The artist's albums and EPs on Deezer, oldest first (web dzCatalog).
    private func catalog(_ name: String) async -> [CatAlbum]? {
        guard let r = await json("https://api.deezer.com/search/artist?limit=10&q=\(enc(name))"), let data = r["data"] as? [[String: Any]] else { return nil }
        let k = Self.key(name)
        guard let hit = data.filter({ Self.key($0["name"] as? String ?? "") == k }).max(by: { ($0["nb_fan"] as? Int ?? 0) < ($1["nb_fan"] as? Int ?? 0) }),
              let id = hit["id"] as? Int else { return [] }
        var all: [[String: Any]] = []
        for i in 0..<5 {
            guard let p = await json("https://api.deezer.com/artist/\(id)/albums?limit=100&index=\(i * 100)") else { break }
            let page = p["data"] as? [[String: Any]] ?? []
            all += page
            if p["next"] == nil || page.count < 100 { break }
        }
        var seen = Set<String>(), out: [CatAlbum] = []
        for a in all where (a["record_type"] as? String) == "album" || (a["record_type"] as? String) == "ep" {
            let title = a["title"] as? String ?? "", date = a["release_date"] as? String ?? ""
            if !seen.insert(AppModel.sn(title) + "|" + date).inserted { continue }
            out.append(CatAlbum(id: a["id"] as? Int ?? 0, title: title, year: String(date.prefix(4)), date: date,
                                cover: (a["cover_medium"] as? String) ?? (a["cover_big"] as? String)))
        }
        return out.sorted { ($0.date.isEmpty ? "9999" : $0.date) < ($1.date.isEmpty ? "9999" : $1.date) }
    }

    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
    private func json(_ u: String) async -> [String: Any]? {
        guard let url = URL(string: u), case let (data, _)? = try? await URLSession.shared.data(from: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    private static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { s = s.replacingOccurrences(of: a, with: b) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The artist page, as on the web: a 170 pt picture with the name over it, tags · listeners, the bio (4 lines, Read
/// more), the artist's albums (yours with a green dot, the others dimmed), similar artists. While the details load,
/// shimmering placeholders hold the space; after a few seconds without them, your own albums are shown.
struct ArtistPage: View {
    var name: String
    @State private var bioOpen = false
    @State private var heroIn = false
    @State private var slow = false
    private var ui: UIState { .shared }
    private var store: ArtistInfo { .shared }

    var body: some View {
        let d = store.get(name)
        VStack(alignment: .leading, spacing: 0) {
            BackButton(title: ui.tab == .artists && ui.artistsPath.count <= 1 ? "Back to Artists" : "Back")
            hero(d)
            let meta = [d?.tags.prefix(3).joined(separator: " · ") ?? "", (d?.listeners ?? 0) > 0 ? Self.fmt(d!.listeners) + " listeners" : ""]
                .filter { !$0.isEmpty }.joined(separator: "  •  ")
            if !meta.isEmpty {
                Text(meta).font(.system(size: 12)).foregroundStyle(Color.w(0.6)).padding(.horizontal, 4).padding(.top, 12)
            }
            bio(d)
            Text("ALBUMS").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5))
                .padding(.horizontal, 4).padding(.top, 14)
            albums(d)
            if let sim = d?.similar, !sim.isEmpty {
                Text("SIMILAR ARTISTS").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5))
                    .padding(.horizontal, 4).padding(.top, 14)
                Chips(items: sim) { n in Haptics.light(); ui.push(.artist(n)) }
                    .padding(.horizontal, 4).padding(.vertical, 10)
                    .modifier(CardRise(index: 0))
            }
        }
        .padding(.bottom, 12)
        .task(id: name) {
            slow = false
            Task { try? await Task.sleep(nanoseconds: 4_000_000_000); slow = true }
            await store.load(name)
        }
    }

    private func hero(_ d: ArtistInfo.Info?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            Color(red: 0x0f / 255, green: 0x2a / 255, blue: 0x35 / 255)
            if let p = d?.photo, let u = URL(string: p) {
                AsyncImage(url: u) { ph in
                    if let img = ph.image {
                        // background-position: center 25%
                        GeometryReader { g in
                            img.resizable().scaledToFill()
                                .frame(width: g.size.width, height: g.size.height, alignment: Alignment(horizontal: .center, vertical: .quarter))
                                .clipped()
                        }
                        .opacity(heroIn ? 1 : 0)
                        .onAppear { withAnimation(Theme.ease) { heroIn = true } }
                    }
                }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0), .init(color: .black.opacity(0), location: 0.62)],
                           startPoint: .bottom, endPoint: .top)
            Text(d?.name ?? name).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .lineSpacing(26 * 1.1 - UIFont.systemFont(ofSize: 26, weight: .bold).lineHeight)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .frame(height: 170)
        .clipShape(shape)
        .onChange(of: name) { _, _ in heroIn = false }
    }

    @ViewBuilder private func bio(_ d: ArtistInfo.Info?) -> some View {
        if d?.albums == nil && !slow {
            Shimmer().frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 4).padding(.top, 10)
        } else if let b = d?.bio, !b.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(b).font(.system(size: 13)).foregroundStyle(Color.w(0.82))
                    .lineSpacing(13 * 1.45 - UIFont.systemFont(ofSize: 13).lineHeight)
                    .lineLimit(bioOpen ? nil : 4)
                    .padding(.top, 10)
                Button(bioOpen ? "Show less" : "Read more") { withAnimation(Theme.ease) { bioOpen.toggle() } }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.w(0.6))
                    .padding(.vertical, 8)
                    .buttonStyle(PopStyle())
            }
            .padding(.horizontal, 4)
            .modifier(CardRise(index: 0))
        } else if slow && d?.albums == nil {
            Text("Artist info isn\u{2019}t loading. Here are your own albums.").font(.system(size: 12)).foregroundStyle(Color.w(0.45))
                .padding(.horizontal, 4).padding(.vertical, 10)
        }
    }

    private struct Card: Identifiable { var id: String; var title: String; var year: String; var cover: String?; var localPath: String?; var own: String? }

    @ViewBuilder private func albums(_ d: ArtistInfo.Info?) -> some View {
        let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 3)
        let local = Artists.albums(of: name)
        let cards: [Card]? = {
            if let cat = d?.albums, !cat.isEmpty {
                return cat.map { a in
                    let own = local.first { AppModel.sn($0.name) == AppModel.sn(a.title) }
                    return Card(id: "\(a.id)", title: a.title, year: a.year, cover: a.cover, localPath: own?.coverPath, own: own?.name)
                }
            }
            if d?.albums != nil || slow {                         // nothing from the services: your own albums
                return local.map { Card(id: $0.name, title: $0.name, year: $0.year, cover: nil, localPath: $0.coverPath, own: $0.name) }
            }
            return nil
        }()
        LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
            if let cards {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    Button { if let o = c.own { Haptics.light(); ui.push(.album(o)) } } label: {
                        VStack(spacing: 8) {
                            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if let p = c.localPath { CoverImage(path: p, px: 300, placeholder: AnyView(IconTile(system: "music.note"))) }
                                    else if let u = c.cover.flatMap(URL.init(string:)) {
                                        AsyncImage(url: u) { ph in if let img = ph.image { img.resizable().scaledToFill() } else { Color.w(0.06) } }
                                    } else { IconTile(system: "music.note") }
                                }
                                .clipShape(shape)
                                .overlay { TileGlass(shape: shape) }
                                .overlay(alignment: .topTrailing) {
                                    if c.own != nil {                            // web .own-dot
                                        Circle().fill(Color(red: 0x2e / 255, green: 0xcc / 255, blue: 0x71 / 255)).frame(width: 9, height: 9)
                                            .shadow(color: Color(red: 0x2e / 255, green: 0xcc / 255, blue: 0x71 / 255), radius: 4).padding(6)
                                    }
                                }
                                .softShadow(radius: 7.5, y: 8, opacity: 0.3, corner: 12)
                            Text(c.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
                            if !c.year.isEmpty { Text(c.year).font(.system(size: 10)).foregroundStyle(Color.w(0.5)).padding(.top, -4) }
                        }
                        .opacity(c.own == nil ? 0.4 : 1)                       // web .album-card.dim
                    }
                    .buttonStyle(TileStyle())
                    .modifier(CardRise(index: i))
                }
            } else {
                ForEach(0..<6, id: \.self) { _ in                              // web .sk-card
                    VStack(spacing: 8) {
                        Shimmer().aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Shimmer().frame(height: 9).clipShape(Capsule()).frame(maxWidth: .infinity).padding(.horizontal, 18)
                    }
                }
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 10)
    }

    static func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { let v = Double(n) / 1e6; return (v.truncatingRemainder(dividingBy: 1) < 0.05 ? String(format: "%.0f", v) : String(format: "%.1f", v)) + "M" }
        if n >= 1000 { return "\(Int((Double(n) / 1000).rounded()))K" }
        return "\(n)"
    }
}

/// web .card-in: fades in, 8 pt up and from 97 %, 400 ms ease, 22 ms apart (at most 12 steps).
struct CardRise: ViewModifier {
    var index: Int
    @State private var p: Double = 0
    func body(content: Content) -> some View {
        content
            .modifier(KFEffect(p: p, dy: KF(stops: [(0, 8), (1, 0)], whole: .ease), scale: KF(stops: [(0, 0.97), (1, 1)], whole: .ease),
                               opacity: KF(stops: [(0, 0), (1, 1)], whole: .ease)))
            .onAppear { withAnimation(.linear(duration: 0.4).delay(Double(min(index, 12)) * 0.022)) { p = 1 } }
    }
}

/// web .sk: a loading placeholder with light sliding across it (1.4 s, forever).
struct Shimmer: View {
    @State private var t: CGFloat = 0
    var body: some View {
        GeometryReader { g in
            let w = g.size.width * 2                           // background-size: 200 %, sliding to -200 %
            let band = LinearGradient(colors: [.w(0.05), .w(0.12), .w(0.05)], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 0) { band.frame(width: w); band.frame(width: w) }
                .offset(x: -w * t)
        }
        .clipped()
        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { t = 1 } }
    }
}

/// web .chips: rounded buttons that wrap onto more lines.
struct Chips: View {
    var items: [String]
    var tap: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { n in
                Button { tap(n) } label: {
                    Text(n).font(.system(size: 12)).foregroundStyle(.white)
                        .padding(.vertical, 8).padding(.horizontal, 13)
                        .background(Capsule().fill(Color.w(0.1)))
                        .overlay(Capsule().strokeBorder(Color.w(0.14), lineWidth: 1))
                }
                .buttonStyle(PopStyle())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > b.width { x = 0; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: b.minX + x, y: b.minY + y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

extension VerticalAlignment {
    /// CSS background-position: center 25% (the picture's point a quarter down sits a quarter down the box)
    private enum Quarter: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height * 0.25 } }
    static let quarter = VerticalAlignment(Quarter.self)
}
