import SwiftUI
import UIKit
import ImageIO

/// Song covers, decoded at the size they're shown and kept in memory.
final class Covers: @unchecked Sendable {
    static let shared = Covers()
    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "macaw.covers", qos: .userInitiated, attributes: .concurrent)

    init() { cache.countLimit = 400 }

    func cached(_ key: String, px: Int) -> UIImage? { cache.object(forKey: "\(key)@\(bucket(px))" as NSString) }

    private func bucket(_ px: Int) -> Int { px <= 120 ? 120 : px <= 300 ? 300 : 700 }

    func image(path: String, px: Int) async -> UIImage? {
        let b = bucket(px), k = "\(path)@\(b)" as NSString
        if let i = cache.object(forKey: k) { return i }
        return await withCheckedContinuation { c in
            queue.async {
                let url = Library.shared.artURL(for: path)
                let img = Covers.downsample(url: url, px: b)
                if let img { self.cache.setObject(img, forKey: k) }
                c.resume(returning: img)
            }
        }
    }

    /// A custom tile cover (a "data:image/jpeg;base64,..." text, as the web player keeps them).
    func image(dataURL: String, px: Int) async -> UIImage? {
        let b = bucket(px), k = "d:\(dataURL.hashValue)@\(b)" as NSString
        if let i = cache.object(forKey: k) { return i }
        return await withCheckedContinuation { c in
            queue.async {
                var img: UIImage?
                if let comma = dataURL.firstIndex(of: ","), let d = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
                   let src = CGImageSourceCreateWithData(d as CFData, nil) { img = Covers.thumb(src, px: b) }
                if let img { self.cache.setObject(img, forKey: k) }
                c.resume(returning: img)
            }
        }
    }

    func prefetch(_ t: Track) { Task { _ = await image(path: t.path, px: 700) } }

    static func downsample(url: URL, px: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumb(src, px: px)
    }
    static func thumb(_ src: CGImageSource, px: Int) -> UIImage? {
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: px]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A song's cover (or a custom tile cover), or the placeholder used in the web player.
struct CoverImage: View {
    var path: String?
    var dataURL: String? = nil
    var px: Int
    var placeholder: AnyView = AnyView(Color.white.opacity(0.06))
    @State private var img: UIImage?
    @State private var loadedKey: String?

    private var key: String { (dataURL.map { "d:\($0.hashValue)" } ?? path ?? "") + "@\(px)" }
    private var memo: UIImage? {
        if let dataURL { return Covers.shared.cached("d:\(dataURL.hashValue)", px: px) }
        if let path { return Covers.shared.cached(path, px: px) }
        return nil
    }

    var body: some View {
        ZStack {
            // already decoded (scrolling back, or the same cover elsewhere): shown at once, without a placeholder frame
            if let shown = (loadedKey == key ? img : nil) ?? memo ?? img {
                Image(uiImage: shown).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: key) {
            if loadedKey == key, img != nil { return }
            var i: UIImage?
            if let dataURL { i = await Covers.shared.image(dataURL: dataURL, px: px) }
            else if let path { i = await Covers.shared.image(path: path, px: px) }
            img = i; loadedKey = key
        }
    }
}

/// The wallpaper: your own photo (Settings > Wallpapers > Choose your own), or one of the built-in ones (web WALLS),
/// which come with the app (Walls/). The first built-in one is the default.
enum Wallpaper {
    struct Builtin: Identifiable { let id: String; let name: String; let file: String }
    static let builtins = [Builtin(id: "autumn", name: "Autumn sky", file: "autumn-sky")]

    static var customFile: URL { Library.shared.supportFolder.appendingPathComponent("wallpaper.jpg") }
    static func url(_ b: Builtin) -> URL? { Bundle.main.url(forResource: b.file, withExtension: "jpg") }
    /// the built-in one you picked (same Store key as the web: wallDefault), the first until you pick
    @MainActor static var chosen: Builtin { builtins.first { $0.id == Store.shared["wallDefault"] } ?? builtins[0] }
    /// picking a built-in one puts your own photo away
    @MainActor static func choose(_ b: Builtin) { clearCustom(); Store.shared["wallDefault"] = b.id }

    static func saveCustom(_ jpeg: Data) { try? jpeg.write(to: customFile, options: .atomic) }
    static func clearCustom() { try? FileManager.default.removeItem(at: customFile) }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customFile.path) }

    @MainActor static func load() async -> UIImage? {
        guard let file = hasCustom ? customFile : url(chosen) else { return nil }
        return await Task.detached { Covers.downsample(url: file, px: 1800) }.value
    }

    /// Settings' squares: small copies, made once
    @MainActor private static var thumbs: [String: UIImage] = [:]
    @MainActor static func thumb(_ b: Builtin) -> UIImage? {
        if let t = thumbs[b.id] { return t }
        guard let u = url(b), let t = Covers.downsample(url: u, px: 240) else { return nil }
        thumbs[b.id] = t; return t
    }
}
