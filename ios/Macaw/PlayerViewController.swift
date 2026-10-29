import UIKit
import WebKit
import UniformTypeIdentifiers

/// The whole app: one full-screen web view showing the player (index.html), served from the app at macaw://app/.
/// The page talks to the app through window.webkit.messageHandlers.macaw:
///   { cmd: "import" }                  show the Files picker and copy the chosen songs in
///   { cmd: "art", n: path, b64: ... }  keep a song's cover (read from its tags by the page)
///   { cmd: "download", id, url, name } download a song from the Telegram bot into the app, then call natDownloaded(id, path, ok)
///   { cmd: "delete", n: path }         remove a song downloaded from the bot
///   { cmd: "open", url }               open a link in another app (Telegram)
/// and the app calls window.natSync() when songs were added.
final class PlayerViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UIDocumentPickerDelegate {
    static let pageColor = UIColor(red: 0x0b / 255.0, green: 0x1d / 255.0, blue: 0x24 / 255.0, alpha: 1)
    private var web: WKWebView!
    private var loaded = false
    private lazy var downloads: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 2                        // a few at a time, the rest wait their turn
        c.timeoutIntervalForRequest = 180                          // the server may first have to fetch a big song from Telegram
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SchemeHandler(), forURLScheme: SchemeHandler.scheme)
        config.websiteDataStore = .default()                       // settings and playlists stay between launches
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []       // the next song starts by itself, also in the background
        config.allowsAirPlayForMediaPlayback = true

        let content = config.userContentController
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        content.addUserScript(WKUserScript(source: "window.MACAW_APP = { version: \"\(version)\" };",
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
        if #available(iOS 16.4, *) { web.isInspectable = true }   // lets Safari on a Mac look inside, for debugging
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        web.load(URLRequest(url: URL(string: "\(SchemeHandler.scheme)://app/index.html")!))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

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
        case "import":
            showPicker()
        case "download":
            guard let id = body["id"] as? String, let s = body["url"] as? String, let url = URL(string: s), let name = body["name"] as? String else { return }
            download(id: id, from: url, as: name)
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

    private func download(id: String, from url: URL, as name: String) {
        downloads.downloadTask(with: url) { [weak self] tmp, response, error in
            var rel: String?, problem = ""
            if let error = error {
                problem = error.localizedDescription
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                problem = "the server answered \(http.statusCode)"
            } else if let tmp = tmp {
                do { rel = try Library.shared.store(downloaded: tmp, as: name) }   // must happen before this closure returns: tmp is deleted after
                catch { problem = "couldn't save it: \(error.localizedDescription)" }
            } else {
                problem = "nothing arrived"
            }
            DispatchQueue.main.async { self?.callPage("natDownloaded", id, rel ?? "", rel != nil, problem) }
        }.resume()
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
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // alert() and confirm() from the page, as native dialogs.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
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
