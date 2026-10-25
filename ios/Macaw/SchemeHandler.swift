import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves the player at macaw://app/ : the page itself from the app bundle (www/), plus the song library:
///   macaw://app/lib/list          the songs, as JSON
///   macaw://app/lib/song/<path>   a song file (supports Range requests, for seeking)
///   macaw://app/lib/art/<path>    a song's cover, once the player has handed it over
/// A fixed address (instead of a file:// page) keeps the player's saved settings and playlists between launches.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "macaw"
    private var stopped = Set<ObjectIdentifier>()
    private let www = Bundle.main.resourceURL!.appendingPathComponent("www", isDirectory: true)
    private let queue = DispatchQueue(label: "macaw.scheme", qos: .userInitiated, attributes: .concurrent)

    private struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let request = task.request
        let id = ObjectIdentifier(task)
        queue.async {
            let reply = self.reply(to: request)
            DispatchQueue.main.async {
                if self.stopped.remove(id) != nil { return }       // the page cancelled it meanwhile
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) else {
                    task.didFailWithError(URLError(.badURL)); return
                }
                task.didReceive(response)
                if request.httpMethod != "HEAD", !reply.body.isEmpty { task.didReceive(reply.body) }
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }

    private func reply(to request: URLRequest) -> Reply {
        guard let url = request.url else { return Reply(status: 400) }
        let path = url.path
        if path == "/lib/list" {
            let data = (try? JSONSerialization.data(withJSONObject: Library.shared.list())) ?? Data("[]".utf8)
            return Reply(headers: ["Content-Type": "application/json", "Cache-Control": "no-store", "Content-Length": "\(data.count)"], body: data)
        }
        if path.hasPrefix("/lib/song/") {
            guard let file = Library.shared.songFile(String(path.dropFirst("/lib/song/".count))) else { return notFound() }
            return serve(file: file, range: request.value(forHTTPHeaderField: "Range"))
        }
        if path.hasPrefix("/lib/art/") {
            guard let data = Library.shared.art(for: String(path.dropFirst("/lib/art/".count))) else { return notFound() }
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            return Reply(headers: ["Content-Type": png ? "image/png" : "image/jpeg", "Content-Length": "\(data.count)", "Cache-Control": "max-age=31536000"], body: data)
        }
        // The page and anything bundled with it.
        var rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if rel.isEmpty { rel = "index.html" }
        guard !rel.split(separator: "/").contains("..") else { return notFound() }
        let file = www.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: file.path) else { return notFound() }
        var reply = serve(file: file, range: request.value(forHTTPHeaderField: "Range"))
        reply.headers["Cache-Control"] = "no-cache"
        return reply
    }

    private func notFound() -> Reply {
        Reply(status: 404, headers: ["Content-Type": "text/plain", "Content-Length": "9"], body: Data("Not found".utf8))
    }

    private func mimeType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "mp3": return "audio/mpeg"
        case "m4a", "m4b", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "aif", "aiff": return "audio/aiff"
        case "caf": return "audio/x-caf"
        case "ogg", "opus": return "audio/ogg"
        default: return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    /// A whole file, or the part asked for with "Range: bytes=a-b" (what the audio player uses to seek).
    private func serve(file: URL, range: String?) -> Reply {
        let type = mimeType(file)
        guard let handle = try? FileHandle(forReadingFrom: file) else { return notFound() }
        defer { try? handle.close() }
        let size = Int((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var headers = ["Content-Type": type, "Accept-Ranges": "bytes"]
        if let range = range, let (start, end) = parse(range: range, size: size) {
            try? handle.seek(toOffset: UInt64(start))
            let data = (try? handle.read(upToCount: end - start + 1)) ?? Data()
            headers["Content-Range"] = "bytes \(start)-\(start + data.count - 1)/\(size)"
            headers["Content-Length"] = "\(data.count)"
            return Reply(status: 206, headers: headers, body: data)
        }
        let data = (try? handle.readToEnd()) ?? Data()
        headers["Content-Length"] = "\(data.count)"
        return Reply(status: 200, headers: headers, body: data)
    }

    private func parse(range: String, size: Int) -> (Int, Int)? {
        guard size > 0, range.hasPrefix("bytes=") else { return nil }
        let spec = range.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {                                         // "bytes=-500": the last 500 bytes
            guard let n = Int(parts[1]), n > 0 else { return nil }
            return (max(0, size - n), size - 1)
        }
        guard let start = Int(parts[0]), start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(Int(parts[1]) ?? (size - 1), size - 1)
        return end >= start ? (start, end) : nil
    }
}
