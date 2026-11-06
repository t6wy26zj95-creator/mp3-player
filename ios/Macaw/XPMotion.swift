import SwiftUI

/// The big player's open / close motion, ported from the web player (XP.render in index.html).
/// One number p (0 = compact, 1 = big) drives everything. Both layouts exist while it moves; every moving thing has a
/// copy in each, and only one copy is seen: the big copy takes over in place and carries the motion.
/// - The cover grows a little behind the rest: grow(p) = p²(1.6 − 0.6p).
/// - The title and artist line circle round the growing cover (orbit): from beside it, round its corner, to under it.
/// - The buttons, the bar and the times follow the cover's bottom edge: they drop to their row first, then slide across.
/// - The panel's height follows the Play button; Up next, the handle, shuffle / repeat fade in towards the end.
/// p glides over 0.4 s on the app's curve (.22, 1, .36, 1), exactly like the web's animateTo.
@MainActor @Observable
final class XPMotion {
    static let shared = XPMotion()
    /// iOS: a critically damped spring instead of the web's 0.4 s curve. That curve (.22, 1, .36, 1) covers about a sixth
    /// of the way in its first frame, so on the phone the motion read as a jump and then a long crawl; a spring starts
    /// from rest (or from the finger's speed) and eases out without the crawl.
    static var curve: Animation { Theme.ease }
    enum Phase { case compact, measuring, moving, big }

    var phase: Phase = .compact
    var p: Double = 0
    /// Where each moving thing sits in the compact layout ("c.…") and in the big one ("b.…"), in the panel's space.
    /// Only taken while that layout is at rest and untouched by the motion.
    @ObservationIgnored var c: [String: CGRect] = [:]
    @ObservationIgnored var b: [String: CGRect] = [:]
    /// The first line of the big title / artist line when it wraps (its width and height): centred text, so the morph
    /// carries that line, not the block's corner, onto the small one-line copy (else the name jumps at the hand-over).
    @ObservationIgnored var line1: [String: CGSize] = [:]

