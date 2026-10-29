import Foundation
import CryptoKit

/// The songs kept inside the app. They live in the app's Documents folder, which the Files app shows as
/// On My iPhone > MacawP3, so music can also be copied in (or deleted) there. Sub-folders are fine.
final class Library {
    static let shared = Library()

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf", "m4b", "mp4", "ogg", "opus"]

    let songsFolder: URL
    private let artFolder: URL
    private let fm = FileManager.default

    private init() {
        songsFolder = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        artFolder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Covers", isDirectory: true)
        try? fm.createDirectory(at: artFolder, withIntermediateDirectories: true)
    }

    /// Every song: n = path inside the folder, s = size in bytes, m = last modified (ms). Sent to the player as JSON.
    func list() -> [[String: Any]] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = fm.enumerator(at: songsFolder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let base = songsFolder.standardizedFileURL.resolvingSymlinksInPath().path
        var out: [[String: Any]] = []
        for case let url as URL in walker {
            guard Library.audioExtensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            let ms = Int64((v.contentModificationDate ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970 * 1000)
            out.append(["n": rel, "s": v.fileSize ?? 0, "m": ms])
        }
        return out.sorted { ($0["n"] as? String ?? "") < ($1["n"] as? String ?? "") }
    }

    /// The file for a path the player asked for, or nil if it isn't a song inside the folder.
    func songFile(_ rel: String) -> URL? {
        guard !rel.isEmpty, !rel.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        let url = songsFolder.appendingPathComponent(rel)
        let base = songsFolder.standardizedFileURL.resolvingSymlinksInPath().path
        guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(base + "/"),
              fm.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Copies songs into the folder. Returns how many were added (a file already there with the same name and size is skipped).
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var added = 0
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            guard Library.audioExtensions.contains(src.pathExtension.lowercased()) else { continue }
            // Already inside our folder (opened in place from Files): nothing to copy.
            if src.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(songsFolder.standardizedFileURL.resolvingSymlinksInPath().path + "/") { continue }
            let size = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            var dest = songsFolder.appendingPathComponent(src.lastPathComponent)
            if let existing = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize, existing == size { continue }
            var k = 2
            let stem = src.deletingPathExtension().lastPathComponent, ext = src.pathExtension
            while fm.fileExists(atPath: dest.path) {
                dest = songsFolder.appendingPathComponent("\(stem) \(k).\(ext)"); k += 1
            }
            do { try fm.copyItem(at: src, to: dest); added += 1 } catch { NSLog("Macaw: couldn't copy \(src.lastPathComponent): \(error)") }
        }
        return added
    }

    /// Puts a downloaded song (from the Telegram bot) at rel, e.g. "Telegram/Artist - Title.mp3", or next to it under a
    /// free name. Returns the path it ended up at.
    func store(downloaded tmp: URL, as rel: String) throws -> String {
        let clean = rel.split(separator: "/").filter { $0 != ".." && $0 != "." }.joined(separator: "/")
        var dest = songsFolder.appendingPathComponent(clean.isEmpty ? "Telegram/Song.mp3" : clean)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let folder = dest.deletingLastPathComponent(), stem = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
        var k = 2
        while fm.fileExists(atPath: dest.path) { dest = folder.appendingPathComponent("\(stem) \(k).\(ext)"); k += 1 }
        try fm.moveItem(at: tmp, to: dest)
        let base = songsFolder.standardizedFileURL.resolvingSymlinksInPath().path
        return String(dest.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
    }

    // A song arriving from the page in pieces: written to a temporary file, then moved into place by finishPieces.
    private func pieceFile(_ id: String) -> URL {
        let safe = String(id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }.map(Character.init))
        return fm.temporaryDirectory.appendingPathComponent("tg-" + (safe.isEmpty ? "song" : safe) + ".part")
    }
    func appendPiece(_ b64: String, number n: Int, to id: String) {
        guard let data = Data(base64Encoded: b64) else { return }
        let file = pieceFile(id)
        if n == 0 { try? data.write(to: file); return }               // the first piece starts the file afresh
        guard let h = try? FileHandle(forWritingTo: file) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    }
    func finishPieces(_ id: String, as rel: String) throws -> String {
        let file = pieceFile(id)
        guard fm.fileExists(atPath: file.path) else { throw CocoaError(.fileNoSuchFile) }
        return try store(downloaded: file, as: rel)
    }

    /// Removes a song the app downloaded from the bot (only those: the Telegram folder).
    func deleteDownloaded(_ rel: String) {
        guard rel.hasPrefix("Telegram/"), let file = songFile(rel) else { return }
        try? fm.removeItem(at: file)
        try? fm.removeItem(at: artFile(rel))
    }

    // Covers: the player reads a song's tags and hands its cover over once; it is kept here, named after the song.
    private func artFile(_ rel: String) -> URL {
        let hash = SHA256.hash(data: Data(rel.utf8)).map { String(format: "%02x", $0) }.joined()
        return artFolder.appendingPathComponent(hash)
    }
    func saveArt(_ data: Data, for rel: String) { try? data.write(to: artFile(rel), options: .atomic) }
    func art(for rel: String) -> Data? { try? Data(contentsOf: artFile(rel)) }
}
