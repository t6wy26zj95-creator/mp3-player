import SwiftUI
import AVFoundation
import CoreImage
import QuartzCore
import UIKit
import UIKit.UIGestureRecognizerSubclass
import CoreMotion

/// The music glow, ported from the web player's decorative loop (pulseLoop, breathe, envelope, bandEvents, coverGlow and
/// the cover-colour picker). Everything here runs at 30 fps and only feeds a few small views: the bloom and the light
/// behind the cover, the cover's glass layers, the breathing controls and the panel tint.
@MainActor @Observable
final class Glow {
    static let shared = Glow()

    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double
        var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        static let neutral = RGB(r: 200, g: 215, b: 225)
    }

    // per frame
    var pulse: Double = 0
    var energy: Double = 0
    var flare: Double = 0
    var rimA: Double = 0
    var glassT: Double = 0
    var br: Double = 0.5
    var bp: [Double] = [0, 0, 0]
    /// The phone's tilt, smoothed, -1…1 (web TILT.x / TILT.y): the cover's glow and light lean with it, the wallpaper
    /// drifts the other way. Changes smaller than you can see aren't written, so a phone lying still costs nothing.
    var tx: Double = 0
    var ty: Double = 0
    /// How tilted the phone is, 0…1, eased over ~0.35 s (web: tilt): 0 lying still, the glass then runs on its own motion.
    var tilt: Double = 0

    // per song
    var c1: RGB = .neutral
    var c2: RGB = .neutral
    var lk: Double = 0.55
    var lum: Double = 0.5
    var bloom: UIImage?
    var light: UIImage?

    // the title spark (web: sparkTick / sparkFire): sparkN counts sparks, the title's glint plays one per change;
    // cometN does the same for the comet round Play that follows it
    var sparkN = 0
    @ObservationIgnored var sparkB = 0.7
    @ObservationIgnored var sparkD = 1.3
    var cometN = 0
    @ObservationIgnored var cometB = 1.0
    /// Width of the title text on screen (stops at the ellipsis), set by the compact title.
    @ObservationIgnored var titleW: CGFloat = 0

    @ObservationIgnored private var env: [Float]?
    @ObservationIgnored private var events: [GlowMath.Event] = []
    @ObservationIgnored private var accents: Accents?
    @ObservationIgnored private var envKey: String?
    @ObservationIgnored private var envCache: [String: ([Float], [GlowMath.Event])] = [:]
    @ObservationIgnored private var envOrder: [String] = []
    @ObservationIgnored private var artKey: String?
    @ObservationIgnored private var lastLight = ""
    @ObservationIgnored private var bpHist: [Double] = []
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: LinkProxy?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var held0 = false
    @ObservationIgnored private var catchUp: Double = 0
    @ObservationIgnored private var rate = 0      // 10, 30 or 120 frames a second, see the end of frame()
    @ObservationIgnored private var clock: Double = 0
    private let motion = CMMotionManager()
    @ObservationIgnored private var rawX = 0.0
    @ObservationIgnored private var rawY = 0.0
    @ObservationIgnored private var sx = 0.0
    @ObservationIgnored private var sy = 0.0
    @ObservationIgnored private var bB: Double?
    @ObservationIgnored private var bG = 0.0

    private init() {}

    func start() {
        guard link == nil else { return }
        let p = LinkProxy { [weak self] l in self?.frame(l) }
        let l = CADisplayLink(target: p, selector: #selector(LinkProxy.fire(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        proxy = p; link = l
        light = Glow.makeLight(.neutral, .neutral); lastLight = "n|n"
        TouchWatch.install()
        startTilt()
    }

    /// web: deviceorientation → tx = (gamma - neutral) / 14, ty = (beta - neutral) / 14; the neutral pose slowly drifts
    /// to however you hold the phone. No permission needed on iOS for this.
    private func startTilt() {
        guard motion.isDeviceMotionAvailable, !UIAccessibility.isReduceMotionEnabled,
              !CommandLine.arguments.contains("-macawScreen") else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 120
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            MainActor.assumeIsolated {
                let beta = a.pitch * 180 / .pi, gamma = a.roll * 180 / .pi
                if self.bB == nil { self.bB = beta; self.bG = gamma }
                var b = self.bB!; b += (beta - b) * 0.004; self.bB = b
                self.bG += (gamma - self.bG) * 0.004
                self.rawX = max(-1, min(1, (gamma - self.bG) / 14))
                self.rawY = max(-1, min(1, (beta - b) / 14))
            }
        }
    }

    /// A new song is loading (web: analyze + the cover colours + flare = 1 once its artwork is in).
    func songChanged(_ t: Track, first: Bool) {
        if !first { flare = 1 }
        analyze(t)
        colours(t)
    }

    // MARK: the loop (web: pulseLoop + breathe)

    private func frame(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = min(0.1, last > 0 ? now - last : 0.033)
        last = now
        // while the big player opens or closes, the light, the glow and the breathing hold still (web: XP freezes them):
        // each tick redraws the covers' glass and the buttons' glow, and on top of the motion's own frame that work
        // dropped a frame every tick (every 6th frame while paused). They carry on from where they were, no jump.
        let ph = XPMotion.shared.phase
        if ph == .moving || ph == .measuring { held0 = true; return }
        // just after it: the tilt glides to where the phone is now over ~0.3 s instead of jumping there
        if held0 { held0 = false; catchUp = now + 0.5 }
        let player = Player.shared
        let playing = player.isPlaying
        var target = 0.0
        if playing {
            if let env, !env.isEmpty {
                target = Double(env[min(env.count - 1, max(0, Int(player.preciseTime * 30)))])
            } else { target = 0.4 + 0.15 * sin(now / 1.5) }
        }
        var p = pulse + (target - pulse) * (1 - pow(target > pulse ? 0.86 : 0.96, dt * 60))   // quick-ish rise, slow fall
        if p < 0.003 && !playing { p = 0 }
        var f = flare, a = rimA
        if f > 0.003 { f *= exp(-dt / 0.45); a += f * 260 * dt } else { f = 0 }               // song change: the light swings round
        // breathe: Play follows the music, the sides ~0.1 s later; paused, Play keeps a slow breath of its own
        bpHist.append(p)
        while bpHist.count > max(2, Int((0.1 / max(dt, 0.016)).rounded()) + 1) { bpHist.removeFirst() }
        var e = energy + ((playing ? 1 : 0) - energy) * (1 - exp(-dt / (playing ? 0.4 : 1.8)))
        if !playing && e < 0.005 { e = 0 }
        let lag = bpHist[0], idle = (1 - e) * (0.16 + 0.14 * sin(now / 1.5))
        let nb = [lag * 0.7, max(p, idle), lag * 0.7]
        // web: while you touch or scroll (and just after), the glass light, its clock and the slow breath hold still,
        // so the phone spends that time following your finger; a song change's swing still plays. It carries on from
        // where it stopped, never with a jump.
        let held = TouchWatch.held(now) && f <= 0.05
        if !held {
            a = (a + (4 + e * (5 + p * 14)) * dt).truncatingRemainder(dividingBy: 360)      // the light slowly orbits the cover
        }
        if p != pulse { pulse = p }
        if f != flare { flare = f }
        if e != energy { energy = e }
        if a != rimA { rimA = a }
        sparkTick(playing, dt, now)
        if !held { glassT += dt; clock += dt }
        // the tilt follows the phone closely (~0.06 s): any slower and the glass seemed to lag behind your hand
        let k = 1 - exp(-dt / (now < catchUp ? 0.3 : 0.06))
        let turning = abs(rawX - sx) + abs(rawY - sy) > 0.006
        sx += (rawX - sx) * k; sy += (rawY - sy) * k
        if abs(sx - tx) + abs(sy - ty) > 0.003 { tx = sx; ty = sy }
        let nt = tilt + (min(1, hypot(sx, sy)) - tilt) * (1 - exp(-dt / 0.35))
        if abs(nt - tilt) > 0.004 { tilt = nt }
        let nbr = 0.5 + 0.5 * sin(clock / 2.6)
        if nbr != br { br = nbr }
        if zip(nb, bp).contains(where: { abs($0 - $1) > 0.006 }) { bp = nb }
        // paused and settled: only the slow drift is left, 10 fps is plenty
        // while the phone is turning, the wallpaper and the glass follow it at the screen's full rate, 120 fps on ProMotion
        // iPhones (at 10 fps it felt like lag)
        let slow = !playing && e < 0.02 && f == 0 && p < 0.003
        let want = turning ? 120 : slow ? 10 : 30
        if want != rate {
            rate = want
            l.preferredFrameRateRange = want == 120 ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                : want == 10 ? CAFrameRateRange(minimum: 8, maximum: 10, preferred: 10) : CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }
    }

    // MARK: the title spark (web: accentsOf, sparkGap, sparkPlan, sparkTick, sparkFire)

    /// Accents = local peaks with a sharp rise over the recent past, ranked by strength within the song.
    struct Accents {
        var list: [(t: Double, s: Double, r: Double)]
        var P: [Double]
        func avg(_ x0: Int, _ y0: Int) -> Double {
            let F = P.count - 1, x = max(0, x0), y = min(F, y0)
            return y > x ? (P[y] - P[x]) / Double(y - x) : 0
        }
        func sec(_ t: Double) -> Double { let f = Int((t * 30).rounded()); return avg(f - 90, f + 90) }   // ~6 s loudness
    }
    private func accentsOf(_ e: [Float]) -> Accents {
        if let a = accents { return a }
        let F = e.count
        var P = [Double](repeating: 0, count: F + 1)
        for i in 0..<F { P[i + 1] = P[i] + Double(e[i]) }
        var a = Accents(list: [], P: P)
        var list: [(t: Double, s: Double, r: Double)] = []
        if F > 18 {
            for f in 12..<(F - 6) {
                let v = Double(e[f])
                var pk = true
                for k in -6...6 where k != 0 && Double(e[f + k]) > v { pk = false; break }
                if !pk { continue }
                if let l = list.last, Double(f) / 30 - l.t < 0.25 { continue }
                var lo = v
                for k in 1...12 { lo = min(lo, Double(e[f - k])) }
                let rise = v - lo, ctx = v - a.avg(f - 60, f - 3)
                if rise >= 0.15 && ctx >= 0.06 { list.append((t: Double(f) / 30, s: rise * 0.6 + ctx * 0.8, r: 0)) }
            }
        }
        let ord = list.indices.sorted { list[$0].s < list[$1].s }
        for (k, i) in ord.enumerated() { list[i].r = list.count > 1 ? Double(k) / Double(list.count - 1) : 1 }
        a.list = list
        accents = a
        return a
    }

    @ObservationIgnored private var spTrack: String?
    @ObservationIgnored private var spWait = 0.0
    @ObservationIgnored private var spTarget: (at: Double, b: Double)?
    @ObservationIgnored private var spLastCt = 0.0
    @ObservationIgnored private var spBusy: CFTimeInterval = 0
    @ObservationIgnored private var spLeadV = 0.7
    @ObservationIgnored private var spLeadAt: CFTimeInterval = 0
    @ObservationIgnored private var spLastEv = -1.0

    private func spDur(_ w: CGFloat) -> Double { max(1.3, min(2.1, 1.15 + Double(w) * 3.4 / 1000)) }   // short titles: a shorter pass
    private func sparkGap(_ ct: Double) -> Double {
        let I = env.map { accentsOf($0).sec(ct) } ?? 0.5
        return (12 + Double.random(in: 0..<1) * 16) * (1.25 - 0.5 * I)
    }
    private func nearEvent(_ t: Double) -> Bool { events.contains { $0.go && abs($0.t - t) < 8 } }
    private func sparkPlan(_ ct: Double, _ now: CFTimeInterval) -> (at: Double, b: Double)? {
        let lead = spLeadV
        var p: (at: Double, b: Double)
        if let e = env {
            let a = accentsOf(e)
            var best: (t: Double, s: Double, r: Double)?
            for x in a.list {
                if x.t < ct + lead + 0.15 { continue }
                if x.t > ct + 6 { break }
                if x.r < 0.35 || nearEvent(x.t) { continue }               // skip the weakest third, and anything next to an energy-change glow
                let sh = 0.5 + 0.45 * sin((now + x.t - ct) / 9.5)            // the cover's reflection streak would be crossing then
                if sh > 0.38 && sh < 0.6 { continue }
                if x.r >= 0.8 { best = x; break }
                if best == nil || x.r > best!.r { best = x }
            }
            if let b = best { p = (b.t - lead, min(1, 0.6 + 0.25 * b.r + 0.25 * a.sec(b.t))) }
            else { p = (ct + 5 + Double.random(in: 0..<1.5), 0.5) }        // no good accent coming: fire anyway, softer
        } else { p = (ct, 0.7) }
        return nearEvent(p.at + lead) ? nil : p
    }
    private func sparkTick(_ playing: Bool, _ dt: Double, _ now: CFTimeInterval) {
        guard playing, let cur = Player.shared.current else { return }
        let ct = Player.shared.preciseTime
        if spTrack != cur.key {                                                       // a "hello" a few seconds into each song
            spTrack = cur.key; spWait = 2.5 + Double.random(in: 0..<2.5); spTarget = nil; spLastEv = -1; spLeadAt = 0
        } else if abs(ct - spLastCt) > 1.2 { spTarget = nil }                         // seek: plan again
        spLastCt = ct
        if now - spLeadAt > 2 { spLeadAt = now; spLeadV = spDur(titleW) * 0.5 }      // brightest halfway through its pass
        for e in events where e.go && e.t != spLastEv {                               // energy-change moments come first
            let at = e.t - spLeadV
            if ct >= at && ct < at + 0.3 {
                spLastEv = e.t; sparkFire(min(1, 0.6 + 0.4 * min(1, (e.s - 4) / 8)), now)
                spTarget = nil; spWait = sparkGap(ct); return
            }
        }
        if now < spBusy { return }
        if let t = spTarget {
            if ct >= t.at { sparkFire(t.b, now); spTarget = nil; spWait = sparkGap(ct) }
            return
        }
        spWait -= dt
        if spWait <= 0 { spTarget = sparkPlan(ct, now); if spTarget == nil { spWait = 4 } }
    }
    private func sparkFire(_ b: Double, _ now: CFTimeInterval) {
        guard titleW >= 12, !UIState.shared.expanded, XPMotion.shared.phase == .compact,
              UIApplication.shared.applicationState == .active else { return }
        let D = spDur(titleW)
        sparkB = b; sparkD = D; sparkN += 1
        spBusy = now + D + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + D * 0.38) { [weak self] in   // the light carries on round Play
            guard let self else { return }
            self.cometB = b; self.cometN += 1
        }
    }

    // MARK: the music's envelope

    private func analyze(_ t: Track) {
        env = nil; events = []; accents = nil; envKey = t.key
        if let c = envCache[t.key] { env = c.0; events = c.1; return }
        guard t.size <= 80_000_000 else { return }
        let key = t.key, url = Library.shared.songsFolder.appendingPathComponent(t.path)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)                  // never competes with the first notes
            guard self.envKey == key else { return }
            let out = await Task.detached(priority: .utility) { () -> ([Float], [GlowMath.Event])? in
                guard let mono = GlowMath.decodeMono(url, sr: 22050) else { return nil }
                let r = GlowMath.envelope(mono, sr: 22050)
                return (r.env, r.events)
            }.value
            guard let out else { return }
            self.envCache[key] = out; self.envOrder.append(key)
            if self.envOrder.count > 24 { self.envCache[self.envOrder.removeFirst()] = nil }
            if self.envKey == key { self.env = out.0; self.events = out.1; self.accents = nil }
        }
    }

    // MARK: cover colours, bloom and light

    private func colours(_ t: Track) {
        artKey = t.path
        let path = t.path
        Task { @MainActor in
            let img = await Covers.shared.image(path: path, px: 300)
            guard self.artKey == path else { return }
            let made = await Task.detached(priority: .userInitiated) { () -> (GlowMath.Palette, UIImage?) in
                guard let img else { return (.neutral, nil) }
                return (GlowMath.palette(img), Glow.makeBloom(img))
            }.value
            guard self.artKey == path else { return }
            let (pal, bl) = made
            self.c1 = pal.c1; self.c2 = pal.c2; self.lk = pal.k; self.lum = pal.lum
            self.bloom = bl
            let k = "\(pal.c1)|\(pal.c2)"
            if k != self.lastLight { self.lastLight = k; self.light = Glow.makeLight(pal.c1, pal.c2) }
        }
    }

    /// The bloom: the artwork 1.5x, saturated 1.6 and blurred (σ ≈ 17 px on 160 px = 280 units), with a soft round fade.
    nonisolated static func makeBloom(_ im: UIImage) -> UIImage? {
        let NB: CGFloat = 160, S = 99 * NB / 280, o = (NB - S) / 2, r = 18 * NB / 280
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let base = UIGraphicsImageRenderer(size: CGSize(width: NB, height: NB), format: fmt).image { _ in
            let side = min(im.size.width, im.size.height)
            let rect = CGRect(x: o, y: o, width: S, height: S)
            UIBezierPath(roundedRect: rect, cornerRadius: r).addClip()
            let k = S / side
            im.draw(in: CGRect(x: o - (im.size.width - side) / 2 * k, y: o - (im.size.height - side) / 2 * k, width: im.size.width * k, height: im.size.height * k))
        }
        guard let cg = base.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        let sat = CIFilter(name: "CIColorControls")!
        sat.setValue(ci, forKey: kCIInputImageKey); sat.setValue(1.6, forKey: kCIInputSaturationKey)
        let bl = CIFilter(name: "CIGaussianBlur")!
        bl.setValue(sat.outputImage, forKey: kCIInputImageKey); bl.setValue(17.5, forKey: kCIInputRadiusKey)
        guard let out = bl.outputImage, let blurred = ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: NB, height: NB)) else { return nil }
        return fade(blurred, NB)
    }

    /// The light: a two-colour wedge in a 110-unit circle on a 180-unit canvas (128 px), blurred 15 units.
    nonisolated static func makeLight(_ a: RGB, _ b: RGB) -> UIImage? {
        let N = 128, u = Double(N) / 180, R0 = 55 * u, c = Double(N) / 2
        let stops: [(Double, RGB, Double)] = [(0, a, 0), (50, a, 0.9), (135, a, 0), (190, b, 0), (245, b, 0.55), (320, b, 0), (360, b, 0)]
        var px = [UInt8](repeating: 0, count: N * N * 4)
        for y in 0..<N { for x in 0..<N {
            let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c, rr = hypot(dx, dy)
            if rr > R0 + 0.5 { continue }
            let edge = min(1, R0 + 0.5 - rr)
            var ang = atan2(dx, -dy) * 180 / .pi; if ang < 0 { ang += 360 }
            var k = 0; while k < stops.count - 2 && ang > stops[k + 1].0 { k += 1 }
            let (a0, C0, al0) = stops[k], (a1, C1, al1) = stops[k + 1], t = (ang - a0) / (a1 - a0)
            let al = (al0 + (al1 - al0) * t) * edge, i = (y * N + x) * 4
            px[i] = UInt8(max(0, min(255, (C0.r + (C1.r - C0.r) * t) * al)))
            px[i + 1] = UInt8(max(0, min(255, (C0.g + (C1.g - C0.g) * t) * al)))
            px[i + 2] = UInt8(max(0, min(255, (C0.b + (C1.b - C0.b) * t) * al)))
            px[i + 3] = UInt8(max(0, min(255, al * 255)))
        } }
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: N, height: N, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: N * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let bl = CIFilter(name: "CIGaussianBlur")!
        bl.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey); bl.setValue(11.5, forKey: kCIInputRadiusKey)
        guard let out = bl.outputImage, let img = ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: N, height: N)) else { return nil }
        return UIImage(cgImage: img)
    }

    /// A soft round fade (web: edgeFade): full to 82 % of the radius, then a smoothstep to nothing at the edge.
    nonisolated private static func fade(_ cg: CGImage, _ n: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: fmt).image { ctx in
            UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: n, height: n))
            let g = ctx.cgContext
            g.setBlendMode(.destinationIn)
            var cols: [CGColor] = [], locs: [CGFloat] = []
            for i in 0...10 {
                let t = Double(i) / 10, k = t < 0.82 ? 1 : 1 - (t - 0.82) / 0.18
                cols.append(UIColor(white: 0, alpha: k * k * (3 - 2 * k)).cgColor); locs.append(t)
            }
            if let gr = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: locs) {
                g.drawRadialGradient(gr, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: n / 2, options: [])
            }
        }
    }

    nonisolated private static let ciContext = CIContext(options: [.cacheIntermediates: false])
}

