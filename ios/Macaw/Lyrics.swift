import SwiftUI

/// Lyrics: synced lines from LRCLIB (a free, open lyrics database), as in the web player.
/// - Looked up by title + artist (remaster / live / edition tags taken off the title), picking the result whose length
///   matches the song best. Synced lyrics whose length is off by more than 8 s (another version) show as plain text.
/// - Kept on the phone (the last 60 songs, "lyrics1", the web player's own key), so a song's lyrics are fetched once.
@MainActor @Observable
final class Lyrics {
    static let shared = Lyrics()
    private static let storeKey = "lyrics1", maxKept = 60

    struct Line: Codable, Hashable { var t: Double; var text: String }
    struct Found: Codable {
        var kind: String            // synced, plain, none, instrumental, error
        var lines: [Line]?
        var text: String?
        var at: Double?
    }

    /// nil = still looking.
    private(set) var data: Found?
    private(set) var songKey: String?
    private var disk: [String: Found] = [:]
    private var memory: [String: Found] = [:]
    private var req = 0

    private init() {
        disk = Store.shared.json(Lyrics.storeKey, as: [String: Found].self) ?? [:]
    }

    /// The web player's key for a song's lyrics.
    static func key(_ t: Track) -> String {
        if let id = t.botId { return "r:" + id }
        return ("l:" + [t.artist, t.album, String(t.disc), String(t.num), t.title].joined(separator: "|")).lowercased()
    }

    /// Called when the big player opens or the song changes.
    func song() {
        guard let t = Player.shared.current else { return }
        if songKey == t.key { return }
        songKey = t.key
        load(t)
    }

    /// Looks again after an error (the bubble or the page came into view).
    func retryIfFailed() {
        guard data?.kind == "error", let t = Player.shared.current else { return }
        load(t)
    }

    private func load(_ t: Track) {
        let k = Lyrics.key(t)
        req += 1
        let my = req
        if let d = memory[t.key] ?? disk[k] { data = d; memory[t.key] = d; return }
        data = nil
        let dur = Player.shared.duration > 0 ? Player.shared.duration : t.duration
        Task {
            let d = await Lyrics.lookup(title: t.title, artist: t.artist, dur: dur)
            guard my == req else { return }
            data = d ?? Found(kind: "error")
            if let d { memory[t.key] = d; remember(k, d) }
        }
    }

    private func remember(_ k: String, _ v: Found) {
        var v = v
        v.at = Date().timeIntervalSince1970 * 1000
        disk[k] = v
        if disk.count > Lyrics.maxKept {
            for old in disk.sorted(by: { ($0.value.at ?? 0) < ($1.value.at ?? 0) }).prefix(disk.count - Lyrics.maxKept) { disk[old.key] = nil }
        }
        Store.shared.setJSON(Lyrics.storeKey, disk)
    }

    /// The line being sung at a time (-1 = before the first).
    func index(at time: Double) -> Int {
        guard let L = data?.lines, data?.kind == "synced" else { return -1 }
        var lo = 0, hi = L.count - 1, i = -1
        while lo <= hi { let m = (lo + hi) >> 1; if L[m].t <= time + 0.2 { i = m; lo = m + 1 } else { hi = m - 1 } }
        return i
    }

    // MARK: LRCLIB

    private struct Hit: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    nonisolated static func clean(_ t: String) -> String {
        var s = t.replacingOccurrences(of: #"\s*[(\[][^)\]]*(remaster|live|version|mono|stereo|edit|mix|deluxe|anniversary|bonus|demo|explicit|feat\.?|ft\.)[^)\]]*[)\]]"#,
                                       with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+-\s+[^-]*(remaster|live|version|mono|stereo|edit|mix)[^-]*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? t : s
    }

    nonisolated static func parse(_ lrc: String) -> [Line] {
        var out: [Line] = []
        let tag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        for ln in lrc.components(separatedBy: .newlines) {
            let ns = ln as NSString
            let tags = tag.matches(in: ln, range: NSRange(location: 0, length: ns.length))
            if tags.isEmpty { continue }
            let text = ln.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<\d+:\d+(?:\.\d+)?>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            for m in tags {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                out.append(Line(t: mm * 60 + ss, text: text))
            }
        }
        out.sort { $0.t < $1.t }
        while let f = out.first, f.text.isEmpty { out.removeFirst() }      // no empty lines before the first words
        return out
    }

