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

/// The wallpaper: your own photo (Settings > Wallpaper), or the default one, kept in the app.
enum Wallpaper {
    static let defaultURL = URL(string: "https://images.unsplash.com/photo-1478760329108-5c3ed9d495a0?auto=format&fit=crop&w=2400&q=75")!
    static var customFile: URL { Library.shared.supportFolder.appendingPathComponent("wallpaper.jpg") }
    static var defaultFile: URL { Library.shared.supportFolder.appendingPathComponent("wallpaper-default.jpg") }

    static func saveCustom(_ jpeg: Data) { try? jpeg.write(to: customFile, options: .atomic) }
    static func clearCustom() { try? FileManager.default.removeItem(at: customFile) }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customFile.path) }

    static func load() async -> UIImage? {
        let file = hasCustom ? customFile : defaultFile
        if !FileManager.default.fileExists(atPath: file.path) && !hasCustom {
            if case let (data, _)? = try? await URLSession.shared.data(from: defaultURL), UIImage(data: data) != nil {
                try? data.write(to: defaultFile, options: .atomic)
            }
        }
        return await Task.detached { Covers.downsample(url: file, px: 1800) }.value
    }
}