final class LinkProxy: NSObject {
    let cb: @MainActor (CADisplayLink) -> Void
    init(_ cb: @escaping @MainActor (CADisplayLink) -> Void) { self.cb = cb }
    @objc func fire(_ l: CADisplayLink) { MainActor.assumeIsolated { cb(l) } }
}

/// The maths, exactly as the web player does it.
enum GlowMath {
    struct Event { var t: Double; var s: Double; var go: Bool }
    struct Palette { var c1: Glow.RGB; var c2: Glow.RGB; var k: Double; var lum: Double
        static let neutral = Palette(c1: .neutral, c2: .neutral, k: 0.55, lum: 0.5) }

    /// The song decoded to mono at `sr` (web: OfflineAudioContext(1, 1, 22050)).
    nonisolated static func decodeMono(_ src: URL, sr: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: src) else { return nil }
        let inFmt = file.processingFormat
        guard inFmt.channelCount > 0,
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: 32768),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: 32768) else { return nil }
        if Double(file.length) / inFmt.sampleRate > 1200 { return nil }
        var a = [Float](); a.reserveCapacity(Int(Double(file.length) * sr / inFmt.sampleRate) + 8192)
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
            if st == .error { return nil }
            let n = Int(outBuf.frameLength)
            if n > 0, let ch = outBuf.floatChannelData { a.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n)) }
            if st == .endOfStream || (eof && n == 0) { break }
        }
        return a.count > Int(sr) ? a : nil
    }

    /// 30 values a second, 0…1: 55 % bass (<150 Hz) + 45 % full level, each normalised between its 5th and 97th
    /// percentile, smoothed over ~170 ms. Also returns the energy-change moments (bandEvents).
    nonisolated static func envelope(_ x: [Float], sr: Double) -> (env: [Float], events: [Event]) {
        let N = x.count, hop = Int((sr / 30).rounded()), F = N / hop
        guard F > 8 else { return ([], []) }
        var full = [Float](repeating: 0, count: F), bass = full, lo = full, mi = full, hi = full
        let al = 1 - exp(-2 * Double.pi * 150 / sr)
        func bq(_ hp: Bool, _ f0: Double) -> [Double] {
            let w = 2 * Double.pi * f0 / sr, c = cos(w), a = sin(w) / 2.0.squareRoot(), a0 = 1 + a, k = hp ? (1 + c) / 2 : (1 - c) / 2
            return [k / a0, (hp ? -2 : 2) * k / a0, k / a0, -2 * c / a0, (1 - a) / a0]
        }
        let P = bq(true, 150), Q = bq(false, 4000), R = bq(true, 4000)
        var lp = 0.0
        var px1 = 0.0, px2 = 0.0, py1 = 0.0, py2 = 0.0, qx1 = 0.0, qx2 = 0.0, qy1 = 0.0, qy2 = 0.0, rx1 = 0.0, rx2 = 0.0, ry1 = 0.0, ry2 = 0.0
        func dB(_ ms: Double) -> Float { Float(max(-80, 10 * log10(ms + 1e-12))) }
        x.withUnsafeBufferPointer { s in
            for f in 0..<F {
                var sf = 0.0, sb = 0.0, sm = 0.0, sh = 0.0
                for i in (f * hop)..<(f * hop + hop) {
                    let v = Double(s[i])
                    lp += al * (v - lp); sf += v * v; sb += lp * lp
                    let y = P[0] * v + P[1] * px1 + P[2] * px2 - P[3] * py1 - P[4] * py2; px2 = px1; px1 = v; py2 = py1; py1 = y
                    let z = Q[0] * y + Q[1] * qx1 + Q[2] * qx2 - Q[3] * qy1 - Q[4] * qy2; qx2 = qx1; qx1 = y; qy2 = qy1; qy1 = z; sm += z * z
                    let h = R[0] * v + R[1] * rx1 + R[2] * rx2 - R[3] * ry1 - R[4] * ry2; rx2 = rx1; rx1 = v; ry2 = ry1; ry1 = h; sh += h * h
                }
                let n = Double(hop)
                full[f] = Float((sf / n).squareRoot()); bass[f] = Float((sb / n).squareRoot())
                lo[f] = dB(sb / n); mi[f] = dB(sm / n); hi[f] = dB(sh / n)
            }
        }
        func nz(_ a: [Float]) -> [Float] {
            let t = a.sorted(), l = t[Int(Double(F) * 0.05)], h = t[min(F - 1, Int(Double(F) * 0.97))], d = (h - l) == 0 ? 1 : h - l
            return a.map { max(0, min(1, ($0 - l) / d)) }
        }
        let b = nz(bass), fl = nz(full)
        var m = [Float](repeating: 0, count: F)
        for f in 0..<F { m[f] = 0.55 * b[f] + 0.45 * fl[f] }
        var out = [Float](repeating: 0, count: F)
        for f in 0..<F {
            var s: Float = 0, n: Float = 0
            for k in -3...3 where f + k >= 0 && f + k < F { s += m[f + k]; n += 1 }
            out[f] = s / n
        }
        return (out, bandEvents(lo, mi, hi))
    }

    /// Where the music suddenly has more going on than in the last 4 s (each band in dB, next 0.7 s vs the 60th percentile).
    nonisolated static func bandEvents(_ L: [Float], _ M: [Float], _ H: [Float]) -> [Event] {
        let F = L.count, A = 21, BW = 120, bands = [L, M, H], W: [Float] = [0.2, 0.3, 0.5]
        guard F > BW + A + 1 else { return [] }
        let P: [[Double]] = bands.map { v in var p = [Double](repeating: 0, count: F + 1); for i in 0..<F { p[i + 1] = p[i] + Double(v[i]) }; return p }
        var base = [[Float]](repeating: [Float](repeating: 0, count: F), count: 3)
        var sc = [Float](repeating: 0, count: F)
        for f in BW..<(F - A) {
            var s: Float = 0
            for bi in 0..<3 {
                if (f - BW) % 3 == 0 { let tmp = bands[bi][(f - BW)..<f].sorted(); base[bi][f] = tmp[Int(Double(BW) * 0.6)] }
                else { base[bi][f] = base[bi][f - 1] }
                let d = Float((P[bi][f + A] - P[bi][f]) / Double(A)) - base[bi][f]
                if d > 0 { s += W[bi] * d }
            }
            sc[f] = s
        }
        var ev: [Event] = []
        for f in BW..<(F - A) {
            let s = sc[f]; if s < 4 { continue }
            var pk = true
            for k in max(0, f - 60)...min(F - 1, f + 60) where sc[k] > s || (sc[k] == s && k < f) { pk = false; break }
            if !pk { continue }
            var best = f, bz: Float = -1e9
            for g in max(1, f - 6)...min(F - 2, f + 30) {
                var z: Float = 0
                for bi in 0..<3 { z += W[bi] * ((bands[bi][g - 1] + bands[bi][g] + bands[bi][g + 1]) / 3 - base[bi][f]) }
                if z > bz { bz = z; best = g }
            }
            let sd = Double(s)
            ev.append(Event(t: Double(best) / 30, s: (sd * 10).rounded() / 10, go: sd >= 10 || Double.random(in: 0..<1) < 0.25 + 0.6 * (sd - 4) / 6))
        }
        return ev
    }

    // MARK: cover colours (web: hue buckets, scored for how good they look as a glow, then corrected)

    nonisolated static func palette(_ im: UIImage) -> Palette {
        let n = 24
        guard let cg = im.cgImage, let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return .neutral }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let raw = ctx.data else { return .neutral }
        let d = Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self), count: n * n * 4))
        return score(d)
    }

    nonisolated static func toHsl(_ r0: Double, _ g0: Double, _ b0: Double) -> (Double, Double, Double) {
        let r = r0 / 255, g = g0 / 255, b = b0 / 255, mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        var h = 0.0, s = 0.0
        if d != 0 {
            s = d / (1 - abs(2 * l - 1))
            h = mx == r ? (g - b) / d + (g < b ? 6 : 0) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
            h *= 60
        }
        return (h, s, l)
    }
    nonisolated static func toRgb(_ h: Double, _ s: Double, _ l: Double) -> Glow.RGB {
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let v: (Double, Double, Double) = h < 60 ? (c, x, 0) : h < 120 ? (x, c, 0) : h < 180 ? (0, c, x) : h < 240 ? (0, x, c) : h < 300 ? (x, 0, c) : (c, 0, x)
        return Glow.RGB(r: ((v.0 + m) * 255).rounded(), g: ((v.1 + m) * 255).rounded(), b: ((v.2 + m) * 255).rounded())
    }
    nonisolated static func score(_ d: [UInt8]) -> Palette {
        struct Bk { var n = 0.0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var B = [Bk](repeating: Bk(), count: 12)
        var tot = 0.0, lsum = 0.0
        for i in stride(from: 0, to: d.count, by: 4) {
            let r = Double(d[i]), g = Double(d[i + 1]), b = Double(d[i + 2])
            let (h, s, l) = toHsl(r, g, b); tot += 1; lsum += l
            if s < 0.2 || l < 0.12 || l > 0.92 { continue }
            let k = Int(h / 30) % 12
            B[k].n += 1; B[k].r += r; B[k].g += g; B[k].b += b
        }
        let lum = tot > 0 ? lsum / tot : 0.5
        func hd(_ a: Double, _ b: Double) -> Double { let x = abs(a - b).truncatingRemainder(dividingBy: 360); return x > 180 ? 360 - x : x }
        struct C { var h: Double; var s: Double; var l: Double; var sc: Double }
        let cs: [C] = B.filter { $0.n > tot * 0.03 }.map { o in
            let (h, s, l) = toHsl(o.r / o.n, o.g / o.n, o.b / o.n)
            var sc = pow(o.n / tot, 0.6) * min(1, s / 0.55) * max(0.2, 1 - abs(l - 0.55) * 1.5)
            if h > 25 && h < 75 && s < 0.45 { sc *= 0.5 }          // muddy brown / olive
            if h > 165 && h < 205 { sc *= 0.7 }                    // would vanish against the teal UI
            return C(h: h, s: s, l: l, sc: sc)
        }.sorted { $0.sc > $1.sc }
        guard let a = cs.first, a.sc >= 0.06 else { return Palette(c1: .neutral, c2: .neutral, k: 0.55, lum: lum) }
        let b = cs.dropFirst().first { hd($0.h, a.h) >= 40 && $0.sc > a.sc * 0.35 } ?? C(h: (a.h + 28).truncatingRemainder(dividingBy: 360), s: a.s, l: a.l, sc: 0)
        func fix(_ x: C) -> Glow.RGB { toRgb(x.h, min(0.85, max(0.55, x.s)), min(0.68, max(0.55, x.l))) }
        return Palette(c1: fix(a), c2: fix(b), k: 1, lum: lum)
    }
}

