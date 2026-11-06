import Foundation
import AVFoundation

/// Settings > Sound effect: None / Gramophone / Old radio / Vinyl, as in the web player.
/// The effect is not applied live. Each song is rendered once, on the phone, into an old-sounding copy (a WAV in Caches),
/// and that copy then replaces the song at the same position, so the lock screen, seeking and headphone buttons keep working.
/// Only the song playing and the next one are rendered, one at a time; the last 3 copies are kept.
@MainActor @Observable
final class Retro {
    static let shared = Retro()
    static let labels = ["gram": "Gramophone", "radio": "Old radio", "vinyl": "Vinyl"]
    private static let keep = 3

    private(set) var mode: String
    /// Something is being rendered for the song playing now (the ticked choice pulses).
    private(set) var busy = false
    /// "key|mode" of the copy that is loaded now, nil = the original.
    var loaded: String?

    private var done: [(key: String, url: URL)] = []
    private var jobs: [String: Task<URL?, Never>] = [:]
    private var chain: Task<Void, Never>?
    private let folder: URL

    private init() {
        let m = Store.shared["retroMode"] ?? "off"
        mode = Retro.labels[m] != nil ? m : "off"
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Retro", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)          // copies from an earlier run are not tracked
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var label: String { Retro.labels[mode] ?? "" }
    private func key(_ t: Track, _ m: String? = nil) -> String { t.key + "|" + (m ?? mode) }
    private func copy(_ k: String) -> URL? { done.first(where: { $0.key == k })?.url }

    /// The file to play for a song: its old-sounding copy when there is one, otherwise the song itself.
    func fileFor(_ t: Track) -> URL {
        let k = key(t)
        if mode != "off", let u = copy(k) { loaded = k; return u }
        loaded = nil
        return t.url
    }

    func set(_ m: String) {
        guard m != mode else { return }
        mode = m
        Store.shared["retroMode"] = m
        Haptics.light()
        if m != "off" { AppModel.shared.toast(label) }
        busy = false
        if let t = Player.shared.current { want(t) }
    }

    /// The song now playing should sound old (or not).
    func want(_ t: Track) {
        guard t.key == Player.shared.currentKey else { return }
        if mode == "off" { if loaded != nil { loaded = nil; Player.shared.swapSource(t.url) }; return }
        let k = key(t)
        if loaded == k { preNext(); return }
        if let u = copy(k) { loaded = k; Player.shared.swapSource(u); preNext(); return }
        busy = true
        Task {
            let u = await render(t)
            guard t.key == Player.shared.currentKey else { return }
            busy = false
            if let u, mode != "off", loaded != key(t), key(t) == k { loaded = k; Player.shared.swapSource(u) }
            preNext()
        }
    }

    func preNext() {
        guard mode != "off", let k = Player.shared.peekNext(), let t = AppModel.shared.byKey[k], k != Player.shared.currentKey else { return }
        _ = Task { await render(t) }
    }

    private func wanted(_ t: Track) -> Bool { t.key == Player.shared.currentKey || t.key == Player.shared.peekNext() }

    /// One song at a time; the same request is shared.
    private func render(_ t: Track) async -> URL? {
        let k = key(t), m = mode
        if let u = copy(k) { return u }
        if let j = jobs[k] { return await j.value }
        let before = chain
        let job = Task<URL?, Never> { [folder] in
            await before?.value
            guard self.mode == m, self.wanted(t), t.size <= 80_000_000, t.duration <= 20 * 60 else { return nil }
            let src = t.url, out = folder.appendingPathComponent(UUID().uuidString + ".wav")
            let ok = await Task.detached(priority: .utility) { Retro.make(src, to: out, mode: m) }.value
            guard ok else { return nil }
            self.remember(k, out)
            return out
        }
        jobs[k] = job
        chain = Task { _ = await job.value }
        let u = await job.value
        jobs[k] = nil
        return u
    }

    private func remember(_ k: String, _ u: URL) {
        done.removeAll { $0.key == k }
        done.append((k, u))
        while done.count > Retro.keep {
            let old = done.removeFirst()
            if old.key != loaded { try? FileManager.default.removeItem(at: old.url) } else { done.append(old); break }
        }
    }

    // MARK: the work itself (off the main thread)

    /// Decodes the song straight to 22 kHz (Vinyl: 32 kHz), mono for the old gear (Vinyl stays stereo), runs the effect, writes a WAV.
    nonisolated private static func make(_ src: URL, to out: URL, mode: String) -> Bool {
        let sr = RetroDSP.rate(mode)
        guard let file = try? AVAudioFile(forReading: src) else { return false }
        let inFmt = file.processingFormat
        let nc = min(2, inFmt.channelCount)
        guard nc > 0, let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: nc, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 32768),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 32768) else { return false }
        let total = Int(Double(file.length) * sr / inFmt.sampleRate) + 8192
        var a = [Float](), b = [Float]()
        a.reserveCapacity(total)
        if nc > 1 { b.reserveCapacity(total) }
        var eof = false
        while true {
            var err: NSError?
            outBuf.frameLength = 0
            let st = conv.convert(to: outBuf, error: &err) { want, status in
                if eof { status.pointee = .endOfStream; return nil }
                do { try file.read(into: inBuf, frameCount: min(want, inBuf.frameCapacity)) } catch { eof = true; status.pointee = .endOfStream; return nil }
                if inBuf.frameLength == 0 { eof = true; status.pointee = .endOfStream; return nil }
                status.pointee = .haveData
                return inBuf
            }
            if st == .error { return false }
            let n = Int(outBuf.frameLength)
            if n > 0, let ch = outBuf.floatChannelData {
                a.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
                if nc > 1 { b.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: n)) }
            }
            if st == .endOfStream || (eof && n == 0) { break }
        }
        guard a.count > Int(sr) else { return false }
        var right: [Float]? = nil
        if nc > 1 {
            if mode == "vinyl" { right = b }
            else { for i in 0..<min(a.count, b.count) { a[i] = (a[i] + b[i]) * 0.5 } }
        }
        b = []
        let pcm = RetroDSP.render(&a, &right, sr: sr, mode: mode)
        a = []
        do { try RetroDSP.wav(pcm, sr: Int(sr)).write(to: out); return true } catch { return false }
    }
}
