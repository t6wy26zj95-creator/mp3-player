import Foundation
import SwiftUI

/// Albums the way the web player sees them (index.html: ALBUM IDENTITY, RELEASES, EDITIONS):
/// - the editions of one album you have ("Faith", "Faith (Deluxe Edition)") are one album, under one name;
/// - each album is matched to its real release on Deezer by its songs (never by title alone);
/// - an album page lists that release's songs, the ones you don't have in grey, in their place;
/// - with several editions, "Mixed" (the original plus what only the others have) or one real edition.

// MARK: names (web: albumSig, edKey, edClean, songKey, verOf, norm, ...)

enum Editions {
    static let liveRE = #"\b(live|in concert|concert|unplugged|mtv|sessions?)\b"#
    static let editionRE = #"\b(deluxe|expanded|remaster(?:ed)?|anniversary|edition|bonus|explicit|special|collector'?s?|super|reissue|version|original (?:game |motion picture )?soundtrack|ost|\d{4})\b"#
    private static let dashTail = #"\s[-–:]\s*[^-–:]*\b(deluxe|remaster(?:ed)?|edition|expanded|anniversary)\b.*$"#

    static func has(_ s: String, _ p: String) -> Bool { s.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
    static func cut(_ s: String, _ p: String, _ with: String = "") -> String {
        s.replacingOccurrences(of: p, with: with, options: [.regularExpression, .caseInsensitive])
    }
    static func isLive(_ s: String) -> Bool { has(s, liveRE) }

    /// Removes the bracketed parts that only name an edition ("(Deluxe Edition)", "[2006 Remaster]"), not "(Live)".
    private static func dropEditionBrackets(_ s: String, spaces: Bool) -> String {
        let p = spaces ? #"\s*[\(\[][^\)\]]*[\)\]]"# : #"[\(\[][^\)\]]*[\)\]]"#
        guard let re = try? NSRegularExpression(pattern: p) else { return s }
        var out = s
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let part = ns.substring(with: m.range)
            if has(part, editionRE) && !has(part, liveRE), let r = Range(m.range, in: out) { out.replaceSubrange(r, with: "") }
        }
        return out
    }

