import SwiftUI
import QuartzCore
import os

/// Measures how smoothly the app draws: every screen refresh is timed, and a frame that took clearly longer than the
/// screen's own refresh (a hitch) is counted. Used two ways:
/// - the build machine's walk-through test (launch argument -macawPerf): each second's numbers go to the log as
///   "MacawPerf …" lines together with where the app is (tab, page, big player), so slow places can be found;
/// - Settings > Speed meter: a small readout in the corner (frames per second and hitches) to check on the phone.
@MainActor @Observable
final class PerfMeter {
    static let shared = PerfMeter()
    nonisolated static let log = Logger(subsystem: "app.macaw.player", category: "perf")

    var fps: Double = 0
    var hitchesPerSec: Double = 0
    var worstMs: Double = 0
    var shown = false

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: LinkProxy?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var winStart: CFTimeInterval = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var hitches = 0
    @ObservationIgnored private var worst: CFTimeInterval = 0
    @ObservationIgnored private var logging = false
    @ObservationIgnored private var totalFrames = 0
    @ObservationIgnored private var totalHitches = 0

    private init() {}

    func start(log: Bool) {
        logging = logging || log
        guard link == nil else { return }
        let p = LinkProxy { [weak self] l in self?.tick(l) }
        let l = CADisplayLink(target: p, selector: #selector(LinkProxy.fire(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        proxy = p; link = l
    }

    func stop() {
        guard !logging else { return }
        link?.invalidate(); link = nil; proxy = nil; last = 0
    }

    private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        defer { last = now }
        guard last > 0 else { winStart = now; return }
        let dt = now - last, expected = max(1.0 / 120, l.targetTimestamp - l.timestamp)
        frames += 1; totalFrames += 1
        if dt > expected * 1.6 { hitches += 1; totalHitches += 1 }
        worst = max(worst, dt)
        if now - winStart >= 1 {
            let span = now - winStart
            fps = Double(frames) / span
            hitchesPerSec = Double(hitches) / span
            worstMs = worst * 1000
            if logging {
                let line = String(format: "MacawPerf fps=%.0f hitches=%d worst=%.0fms where=%@ total=%d/%d", fps, hitches, worstMs, Self.where_(), totalHitches, totalFrames)
                Self.log.notice("\(line, privacy: .public)")
            }
            frames = 0; hitches = 0; worst = 0; winStart = now
        }
    }

    /// Where the app is, for the log.
    static func where_() -> String {
        let ui = UIState.shared
        var s = ui.tab.map { "\($0)" } ?? "panel"
        let path = ui.tab == .artists ? ui.artistsPath : ui.tab == .library ? ui.libraryPath : []
        if let p = path.last { s += "/\(p)" }
        if ui.expanded { s += "+big" }
        if ui.lyricsOpen { s += "+lyrics" }
        if ui.settingsOpen { s += "+settings" }
        return s.replacingOccurrences(of: " ", with: "_")
    }
}

/// The small readout in the top corner (Settings > Speed meter).
struct PerfHUD: View {
    private var m: PerfMeter { .shared }
    var body: some View {
        let bad = m.hitchesPerSec > 2
        Text("\(Int(m.fps.rounded())) fps · \(Int(m.hitchesPerSec.rounded())) hitches · \(Int(m.worstMs)) ms")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(bad ? Color(red: 1, green: 0.55, blue: 0.5) : Color.w(0.85))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .allowsHitTesting(false)
    }
}