// MARK: views

/// Behind the cover: the bloom (the artwork, enlarged and blurred) and the coloured light circling round it.
struct CoverGlowBack: View {
    var size: CGFloat
    private var g: Glow { .shared }
    var body: some View {
        let k = size / 66
        ZStack {
            if let b = g.bloom {
                Image(uiImage: b).resizable().interpolation(.medium)
                    .frame(width: 280 * k, height: 280 * k)
                    .scaleEffect(1 + g.pulse * 0.08 + g.br * 0.0333 + g.flare * 0.1467)
                    .opacity(0.32 + g.energy * 0.06 + g.pulse * 0.22 + g.br * 0.06 + g.flare * 0.22)
                    .offset(x: g.tx * 12 * k, y: g.ty * 12 * k)                 // web: translate(--tx × 12px × --k)
                    .transition(.opacity.animation(Theme.easeN.slowed))
            }
            if let l = g.light {
                Image(uiImage: l).resizable().interpolation(.medium)
                    .frame(width: 180 * k, height: 180 * k)
                    .rotationEffect(.degrees(g.rimA))
                    .scaleEffect(1 + g.flare * 0.18)
                    .opacity((0.24 + g.energy * 0.26 + g.pulse * 0.22 + g.br * 0.05 + g.flare * 0.45) * g.lk)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)                 // decoration: not for VoiceOver, never in the way of a touch
    }
}

/// The cover's glass, on top of the artwork (web: .g-refr, .g-shade, .g-spec, .g-streak, .g-glow, .g-rim). One light
/// direction drives the hotspot, the edge glow and the rim; it orbits on its own, a little livelier with the music.
struct CoverGlass: View {
    var path: String?
    var size: CGFloat
    var radius: CGFloat
    /// Width of the fine details in pt per web px (web --u): the small cover's own scale, 1.6 on the open big cover.
    var u: CGFloat? = nil
    private var g: Glow { .shared }
    var body: some View {
        let u = self.u ?? size / 66, s = g.glassT
        let la = g.rimA + 50 + g.tx * 40 - g.ty * 12, th = la * .pi / 180, rr = 30 + 6 * sin(s / 7.3)
        // moving the phone shifts the light, as if you moved while looking at the glass (web: tilt terms)
        let gx = (50 + rr * sin(th) - g.tx * 12) / 100, gy = (50 - rr * cos(th) - g.ty * 12) / 100
        let gi = min(1, 0.5 + g.energy * 0.12 + g.pulse * 0.14 + g.tilt * 0.35 + 0.06 * sin(s / 3.1))
        let sh = max(0, min(1, 0.5 + 0.45 * sin(s / 9.5) + g.tx * 0.4))
        let rx = (1.1 * sin(s / 8.7) + g.tx * 2.6) * u, ry = (1.1 * cos(s / 11.3) + g.ty * 2.6) * u
        let gl = 1.25 - 0.6 * g.lum
        let c1 = g.c1.color, c2 = g.c2.color
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            // edge refraction: a thin band where the artwork looks magnified through the glass edge
            if let path {
                CoverImage(path: path, px: Int(size * 3), placeholder: AnyView(Color.clear))
                    .frame(width: size * 1.07, height: size * 1.07)
                    .offset(x: rx, y: ry)
                    .saturation(1.35).brightness(0.07).blur(radius: 0.4 * u)
                    .frame(width: size, height: size)
                    .mask(EdgeBand(w: 4 * u, size: size))
                    .opacity(0.42)
            }
            // thickness: the lower edge in a little shadow, the upper edge catching a little light
            LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0), .init(color: .white.opacity(0), location: 7 * u / size),
                                   .init(color: .black.opacity(0), location: 1 - 9 * u / size), .init(color: .black.opacity(0.2), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // surface: a hotspot on the side the light comes from + a faint sky reflection at the top
            RadialGradient(stops: [.init(color: .white.opacity(0.19 * gl * (1 + 0.7 * g.tilt)), location: 0), .init(color: .white.opacity(0.06 * gl), location: 0.34),
                                   .init(color: .white.opacity(0), location: 0.7)],
                           center: UnitPoint(x: gx, y: gy), startRadius: 0, endRadius: size * 0.62)
            LinearGradient(stops: [.init(color: .white.opacity(0.08), location: 0), .init(color: .white.opacity(0.02), location: 0.38), .init(color: .white.opacity(0), location: 0.52)],
                           startPoint: UnitPoint(x: 0.377, y: -0.080), endPoint: UnitPoint(x: 0.623, y: 1.080))
            // a long reflection that glides across now and then
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.40), .init(color: .white.opacity(0.13 * gl * (1 + g.tilt)), location: 0.47),
                                   .init(color: .white.opacity(0.03), location: 0.50), .init(color: .white.opacity(0.07 * gl), location: 0.53),
                                   .init(color: .white.opacity(0), location: 0.57)],
                           startPoint: UnitPoint(x: 0.0123, y: -0.092), endPoint: UnitPoint(x: 0.9877, y: 1.092))
                .frame(width: size * 3, height: size)
                .offset(x: size - 2 * size * sh)
                .frame(width: size, height: size)
                .blendMode(.screen)
            // soft inner glow along the edge, brightest where the light hits, tinted with the artwork's colours
            AngularGradient(stops: [
                .init(color: .white.opacity(0.16 + 0.3 * gi), location: 0), .init(color: c1.opacity(0.1 + 0.22 * gi), location: 40 / 360),
                .init(color: .white.opacity(0), location: 95 / 360), .init(color: .white.opacity(0), location: 150 / 360),
                .init(color: c2.opacity(0.05 + 0.15 * gi), location: 0.5), .init(color: .white.opacity(0), location: 210 / 360),
                .init(color: .white.opacity(0), location: 265 / 360), .init(color: c1.opacity(0.1 + 0.22 * gi), location: 320 / 360),
                .init(color: .white.opacity(0.16 + 0.3 * gi), location: 1)],
                center: .center, startAngle: .degrees(la - 90), endAngle: .degrees(la + 270))
                .mask(EdgeBand(w: 7 * u, size: size))
            // the crisp rim: catches the light on one side and a weaker bounce on the other
            shape.strokeBorder(AngularGradient(stops: [
                .init(color: .white.opacity(0.5 + 0.45 * gi), location: 0), .init(color: c1.opacity(0.3 + 0.3 * gi), location: 32 / 360),
                .init(color: .white.opacity(0.18), location: 80 / 360), .init(color: .white.opacity(0.13), location: 145 / 360),
                .init(color: c2.opacity(0.18 + 0.3 * gi), location: 0.5), .init(color: .white.opacity(0.13), location: 215 / 360),
                .init(color: .white.opacity(0.18), location: 280 / 360), .init(color: c1.opacity(0.3 + 0.3 * gi), location: 328 / 360),
                .init(color: .white.opacity(0.5 + 0.45 * gi), location: 1)],
                center: .center, startAngle: .degrees(la - 90), endAngle: .degrees(la + 270)), lineWidth: max(1, u))
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // the glass layers change 30 times a second; drawn as one picture on the graphics chip, not by the CPU
        // (the profiler found the circular rim gradients being shaded on the CPU every frame)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)                 // decoration: not for VoiceOver, never in the way of a touch
    }
}