    /// web norm: lower case, without (…) and […], letters and digits only.
    static func norm(_ s: String) -> String {
        AppModel.sn(cut(s.lowercased(), #"\(.*?\)|\[.*?\]"#))
    }
    static func amp(_ s: String) -> String { s.replacingOccurrences(of: "&", with: " and ") }

    /// An album's identity: its title without edition words, plus whether it's live.
    static func albumSig(_ title: String) -> String {
        let live = isLive(title)
        let x = cut(dropEditionBrackets(title, spaces: false), dashTail)
        let b = norm(x)
        return b.isEmpty ? "" : b + (live ? "#live" : "")
    }
    static func edKey(_ n: String) -> String { albumSig(amp(n)) }
    /// "Faith (Deluxe Edition)" → "Faith".
    static func edClean(_ n: String) -> String {
        let x = cut(dropEditionBrackets(n, spaces: true), dashTail).trimmingCharacters(in: .whitespaces)
        return x.isEmpty ? n : x
    }
    /// "Live", "Demo", "Rough mix"…: a different recording of a song.
    static func verOf(_ s: String) -> String {
        guard let r = s.range(of: #"\b(live|demo|rough(?: mix| vocal)?|instrumental|acoustic|remix|alternate|session)\b"#, options: [.regularExpression, .caseInsensitive]) else { return "" }
        let w = s[r].lowercased()
        return w.prefix(1).uppercased() + w.dropFirst()
    }
    /// "The Snakepit" = "Snakepit" = "Snakepit (2006 Remaster)"; "Snakepit (Rough Mix)" is another song.
    static func songKey(_ s: String) -> String {
        var v = verOf(s)
        if v.isEmpty, let r = s.range(of: #"\b(reprise|single|edit|mono|extended|radio|dub|unplugged|orchestral)\b"#, options: [.regularExpression, .caseInsensitive]) { v = String(s[r]) }
        var x = cut(cut(s, #"\s*[\(\[][^\)\]]*[\)\]]"#), #"\s[-–]\s.*$"#).lowercased()
        x = norm(cut(amp(x).trimmingCharacters(in: .whitespaces), #"^(the|a|an)\s+"#))
        if x.isEmpty { x = norm(s) }
        return x + (v.isEmpty ? "" : "#" + v.lowercased())
    }
    static func cleanTitle(_ s: String) -> String {
        cut(cut(s, #"\s*[\(\[].*?[\)\]]"#), #"\s-\s.*$"#).trimmingCharacters(in: .whitespaces)
    }
    static func tokSet(_ s: String) -> Set<String> {
        Set(s.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { $0.count > 1 })
    }
    static func artistKey(_ t: Track) -> String {
        let a = !t.albumArtist.isEmpty ? t.albumArtist : !t.artist.isEmpty ? t.artist : "Unknown Artist"
        return norm(Artists.main(a))
    }

    // MARK: one album for all its editions (web albumGroups)

    /// Gives each song the album it's shown under: the editions of an album by the same artist share one name, the plain
    /// edition's if you have it, else the name without "(Deluxe Edition)". The file's own album stays in `ed`.
    static func group(_ list: [Track], order: [String]) -> [Track] {
        var eds: [String: (n: Int, by: [String: Int])] = [:], edOrder: [String] = []
        for t in list {
            let e = t.ed.isEmpty ? t.album : t.ed
            if eds[e] == nil { eds[e] = (0, [:]); edOrder.append(e) }
            eds[e]!.n += 1; eds[e]!.by[artistKey(t), default: 0] += 1
        }
        var groups: [String: [(e: String, n: Int, artists: [String])]] = [:], gOrder: [String] = []
        for e in edOrder {
            let x = eds[e]!
            let a = x.by.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.first?.key ?? ""
            let sig = e.isEmpty ? "" : edKey(e)
            let g = !sig.isEmpty && !a.isEmpty ? sig + "|" + a : "\u{2}" + e
            if groups[g] == nil { groups[g] = []; gOrder.append(g) }
            groups[g]!.append((e, x.n, Array(x.by.keys)))
        }
        var of: [String: String] = [:]
        for g in gOrder {
            let members = groups[g]!
            var name = members[0].e
            if members.count > 1 {
                let by: ((e: String, n: Int, artists: [String]), (e: String, n: Int, artists: [String])) -> Bool = { p, q in p.n != q.n ? p.n > q.n : p.e < q.e }
                let plain = members.filter { edClean($0.e) == $0.e.trimmingCharacters(in: .whitespaces) }.sorted(by: by).first
                let kept = plain == nil ? members.first { order.contains($0.e) } : nil
                name = plain?.e ?? (kept.map { edClean($0.e) } ?? edClean(members.sorted(by: by)[0].e))
            }
            for m in members { for a in m.artists { of[m.e + "\u{1}" + a] = name } }
        }
        return list.map { t in
            var t = t
            let e = t.ed.isEmpty ? t.album : t.ed
            t.ed = e
            t.album = of[e + "\u{1}" + artistKey(t)] ?? e
            return t
        }
    }
}

// MARK: the data

struct RelTrack: Codable, Hashable { var title: String; var num: Int; var disc: Int; var isrc: String; var dur: Double }
struct Edition: Hashable { var id: Int; var title: String; var year: String; var date: String; var tracks: [RelTrack] }

/// One row of an album page: a song you have, or one you don't (grey), a heading, or "Show N more".
struct AlbumEntry: Identifiable {
    var id: String
    var track: Track?
    var title: String
    var want: String = ""
    var num: Int = 0
    var disc: Int = 1
    var head: String? = nil
    var more: Int? = nil          // -1: "Hide the songs you don't have"; n: "Show n more from other editions"
}

/// An album on an artist's page, opened from there (web currentCat).
struct CatRef: Hashable { var id: Int; var title: String; var artist: String; var cover: String?; var year: String }

// MARK: releases and editions (web resolveAlbum, loadEditions, albumEntries…)

@MainActor @Observable
final class Releases {
    static let shared = Releases()

    private(set) var albumRelease: [String: Int] = [:]          // album -> Deezer release id (0: none)
    private(set) var relTracks: [Int: [RelTrack]] = [:]
    private(set) var eds: [String: (rid: Int, list: [Edition]?)] = [:]
    private(set) var edPick: [String: String] = [:]             // album -> the edition you switched to ("mix" or none: Mixed)
    private(set) var edOpen: Set<String> = []                   // albums showing the other editions' songs you don't have
    private(set) var albumMeta: [String: [String]] = [:]        // album -> Last.fm's tracklist (when Deezer has no release)
    private(set) var resolvingNow = false
    @ObservationIgnored private var relPrev: [String: Int] = [:]
    @ObservationIgnored private var relStore: [String: [String: Double]] = [:]   // "artist|album" -> { id, n, at }
    @ObservationIgnored private var pins: [String: String] = [:]
    @ObservationIgnored private var cats: [String: Task<(id: Int?, albums: [ArtistInfo.CatAlbum])?, Never>] = [:]
    @ObservationIgnored private var listTasks: [Int: Task<[RelTrack]?, Never>] = [:]
    @ObservationIgnored private var tries: [String: Int] = [:]
    @ObservationIgnored private var counts: [String: Int] = [:]
    @ObservationIgnored private var metaAsked: Set<String> = []
    @ObservationIgnored private var edLoading: Set<String> = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var chain: Task<Void, Never> = Task {}

    private init() {
        let s = Store.shared
        if let d = s["releaseMap2"]?.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: [String: Any]] {
            for (k, v) in o { relStore[k] = v.compactMapValues { ($0 as? NSNumber)?.doubleValue } }
        }
        edPick = Self.stringMap(s["edPick"])
        pins = Self.stringMap(s["rowPins"])
    }
    private static func stringMap(_ json: String?) -> [String: String] {
        guard let d = json?.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return o.compactMapValues { v in (v as? String) ?? (v as? NSNumber).map { "\($0.intValue)" } }
    }

    private var tracks: [Track] { AppModel.shared.tracks }
    private func songs(_ album: String) -> [Track] { tracks.filter { $0.album == album } }
    func relOf(_ n: String) -> Int? { albumRelease[n] ?? relPrev[n] }
    var resolving: Bool { tracks.contains { albumRelease[$0.album] == nil && !$0.album.isEmpty } }

    /// The songs changed: albums whose songs changed are matched again (keeping the old match on screen meanwhile).
    func libraryChanged() {
        var now: [String: Int] = [:]
        for t in tracks where !t.album.isEmpty { now[t.album, default: 0] += 1 }
        for (n, c) in now where counts[n] != nil && counts[n] != c {
            if let r = albumRelease[n], r != 0 { relPrev[n] = r }
            albumRelease[n] = nil
        }
        counts = now
        schedule(1.2)
    }
    private func schedule(_ s: Double) {
        timer?.cancel()
        timer = Task { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)); if !Task.isCancelled { await run() } }
    }
    private func run() async {
        if busy { schedule(1.2); return }
        busy = true; resolvingNow = true
        var again = false
        for n in Set(tracks.map(\.album)) where !n.isEmpty && albumRelease[n] == nil {
            if await resolve(n) == false {
                tries[n, default: 0] += 1
                if tries[n]! < 4 { again = true } else { albumRelease[n] = 0 }
            }
        }
        busy = false; resolvingNow = false
        if again { schedule(5) }
    }

    // MARK: Deezer (one request at a time, retried; web dz)

    private func dz(_ url: String) async -> [String: Any]? {
        let prev = chain
        let job = Task<[String: Any]?, Never> { @MainActor in
            await prev.value
            for i in 0..<4 {
                if let u = URL(string: url), case let (d, _)? = try? await URLSession.shared.data(from: u),
                   let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], j["error"] == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    return j
                }
                if i == 3 { return nil }
                try? await Task.sleep(nanoseconds: UInt64(900_000_000 * (i + 1)))
            }
            return nil
        }
        chain = Task { _ = await job.value }
        return await job.value
    }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    /// The artist's albums and EPs, oldest first (web dzCatalog).
    func catalog(_ name: String) async -> (id: Int?, albums: [ArtistInfo.CatAlbum])? {
        let k = Editions.norm(name)
        if let t = cats[k] { return await t.value }
        let t = Task<(id: Int?, albums: [ArtistInfo.CatAlbum])?, Never> { @MainActor in
            guard let r = await self.dz("https://api.deezer.com/search/artist?limit=10&q=\(self.enc(name))"), let data = r["data"] as? [[String: Any]] else { return nil }
            guard let hit = data.filter({ Editions.norm($0["name"] as? String ?? "") == k }).max(by: { ($0["nb_fan"] as? Int ?? 0) < ($1["nb_fan"] as? Int ?? 0) }),
                  let id = hit["id"] as? Int else { return (nil, []) }
            var all: [[String: Any]] = []
            for i in 0..<5 {
                guard let p = await self.dz("https://api.deezer.com/artist/\(id)/albums?limit=100&index=\(i * 100)") else { break }
                let page = p["data"] as? [[String: Any]] ?? []
                all += page
                if p["next"] == nil || page.count < 100 { break }
            }
            var seen = Set<String>(), out: [ArtistInfo.CatAlbum] = []
            for a in all where (a["record_type"] as? String) == "album" || (a["record_type"] as? String) == "ep" {
                let title = a["title"] as? String ?? "", date = a["release_date"] as? String ?? ""
                if !seen.insert(AppModel.sn(title) + "|" + date).inserted { continue }
                out.append(.init(id: a["id"] as? Int ?? 0, title: title, year: String(date.prefix(4)), date: date,
                                 cover: (a["cover_medium"] as? String) ?? (a["cover_big"] as? String)))
            }
            return (id, out.sorted { ($0.date.isEmpty ? "9999" : $0.date) < ($1.date.isEmpty ? "9999" : $1.date) })
        }
        cats[k] = t
        let v = await t.value
        if v == nil { cats[k] = nil }
        return v
    }

    /// A release's songs (web relTrackList).
    func trackList(_ id: Int) async -> [RelTrack]? {
        if let l = relTracks[id] { return l }
        if let t = listTasks[id] { return await t.value }
        let t = Task<[RelTrack]?, Never> { @MainActor in
            var out: [[String: Any]] = []
            for i in 0..<3 {
                guard let r = await self.dz("https://api.deezer.com/album/\(id)/tracks?limit=100&index=\(i * 100)"), let d = r["data"] as? [[String: Any]] else { return nil }
                out += d
                if r["next"] == nil || d.count < 100 { break }
            }
            if out.isEmpty { return nil }
            return out.enumerated().map { i, t in
                RelTrack(title: t["title"] as? String ?? "", num: (t["track_position"] as? Int) ?? i + 1, disc: (t["disk_number"] as? Int) ?? 1,
                         isrc: t["isrc"] as? String ?? "", dur: (t["duration"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        listTasks[id] = t
        let l = await t.value
        listTasks[id] = nil
        if let l { relTracks[id] = l }
        return l
    }

    // MARK: which release is this album (web resolveAlbum)

    private func shortlist(_ name: String, _ albums: [ArtistInfo.CatAlbum]) -> [ArtistInfo.CatAlbum] {
        let sig = Editions.albumSig(name), tk = Editions.tokSet(name), live = Editions.isLive(name)
        return albums.filter { Editions.isLive($0.title) == live }.compactMap { a -> (ArtistInfo.CatAlbum, Int, Double)? in
            let s2 = Editions.albumSig(a.title), t2 = Editions.tokSet(a.title)
            let inter = Double(tk.intersection(t2).count), uni = Double(tk.count + t2.count) - inter
            let jac = inter / (uni == 0 ? 1 : uni)
            let rank = s2 == sig ? 3 : (s2.count > 3 && sig.count > 3 && (s2.contains(sig) || sig.contains(s2))) ? 2 : jac >= 0.5 ? 1 : 0
            return rank > 0 ? (a, rank, jac) : nil
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }.prefix(6).map(\.0)
    }
    private func score(_ L: [Track], _ name: String, _ year: Int, _ cand: ArtistInfo.CatAlbum, _ ctr: [RelTrack]) -> Double {
        var used = Set<Int>(), m = 0
        for t in L {
            var j = ctr.indices.first { !used.contains($0) && AppModel.sn(ctr[$0].title) == AppModel.sn(t.title) }
            if j == nil {
                j = ctr.indices.first { k in let x = ctr[k]
                    return !used.contains(k) && x.num == t.num && x.disc == max(1, t.disc)
                        && Editions.norm(Editions.cleanTitle(x.title)) == Editions.norm(Editions.cleanTitle(t.title)) && Editions.verOf(x.title) == Editions.verOf(t.title) }
            }
            if let j { used.insert(j); m += 1 }
        }
        let cov = Double(m) / Double(L.count)
        if cov < 0.6 || m == 0 { return -1 }
        return cov * 100 + (AppModel.sn(name) == AppModel.sn(cand.title) ? 25 : 0) + (year > 0 && Int(cand.year) == year ? 10 : 0) + Double(m) / Double(ctr.count) * 20
    }
    private func topArtist(_ L: [Track]) -> String {
        var cnt: [String: Int] = [:], order: [String] = []
        for t in L { let a = Artists.main(!t.albumArtist.isEmpty ? t.albumArtist : t.artist); if cnt[a] == nil { order.append(a) }; cnt[a, default: 0] += 1 }
        return order.max { (cnt[$0] ?? 0) < (cnt[$1] ?? 0) } ?? ""
    }
    /// false: try again later (the services didn't answer).
    private func resolve(_ name: String) async -> Bool {
        let L = songs(name)
        guard !L.isEmpty else { return true }
        let artist = topArtist(L)
        if artist.isEmpty || artist == "Unknown Artist" { albumRelease[name] = 0; return true }
        let key = Editions.norm(artist) + "|" + AppModel.sn(name)
        let now = Date().timeIntervalSince1970 * 1000
        if let c = relStore[key], Int(c["n"] ?? -1) == L.count, (c["id"] ?? 0) != 0 || now - (c["at"] ?? 0) < 7 * 864e5 {
            let id = Int(c["id"] ?? 0)
            albumRelease[name] = id
            if id != 0 && relTracks[id] == nil { _ = await trackList(id) }
            return true
        }
        guard let cat = await catalog(artist) else { return false }
        let year = L.compactMap { Int($0.year) }.first { $0 > 0 } ?? 0
        var best: (sc: Double, id: Int)? = nil, ok = true, seen = Set<Int>(), cands: [ArtistInfo.CatAlbum] = []
        func add(_ c: ArtistInfo.CatAlbum) { if seen.insert(c.id).inserted { cands.append(c) } }
        if let isrc = L.first(where: { !$0.isrc.isEmpty })?.isrc,
           let r = await dz("https://api.deezer.com/track/isrc:\(enc(isrc))"), let al = r["album"] as? [String: Any], let aid = al["id"] as? Int {
            add(cat.albums.first { $0.id == aid } ?? .init(id: aid, title: al["title"] as? String ?? "", year: "", date: "", cover: nil))
        }
        let first = cands
        shortlist(name, cat.albums).forEach(add)
        func eval(_ list: [ArtistInfo.CatAlbum]) async {
            for c in list {
                guard let ctr = await trackList(c.id) else { ok = false; continue }
                let sc = score(L, name, year, c, ctr)
                if sc > 0 && (best == nil || sc > best!.sc) { best = (sc, c.id) }
            }
        }
        await eval(first)
        if !(best != nil && !first.isEmpty && Editions.albumSig(first[0].title) == Editions.albumSig(name) && AppModel.sn(first[0].title) == AppModel.sn(name)) {
            await eval(cands.filter { c in !first.contains { f in f.id == c.id } })
        }
        if best == nil {                                                  // titles differ? check the tracks anyway
            let live = Editions.isLive(name)
            let rest = cat.albums.filter { !seen.contains($0.id) && Editions.isLive($0.title) == live }.prefix(6)
            for a in rest { seen.insert(a.id) }
            await eval(Array(rest))
        }
        if best == nil && !ok { return false }
        albumRelease[name] = best?.id ?? 0
        relPrev[name] = nil
        if ok {
            relStore[key] = ["id": Double(best?.id ?? 0), "n": Double(L.count), "at": now]
            if let d = try? JSONSerialization.data(withJSONObject: relStore), let s = String(data: d, encoding: .utf8) { Store.shared["releaseMap2"] = s }
        }
        return true
    }

    /// Which of your albums is this release (or another edition of it)? (web ownedAlbumKey)
    func ownedAlbum(_ id: Int) -> String? {
        let names = Set(albumRelease.keys).union(relPrev.keys)
        let have = Set(tracks.map(\.album))
        if let n = names.first(where: { n in relOf(n) == id && have.contains(n) }) { return n }
        return eds.first { kv in (kv.value.list?.contains { e in e.id == id } ?? false) && have.contains(kv.key) }?.key
    }

    // MARK: matching songs to rows (web matchRows, belongs, edHome)

    private func belongs(_ l: Track, _ x: RelTrack, _ edTitle: String) -> Bool {
        if !l.isrc.isEmpty && !x.isrc.isEmpty { return l.isrc.uppercased() == x.isrc.uppercased() }
        if l.duration > 0 && x.dur > 0 { return abs(l.duration - x.dur) <= 2 }
        return AppModel.sn(Editions.amp(l.ed)) == AppModel.sn(Editions.amp(edTitle))
    }
    private func pinFor(_ name: String?) -> ((RelTrack) -> String?)? {
        guard let name else { return nil }
        return { self.pins[name + "|" + Editions.songKey($0.title)] }
    }
    private func matchRows(_ rows: [RelTrack], _ local: [Track], strict: Bool, edTitle: String, pin: ((RelTrack) -> String?)?) -> (got: [Track?], used: Set<String>) {
        var used = Set<String>(), got = [Track?](repeating: nil, count: rows.count)
        func pass(_ fn: (Track, RelTrack) -> Bool) {
            for (i, x) in rows.enumerated() where got[i] == nil {
                if let t = local.first(where: { !used.contains($0.path) && fn($0, x) }) { used.insert(t.path); got[i] = t }
            }
        }
        let ok: (Track, RelTrack) -> Bool = strict ? { self.belongs($0, $1, edTitle) } : { _, _ in true }
        if let pin { pass { l, x in if let id = pin(x) { return l.botId == id && Editions.verOf(l.title) == Editions.verOf(x.title) }; return false } }
        pass { l, x in !l.isrc.isEmpty && !x.isrc.isEmpty && l.isrc.uppercased() == x.isrc.uppercased() }
        pass { l, x in AppModel.sn(l.title) == AppModel.sn(x.title) && ok(l, x) }
        pass { l, x in Editions.songKey(l.title) == Editions.songKey(x.title) && ok(l, x) }
        return (got, used)
    }
    private func edHome(_ t: Track, _ list: [Edition]) -> Int {
        let k = Editions.songKey(t.title), id = t.isrc.uppercased()
        if !id.isEmpty, let i = list.firstIndex(where: { $0.tracks.contains { $0.isrc.uppercased() == id } }) { return i }
        let row = list.map { ed in ed.tracks.first { Editions.songKey($0.title) == k } }
        if t.duration > 0 {
            var best = -1, bd = 3.0
            for (i, x) in row.enumerated() { if let x, x.dur > 0, abs(x.dur - t.duration) < bd { bd = abs(x.dur - t.duration); best = i } }
            if best >= 0 { return best }
        }
        if let i = row.indices.first(where: { row[$0] != nil && AppModel.sn(Editions.amp(list[$0].title)) == AppModel.sn(Editions.amp(t.ed)) }) { return i }
        return row.firstIndex { $0 != nil } ?? -1
    }

    // MARK: what an album page lists

    private func rowsOf(_ rows: [RelTrack], _ got: [Track?], _ pre: String) -> [AlbumEntry] {
        rows.enumerated().map { i, x in
            AlbumEntry(id: pre + "\(i)", track: got[i], title: got[i]?.title ?? x.title, want: x.title, num: x.num, disc: x.disc)
        }
    }
    /// One real edition: its tracklist, with only the songs that live in it (web editionEntries).
    func editionEntries(_ name: String?, _ ed: Edition) -> [AlbumEntry] {
        let all = name.map(songs) ?? []
        let list = name.flatMap { eds[$0]?.list }
        let j = list?.firstIndex { $0.id == ed.id } ?? -1
        let here = Set(ed.tracks.map { $0.isrc.uppercased() }.filter { !$0.isEmpty })
        let got: [Track?]
        if let list, j >= 0 {
            let inIt: (Track) -> Bool = { t in
                let id = t.isrc.uppercased()
                return !id.isEmpty && list.contains { $0.tracks.contains { $0.isrc.uppercased() == id } } ? here.contains(id) : self.edHome(t, list) == j
            }
            got = matchRows(ed.tracks, all.filter(inIt), strict: false, edTitle: "", pin: nil).got
        } else {
            got = matchRows(ed.tracks, all, strict: true, edTitle: ed.title, pin: nil).got
        }
        return rowsOf(ed.tracks, got, "e\(ed.id)-")
    }
    /// "Deluxe Edition · 2006", "Original · 1987", "Reissue · 2005" (web edLabel).
    func edLabel(_ ed: Edition, _ i: Int, _ list: [Edition]) -> String {
        let t = ed.title, c = Editions.edClean(t)
        var l: String
        if let r = t.range(of: #"[\(\[]([^\)\]]*)[\)\]]\s*$"#, options: .regularExpression), Editions.has(String(t[r]), Editions.editionRE) {
            l = String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
        } else if c != t.trimmingCharacters(in: .whitespaces) {
            l = Editions.cut(String(t.dropFirst(c.count)), #"^[\s\-–:]+"#)
        } else {
            l = i == 0 ? "Original" : (list.first.map { ed.tracks.count > $0.tracks.count } ?? false) ? "Expanded" : "Reissue"
        }
        return l + (ed.year.isEmpty ? "" : " · " + ed.year)
    }
    /// Mixed: the original edition in its order, then what only the other editions have (web mixedEntries).
    private func mixedEntries(_ name: String, _ list: [Edition]) -> [AlbumEntry] {
        let mine = songs(name)
        let home = Dictionary(mine.map { ($0.path, edHome($0, list)) }, uniquingKeysWith: { a, _ in a })
        let local = mine.enumerated().sorted { a, b in
            let ha = home[a.element.path]! < 0 ? 99 : home[a.element.path]!, hb = home[b.element.path]! < 0 ? 99 : home[b.element.path]!
            return ha != hb ? ha < hb : a.offset < b.offset
        }.map(\.element)
        var rows: [(x: RelTrack, ed: Edition?, j: Int)] = [], keys = Set<String>(), ids = Set<String>()
        for (j, ed) in list.enumerated() {
            for x in ed.tracks {
                let k = Editions.songKey(x.title), i = x.isrc.uppercased()
                if j > 0 && (keys.contains(k) || (!i.isEmpty && ids.contains(i))) { continue }
                keys.insert(k); if !i.isEmpty { ids.insert(i) }
                rows.append((x, j > 0 ? ed : nil, j))
            }
        }
        let (got, used) = matchRows(rows.map(\.x), local, strict: false, edTitle: "", pin: pinFor(name))
        let open = edOpen.contains(name)
        var out: [AlbumEntry] = [], hidden = 0
        for (i, r) in rows.enumerated() {
            let t = got[i], x = r.x
            guard let ed = r.ed else { out.append(AlbumEntry(id: "m\(i)", track: t, title: t?.title ?? x.title, want: x.title, num: x.num, disc: x.disc)); continue }
            if t == nil && !open { hidden += 1; continue }
            out.append(AlbumEntry(id: "m\(i)", track: t, title: t?.title ?? x.title, want: x.title, num: 0, disc: 50 + r.j, head: "From " + edLabel(ed, r.j, list)))
        }
        if hidden > 0 || open {
            let n = rows.indices.filter { rows[$0].ed != nil && got[$0] == nil }.count
            if n > 0 { out.append(AlbumEntry(id: "more", track: nil, title: "", disc: 96, more: open ? -1 : hidden)) }
        }
        for t in local where !used.contains(t.path) {
            out.append(AlbumEntry(id: "f" + t.path, track: t, title: t.title, num: t.num, disc: keys.contains(Editions.songKey(t.title)) ? 97 : 99))
        }
        let rank: (AlbumEntry) -> Int = { $0.disc >= 96 ? $0.disc : 0 }
        return out.enumerated().sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }.map(\.element)
    }
    /// An album you have, before its editions are known; or a release opened from an artist page (web catEntries).
    func catEntries(_ cat: CatRef?, own: String?, list: [RelTrack]?) -> [AlbumEntry] {
        let mineName = own ?? cat.flatMap { ownedAlbum($0.id) }
        let local = mineName.map(songs) ?? []
        func plain(_ t: Track) -> AlbumEntry { AlbumEntry(id: "p" + t.path, track: t, title: t.title, num: t.num, disc: max(1, t.disc)) }
        guard let list, !list.isEmpty else { return own != nil ? local.map(plain) : [] }
        if own == nil, let cat { return editionEntries(mineName, Edition(id: -1, title: cat.title, year: cat.year, date: "", tracks: list)) }
        let (got, used) = matchRows(list, local, strict: false, edTitle: "", pin: pinFor(mineName))
        var out = rowsOf(list, got, "c")
        for t in local where !used.contains(t.path) { var e = plain(t); e.disc = 99; out.append(e) }
        return out
    }

    func edView(_ name: String) -> Edition? {
        guard let list = eds[name]?.list, let p = edPick[name], p != "mix" else { return nil }
        return list.first { "\($0.id)" == p }
    }
    func pickEdition(_ name: String, _ id: String) {
        if id == "mix" { edPick[name] = nil } else { edPick[name] = id }
        var o: [String: Any] = [:]
        for (k, v) in edPick { o[k] = Int(v).map { $0 as Any } ?? v }
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) { Store.shared["edPick"] = s }
        Haptics.light()
    }
    func toggleOpen(_ name: String) {
        if edOpen.contains(name) { edOpen.remove(name) } else { edOpen.insert(name) }
        Haptics.light()
    }

    /// The editions of an album you have (web loadEditions): the release your songs matched and the other releases with the
    /// same title, earliest first, the same tracklist only once, 6 at most.
    private func loadEditions(_ name: String, _ rid: Int) {
        if let e = eds[name], e.rid == rid { return }
        guard edLoading.insert(name + "|\(rid)").inserted else { return }
        Task {
            eds[name] = (rid: rid, list: nil)
            let artist = topArtist(songs(name))
            let cat = artist.isEmpty ? nil : await catalog(artist)
            let me = cat?.albums.first { $0.id == rid }
            let sig = Editions.albumSig(me?.title ?? name), live = Editions.isLive(me?.title ?? name)
            var list0 = cat?.albums.filter { $0.id == rid || (Editions.albumSig($0.title) == sig && Editions.isLive($0.title) == live) } ?? []
            if !list0.contains(where: { $0.id == rid }) { list0.insert(.init(id: rid, title: name, year: "", date: "", cover: nil), at: 0) }
            let plain: (ArtistInfo.CatAlbum) -> Int = { Editions.edClean($0.title) == $0.title.trimmingCharacters(in: .whitespaces) ? 0 : 1 }
            list0 = list0.enumerated().sorted { a, b in
                let ya = a.element.year.isEmpty ? "9999" : a.element.year, yb = b.element.year.isEmpty ? "9999" : b.element.year
                if ya != yb { return ya < yb }
                if plain(a.element) != plain(b.element) { return plain(a.element) < plain(b.element) }
                let da = a.element.date.isEmpty ? "9999" : a.element.date, db = b.element.date.isEmpty ? "9999" : b.element.date
                return da != db ? da < db : a.offset < b.offset
            }.map(\.element)
            if list0.count > 6 { let r = list0.first { $0.id == rid }; list0 = Array(list0.prefix(6)); if let r, !list0.contains(r) { list0[5] = r } }
            var list: [Edition] = [], seen = Set<String>()
            for a in list0 {
                guard let l = await trackList(a.id) else { continue }
                let k = l.map { "\($0.disc):\(AppModel.sn($0.title))" }.joined(separator: "|")
                if !seen.insert(k).inserted { continue }
                list.append(Edition(id: a.id, title: a.title, year: a.year, date: a.date, tracks: l))
            }
            eds[name] = list.isEmpty ? nil : (rid: rid, list: Optional(list))          // none found: not asked again this session
        }
    }

    /// Last.fm's tracklist for an album no release was found for (web fetchAlbumMeta).
    private func askMeta(_ name: String) {
        guard !metaAsked.contains(name) else { return }
        metaAsked.insert(name)
        let artist = AppModel.albumArtist(songs(name))
        guard !artist.isEmpty, artist != "Unknown Artist" else { return }
        Task {
            let q = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
            guard let u = URL(string: "https://ws.audioscrobbler.com/2.0/?method=album.getinfo&api_key=dbe9aea2d4e59436f4b2015d1f0e027a&artist=\(q(artist))&album=\(q(name))&format=json"),
                  case let (d, _)? = try? await URLSession.shared.data(from: u),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let a = j["album"] as? [String: Any] else { return }
            let tr = (a["tracks"] as? [String: Any])?["track"]
            let list = (tr as? [[String: Any]]) ?? ((tr as? [String: Any]).map { [$0] } ?? [])
            albumMeta[name] = list.compactMap { $0["name"] as? String }
        }
    }

    /// What one of your albums' pages lists (web albumEntries).
    func albumEntries(_ name: String) -> [AlbumEntry] {
        let rid = relOf(name)
        if let rid, rid != 0 { loadEditions(name, rid) }
        if let list = eds[name]?.list { return edView(name).map { editionEntries(name, $0) } ?? mixedEntries(name, list) }
        if let rid, rid != 0, let l = relTracks[rid] { return catEntries(nil, own: name, list: l) }
        let local = songs(name)
        let plain = { local.map { AlbumEntry(id: "p" + $0.path, track: $0, title: $0.title, num: $0.num, disc: max(1, $0.disc)) } }
        if rid == 0 { askMeta(name) }
        guard let meta = albumMeta[name], !meta.isEmpty, !local.isEmpty else { return plain() }
        if local.contains(where: { $0.disc > 1 }) { return plain() }                 // several discs: never guess where missing songs go
        let nums = local.map(\.num)
        if nums.contains(where: { $0 <= 0 }) || Set(nums).count != nums.count || meta.count < (nums.max() ?? 0) { return plain() }
        let agree = local.filter { t in
            let a = Editions.norm(meta[t.num - 1]), b = Editions.norm(t.title)
            return !a.isEmpty && !b.isEmpty && (a == b || a.contains(b) || b.contains(a))
        }.count
        if Double(agree) / Double(local.count) < 0.6 { return plain() }
        let byNum = Dictionary(local.map { ($0.num, $0) }, uniquingKeysWith: { a, _ in a })
        return meta.enumerated().map { i, n in
            let t = byNum[i + 1]
            return AlbumEntry(id: "l\(i)", track: t, title: t?.title ?? n, want: n, num: i + 1, disc: 1)
        }
    }

    /// The editions switch shows when an album has more than one.
    func editions(_ name: String) -> [Edition]? { eds[name]?.list }
}
