import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import SwiftUI

/// Playback, with the same rules as the web player:
/// - queue: only songs you added (Play next = top, Play last = bottom). It always plays first.
/// - context: what you started (an album, the whole library, a playlist), with an optional own order (shuffle).
/// - history: what you heard; Previous walks back through it.
/// Songs are referred to by their key (Track.key), which is also what the saved state ("playState") uses.
@MainActor @Observable
final class Player {
    static let shared = Player()

    struct Context: Codable, Equatable {
        var name: String
        var ids: [String]?       // nil = the whole library
        var order: [String]?     // your own order (shuffle, drags); nil = the album's order
        var at: String?          // the context song that is (or was last) playing
    }
    enum From: String, Codable { case queue, context, other }

    private(set) var currentKey: String?
    var current: Track? { currentKey.flatMap { AppModel.shared.byKey[$0] } }
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    var scrubbing: Double?                       // while you drag a progress bar (it only seeks when you let go)
    private(set) var queue: [String] = []
    struct HistoryEntry { var key: String; var from: From }
    private(set) var history: [HistoryEntry] = []
    private(set) var context: Context?
    private(set) var nowFrom: From = .context
    private(set) var shuffle = false
    private(set) var repeatMode: RepeatMode = .all
    private(set) var songDirection = 1          // +1 next, -1 previous, 0 picked from a list: which way the title slides

    private let av = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var pendingSeek: Double?
    private var restored = false
    private var failures = 0
    private var lastPosSave = Date.distantPast
    private var saveWork: Task<Void, Never>?