    /// nil = couldn't reach the service.
    nonisolated private static func lookup(title: String, artist: String, dur: Double) async -> Found? {
        func get(_ q: [String: String]) async throws -> [Hit] {
            var c = URLComponents(string: "https://lrclib.net/api/search")!
            c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
            var r = URLRequest(url: c.url!, timeoutInterval: 15)
            r.setValue("MacawP3 (https://github.com/t6wy26zj95-creator/mp3-player)", forHTTPHeaderField: "User-Agent")
            let (d, resp) = try await URLSession.shared.data(for: r)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode([Hit].self, from: d)
        }
        do {
            let name = clean(title)
            var arr = try await get(["track_name": name, "artist_name": artist])
            if arr.isEmpty { arr = try await get(["q": "\(artist) \(name)"]) }
            func score(_ x: Hit) -> Double {
                (x.syncedLyrics != nil ? 0 : 20) + (x.instrumental == true ? 40 : 0) + (dur > 0 && (x.duration ?? 0) > 0 ? abs(x.duration! - dur) : 5)
            }
            guard let best = arr.filter({ $0.syncedLyrics != nil || $0.plainLyrics != nil || $0.instrumental == true }).min(by: { score($0) < score($1) })
            else { return Found(kind: "none") }
            if best.instrumental == true && best.syncedLyrics == nil && best.plainLyrics == nil { return Found(kind: "instrumental") }
            if let s = best.syncedLyrics, dur == 0 || (best.duration ?? 0) == 0 || abs(best.duration! - dur) <= 8 {
                let lines = parse(s)
                if !lines.isEmpty { return Found(kind: "synced", lines: lines) }
            }
            let plain = (best.plainLyrics ?? (best.syncedLyrics ?? "").replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? Found(kind: "none") : Found(kind: "plain", text: plain)
        } catch { return nil }
    }
}

// MARK: the bubble under the big player

/// Three lines: the one just sung, the one being sung, the next. Unsynced lyrics show their first three lines; while
/// looking, or with no lyrics, a short note. When the line changes the three lines glide up into place.
struct LyricsBubble: View {
    var open: () -> Void
    private var lyr: Lyrics { .shared }
    private var player: Player { .shared }

    private var lines: (a: String, b: String, c: String, style: String) {
        guard let d = lyr.data else { return ("", "Looking for lyrics…", "", "note") }
        switch d.kind {
        case "error": return ("", "Couldn't reach the lyrics service", "", "note")
        case "none": return ("", "No lyrics for this song", "", "note")
        case "instrumental": return ("", "♪  Instrumental  ♪", "", "note")
        case "plain":
            let r = (d.text ?? "").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return (r.count > 0 ? r[0] : "", r.count > 1 ? r[1] : "", r.count > 2 ? r[2] : "", "plain")
        default:
            let L = d.lines ?? [], i = lyr.index(at: player.time)
            func tx(_ k: Int) -> String { k < 0 || k >= L.count ? "" : (L[k].text.isEmpty ? "•••" : L[k].text) }
            return i < 0 ? ("", "•••", tx(0), "") : (tx(i - 1), tx(i), tx(i + 1), "")
        }
    }

    var body: some View {
        let l = lines
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("LYRICS").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.w(0.45))
                }
                VStack(alignment: .leading, spacing: 3) {
                    line(l.a, size: l.style == "plain" ? 15 : 14, weight: .semibold, opacity: l.style == "plain" ? 0.8 : 0.36)
                    line(l.b, size: l.style == "" ? 17 : 15, weight: l.style == "" ? .bold : (l.style == "note" ? .medium : .semibold),
                         opacity: l.style == "" ? 1 : (l.style == "note" ? 0.62 : 0.8))
                    line(l.c, size: l.style == "plain" ? 15 : 14, weight: .semibold, opacity: l.style == "plain" ? 0.8 : 0.55)
                }
                .id(l.a + "\n" + l.b + "\n" + l.c)
                .transition(.asymmetric(insertion: .offset(y: 10).combined(with: .opacity), removal: .identity))
            }
            .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.w(0.1), Color.w(0.05)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.w(0.13), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 13, y: 10)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.44), value: l.b)
        }
        .buttonStyle(PressStyle())
    }

    private func line(_ t: String, size: CGFloat, weight: Font.Weight, opacity: Double) -> some View {
        Text(t.isEmpty ? " " : t).font(.system(size: size, weight: weight)).foregroundStyle(.white.opacity(opacity))
            .lineLimit(1).truncationMode(.tail)
    }
}

