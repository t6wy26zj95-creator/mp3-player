import SwiftUI

/// Small tools for copying the web player's Web Animations exactly.
///
/// A one-off motion (a nudge, a pop, a comet) is a progress `p` that goes 0 → 1, read through the same keyframes,
/// offsets and cubic-bezier curves as index.html. Its resting value is always p = 1, which is the resting pose, so if
/// iOS drops an animation (app sent to the background, screen locked mid-motion) the view still ends up where it
/// belongs instead of frozen halfway, which is what left the pause icon tilted.

/// CSS cubic-bezier(x1, y1, x2, y2) as a function of time 0…1.
struct Bezier {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }
    static let linear = Bezier(0, 0, 1, 1)
    static let ease = Bezier(0.22, 1, 0.36, 1)                  // the web's --ease

    private func bx(_ t: Double) -> Double { let u = 1 - t; return 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t }
    private func by(_ t: Double) -> Double { let u = 1 - t; return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t }
    private func dbx(_ t: Double) -> Double { let u = 1 - t; return 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2) }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {                                         // Newton's method, then bisection if it stalls
            let e = bx(t) - x
            if abs(e) < 1e-6 { return by(t) }
            let d = dbx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0; t = x
        for _ in 0..<30 {
            let v = bx(t)
            if abs(v - x) < 1e-6 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }
}

/// One animated number through keyframes, as a Web Animation: `stops` are (offset, value); `each` is the easing of every
/// segment (keyframe easing), `whole` the easing of the whole timeline (the animation's own easing).
struct KF {
    var stops: [(Double, Double)]
    var each: Bezier = .linear
    var whole: Bezier = .linear

    func at(_ p: Double) -> Double {
        let x = whole(min(1, max(0, p)))
        guard let first = stops.first, let last = stops.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<stops.count where x <= stops[i].0 {
            let (o0, v0) = stops[i - 1], (o1, v1) = stops[i]
            let l = o1 > o0 ? (x - o0) / (o1 - o0) : 1
            return v0 + (v1 - v0) * each(l)
        }
        return last.1
    }
}

/// Draws a view at progress p of a one-off motion. SwiftUI animates p frame by frame.
struct KFEffect: ViewModifier, Animatable {
    var p: Double
    var dx: KF? = nil
    var dy: KF? = nil
    var scale: KF? = nil
    var angle: KF? = nil
    var opacity: KF? = nil
    var animatableData: Double { get { p } set { p = newValue } }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle?.at(p) ?? 0))
            .scaleEffect(scale.map { CGFloat($0.at(p)) } ?? 1)
            .offset(x: dx.map { CGFloat($0.at(p)) } ?? 0, y: dy.map { CGFloat($0.at(p)) } ?? 0)
            .opacity(opacity?.at(p) ?? 1)
    }
}

/// Plays a one-off motion: jumps p to 0 and runs it to 1 over `duration` (linear: the curves live in the keyframes).
/// The slow-motion recording's factor (-macawSlow N), else 1. Animations that bypass the root's slow hook (a
/// transition's own animation, a pause between two steps) multiply by it so the whole motion slows together.
let motionSlow: Double = {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "-macawSlow"), i + 1 < a.count, let v = Double(a[i + 1]), v > 1 { return v }
    return 1
}()

extension Animation {
    /// Stretched in the slow-motion recording (for animations the root's slow hook doesn't reach: a view's own
    /// .animation(_:value:) and a transition's own animation override it).
    var slowed: Animation { motionSlow > 1 ? speed(1 / motionSlow) : self }
}

extension View {
    /// .animation(_:value:), stretched in the slow-motion recording.
    func anim<V: Equatable>(_ a: Animation?, value: V) -> some View { animation(a?.slowed, value: value) }
}

/// A pause inside a motion (stretched in the slow-motion recording).
func motionPause(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * motionSlow * 1_000_000_000))
}

@MainActor func replay(_ p: Binding<Double>, duration: Double) {
    var jump = Transaction(); jump.disablesAnimations = true
    withTransaction(jump) { p.wrappedValue = 0 }
    DispatchQueue.main.async {
        withAnimation(.linear(duration: duration)) { p.wrappedValue = 1 }
    }
}

/// An animation along a curve given as a function (for the web's hand-written easings, such as Play's "back").
struct CurveAnimation: CustomAnimation {
    var duration: Double
    var kind: Int                                                   // 0: Play / pause morph ("back")

    func curve(_ x: Double) -> Double {
        switch kind {
        default: return 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2)   // web setPlayIcon: back(x)
        }
    }
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        if time >= duration { return nil }
        return value.scaled(by: curve(time / duration))
    }
}

extension Animation {
    /// The web's Play / pause morph: 400 ms with a small overshoot.
    static let playMorph = Animation(CurveAnimation(duration: 0.4, kind: 0))
}