    private init() {
        repeatMode = RepeatMode(rawValue: Store.shared["repeatMode"] ?? "") ?? .all
        av.automaticallyWaitsToMinimizeStalling = false
        timeObserver = av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor in self?.tick(t.seconds) }
        }
        setUpRemote()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            Task { @MainActor in
                guard let self else { return }
                if type == .began { self.isPlaying = false; self.updateNowPlaying() }
                else if type == .ended, opts?.contains(.shouldResume) == true { self.play() }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            Task { @MainActor in if reason == .oldDeviceUnavailable { self?.pause() } }   // headphones unplugged
        }
    }

    // MARK: lists

    private var model: AppModel { AppModel.shared }
    private var allKeys: [String] { model.tracks.map(\.key) }
    private func exists(_ k: String) -> Bool { model.byKey[k] != nil }

    func contextList() -> [String] {
        guard let c = context else { return [] }
        guard let ids = c.ids else { return allKeys }
        return ids.filter(exists)
    }
    func contextOrder() -> [String] {
        guard let c = context else { return [] }
        guard let o = c.order else { return contextList() }
        return o.filter(exists)
    }
    func contextUpcoming() -> [String] {
        let o = contextOrder()
        guard let at = context?.at, let i = o.firstIndex(of: at) else { return o }
        return Array(o[(i + 1)...])
    }
    private func contextRestart() {
        let l = contextList()
        context?.order = shuffle ? l.shuffled() : nil
        context?.at = nil
    }
    private func contextNext(commit: Bool) -> String? {
        guard context != nil else { return nil }
        if let first = contextUpcoming().first { return first }
        if contextList().isEmpty { return nil }
        if !commit { return shuffle ? nil : contextList().first }
        contextRestart()
        return contextOrder().first
    }
    /// What Next would play (to prepare it ahead).
    func peekNext() -> String? { queue.first ?? contextNext(commit: false) }
    /// Your queue, then what the album still has to play.
    var upNext: [Track] { (queue + contextUpcoming()).compactMap { model.byKey[$0] } }

    // MARK: starting things

    /// A song tapped in a list: that list becomes the context (name = "Library" for All Tracks); your queue stays.
    func start(_ list: [Track], at t: Track, name: String, wholeLibrary: Bool = false) {
        var c = Context(name: name, ids: wholeLibrary ? nil : list.map(\.key), order: nil, at: t.key)
        if shuffle { c.order = [t.key] + list.map(\.key).filter { $0 != t.key }.shuffled() }
        context = c
        songDirection = 0
        playKey(t.key, from: .context)
    }
    /// The Play button on an album or playlist: from its first song (or shuffled, when shuffle is on).
    func playAll(_ list: [Track], name: String, wholeLibrary: Bool = false) {
        guard !list.isEmpty else { return }
        let first = shuffle ? list.randomElement()! : list[0]
        start(list, at: first, name: name, wholeLibrary: wholeLibrary)
    }

    func enqueue(_ t: Track, last: Bool) {
        if last { queue.append(t.key) } else { queue.insert(t.key, at: 0) }
        model.toast(last ? "“\(t.title)” added to the queue" : "“\(t.title)” plays next")
        changed()
    }
    func enqueueAll(_ ts: [Track], last: Bool) {
        if last { queue += ts.map(\.key) } else { queue.insert(contentsOf: ts.map(\.key), at: 0) }
        model.toast(last ? "\(ts.count) songs added to the queue" : "\(ts.count) songs play next")
        changed()
    }
    func removeFromQueue(at offsets: IndexSet) { queue.remove(atOffsets: offsets); changed() }
    func clearQueue() { queue.removeAll(); model.toast("Queue cleared"); Haptics.light(); changed() }
    func clearHistory() { history.removeAll(); changed() }
    func removeHistory(at i: Int) { if history.indices.contains(i) { history.remove(at: i); changed() } }
    /// A song from History played again: the album stays where it was.
    func replay(_ t: Track) {
        if let i = history.lastIndex(where: { $0.key == t.key }) { history.remove(at: i) }
        songDirection = 0
        playKey(t.key, from: .other)
    }
    func moveQueue(from: IndexSet, to: Int) { queue.move(fromOffsets: from, toOffset: to); changed() }
    func playFromQueue(index i: Int) {
        guard queue.indices.contains(i) else { return }
        let k = queue.remove(at: i)
        songDirection = 0
        playKey(k, from: .queue)
    }
    /// A song further down the album in Up next: the album jumps there.
    func playFromContext(_ key: String) {
        songDirection = 0
        context?.at = key
        playKey(key, from: .context)
    }
    /// Removes an album song from what's coming (the context gets its own order).
    func removeUpcoming(_ key: String) {
        guard context != nil else { return }
        var o = contextOrder()
        o.removeAll { $0 == key && $0 != context?.at }
        context?.order = o
        changed()
    }
    func moveUpcoming(from: IndexSet, to: Int) {
        guard context != nil else { return }
        let o = contextOrder()
        let i = context?.at.flatMap { o.firstIndex(of: $0) }
        let head = i.map { Array(o[...$0]) } ?? []
        var up = i.map { Array(o[($0 + 1)...]) } ?? o
        up.move(fromOffsets: from, toOffset: to)
        context?.order = head + up
        changed()
    }

    // MARK: transport

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        if currentKey == nil { ensureContext() }
        guard av.currentItem != nil else { if let k = currentKey { load(k, autoplay: true) }; return }
        try? AVAudioSession.sharedInstance().setActive(true)
        av.play(); isPlaying = true
        updateNowPlaying()
    }
    func pause() {
        av.pause(); isPlaying = false
        savePosition(); saveStateNow()
        updateNowPlaying()
    }

    func next() {
        songDirection = 1
        if !queue.isEmpty { playKey(queue.removeFirst(), from: .queue); return }
        if let k = contextNext(commit: true) { playKey(k, from: .context) }
    }

    /// Restarts the song past 3 s; otherwise goes back to the song you actually heard before.
    func previous() {
        if time > 3 { seek(to: 0); return }
        while let last = history.last, !exists(last.key) { history.removeLast() }
        guard let h = history.popLast() else { seek(to: 0); return }
        songDirection = -1
        if nowFrom == .queue, let cur = currentKey { queue.insert(cur, at: 0) }
        let back = h.from == .context && contextOrder().contains(h.key)
        if !back && nowFrom == .context, context != nil {
            let o = contextOrder()
            if let at = context?.at, let i = o.firstIndex(of: at) { context?.at = i > 0 ? o[i - 1] : nil }
        }
        playKey(h.key, from: back ? .context : (h.from == .queue ? .queue : .other), recordHistory: false)
    }

    func seek(to t: Double) {
        let d = duration > 0 ? duration : (current?.duration ?? 0)
        let to = max(0, d > 0 ? min(t, d - 0.2) : t)
        time = to
        if av.currentItem?.status == .readyToPlay {
            av.seek(to: CMTime(seconds: to, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in self?.updateNowPlaying() }
            }
        } else { pendingSeek = to }
        savePosition()
    }

    func toggleShuffle() {
        shuffle.toggle()
        model.toast(shuffle ? "Shuffle on" : "Shuffle off")
        Haptics.medium()
        if context != nil {
            if shuffle {
                let l = contextList(), at = context?.at
                if let at, l.contains(at) { context?.order = [at] + l.filter { $0 != at }.shuffled() } else { context?.order = l.shuffled() }
            } else { context?.order = nil }
        }
        changed()
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .all ? .one : repeatMode == .one ? .off : .all
        Store.shared["repeatMode"] = repeatMode.rawValue
        model.toast(repeatMode == .one ? "Repeat this song" : repeatMode == .off ? "Repeat off" : "Repeat all")
        Haptics.medium()
        changed()
    }

    private func ended() {
        if repeatMode == .one { seek(to: 0); av.play(); return }
        if repeatMode == .off, queue.isEmpty, context != nil, contextUpcoming().isEmpty, !contextList().isEmpty {
            contextRestart()
            if let k = contextOrder().first { songDirection = 1; playKey(k, from: .context, autoplay: false) }
            return
        }
        next()
    }

    private func ensureContext() {
        if currentKey == nil, let first = model.tracks.first { playKey(first.key, from: .context, autoplay: false, recordHistory: false) }
        if context == nil, let cur = currentKey { context = Context(name: "Library", ids: nil, order: nil, at: cur); nowFrom = .context }
    }

    private func playKey(_ key: String, from: From, autoplay: Bool = true, recordHistory: Bool = true) {
        if recordHistory, let cur = currentKey {
            if history.last?.key != cur { history.append(HistoryEntry(key: cur, from: nowFrom)) }
            if history.count > 200 { history.removeFirst(history.count - 200) }
        }
        if from == .context { context?.at = key }
        nowFrom = from
        load(key, autoplay: autoplay)
        changed()
    }

    private func load(_ key: String, autoplay: Bool, at start: Double = 0) {
        guard let t = model.byKey[key] else { return }
        currentKey = key
        time = start
        duration = t.duration
        pendingSeek = start > 0 ? start : nil
        attach(Retro.shared.fileFor(t))
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            av.play(); isPlaying = true
        } else { av.pause(); isPlaying = false }
        updateNowPlaying()
        Covers.shared.prefetch(t)
        Retro.shared.want(t)
    }

    /// Swaps the song between its original and its old-sounding copy, at the same place, playing or not.
    func swapSource(_ url: URL) {
        guard currentKey != nil else { return }
        pendingSeek = pendingSeek ?? max(0, time)
        if pendingSeek == 0 { pendingSeek = nil }
        attach(url)
        if isPlaying { av.play() }
    }

    private func attach(_ url: URL) {
        let item = AVPlayerItem(url: url)
        statusObservation = Player.observeStatus(item) { [weak self] status, d in self?.itemStatus(status, duration: d) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ended() }
        }
        av.replaceCurrentItem(with: item)
    }

    private func itemStatus(_ s: AVPlayerItem.Status, duration d: Double) {
        switch s {
        case .readyToPlay:
            failures = 0
            if d.isFinite, d > 0 { duration = d }
            if let p = pendingSeek {
                pendingSeek = nil
                av.seek(to: CMTime(seconds: p, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            updateNowPlaying()
        case .failed:
            failures += 1
            model.toast("Couldn't play “\(current?.title ?? "this song")”, skipped")
            if failures < 4 { next() } else { isPlaying = false; failures = 0 }
        default: break
        }
    }

    private func tick(_ t: Double) {
        guard t.isFinite, pendingSeek == nil else { return }
        time = t
        if isPlaying && av.timeControlStatus == .paused && av.rate == 0 && av.currentItem?.status == .readyToPlay && t > 0 {
            // paused from outside (e.g. Control Center): keep the buttons honest
        }
        if Date().timeIntervalSince(lastPosSave) > 4 { savePosition() }
    }

    // MARK: library changes

    func libraryChanged() {
        if !restored { restore(); return }
        if let k = currentKey, model.byKey[k] == nil {      // the playing song was removed
            av.replaceCurrentItem(with: nil); currentKey = nil; isPlaying = false
            ensureContext()
        }
        queue.removeAll { !exists($0) }
        if currentKey == nil { ensureContext() }
        changed()
    }
    func playlistsChanged() { changed() }

    // MARK: saving (same format as the web player's playState / playPos)

    private struct SavedState: Codable {
        var v: Int
        var cur: String
        var from: String?
        var pos: Double?
        var dur: Double?
        var queue: [String]?
        var hist: [[String?]]?
        var ctx: Context?
    }
    private struct SavedPos: Codable { var cur: String; var pos: Double; var dur: Double? }

    private func changed() {
        Retro.shared.preNext()
        saveWork?.cancel()
        saveWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveStateNow()
        }
    }

    func saveStateNow() {
        guard restored, let cur = currentKey else { return }
        let s = SavedState(v: 3, cur: cur, from: nowFrom.rawValue, pos: (time * 10).rounded() / 10, dur: (duration * 10).rounded() / 10,
                           queue: queue, hist: history.suffix(50).map { [$0.key, $0.from.rawValue] }, ctx: context)
        Store.shared.setJSON("playState", s)
        savePosition()
    }
    private func savePosition() {
        lastPosSave = Date()
        guard restored, let cur = currentKey else { return }
        Store.shared.setJSON("playPos", SavedPos(cur: cur, pos: (time * 10).rounded() / 10, dur: duration))
    }

    private func restore() {
        restored = true
        guard var s = Store.shared.json("playState", as: SavedState.self), s.v == 3 else { ensureContext(); return }
        if let p = Store.shared.json("playPos", as: SavedPos.self), p.cur == s.cur { s.pos = p.pos; s.dur = p.dur ?? s.dur }
        guard exists(s.cur) else { ensureContext(); return }
        queue = (s.queue ?? []).filter(exists)
        history = (s.hist ?? []).compactMap { h in
            guard let k = h.first ?? nil, exists(k) else { return nil }
            return HistoryEntry(key: k, from: From(rawValue: (h.count > 1 ? h[1] : nil) ?? "") ?? .context)
        }
        context = s.ctx
        if let ids = context?.ids, ids.filter(exists).isEmpty { context = nil }
        let from = From(rawValue: s.from ?? "") ?? .context
        nowFrom = from == .context && context == nil ? .other : from
        let pos = s.pos ?? 0, dur = s.dur ?? 0
        let resume = pos > 2 && (dur == 0 || pos < dur - 2)
        load(s.cur, autoplay: false, at: resume ? pos : 0)
        if context == nil { ensureContext() }
    }

    // iOS calls these back on its own threads, so they are made outside the main actor.
    nonisolated private static func observeStatus(_ item: AVPlayerItem, _ done: @escaping @MainActor (AVPlayerItem.Status, Double) -> Void) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { item, _ in
            let status = item.status, d = item.duration.seconds
            Task { @MainActor in done(status, d) }
        }
    }
    nonisolated private static func artwork(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }

    // MARK: lock screen, Control Center, headphones

    private func setUpRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }

    private var nowPlayingArtKey: String?
    private var nowPlayingArt: MPMediaItemArtwork?

    func updateNowPlaying() {
        guard let t = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.shownArtist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if nowPlayingArtKey != t.path {
            nowPlayingArtKey = t.path
            nowPlayingArt = nil
            if let data = Library.shared.art(for: t.path), let img = UIImage(data: data) {
                nowPlayingArt = Player.artwork(img)
            }
        }
        if let a = nowPlayingArt { info[MPMediaItemPropertyArtwork] = a }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
