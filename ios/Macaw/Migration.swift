import Foundation
import WebKit

/// The old app was the web player in a web view, which kept your playlists, Telegram link and settings in its own
/// storage (localStorage at macaw://app). The first time this version opens, it reads them from there once, so nothing
/// is lost. The old storage is left as it is (installing the old app again would still find it).
@MainActor
final class Migration: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    static let doneKey = "nativeMigrated"
    /// Keys taken over as they are (same names and format in this app).
    static let keys = ["playlists", "hiddenAlbums", "albumOrder", "releaseMap2", "tileCovers", "allName", "wallpaperBlur", "wallDefault", "repeatMode",
                       "playState", "playPos", "tgKey", "tgDone", "tgAlbums", "tgDur", "tgPending", "syncSeen", "oldPanel", "retroMode",
                       "libView", "lightMin", "tiltOn", "artistCache", "lyrics1"]

    private var web: WKWebView?
    private var finish: ((([String: String])?) -> Void)?

    static func runIfNeeded() async {
        if UserDefaults.standard.bool(forKey: doneKey) { return }
        let m = Migration()
        let values = await m.read()
        if let values {
            for k in keys { if let v = values[k], !v.isEmpty { Store.shared.setQuietly(k, v) } }
            if let at = values["syncAt"] { Sync.shared.importTimes(at) }
            if let photo = values["photoData"], let comma = photo.firstIndex(of: ","), let data = Data(base64Encoded: String(photo[photo.index(after: comma)...])) {
                Wallpaper.saveCustom(data)
            }
            Store.shared.saveNow()
        }
        UserDefaults.standard.set(true, forKey: doneKey)
        UserDefaults.standard.synchronize()
    }

    private func read() async -> [String: String]? {
        await withCheckedContinuation { (c: CheckedContinuation<[String: String]?, Never>) in
            var finished = false
            finish = { v in
                if finished { return }
                finished = true
                c.resume(returning: v)
            }
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.setURLSchemeHandler(self, forURLScheme: "macaw")
            config.userContentController.add(self, name: "m")
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
            web = w
            w.load(URLRequest(url: URL(string: "macaw://app/migrate.html")!))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)        // never hold the app up for long
                self?.done(nil)
            }
        }
    }

    private func done(_ v: [String: String]?) {
        finish?(v); finish = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "m")
        web = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = message.body as? String, let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: String].self, from: d) else { done([:]); return }
        done(v)
    }

    // The same address the old page had (macaw://app), so the browser storage is the same one.
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let html = "<!doctype html><script>var o={};try{for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);o[k]=localStorage.getItem(k);}}catch(e){}webkit.messageHandlers.m.postMessage(JSON.stringify(o));</script>"
        let data = Data(html.utf8)
        task.didReceive(HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": "text/html", "Content-Length": "\(data.count)"])!)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