    /// greedy word wrap, as Text lays it out: the first line's width and how many lines
    nonisolated static func firstLine(_ s: String, font: UIFont, width: CGFloat) -> (w: CGFloat, lines: Int) {
        func w(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: [.font: font]).width }
        guard width > 20 else { return (w(s), 1) }
        var lines = 0, first: CGFloat = 0
        for para in s.components(separatedBy: "\n") {
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let t = cur.isEmpty ? word : cur + " " + word
                if cur.isEmpty || w(t) <= width { cur = t } else {
                    if lines == 0 { first = w(cur) }
                    lines += 1; cur = word
                }
            }
            if lines == 0 { first = min(width, w(cur)) }
            lines += 1
        }
        return (first, lines)
    }

    private var ui: UIState { .shared }

    func report(_ tag: String, _ r: CGRect) {
        if tag.hasPrefix("c.") {
            if phase == .compact || (phase == .measuring && tag != "c.stack") { c[tag] = r }
        } else if phase == .measuring || (phase == .big && ui.lyricsScroll == 0 && !ui.lyricsOpen) { b[tag] = r }
    }

    func open() {
        if phase == .moving && !ui.expanded {                       // tapped again while it folds: it turns round
            withAnimation(Self.curve) { p = 1; ui.expanded = true } completion: {
                if self.p == 1 && self.phase == .moving { self.phase = .big }
            }
            return
        }
        guard phase == .compact, Player.shared.current != nil else { return }
        if ui.tab != nil {                                          // a section is open: close it first, then unfold
            withAnimation(Theme.ease) { ui.tab = nil }
            Task { @MainActor in try? await Task.sleep(nanoseconds: 420_000_000); self.open() }
            return
        }
        Haptics.light()
        p = 0
        b["b.art"] = nil; b["b.stack"] = nil
        phase = .measuring                                          // the big layout is laid out (unseen) and measured first
        withAnimation(Theme.ease) { ui.expanded = true }
        Task { @MainActor in
            await self.measured()
            guard self.phase == .measuring else { return }
            self.phase = .moving
            withAnimation(Self.curve) { self.p = 1 } completion: {
                if self.p == 1 && self.phase == .moving { self.phase = .big }
            }
        }
    }

    /// Waits only until the big layout has been laid out and measured (usually the very next frame), instead of a
    /// fixed pause: the motion starts as soon as it can (at most ~100 ms on a slow first build).
    private func measured() async {
        for _ in 0..<14 {
            try? await Task.sleep(nanoseconds: 7_000_000)
            if b["b.art"] != nil && b["b.stack"] != nil {
                try? await Task.sleep(nanoseconds: 8_000_000)   // one more frame, so it has been drawn once
                return
            }
        }
    }

    // MARK: pulled by the finger (web: the expand gesture, begin / pointermove / gEnd)

    var dragging = false
    @ObservationIgnored private var dragFrom: Double = 0
    @ObservationIgnored private var pendingP: Double?

    /// how far the finger travels for the whole motion: the panel's growth, at least 200 pt
    private var travel: Double {
        let h0 = c["c.stack"]?.height ?? 0, h1 = b["b.stack"]?.height ?? 0
        return h1 > 0 ? Double(max(200, h1 - h0)) : 420
    }

    /// A pull starts: from the compact row (down) or from the big cover / handle (up). false: it isn't one.
    func dragBegin() -> Bool {
        if phase == .big {
            guard !ui.lyricsOpen, ui.lyricsScroll < 0.5 else { return false }
            dragging = true; dragFrom = 1; phase = .moving
            return true
        }
        guard phase == .compact, Player.shared.current != nil else { return false }
        if ui.tab != nil { open(); return false }                   // a section is open: it folds away and the player unfolds
        dragging = true; dragFrom = 0; pendingP = nil
        p = 0
        b["b.art"] = nil; b["b.stack"] = nil
        phase = .measuring
        withAnimation(Theme.ease) { ui.expanded = true }
        Task { @MainActor in
            await self.measured()
            guard self.phase == .measuring else { return }
            self.phase = .moving
            if let q = self.pendingP { self.p = q }
        }
        return true
    }

    /// dy: how far the finger has gone since the pull started. Clamped to the two layouts.
    func dragTo(_ dy: Double) {
        guard dragging else { return }
        let q = min(1, max(0, dragFrom + dy / travel))
        if phase == .moving {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { p = q }
        } else { pendingP = q }
    }

    /// The finger lets go (vy: its speed, pt / s): a short quick flick is enough, a slow drag must go about a third of the way.
    func dragEnd(_ vy: Double) {
        guard dragging else { return }
        dragging = false
        let v = vy / travel
        let go = {
            let proj = self.p + max(-0.6, min(0.6, v * 0.16))
            let t: Double = self.dragFrom < 0.5 ? (proj > 0.3 ? 1 : 0) : (proj < 0.72 ? 0 : 1)
            if t != self.dragFrom { Haptics.light() }
            self.settle(to: t, v: v)
        }
        if phase == .measuring {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                if self.phase == .measuring { self.phase = .moving }
                if let q = self.pendingP { self.p = q }
                go()
            }
        } else { go() }
    }

    /// web animateTo: 0.4 s for the whole way (less for part of it) on the app's curve; a fast flick shortens it
    private func settle(to t: Double, v: Double) {
        // carries on at the finger's speed (as a share of the way left per second), so letting go never jolts
        let d = t - p, base = 0.4 * (0.6 + 0.4 * abs(d))
        let rel = abs(d) > 0.001 ? max(0, min(10, v / d)) : 0
        withAnimation(.interpolatingSpring(duration: base, bounce: 0, initialVelocity: rel)) {
            p = t
            ui.expanded = t == 1
            if t == 0 { ui.lyricsScroll = 0 }
        } completion: {
            guard self.p == t, self.phase == .moving, !self.dragging else { return }
            self.phase = t == 1 ? .big : .compact
        }
    }

    func close(then: (() -> Void)? = nil) {
        guard phase == .big || phase == .moving || phase == .measuring else { ui.expanded = false; then?(); return }
        if ui.lyricsOpen || ui.lyricsScroll > 0.5 {                  // lyrics open, or scrolled down: back to the player first
            withAnimation(Theme.ease) { ui.lyricsOpen = false; ui.lyricsScroll = 0 }
            Task { @MainActor in try? await Task.sleep(nanoseconds: 420_000_000); self.close(then: then) }
            return
        }
        Haptics.light()
        if phase == .measuring { phase = .compact; ui.expanded = false; then?(); return }
        phase = .moving
        withAnimation(Self.curve) { p = 0; ui.expanded = false; ui.lyricsScroll = 0 } completion: {
            if self.p == 0 && self.phase == .moving { self.phase = .compact; then?() }
        }
    }
}

// MARK: poses

struct XPPose: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1
    var anchor: UnitPoint = .center
    var opacity: Double = 1
    var width: CGFloat?
}

