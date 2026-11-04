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