// MARK: the full lyrics page

/// The whole panel: the line being sung is lit (the ones before it dim) and kept a third of the way down.
/// Scroll yourself and it leaves the list alone for 3 s. Tap a line to play from there.
struct LyricsPage: View {
    var close: () -> Void
    @State private var userAt = Date.distantPast
    @State private var lastIdx = -2
    private var lyr: Lyrics { .shared }
    private var player: Player { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: close) {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.w(0.08)))
                }
                .buttonStyle(PopStyle())
                .padding(.leading, -8).padding(.trailing, -4)
                CoverImage(path: player.current?.path, px: 140)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? "").font(.system(size: 15, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(player.current?.shownArtist ?? "").font(.system(size: 12.5)).foregroundStyle(Color.w(0.6)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TransportButton(kind: .play, size: 40)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)

            GeometryReader { g in
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        content(proxy, height: g.size.height)
                    }
                    .onScrollPhaseChange { _, p in if p == .interacting || p == .decelerating { userAt = Date() } }
                    .onChange(of: idx, initial: true) { _, i in follow(proxy, i, jump: lastIdx == -2) }
                    .onChange(of: lyr.data?.kind) { _, _ in lastIdx = -2; follow(proxy, idx, jump: true) }
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 28 / max(1, g.size.height)),
                                             .init(color: .black, location: 1 - 40 / max(1, g.size.height)), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .onAppear { lyr.retryIfFailed() }
    }

    private var idx: Int { lyr.index(at: player.time) }

    private func follow(_ proxy: ScrollViewProxy, _ i: Int, jump: Bool) {
        lastIdx = i
        guard lyr.data?.kind == "synced", jump || Date().timeIntervalSince(userAt) > 3 else { return }
        if jump { proxy.scrollTo(max(0, i), anchor: UnitPoint(x: 0, y: 0.32)) }
        else { withAnimation(Theme.ease) { proxy.scrollTo(max(0, i), anchor: UnitPoint(x: 0, y: 0.32)) } }
    }

    @ViewBuilder
    private func content(_ proxy: ScrollViewProxy, height: CGFloat) -> some View {
        if let d = lyr.data, d.kind == "synced" || d.kind == "plain" {
            let synced = d.kind == "synced"
            let rows: [Lyrics.Line] = synced ? (d.lines ?? []) : (d.text ?? "").components(separatedBy: .newlines).map { Lyrics.Line(t: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
            let cur = idx
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, l in
                    let on = synced && i == cur, past = synced && i < cur
                    Text(l.text.isEmpty ? (synced ? "•••" : " ") : l.text)
                        .font(.system(size: synced ? (l.text.isEmpty ? 20 : 23) : 20, weight: .bold))
                        .tracking(l.text.isEmpty && synced ? 4 : 0)
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .opacity(synced ? (on ? 1 : past ? 0.22 : 0.32) : 0.85)
                        .scaleEffect(on ? 1.03 : 1, anchor: .leading)
                        .animation(Theme.ease, value: on)
                        .animation(Theme.ease, value: past)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard synced else { return }
                            player.seek(to: l.t)
                            if !player.isPlaying { player.play() }
                            userAt = .distantPast
                            Haptics.light()
                        }
                        .id(i)
                }
                Text(synced ? "Lyrics from LRCLIB" : "Lyrics from LRCLIB · not synced")
                    .font(.system(size: 10.5)).foregroundStyle(Color.w(0.35)).padding(.top, 12)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, height * 0.45)
        } else {
            Text(noteText)
                .font(.system(size: 14)).foregroundStyle(Color.w(0.55)).lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.top, 48)
        }
    }

    private var noteText: String {
        switch lyr.data?.kind {
        case nil: return "Looking for lyrics…"
        case "error": return "Couldn't reach the lyrics service. Check the connection and open the lyrics again to retry."
        case "instrumental": return "♪  Instrumental  ♪"
        default: return "No lyrics found for this song."
        }
    }
}
