import SwiftUI
import WebKit
import UniformTypeIdentifiers
import MediaPlayer

/// The hidden switch between this native player and the web player (index.html, the same page as the website, kept
/// inside the app). Tap the version line at the bottom of Settings 3 times to switch; in the web player, the same
/// 3 taps on its version line switch back. The choice is remembered between launches.
/// Both players use the same songs (the app's Documents folder). The web player keeps its own playlists and settings
/// (the old web app's storage at macaw://app), as it did before the app went native.
@MainActor @Observable
final class WebMode {
    static let shared = WebMode()
    static let key = "webMode"
    private(set) var on = UserDefaults.standard.bool(forKey: WebMode.key)
    private init() {}

    func set(_ web: Bool) {
        guard web != on else { return }
        Haptics.medium()
        if web {
            // the native player steps aside: no sound, no lock-screen controls, no background work
            UIState.shared.settingsOpen = false
            if Boot.done {
                Player.shared.handOver()
                Store.shared.saveNow()
                Glow.shared.hold(true)
                Telegram.shared.wentToBackground()
            }
        } else if Boot.done {
            Player.shared.takeBack()
            Glow.shared.hold(false)
            Telegram.shared.becameActive()
            Task { await AppModel.shared.scan() }                // songs the web player added meanwhile
        }
        on = web
        UserDefaults.standard.set(web, forKey: WebMode.key)
    }
}

