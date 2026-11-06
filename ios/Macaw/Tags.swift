import Foundation
import AVFoundation

/// A song's name, artist, album... read once from the file and remembered (tags.json), like the web player's natTags.
struct TagInfo: Codable {
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var num: Int
    var disc: Int
    var year: String
    var duration: Double
    var isrc: String? = nil     // nil: not read yet (tags cached before ISRCs were read)
}

enum Tags {
    /// Reads a file's tags with AVFoundation (MP3 ID3, M4A/AAC iTunes tags). Its cover is kept in the Covers folder.
    static func read(_ url: URL, path: String) async -> TagInfo {
        let asset = AVURLAsset(url: url)
        var info = fromFileName(url.deletingPathExtension().lastPathComponent)
        if let d = try? await asset.load(.duration), d.seconds.isFinite { info.duration = d.seconds }
        guard let items = try? await asset.load(.metadata) else { return info }
        var picture: Data?
        for item in items {
            guard let id = item.identifier else { continue }
            switch id {
            case .commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName:
                if let s = await string(item), !s.isEmpty { info.title = s }
            case .commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist:
                if let s = await string(item), !s.isEmpty { info.artist = s }
            case .commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum:
                if let s = await string(item), !s.isEmpty { info.album = s }
            case .id3MetadataBand, .iTunesMetadataAlbumArtist:
                if let s = await string(item), !s.isEmpty { info.albumArtist = s }
            case .id3MetadataTrackNumber:
                if let s = await string(item) { info.num = leadingInt(s) }
            case .id3MetadataPartOfASet:
                if let s = await string(item) { info.disc = leadingInt(s) }
            case .iTunesMetadataTrackNumber:
                if let d = try? await item.load(.dataValue), d.count >= 4 { info.num = Int(d[2]) << 8 | Int(d[3]) }
                else if let n = try? await item.load(.numberValue) { info.num = n.intValue }
            case .iTunesMetadataDiscNumber:
                if let d = try? await item.load(.dataValue), d.count >= 4 { info.disc = Int(d[2]) << 8 | Int(d[3]) }
                else if let n = try? await item.load(.numberValue) { info.disc = n.intValue }
            case .id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .commonIdentifierCreationDate, .id3MetadataReleaseTime:
                if info.year.isEmpty, let s = await string(item), let y = s.range(of: #"\d{4}"#, options: .regularExpression) { info.year = String(s[y]) }
            case .id3MetadataInternationalStandardRecordingCode:
                if let s = await string(item), !s.isEmpty { info.isrc = s }
            case .commonIdentifierArtwork, .id3MetadataAttachedPicture, .iTunesMetadataCoverArt:
                if picture == nil, let d = try? await item.load(.dataValue), d.count > 100 { picture = d }
            default:
                break
            }
        }
        if let picture, !Library.shared.hasArt(path) { Library.shared.saveArt(picture, for: path) }
        if info.isrc == nil { info.isrc = "" }
        return info
    }

    /// Only the recording's ID code (for songs whose tags were read before ISRCs were).
    static func isrc(_ url: URL) async -> String {
        guard let items = try? await AVURLAsset(url: url).load(.metadata) else { return "" }
        for item in items where item.identifier == .id3MetadataInternationalStandardRecordingCode {
            if let s = await string(item), !s.isEmpty { return s }
        }
        return ""
    }

    private static func string(_ item: AVMetadataItem) async -> String? {
        if let s = try? await item.load(.stringValue) { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = try? await item.load(.numberValue) { return n.stringValue }
        return nil
    }

    private static func leadingInt(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })) ?? 0
    }

    /// "Artist - Title" (or "01 Title") from the file name, used when a file has no tags.
    static func fromFileName(_ name: String) -> TagInfo {
        var title = name, artist = "", num = 0
        if let r = name.range(of: " - ") {
            artist = String(name[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            title = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let m = title.range(of: #"^\d{1,3}[ .\-_]+"#, options: .regularExpression) {
            num = leadingInt(String(title[m])); title = String(title[m.upperBound...])
        }
        return TagInfo(title: title.isEmpty ? name : title, artist: artist, album: "", albumArtist: "", num: num, disc: 0, year: "", duration: 0)
    }
}