struct XPPoses: Equatable {
    var map: [String: XPPose] = [:]
    var height: CGFloat?
    var compactOn = true          // the whole compact layer
    var bigOn = false             // the whole big layer (hidden while it is measured)
    var p: Double = 0
    var artRadius: CGFloat?       // the big cover's corner while it grows (in its own size)
    var titleReveal: CGFloat?     // a cut-short title: how much of the big one (from its start, big px) has written itself in
    var artGrow: Double?          // how far the big cover has grown, 0 (on the small one) … 1 (open)
    var artScale: Double?         // its current scale (its own px → screen px)
    var extra: Double = 1         // album · year write themselves in
    var chev: Double = 0          // the small artist line's " ›", riding along
    var moving = false
    var measuring = false         // the big layer is being laid out unseen (drawn at 0.1 % so it's ready on the first frame)
    subscript(_ k: String) -> XPPose { map[k] ?? XPPose() }
}

private struct XPPosesKey: EnvironmentKey { static let defaultValue = XPPoses() }
extension EnvironmentValues {
    var xpPoses: XPPoses {
        get { self[XPPosesKey.self] }
        set { self[XPPosesKey.self] = newValue }
    }
}

/// Feeds the poses for the current p down to the tagged views. Animatable, so it runs every frame of the glide.
struct XPDriver: ViewModifier, Animatable {
    var p: Double
    var phase: XPMotion.Phase
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let poses = XPLayout.compute(p: p, phase: phase)
        content
            .environment(\.xpPoses, poses)
            .frame(height: poses.height, alignment: .top)
    }
}

extension View {
    /// A moving part of the compact ("c.…") or big ("b.…") layout: measured at rest, posed while it moves.
    func xp(_ tag: String) -> some View { modifier(XPTag(tag: tag)) }
}

struct XPTag: ViewModifier {
    var tag: String
    @Environment(\.xpPoses) private var poses
    func body(content: Content) -> some View {
        let p = poses[tag]
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("xp")) } action: { XPMotion.shared.report(tag, $0) }
            .frame(width: p.width)
            .scaleEffect(p.scale, anchor: p.anchor)
            .offset(x: p.dx, y: p.dy)
            .opacity(p.opacity)
    }
}

// MARK: the web's render(p)

enum XPLayout {
    static func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lin(_ p: Double, _ a: Double, _ b: Double) -> Double { clamp01((p - a) / (b - a)) }
    static func fade(_ p: Double, _ a: Double, _ b: Double) -> Double { let t = lin(p, a, b); return t * t * (3 - 2 * t) }
    static func grow(_ p: Double) -> Double { p * p * (1.6 - 0.6 * p) }
    /// distance from a rounded square's centre to its edge at angle a (the path hugs the cover in a smooth curve)
    static func edge(_ a: Double, _ half: Double) -> Double { half / pow(pow(abs(cos(a)), 4) + pow(abs(sin(a)), 4), 0.25) }