/// What the app shows: the native player, or the web player full-screen.
struct AppShell: View {
    private var mode: WebMode { .shared }
    var body: some View {
        Group {
            if mode.on {
                WebPlayer()
                    .ignoresSafeArea()
                    .background(Color(uiColor: WebPlayerController.pageColor).ignoresSafeArea())
                    .onOpenURL { url in if url.isFileURL { WebPlayerController.current?.importSongs([url]) } }
            } else {
                RootView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct WebPlayer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebPlayerController { WebPlayerController() }
    func updateUIViewController(_ c: WebPlayerController, context: Context) {}
    static func dismantleUIViewController(_ c: WebPlayerController, coordinator: ()) { c.stop() }
}

/// The web player in a full-screen web view, served from the app at macaw://app/ (this is how the app worked before it
/// went native). The page talks to the app through window.webkit.messageHandlers.macaw:
///   { cmd: "import" }                  show the Files picker and copy the chosen songs in
///   { cmd: "art", n: path, b64: ... }  keep a song's cover (read from its tags by the page)
///   { cmd: "chunk", id, n, b64 }       a piece of a song the page downloaded from the Telegram bot (n = 0, 1, 2...)
///   { cmd: "drop", id }                that download failed: throw its pieces away
///   { cmd: "save", id, name }          that song is complete: put it at name, then call natDownloaded(id, path, ok, problem)
///   { cmd: "delete", n: path }         remove a song downloaded from the bot
///   { cmd: "open", url }               open a link in another app (Telegram)
///   { cmd: "native" }                  switch back to the native player (3 taps on the version line)
/// and the app calls window.natSync() when songs were added.
final class WebPlayerController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UIDocumentPickerDelegate {
    static let pageColor = UIColor(red: 0x0b / 255.0, green: 0x1d / 255.0, blue: 0x24 / 255.0, alpha: 1)
    static weak var current: WebPlayerController?
    private var web: WKWebView!
    private var loaded = false
    private let incoming = DispatchQueue(label: "macaw.incoming")  // song pieces are written in the order they arrive

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(WebSchemeHandler(), forURLScheme: WebSchemeHandler.scheme)
        config.websiteDataStore = .default()                       // settings and playlists stay between launches
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []       // the next song starts by itself, also in the background
        config.allowsAirPlayForMediaPlayback = true

        let content = config.userContentController
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        content.addUserScript(WKUserScript(source: "window.MACAW_APP = { version: \"\(version)\", native: true };",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // A copy of the tag reader the page loads from the internet, so songs added offline still get their names and covers.
        if let url = Bundle.main.url(forResource: "jsmediatags.min", withExtension: "js", subdirectory: "www"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            content.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        content.add(WeakMessageHandler(self), name: "macaw")

        web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = Self.pageColor
        web.scrollView.backgroundColor = Self.pageColor
        web.scrollView.contentInsetAdjustmentBehavior = .never     // the page handles the notch and home bar itself
        web.scrollView.bounces = false
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isInspectable = true                                   // lets Safari on a Mac look inside, for debugging
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.current = self
        web.load(URLRequest(url: URL(string: "\(WebSchemeHandler.scheme)://app/index.html")!))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    /// Switching back to the native player: the web player's music stops with it.
    func stop() {
        web?.pauseAllMediaPlayback(completionHandler: nil)
        web?.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(a => { try { a.pause() } catch (e) {} })", completionHandler: nil)
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "macaw")
        if Self.current === self { Self.current = nil }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: songs

    func importSongs(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let added = Library.shared.importFiles(urls)
            DispatchQueue.main.async {
                if added > 0 || !urls.isEmpty { self.refreshLibrary() }
            }
        }
    }

    private func refreshLibrary() {
        guard loaded else { return }                               // the page reads the library itself when it loads
        web.evaluateJavaScript("window.natSync && window.natSync()", completionHandler: nil)
    }

    private func showPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importSongs(urls)
    }

    // MARK: messages from the page

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "native":
            MainActor.assumeIsolated { WebMode.shared.set(false) }
        case "import":
            showPicker()
        case "chunk":
            guard let id = body["id"] as? String, let n = body["n"] as? Int, let b64 = body["b64"] as? String else { return }
            incoming.async { Library.shared.appendPiece(b64, number: n, to: id) }
        case "save":
            guard let id = body["id"] as? String, let name = body["name"] as? String else { return }
            incoming.async { [weak self] in
                var rel: String?, problem = ""
                do { rel = try Library.shared.finishPieces(id, as: name) } catch { problem = "couldn't save it: \(error.localizedDescription)" }
                DispatchQueue.main.async { self?.callPage("natDownloaded", id, rel ?? "", rel != nil, problem) }
            }
        case "drop":
            guard let id = body["id"] as? String else { return }
            incoming.async { Library.shared.dropPieces(id) }
        case "delete":
            guard let rel = body["n"] as? String else { return }
            DispatchQueue.global(qos: .utility).async { Library.shared.deleteDownloaded(rel) }
        case "open":
            guard let s = body["url"] as? String, let url = URL(string: s), ["https", "tg"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        case "art":
            guard let rel = body["n"] as? String, let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) else { return }
            DispatchQueue.global(qos: .utility).async { Library.shared.saveArt(data, for: rel) }
        default:
            break
        }
    }

    /// Calls window.<fn>(args...) in the page, with the arguments passed as JSON.
    private func callPage(_ fn: String, _ args: Any...) {
        guard let data = try? JSONSerialization.data(withJSONObject: args), let list = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.\(fn) && window.\(fn).apply(null, \(list))", completionHandler: nil)
    }

    // MARK: web view

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }

    // If iOS stops the page in the background (low memory), reload it instead of showing a blank screen.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        webView.reload()
    }

    // Links to websites open in Safari; the app itself stays on the player.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? ""),
           navigationAction.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // The tilt effect asks for motion access; inside our own app that's always fine.
    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // alert() and confirm() from the page, as native dialogs.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}

/// The web view keeps its message handlers alive; this keeps it from keeping the view controller alive too.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves the web player at macaw://app/ : the page itself from the app bundle (www/), plus the song library:
///   macaw://app/lib/list          the songs, as JSON
///   macaw://app/lib/song/<path>   a song file (supports Range requests, for seeking)
///   macaw://app/lib/art/<path>    a song's cover, once the player has handed it over
/// A fixed address (instead of a file:// page) keeps the player's saved settings and playlists between launches.
final class WebSchemeHandler: NSObject, WKURLSchemeHandler {
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
            let list: [[String: Any]] = Library.shared.scan().map { ["n": $0.path, "s": $0.size, "m": $0.modified] }
            let data = (try? JSONSerialization.data(withJSONObject: list)) ?? Data("[]".utf8)
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