/// CSS filter: brightness(x): every colour multiplied by x (above 1 brighter, below 1 darker), exactly.
struct CSSBrightness<S: Shape>: ViewModifier {
    var x: Double
    var shape: S
    func body(content: Content) -> some View {
        content
            .overlay { if x > 1.001 { content.opacity(min(1, x - 1)).blendMode(.plusLighter).allowsHitTesting(false) } }
            .overlay { if x < 0.999 { shape.fill(Color.black.opacity(1 - x)).allowsHitTesting(false) } }
    }
}

/// The web player's own icons (SVG path data on a 24 × 24 box), drawn exactly. Reads M L H V C Z, absolute and relative.
struct SVGIcon: Shape {
    var d: String

    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        let ox = r.midX - 12 * k, oy = r.midY - 12 * k
        var p = Path()
        var cur = CGPoint.zero, start = CGPoint.zero, c2prev: CGPoint? = nil
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }
        var nums: [Double] = []
        var cmd: Character = "M"
        func flush() {
            var i = 0
            func take(_ n: Int) -> [Double]? { guard i + n <= nums.count else { return nil }; defer { i += n }; return Array(nums[i..<i + n]) }
            let rel = cmd.isLowercase
            var c = Character(cmd.uppercased())
            repeat {
                switch c {
                case "M":
                    guard let a = take(2) else { return }
                    cur = rel ? CGPoint(x: cur.x + a[0], y: cur.y + a[1]) : CGPoint(x: a[0], y: a[1])
                    start = cur; p.move(to: pt(cur.x, cur.y)); c = "L"                     // more pairs after M are lines
                case "L":
                    guard let a = take(2) else { return }
                    cur = rel ? CGPoint(x: cur.x + a[0], y: cur.y + a[1]) : CGPoint(x: a[0], y: a[1])
                    p.addLine(to: pt(cur.x, cur.y))
                case "H":
                    guard let a = take(1) else { return }
                    cur.x = rel ? cur.x + a[0] : a[0]; p.addLine(to: pt(cur.x, cur.y))
                case "V":
                    guard let a = take(1) else { return }
                    cur.y = rel ? cur.y + a[0] : a[0]; p.addLine(to: pt(cur.x, cur.y))
                case "C":
                    guard let a = take(6) else { return }
                    let b = rel ? cur : .zero
                    let c1 = CGPoint(x: b.x + a[0], y: b.y + a[1]), c2 = CGPoint(x: b.x + a[2], y: b.y + a[3]), e = CGPoint(x: b.x + a[4], y: b.y + a[5])
                    p.addCurve(to: pt(e.x, e.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); cur = e; c2prev = c2; continue
                case "S":                                                                   // smooth: the first control mirrors the last one
                    guard let a = take(4) else { return }
                    let b = rel ? cur : .zero
                    let c1 = c2prev.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                    let c2 = CGPoint(x: b.x + a[0], y: b.y + a[1]), e = CGPoint(x: b.x + a[2], y: b.y + a[3])
                    p.addCurve(to: pt(e.x, e.y), control1: pt(c1.x, c1.y), control2: pt(c2.x, c2.y)); cur = e; c2prev = c2; continue
                case "Z":
                    p.closeSubpath(); cur = start; return
                default: return
                }
                c2prev = nil
            } while i < nums.count
        }
        var numStr = ""
        func endNum() { if let v = Double(numStr) { nums.append(v) }; numStr = "" }
        for ch in d {
            if ch.isLetter {
                endNum(); flush(); nums = []; cmd = ch
                if ch == "Z" || ch == "z" { flush(); cmd = " " }
            } else if ch == "-" {
                if !numStr.isEmpty && numStr.last != "e" { endNum() }
                numStr.append(ch)
            } else if ch == "." && numStr.contains(".") {
                endNum(); numStr = "."
            } else if ch == "," || ch == " " {
                endNum()
            } else { numStr.append(ch) }
        }
        endNum(); flush()
        return p
    }

    static let prev = "M6 6h2v12H6zm3.5 6l8.5 6V6z"
    static let next = "M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"
    static let shuffle = "M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z"
    static let repeatAll = "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z"
    static let repeatOne = repeatAll + "m-4-2V9h-1l-2 1v1h1.5v4H13z"
    static let qNext = "M2 6h12v2H2zm0 4h12v2H2zm0 4h8v2H2zm14-4v8l6-4z"
    static let qLast = "M14 10H2v2h12v-2zm0-4H2v2h12V6zm4 8v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zM2 16h8v-2H2v2z"
    static let trash = "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"
    static let more = "M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"
    static let check = "M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"
    static let add = "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"
    static let photo = "M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"
    static let edit = "M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 000-1.41l-2.34-2.34a1 1 0 00-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"
    static let undo = "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z"
}