    @MainActor
    static func compute(p rawP: Double, phase: XPMotion.Phase) -> XPPoses {
        var out = XPPoses()
        switch phase {
        case .compact: return out
        case .measuring:
            out.bigOn = false; out.measuring = true
            out.height = XPMotion.shared.c["c.stack"]?.height
            return out
        case .big:
            out.compactOn = false; out.bigOn = true; out.p = 1
            out.map = ["b.lyr": XPPose()]
            return out
        case .moving: break
        }
        let m = XPMotion.shared, c = m.c, b = m.b
        guard let ca = c["c.art"], let ba = b["b.art"], let cs = c["c.stack"], let bs = b["b.stack"] else {
            out.compactOn = rawP < 0.5; out.bigOn = rawP >= 0.5; return out
        }
        out.bigOn = true; out.moving = true
        let P = clamp01(rawP)
        out.p = P
        var map: [String: XPPose] = [:]

        // the cover: the big one, scaled down onto the small one at p = 0, grows a little behind the rest
        let G = grow(P), S = Double(ba.width), aw = Double(ca.width)
        let size = lerp(aw, S, G), curX = lerp(ca.minX, ba.minX, G), curY = lerp(ca.minY, ba.minY, G), s = size / S
        map["b.art"] = XPPose(dx: curX - ba.minX, dy: curY - ba.minY, scale: s, anchor: .topLeading, opacity: P > 0 ? 1 : 0)
        map["c.art"] = XPPose(opacity: P > 0 ? 0 : 1)
        out.artRadius = lerp(12, 18, G) / max(s, 0.01)
        out.artGrow = G; out.artScale = max(s, 0.01)

        let v = 1 - (1 - P) * (1 - P), bottom = curY + size, bottom0 = Double(ca.maxY), bottom1 = Double(ba.maxY)
        func rowY(_ y0: Double, _ y1: Double) -> Double { bottom + lerp(y0 - bottom0, y1 - bottom1, v) }

        // title and artist line, circling round the growing cover
        let ccx = curX + size / 2, ccy = curY + size / 2, W = Double(cs.width), limit = W - 14
        let extra = fade(P, 0.14, 0.72)
        out.extra = extra
        out.chev = 1 - fade(P, 0, 0.13)
        let c0x = Double(ca.midX), c0y = Double(ca.midY), c1x = Double(ba.midX), c1y = Double(ba.midY)
        func orbit(_ a: (Double, Double), _ bb: (Double, Double), _ t: Double) -> (Double, Double) {
            let a0 = atan2(a.1 - c0y, a.0 - c0x)
            var a1 = atan2(bb.1 - c1y, bb.0 - c1x)
            while a1 - a0 > .pi { a1 -= 2 * .pi }
            while a0 - a1 > .pi { a1 += 2 * .pi }
            let g0 = hypot(a.0 - c0x, a.1 - c0y) - edge(a0, aw / 2), g1 = hypot(bb.0 - c1x, bb.1 - c1y) - edge(a1, S / 2)
            let ang = lerp(a0, a1, t * t), r = edge(ang, size / 2) + lerp(g0, g1, t)
            return (ccx + r * cos(ang), ccy + r * sin(ang))
        }
        struct Line { var X = 0.0; var Y = 0.0; var k = 1.0; var r = 1.0; var below = 0.0; var swap = true }
        var lead: Line?
        var artistLine: Line?
        for (name, ratio) in [("title", 20.0 / 17), ("artist", 13.5 / 13)] {
            guard let cb = c["c." + name], let xb = b["b." + name] else { continue }
            // the line that matches the small copy: the whole block, or its first line when the big text wraps
            var L = xb
            if let l1 = m.line1["b." + name], xb.height > l1.height * 1.5 {
                L = CGRect(x: xb.midX - min(l1.width, xb.width) / 2, y: xb.minY, width: min(l1.width, xb.width), height: l1.height)
            }
            let r = ratio, k = lerp(1, r, P), sc = k / r, oy = Double(L.height) / 2
            let avail = W - Theme.panelPad - Double(cb.minX)
            let swap = Double(cb.width) < avail - 1                    // the small line isn't cut short: the big copy takes over in place
            // cut short ("…") while the big one fits on one line: it still takes over in place, and the letters the small
            // one hid write themselves in (a cross-fade of two different copies read as the text jumping)
            let reveal = name == "title" && !swap && L == xb ? max(0, Double(cb.width) - 14) * r : 0
            var shown = 0.0
            if reveal > 0 { shown = lerp(reveal, Double(xb.width), fade(P, 0, 0.45)); out.titleReveal = name == "title" && P < 1 ? CGFloat(shown) : nil }
            let inPlace = swap || reveal > 0
            let cOp = inPlace ? (P > 0 ? 0 : 1) : max(0, 1 - fade(P, 0.1, 0.22)), xOp = inPlace ? (P > 0 ? 1 : 0) : fade(P, 0.06, 0.2)
            let (cx, cy) = orbit((Double(cb.minX), Double(cb.midY) - oy / r), (Double(L.minX), Double(L.minY)), P)
            var X = cx, Y = cy + oy * sc
            if P > 0 && P < 1 {
                let full = Double(L.width)
                let vis = reveal > 0 ? shown : name == "title" ? full : lerp(min(full, Double(b["b.artistName"]?.width ?? xb.width)), full, extra)
                let f0 = fade(P, 0, 0.06)
                X -= f0 * max(0, X + vis * sc - limit)                 // never past the right edge
                let wd = max(clamp01((vis * sc - (limit - (curX + size + 12)) + 40) / 80), clamp01((curX + size + 12 - X) / 16)) * f0
                Y += wd * max(0, curY + size + 12 + oy * sc - Y)        // no room beside the cover: it goes under it
            }
            if let l = lead, P > 0 && P < 1 {                          // the artist line keeps below the title on the way
                let leadBottom = l.Y + l.below * l.k / l.r, need = leadBottom + 2 - (Y - oy * sc)
                Y += max(0, need) * (l.swap ? fade(P, 0, 0.2) : fade(P, 0, 0.06))
            }
            map["c." + name] = XPPose(dx: X - Double(cb.minX), dy: Y - Double(cb.midY), scale: k, anchor: UnitPoint(x: 0, y: 0.5), opacity: cOp)
            // scaled round that line's left middle, which lands on (X, Y)
            let anchor = UnitPoint(x: (L.minX - xb.minX) / max(1, xb.width), y: (L.midY - xb.minY) / max(1, xb.height))
            map["b." + name] = XPPose(dx: X - Double(L.minX), dy: Y - Double(L.midY), scale: sc, anchor: anchor, opacity: xOp)
            let line = Line(X: X, Y: Y, k: k, r: r, below: Double(xb.maxY - L.midY), swap: swap)
            if name == "title" { lead = line } else { artistLine = line }
        }

        // buttons, bar, times: drop to their row, then slide across
        let hc = P * P
        var push = 0.0
        if let al = artistLine, let cbar = c["c.bar"], let xbar = b["b.bar"], let xart = b["b.artist"], P > 0 && P < 1 {
            let subBottom = al.Y + al.below * al.k / al.r
            let gapEnd = Double(xbar.minY) - Double(xart.maxY)
            let barTop = rowY(Double(cbar.midY), Double(xbar.midY)) - Double(xbar.height) / 2
            push = max(0, subBottom + gapEnd * 0.5 + 9 * sin(.pi * P) - barTop)
        }
        var playY = 0.0, playDy = 0.0, playDy0 = 0.0, tail0 = 0.0, tail1 = 0.0
        for (name, f, isTime, same) in [("prev", 0.5, false, true), ("play", 0.5, false, true), ("next", 0.5, false, true),
                                        ("bar", 0.5, false, true), ("cur", 0.0, true, true), ("left", 1.0, true, false)] {
            let cname = name == "left" ? "c.dur" : "c." + name
            guard let cb = c[cname], let xb = b["b." + name] else { continue }
            let track = name == "bar", r = track || isTime ? 1 : Double(xb.width) / max(1, Double(cb.width))
            let c0 = (Double(cb.minX) + Double(cb.width) * f, Double(cb.midY)), x1 = (Double(xb.minX) + Double(xb.width) * f, Double(xb.midY))
            let tx = 1 - cos(fade(P, isTime ? 0.3 : 0.1, 1) * .pi / 2)
            let X = lerp(c0.0, x1.0, tx), Y = rowY(c0.1, x1.1) + push, k = lerp(1, r, hc)
            let anchor = UnitPoint(x: f, y: 0.5)
            let cOp = same ? (P > 0 ? 0 : 1) : max(0, 1 - fade(P, 0, 0.12)), xOp = same ? (P > 0 ? 1 : 0) : fade(P, 0.12, 0.32)
            map[cname] = XPPose(dx: X - c0.0, dy: Y - c0.1, scale: k, anchor: anchor, opacity: cOp)
            if track {
                let w = lerp(Double(cb.width), Double(xb.width), hc)    // the bar opens up from the small one's length (its dot stays round)
                map["b.bar"] = XPPose(dx: X - x1.0, dy: Y - x1.1, anchor: anchor, opacity: xOp, width: w)
            } else {
                map["b." + name] = XPPose(dx: X - x1.0, dy: Y - x1.1, scale: k / r, anchor: anchor, opacity: xOp)
            }
            if name == "play" {
                playY = Y; playDy = Y - x1.1; playDy0 = Y - c0.1
                tail0 = Double(cs.height) - c0.1; tail1 = Double(bs.height) - x1.1
            }
        }
        // the panel is carried by what's in it: its bottom edge keeps to the controls
        out.height = playY + lerp(tail0, tail1, fade(P, 0.1, 1))
        let fo = fade(P, 0.72, 1)
        map["b.shuf"] = XPPose(dy: playDy, opacity: fo)
        map["b.rep"] = XPPose(dy: playDy, opacity: fo)
        map["c.foot"] = XPPose(dy: playDy0, opacity: 1 - fade(P, 0, 0.13))
        let bo = fade(P, 0.74, 1)
        map["b.strip"] = XPPose(dy: (1 - bo) * 12, opacity: bo)
        map["b.handle"] = XPPose(opacity: fade(P, 0.5, 0.9))
        map["b.lyr"] = XPPose(opacity: 0)
        out.map = map
        return out
    }
}