/// A band along all four edges, `w` wide, fading inwards (web: two linear-gradient masks).
struct EdgeBand: View {
    var w: CGFloat
    var size: CGFloat
    var body: some View {
        let e = min(0.5, w / max(size, 1))
        ZStack {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: e), .init(color: .clear, location: 1 - e), .init(color: .black, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: e), .init(color: .clear, location: 1 - e), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The controls breathe with the music: Play leads, the sides follow ~0.1 s later; a glow ring tinted with the cover's
/// colour fades in with it (web: --bp, .player-btn::after).
struct Breath: ViewModifier {
    var index: Int
    var amount: CGFloat
    @State private var side: CGFloat = 0
    private var g: Glow { .shared }
    func body(content: Content) -> some View {
        let v = g.bp[index]
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if abs($0 - side) > 0.5 { side = $0 } }
            .background {
                // the glow is a picture drawn once per size and cover colour, then only faded: redrawing its blurs
                // and cut-out every frame was the player's biggest cost while a song plays
                if side > 0, let im = BreathArt.image(side: side, color: g.c1) {
                    Image(uiImage: im).resizable()
                        .frame(width: side + 2 + 2 * BreathArt.pad, height: side + 2 + 2 * BreathArt.pad)
                        .opacity(v)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(1 + v * amount)
    }
}

/// The breathing glow round Prev / Play / Next, drawn once (web: box-shadow 0 0 15px in the cover's colour outside the
/// rim, a faint rim, a soft inner light).
@MainActor
enum BreathArt {
    static let pad: CGFloat = 30
    private static var cache: [String: UIImage] = [:]
    static func image(side: CGFloat, color: Glow.RGB) -> UIImage? {
        let key = "\(Int(side.rounded()))|\(Int(color.r)),\(Int(color.g)),\(Int(color.b))"
        if let im = cache[key] { return im }
        let d = side + 2
        let art = ZStack {
            Circle().fill(color.color.opacity(0.42)).blur(radius: 7.5)
                .mask { ZStack { Rectangle().padding(-pad); Circle().blendMode(.destinationOut) }.compositingGroup() }
            Circle().strokeBorder(Color.w(0.26), lineWidth: 1)
            Circle().stroke(Color.w(0.2), lineWidth: 3).blur(radius: 3).clipShape(Circle())
        }
        .frame(width: d, height: d)
        .padding(pad)
        let r = ImageRenderer(content: art)
        r.scale = 3
        guard let im = r.uiImage else { return nil }
        if cache.count > 30 { cache.removeAll() }
        cache[key] = im
        return im
    }
}

/// The panel's soft tint behind the cover, in the cover's colour (web: .player-wrapper::after). None for a muted cover.
struct PanelTint: View {
    private var g: Glow { .shared }
    var body: some View {
        let a = max(0, g.lk - 0.55) * 0.38
        EllipticalGradient(stops: [.init(color: g.c1.color.opacity(a), location: 0), .init(color: g.c1.color.opacity(0), location: 0.7)],
                           center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: 480, height: 380)
            .offset(x: 80 - 240, y: 70 - 190)
            .anim(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9), value: g.c1)
            .anim(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9), value: a)
            .allowsHitTesting(false)
        .accessibilityHidden(true)                 // decoration: not for VoiceOver, never in the way of a touch
    }
}

/// Knows when a finger is on the screen (and for a moment after it lifts, while a list may still be gliding), without
/// taking part in any touch: a recognizer on the window that never claims anything.
@MainActor
final class TouchWatch: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static var down = 0
    private static var calmAt: CFTimeInterval = 0
    private static var installed = false

    /// Where the last finger came down, in screen points (SwiftUI's .global space).
    static var lastDown: CGPoint?

    static func held(_ now: CFTimeInterval) -> Bool { down > 0 || now < calmAt }

    static func install() {
        guard !installed else { return }
        guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { install() }
            return
        }
        installed = true
        let r = TouchWatch(target: nil, action: nil)
        r.cancelsTouchesInView = false
        r.delaysTouchesBegan = false
        r.delaysTouchesEnded = false
        r.delegate = r
        w.addGestureRecognizer(r)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        TouchWatch.down += touches.count
        if let t = touches.first, let v = view { TouchWatch.lastDown = t.location(in: v) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { lift(touches) }
    private func lift(_ touches: Set<UITouch>) {
        TouchWatch.down = max(0, TouchWatch.down - touches.count)
        TouchWatch.calmAt = CACurrentMediaTime() + 0.7         // web: 450 ms after the finger lifts, 250 ms after a scroll
        if TouchWatch.down == 0 { state = .failed }
    }
    override func reset() { TouchWatch.down = 0 }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy o: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf o: UIGestureRecognizer) -> Bool { false }
}
