import Foundation
import UIKit

let API_BASE = "https://macawp3.duckdns.org"

/// Link Telegram (Settings > Library): songs you send your bot download into the app's Telegram folder.
/// Same server API and the same rules as the web player had in the app:
/// POST /api/link -> open t.me/<bot>?start=app_<code> -> GET /api/link/<code> gives an app key (sent as X-App-Key).
@MainActor @Observable
final class Telegram {
    static let shared = Telegram()

    private(set) var key: String = ""
    private(set) var done: [String: String] = [:]       // bot song id -> its path in the app, or "skip:" (you already had it)
    private(set) var albums: [String: String] = [:]     // bot song id -> album on the server
    private(set) var durations: [String: Double] = [:]  // bot song id -> length in seconds
    private(set) var waiting: Set<String> = []          // downloading now
    private(set) var problem = ""
    private(set) var status: String?                    // "Opening Telegram…", "Press Start in the bot…"
    private var version = -1
    private var busy = false
    private var polling = false
    private var linking = false
    private var jobs: [Job] = []
    private var active = 0
    private var tasks: [String: Task<Void, Never>] = [:]
    private var timer: Timer?
    var appActive = true

    struct Job { let id: String; let url: URL; let name: String; let title: String }

    private init() {}

    func load() {
        let s = Store.shared
        key = s["tgKey"] ?? ""
        done = s.json("tgDone", as: [String: String].self) ?? [:]
        albums = s.json("tgAlbums", as: [String: String].self) ?? [:]
        durations = s.json("tgDur", as: [String: Double].self) ?? [:]
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in if Telegram.shared.appActive { await Telegram.shared.sync() } }
        }
        Task { await poll() }
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await sync() }
    }

    func becameActive() {
        appActive = true
        Task { await poll() }
        Task { await sync() }
        pump()
    }
    func wentToBackground() {
        appActive = false
        // iOS cuts connections in the background: stop, and try those songs again when the app is open.
        for (_, t) in tasks { t.cancel() }
    }

    func botIdsByPath() -> [String: String] {
        var m: [String: String] = [:]
        for (id, rel) in done where rel.hasPrefix("Telegram/") { m[rel] = id }
        return m
    }

    var statusLine: String {
        if let status { return status }
        let had = done.values.filter { $0.hasPrefix("skip:") }.count, n = done.count - had
        guard !key.isEmpty else { return "Songs you send the bot download into the app" }
        var s = "Linked: \(n) song\(n == 1 ? "" : "s") from the bot so far"
        if had > 0 { s += " (and \(had) you already had)" }
        if !waiting.isEmpty { s += ", \(waiting.count) downloading" }
        if !problem.isEmpty { s += ". Problem: " + problem }
        return s
    }

    // MARK: linking

    func linkOrUnlink() async {
        if !key.isEmpty {
            let k = key
            key = ""; version = -1; Store.shared["tgKey"] = ""
            var r = URLRequest(url: URL(string: API_BASE + "/api/link")!); r.httpMethod = "DELETE"; r.setValue(k, forHTTPHeaderField: "X-App-Key")
            _ = try? await URLSession.shared.data(for: r)
            return
        }
        guard !linking else { return }
        linking = true; status = "Opening Telegram…"
        defer { linking = false }
        do {
            var r = URLRequest(url: URL(string: API_BASE + "/api/link")!, timeoutInterval: 20); r.httpMethod = "POST"
            let (data, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 404 { throw Problem("it doesn't know about linking yet: it needs the server update") }
            guard (200..<300).contains(code), let c = j["code"] as? String, let u = j["url"] as? String, let url = URL(string: u) else {
                throw Problem((j["error"] as? String) ?? "HTTP \(code)")
            }
            let expires = (j["expires"] as? Double) ?? 600
            Store.shared.setJSON("tgPending", Pending(code: c, until: Date().timeIntervalSince1970 * 1000 + expires * 1000))
            await UIApplication.shared.open(url)
        } catch {
            status = "Couldn't reach your music server (\(Problem.text(error)))"
            return
        }
        await poll()
    }

    private struct Pending: Codable { var code: String; var until: Double }

    /// Waits for you to press Start in the bot (the code is kept, so it carries on after the app was closed).
    func poll() async {
        guard key.isEmpty, !polling, let p = Store.shared.json("tgPending", as: Pending.self) else { return }
        polling = true; defer { polling = false }
        status = "Press Start in the bot, then come back here"
        while Date().timeIntervalSince1970 * 1000 < p.until {
            if case let (data, resp)? = try? await URLSession.shared.data(from: URL(string: API_BASE + "/api/link/" + p.code)!) {
                if (resp as? HTTPURLResponse)?.statusCode == 410 { break }
                if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let k = j["key"] as? String, !k.isEmpty {
                    Store.shared["tgPending"] = ""
                    key = k; version = -1; problem = ""; status = nil
                    Store.shared["tgKey"] = k
                    AppModel.shared.toast("Telegram linked")
                    await sync()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        Store.shared["tgPending"] = ""
        status = "The link expired. Tap Link to try again"
    }

    // MARK: the bot library

    static func normKey(_ artist: String, _ title: String) -> String {
        let s = (artist + "|" + title).lowercased()
            .replacingOccurrences(of: #"\(.*?\)|\[.*?\]|feat\..*$"#, with: "", options: .regularExpression)
        return String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "|" }))
    }

    private static let ext = ["audio/mpeg": ".mp3", "audio/mp3": ".mp3", "audio/mp4": ".m4a", "audio/x-m4a": ".m4a", "audio/aac": ".aac", "audio/flac": ".flac",
                              "audio/x-flac": ".flac", "audio/wav": ".wav", "audio/x-wav": ".wav", "audio/ogg": ".ogg", "audio/aiff": ".aiff"]
    private static func safe(_ s: String) -> String {
        var t = String(s.map { "/\\:*?\"<>|".contains($0) || ($0.asciiValue ?? 32) < 32 ? "_" : $0 })
        while let f = t.first, f == "." || f == " " { t.removeFirst() }
        t = String(t.trimmingCharacters(in: .whitespaces).prefix(120))
        return t.isEmpty ? "Song" : t
    }

    private static func idOf(_ x: [String: Any]) -> String? {
        if let s = x["id"] as? String { return s }
        if let n = x["id"] as? Int { return String(n) }
        return nil
    }

    func sync() async {
        guard !key.isEmpty, !busy, AppModel.shared.loaded else { return }
        busy = true; defer { busy = false }
        do {
            var r = URLRequest(url: URL(string: "\(API_BASE)/api/library?since=\(version)")!, timeoutInterval: 20)
            r.setValue(key, forHTTPHeaderField: "X-App-Key")
            let (data, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 401 || code == 403 {
                key = ""; Store.shared["tgKey"] = ""; status = "The link stopped working. Tap Link to link again"
                AppModel.shared.toast("Telegram is no longer linked"); return
            }
            guard (200..<300).contains(code) else { problem = "the server said " + ((j["error"] as? String) ?? "HTTP \(code)"); return }
            if !problem.isEmpty && waiting.isEmpty { problem = "" }
            await Sync.shared.pull()
            if j["same"] as? Bool == true { return }
            guard let list = j["tracks"] as? [[String: Any]] else { return }
            let token = j["token"] as? String ?? ""
            try await apply(list, token: token)
            version = j["version"] as? Int ?? version
        } catch {
            problem = "couldn't reach your music server (\(Problem.text(error)))"
        }
    }

    private func apply(_ list: [[String: Any]], token: String) async throws {
        let model = AppModel.shared
        let files = Dictionary(Library.shared.scan().map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        // Songs you added yourself (outside the Telegram folder): a bot song that is one of them isn't downloaded again.
        var mineKeys = Set<String>(), mineSizes = Set<Int>()
        for t in model.tracks where !t.path.hasPrefix("Telegram/") { mineKeys.insert(Telegram.normKey(t.artist, t.title)) }
        for (rel, size) in files where !rel.hasPrefix("Telegram/") { mineSizes.insert(size) }
        var gone = dedupe(files), found = 0
        var seen = Set<String>()
        for x in list {
            guard let id = Telegram.idOf(x) else { continue }
            seen.insert(id)
            if waiting.contains(id) { continue }
            let title = x["title"] as? String ?? "", artist = x["artist"] as? String ?? "", size = x["size"] as? Int ?? 0
            let name = "Telegram/" + Telegram.safe((artist.isEmpty ? "" : artist + " - ") + (title.isEmpty ? "Song" : title))
                + (Telegram.ext[(x["mime"] as? String ?? "").lowercased()] ?? ".mp3")
            let have = files[name]
            let taken = Set(done.values)
            let dup = (!title.isEmpty && mineKeys.contains(Telegram.normKey(artist, title))) || (size > 0 && mineSizes.contains(size))
            if dup && !(done[id] ?? "").hasPrefix("skip:") {
                let extra = done[id] ?? ((have != nil && (size == 0 || have == size) && !taken.contains(name)) ? name : "")
                if !extra.isEmpty { Library.shared.deleteDownloaded(extra); gone += 1 }
                done[id] = "skip:"; found += 1; continue
            }
            if done[id] != nil { continue }
            if let have, size == 0 || have == size, !taken.contains(name) { done[id] = name; found += 1; continue }
            guard let url = URL(string: "\(API_BASE)/api/audio/\(id)?t=\(token)") else { continue }
            waiting.insert(id)
            jobs.append(Job(id: id, url: url, name: name, title: title))
        }
        for (id, rel) in done where !seen.contains(id) {                     // /remove in the bot: the song goes here too
            if rel.hasPrefix("Telegram/") { Library.shared.deleteDownloaded(rel) }
            done[id] = nil; gone += 1
        }
        var al: [String: String] = [:], du: [String: Double] = [:]
        for x in list {
            guard let id = Telegram.idOf(x) else { continue }
            if let a = x["album"] as? String, !a.isEmpty { al[id] = a }
            if let d = x["duration"] as? Double, d > 0 { du[id] = d } else if let d = x["duration"] as? Int, d > 0 { du[id] = Double(d) }
        }
        var rescan = false
        if du != durations { durations = du; Store.shared.setJSON("tgDur", du) }
        if al != albums { albums = al; Store.shared.setJSON("tgAlbums", al); rescan = true }
        if found > 0 || gone > 0 { Store.shared.setJSON("tgDone", done) }
        if gone > 0 { rescan = true }
        if rescan { await model.scan() }
        pump()
    }

    /// A song saved twice ("Song.mp3" and "Song 2.mp3", same size, in the Telegram folder): the copy is removed.
    private func dedupe(_ files: [String: Int]) -> Int {
        var owner: [String: String] = [:], n = 0
        for (id, rel) in done { owner[rel] = id }
        let re = try! NSRegularExpression(pattern: #"^(Telegram/.+) (\d+)(\.\w+)$"#)
        for (rel, size) in files {
            guard let m = re.firstMatch(in: rel, range: NSRange(rel.startIndex..., in: rel)),
                  let a = Range(m.range(at: 1), in: rel), let c = Range(m.range(at: 3), in: rel) else { continue }
            let base = String(rel[a]) + String(rel[c])
            guard files[base] == size else { continue }
            if owner[rel] != nil && owner[base] != nil { continue }
            if let id = owner[rel] { done[id] = base; owner[base] = id; owner[rel] = nil }
            Library.shared.deleteDownloaded(rel); n += 1
        }
        return n
    }

    // MARK: downloads: two at a time, each in 2 MB pieces, each piece tried up to 4 times

    private static let piece = 2 * 1024 * 1024

    private func pump() {
        while active < 2, !jobs.isEmpty, appActive {
            let job = jobs.removeFirst()
            active += 1
            tasks[job.id] = Task { [weak self] in
                await self?.fetch(job)
                guard let self else { return }
                self.active -= 1; self.tasks[job.id] = nil
                self.pump()
            }
        }
    }

    private func fetch(_ job: Job) async {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tg-\(job.id.filter { $0.isLetter || $0.isNumber }).part")
        var at = 0
        do {
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            let h = try FileHandle(forWritingTo: tmp)
            defer { try? h.close() }
            var total = Int.max
            while at < total {
                let (data, whole, size) = try await getPiece(job.url, from: at, timeout: at == 0 ? 300 : 60)
                if data.isEmpty { throw Problem("the song was empty") }
                if whole && at > 0 { throw Problem("the server sent the whole song again") }
                total = whole ? data.count : size
                try h.write(contentsOf: data)
                at += data.count
            }
            try h.close()
            let rel = try Library.shared.store(downloaded: tmp, as: job.name)
            waiting.remove(job.id)
            done[job.id] = rel; Store.shared.setJSON("tgDone", done)
            scheduleRescan()
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            waiting.remove(job.id)
            version = -1                                              // tried again on the next check
            if Task.isCancelled || !appActive { return }              // the app went to the background: not a problem
            let why = (error as? URLError)?.code == .timedOut ? "no answer from the server" : Problem.text(error)
            problem = "a song didn't download (“\(job.title.isEmpty ? job.name : job.title)”: \(why)"
                + (at > 0 ? String(format: " after %.1f MB)", Double(at) / 1_048_576) : " before any of it arrived)")
        }
    }

    private func getPiece(_ url: URL, from: Int, timeout: TimeInterval) async throws -> (Data, Bool, Int) {
        var last: Error = Problem("unknown error")
        for i in 0..<4 {
            if i > 0 { try await Task.sleep(nanoseconds: UInt64(1_500_000_000 * Double(i))) }
            try Task.checkCancellation()
            var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            r.setValue("bytes=\(from)-\(from + Telegram.piece - 1)", forHTTPHeaderField: "Range")
            do {
                let (data, resp) = try await URLSession.shared.data(for: r)
                let http = resp as? HTTPURLResponse, code = http?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    let m = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
                    let e = Problem("the server answered \(code)" + (m.map { ": " + $0 } ?? ""))
                    if code < 500 { throw Final(e) }
                    last = e; continue
                }
                let cr = http?.value(forHTTPHeaderField: "Content-Range") ?? ""
                let total = cr.split(separator: "/").last.flatMap { Int($0) } ?? data.count
                return (data, code == 200, code == 206 ? total : data.count)
            } catch let f as Final { throw f.inner }
            catch { if Task.isCancelled { throw error }; last = error }
        }
        throw last
    }

    private var rescanTask: Task<Void, Never>?
    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { try? await Task.sleep(nanoseconds: 600_000_000); if !Task.isCancelled { await AppModel.shared.scan() } }
    }
}

struct Problem: Error, LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
    static func text(_ e: Error) -> String { (e as? Problem)?.message ?? e.localizedDescription }
}
private struct Final: Error { let inner: Error; init(_ e: Error) { inner = e } }

/// Playlists, hidden albums, tile order and covers, the All Tracks name and the album matches are kept on your music
/// server too (/api/state), so the Mini App, this app and the Windows app show the same thing. Same rules as the web
/// player: the newer copy of a key wins; the first time, what this phone already had is merged in.
@MainActor
final class Sync {
    static let shared = Sync()
    static let keys = ["playlists", "hiddenAlbums", "albumOrder", "releaseMap2", "tileCovers", "allName"]
    private var dirty = Set<String>()
    private var at: [String: Double] = [:]
    private var pushTask: Task<Void, Never>?
    private var busy = false
    private var lastPull = Date.distantPast
    private var quiet = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: "syncAt"), let a = try? JSONDecoder().decode([String: Double].self, from: d) { at = a }
    }
    func importTimes(_ json: String) {
        if let d = json.data(using: .utf8), let a = try? JSONDecoder().decode([String: Double].self, from: d) { at = a; saveTimes() }
    }
    private func saveTimes() { if let d = try? JSONEncoder().encode(at) { UserDefaults.standard.set(d, forKey: "syncAt") } }

    private var headers: [String: String]? {
        let k = Telegram.shared.key
        return k.isEmpty ? nil : ["X-App-Key": k]
    }

    /// Called by Store whenever a setting changes.
    func changed(_ key: String) {
        guard Sync.keys.contains(key) else { return }
        mark(key)
    }
    private func mark(_ key: String) {
        if quiet { return }
        at[key] = Date().timeIntervalSince1970 * 1000; saveTimes()
        dirty.insert(key)
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    func push() async {
        guard let h = headers, !dirty.isEmpty, Store.shared["syncSeen"] != nil else { return }
        let ks = dirty; dirty.removeAll()
        var body: [String: Any] = [:]
        for k in ks { if let v = Store.shared[k] { body[k] = ["v": v, "at": at[k] ?? Date().timeIntervalSince1970 * 1000] } }
        var r = URLRequest(url: URL(string: API_BASE + "/api/state")!, timeoutInterval: 20); r.httpMethod = "POST"
        h.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: r)
            if !((resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false) { dirty.formUnion(ks) }
        } catch { dirty.formUnion(ks) }
    }

    private func parse<T>(_ s: String?, _ d: T) -> T {
        guard let s, let data = s.data(using: .utf8), let x = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? T else { return d }
        return x
    }
    private func text(_ x: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: x)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func merge(_ k: String, loc: String, rem: String, first: Bool, remNewer: Bool) -> String {
        if k == "releaseMap2" {
            let a: [String: Any] = parse(loc, [:]), b: [String: Any] = parse(rem, [:])
            return text(remNewer ? a.merging(b) { _, n in n } : b.merging(a) { _, n in n })
        }
        if !first { return remNewer ? rem : loc }
        if k == "playlists" {
            let a: [[String: Any]] = parse(loc, []), b: [[String: Any]] = parse(rem, [])
            let ids = Set(b.compactMap { $0["id"] as? String })
            return text(b + a.filter { !ids.contains(($0["id"] as? String) ?? "") })
        }
        if k == "hiddenAlbums" || k == "albumOrder" {
            let a: [String] = parse(loc, []), b: [String] = parse(rem, [])
            var seen = Set<String>(); return text((b + a).filter { seen.insert($0).inserted })
        }
        if k == "tileCovers" {
            let a: [String: Any] = parse(loc, [:]), b: [String: Any] = parse(rem, [:])
            return text(a.merging(b) { _, n in n })
        }
        return rem.isEmpty ? loc : rem
    }

    func pull() async {
        guard let h = headers, !busy, Date().timeIntervalSince(lastPull) > 10 else { return }
        busy = true; lastPull = Date(); defer { busy = false }
        var r = URLRequest(url: URL(string: API_BASE + "/api/state")!, timeoutInterval: 20)
        h.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
        guard case let (data, resp)? = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let rs = j["state"] as? [String: Any] ?? [:]
        let first = Store.shared["syncSeen"] == nil
        var changed: [String] = []
        for k in Sync.keys {
            let loc = Store.shared[k], la = at[k] ?? 0
            guard let rem = rs[k] as? [String: Any], let rv = rem["v"] as? String else { if loc != nil { dirty.insert(k) }; continue }
            let ra = (rem["at"] as? Double) ?? Double((rem["at"] as? Int) ?? 0)
            if rv == loc { if la == 0 || la < ra { at[k] = ra }; continue }
            let remNewer = loc == nil || ra > la
            let v = loc == nil ? rv : merge(k, loc: loc!, rem: rv, first: first, remNewer: remNewer)
            if v != loc { Store.shared.setQuietly(k, v); changed.append(k) }
            if v == rv { at[k] = ra } else { at[k] = Date().timeIntervalSince1970 * 1000; dirty.insert(k) }
        }
        saveTimes()
        if first { Store.shared.setQuietly("syncSeen", "1") }
        for k in changed { AppModel.shared.applySynced(k) }
        await push()
    }
}
