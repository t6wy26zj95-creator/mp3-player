import SwiftUI

/// The one glass panel: the now-playing row, the controls, the footer (+ Songs, Queue · Library · Artists) and the drawer
/// under it. Tapping the cover (or pulling the row down) grows the same panel into the big player.
struct PlayerPanel: View {
    var room: CGFloat
    @State private var pull: CGFloat = 0
    @State private var lean: CGSize = .zero                 // the web player's pull: the panel leans after your finger...
    @State private var sx: CGFloat = 1                      // ...stretches a little along the drag, gives a hair across it,
    @State private var sy: CGFloat = 1                      // and sinks ~1 % while your finger is down
    @State private var leaning = false
    @State private var scrollFrom: CGFloat?
    /// The big player's handle and cover: a drag that starts there folds it back.
    private let foldZone: CGFloat = 240
    private func rub(_ d: CGFloat) -> CGFloat { 34 * (1 - exp(-d / 90)) }      // past either end: a little give
    private var ui: UIState { .shared }
    private var player: Player { .shared }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        let motion = XPMotion.shared
        // both layouts while the big player opens or closes (see XPMotion): the compact one under, the big one over it
        ZStack(alignment: .top) {
            XPLayer(big: false) {
                VStack(spacing: 0) {
                    CompactPlayer(open: open)
                        .padding(.horizontal, Theme.panelPad)
                        .padding(.top, Theme.panelPad)
                        .padding(.bottom, 16)
                    if let tab = ui.tab {
                        // web: the drawer's height grows with the panel (400 ms ease) while it fades in (250 ms)
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.w(0.1)).frame(height: 1)
                                .padding(.horizontal, Theme.panelPad)
                            DrawerView(tab: tab, room: room)
                                .padding(.bottom, Theme.panelPad - 6)
                        }
                        .transition(.opacity.animation(Theme.easeN))
                    } else {
                        Color.clear.frame(height: Theme.panelPad)
                    }
                }
                .xp("c.stack")
            }
            if motion.phase != .compact {
                XPLayer(big: true) { BigPlayer(close: close).xp("b.stack") }
                    .transition(.identity)
            }
        }
        .coordinateSpace(name: "xp")
        .fixedSize(horizontal: false, vertical: motion.phase == .measuring || motion.phase == .moving)
        .modifier(XPDriver(p: motion.p, phase: motion.phase))
        .frame(maxWidth: .infinity)
        .background(alignment: .topLeading) { if !ui.minimalLight { PanelTint() } }
        .clipShape(shape)
        .contentShape(shape)
        .panelGlass(shape, classic: ui.classic)
        .scaleEffect(x: sx, y: sy)
        .offset(lean)
        .offset(y: pull > 0 ? pull * 0.12 : pull * 0.06)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    // the lean: anywhere on the compact panel except the drawer's lists and the progress bar
                    if !ui.expanded && pull == 0 && player.scrubbing == nil && !(ui.tab != nil && v.startLocation.y > 228) {
                        leanTo(v.translation)
                    } else if leaning { release() }
                    guard hypot(v.translation.width, v.translation.height) > 14 || scrollFrom != nil || pull != 0 else { return }
                    if scrollFrom == nil && pull == 0 {
                        guard abs(v.translation.height) > abs(v.translation.width), player.scrubbing == nil, !ui.lyricsOpen else { return }
                        // open: the handle and the cover fold it back; anywhere else scrolls down to the lyrics bubble
                        if ui.expanded && (v.startLocation.y + ui.lyricsScroll) >= foldZone { scrollFrom = ui.lyricsScroll }
                    }
                    if let from = scrollFrom {
                        let m = ui.lyricsMax, s = from - v.translation.height
                        ui.lyricsScroll = s < 0 ? -rub(-s) : s > m ? m + rub(s - m) : s
                        return
                    }
                    guard abs(v.translation.height) > abs(v.translation.width) || pull != 0 else { return }
                    if !ui.expanded && ui.tab == nil && v.startLocation.y < 130 { pull = v.translation.height }
                    else if ui.expanded && !ui.lyricsOpen && v.startLocation.y < foldZone { pull = v.translation.height }
                }
                .onEnded { v in
                    release()
                    let dy = v.translation.height, fling = v.predictedEndTranslation.height
                    if scrollFrom != nil {
                        scrollFrom = nil
                        let m = ui.lyricsMax, vel = fling - dy
                        let proj = ui.lyricsScroll + max(-m, min(m, -vel * 0.4)), t: CGFloat = proj > m * 0.42 ? m : 0
                        if (t > 0) != (ui.lyricsScroll > m * 0.5) { Haptics.select() }
                        withAnimation(.spring(response: 0.42, dampingFraction: 1)) { ui.lyricsScroll = t }
                        return
                    }
                    if pull != 0 {
                        if !ui.expanded && ui.tab == nil && v.startLocation.y < 130 && (dy > 50 || fling > 160) { open() }
                        else if ui.expanded && v.startLocation.y < foldZone && (dy < -50 || fling < -160) { close() }
                    }
                    withAnimation(Theme.ease) { pull = 0 }
                }
        )
    }

    /// web: bubble.frame (index.html): strong resistance (1 - e^(-d/95)), at most ~7 px of lean, 1.8 % stretch, 0.9 % give,
    /// 1.1 % press; follows closely while held (k 300, critically damped), glides back without bounce (k 150, damping .86).
    private func leanTo(_ t: CGSize) {
        let d = hypot(t.width, t.height)
        var ux: CGFloat = 0, uy: CGFloat = 1, m: CGFloat = 0
        if d > 0.5 { ux = t.width / d; uy = t.height / d; m = 1 - exp(-d / 95) }
        leaning = true
        withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 1)) {
            lean = CGSize(width: ux * 9 * 0.8 * m, height: uy * 9 * 0.8 * m)
            sx = 1 + m * (0.018 * ux * ux - 0.009 * uy * uy) - 0.011
            sy = 1 + m * (0.018 * uy * uy - 0.009 * ux * ux) - 0.011
        }
    }
    private func release() {
        guard leaning else { return }
        leaning = false
        withAnimation(.spring(response: 0.51, dampingFraction: 0.86)) { lean = .zero; sx = 1; sy = 1 }
    }

    private func open() { XPMotion.shared.open() }
    private func close() { XPMotion.shared.close() }
}

// MARK: compact

struct CompactPlayer: View {
    var open: () -> Void
    private var ui: UIState { .shared }
    private var player: Player { .shared }

    var body: some View {
        VStack(spacing: 16) {
            // now playing: cover (centred over the three buttons), title, artist ›
            HStack(alignment: .center, spacing: 16) {
                Button(action: open) {
                    CoverArt(track: player.current, size: 66, radius: 12, glow: !ui.minimalLight, motion: true, direction: player.songDirection)
                        .xp("c.art")
                }
                .buttonStyle(PressStyle())
                .padding(.leading, 34)
                VStack(alignment: .leading, spacing: 2) {
                    SlidingTitle(text: player.current?.title ?? "", size: 17, direction: player.songDirection, tag: "c.title")
                    HStack(spacing: 6) {
                        Button { if let a = player.current?.shownArtist { ui.showArtist(a) } } label: {
                            Text((player.current?.shownArtist ?? "") + " ›")
                                .font(.system(size: 13)).foregroundStyle(Color.w(0.6)).lineLimit(1)
                                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                        }
                        .buttonStyle(PressStyle())
                        .songSwap((player.current?.key ?? "") + "|a", direction: player.songDirection, delay: 0.06)
                        if player.shuffle {
                            Image(systemName: "shuffle").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.teal)
                        }
                    }
                    .xp("c.artist")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 70)
            .contentShape(Rectangle())

            // controls: prev / play / next, time, bar, length
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TransportButton(kind: .prev, size: 34).xp("c.prev")
                    TransportButton(kind: .play, size: 34).xp("c.play")
                    TransportButton(kind: .next, size: 34).xp("c.next")
                }
                Text(formatTime(player.scrubbing ?? player.time))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.7))
                    .xp("c.cur")
                    .frame(minWidth: 24, alignment: .leading)
                Scrubber(height: 4)
                    .xp("c.bar")
                Text(formatTime(player.duration))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.7))
                    .xp("c.dur")
                    .frame(minWidth: 24, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Footer()
                .frame(height: 34)
                .xp("c.foot")
        }
    }
}

/// Song change, as the web player's songOut / songIn: the old text leaves (150 ms, cubic-bezier(.4,0,1,1)) 22 pt towards
/// the side you skipped from, blurring out; the new one arrives from the other side once it has gone (400 ms ease),
/// the artist line 60 ms after the title. Picked from a list (direction 0): out upwards, in from below.
struct SongSwap: ViewModifier {
    var dx: CGFloat, dy: CGFloat, fade: Bool
    var blur: CGFloat = 4
    func body(content: Content) -> some View {
        content.offset(x: dx, y: dy).opacity(fade ? 0 : 1).blur(radius: fade ? blur : 0)
    }
}

extension View {
    func songSwap(_ key: String, direction d: Int, delay: Double = 0, center: Bool = false) -> some View {
        let dx = CGFloat(d) * 22
        let inT = AnyTransition.modifier(active: SongSwap(dx: dx, dy: d == 0 ? 10 : 0, fade: true), identity: SongSwap(dx: 0, dy: 0, fade: false))
            .animation(Theme.ease.delay(0.15 + delay))
        let outT = AnyTransition.modifier(active: SongSwap(dx: -dx, dy: d == 0 ? -10 : 0, fade: true), identity: SongSwap(dx: 0, dy: 0, fade: false))
            .animation(.timingCurve(0.4, 0, 1, 1, duration: 0.15))
        return ZStack(alignment: center ? .center : .leading) {
            self.id(key).transition(.asymmetric(insertion: inT, removal: outT))
        }
        .animation(Theme.ease, value: key)
    }
}

/// The title, with the song-change motion.
struct SlidingTitle: View {
    var text: String
    var size: CGFloat
    var direction: Int
    var center = false
    var tag = ""
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2.5, y: 2)        // web: text-shadow 0 2px 5px rgba(0,0,0,.5)
            .lineLimit(1)
            .songSwap(text, direction: direction, center: center)
            .xp(tag)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
    }
}

struct TransportButton: View {
    enum Kind { case prev, play, next }
    var kind: Kind
    var size: CGFloat
    private var player: Player { .shared }
    var body: some View {
        if kind == .play { PlayButton(size: size) } else { SkipButton(next: kind == .next, size: size) }
    }
}

/// Prev / Next: the icon nudges the way it points (web: nudge, 400 ms: 4 pt out, 1 pt back, home).
struct SkipButton: View {
    var next: Bool
    var size: CGFloat
    @State private var taps = 0
    private var player: Player { .shared }
    var body: some View {
        let d: CGFloat = next ? 1 : -1
        Button {
            Haptics.light(); taps += 1
            if next { player.next() } else { player.previous() }
        } label: {
            Image(systemName: next ? "forward.end.fill" : "backward.end.fill")
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(.white)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: taps) { v, x in v.offset(x: x) } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(d * 4, duration: 0.12)
                        CubicKeyframe(-d, duration: 0.14)
                        CubicKeyframe(0, duration: 0.14)
                    }
                }
        }
        .buttonStyle(RoundButtonStyle(size: size))
        .modifier(Breath(index: next ? 2 : 0, amount: 0.035))
    }
}

/// Play / pause: one shape whose two pieces glide from the triangle's halves to the two bars (with a little overshoot),
/// the icon turning in as it changes. Hold it for shuffle: after 140 ms a ring appears and fills; full (560 ms) =
/// shuffle toggles, the ring bursts outwards and a comet of light runs round the rim. Let go early and it runs back.
struct PlayButton: View {
    var size: CGFloat
    @State private var t: CGFloat = 0                   // 0 = play triangle, 1 = pause bars
    @State private var turns = 0
    @State private var hold: CGFloat = 0
    @State private var ringOn = false
    @State private var burst = 0
    @State private var comet = 0
    @State private var fired = false
    @State private var holdTask: Task<Void, Never>?
    private var player: Player { .shared }

    var body: some View {
        Button {
            if fired { fired = false; return }
            Haptics.light(); player.toggle()
        } label: {
            PlayPauseShape(t: t)
                .fill(.white)
                .frame(width: size * 0.41, height: size * 0.41)
                .keyframeAnimator(initialValue: PlayTurn(), trigger: turns) { v, k in v.rotationEffect(.degrees(k.angle)).scaleEffect(k.scale) } keyframes: { _ in
                    KeyframeTrack(\.angle) { LinearKeyframe(player.isPlaying ? -14 : 14, duration: 0.001); SpringKeyframe(0, duration: 0.4, spring: .init(duration: 0.4, bounce: 0.25)) }
                    KeyframeTrack(\.scale) { LinearKeyframe(0.72, duration: 0.001); SpringKeyframe(1, duration: 0.4, spring: .init(duration: 0.4, bounce: 0.25)) }
                }
        }
        .buttonStyle(RoundButtonStyle(size: size))
        .modifier(Breath(index: 1, amount: 0.06))
        .overlay {
            ZStack {
                Circle().stroke(Color.w(0.16), lineWidth: 2.3)
                Circle().trim(from: 0, to: hold).stroke(.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .padding(-5 + 1.15)
            .opacity(ringOn ? 1 : 0)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: burst) { v, k in v.scaleEffect(1 + k * 0.45).opacity(k == 0 ? 1 : 1 - k) } keyframes: { _ in
                KeyframeTrack { LinearKeyframe(0.001, duration: 0.001); CubicKeyframe(1, duration: 0.4); LinearKeyframe(0, duration: 0.001) }
            }
            .allowsHitTesting(false)
        }
        .overlay { Comet(trigger: comet).padding(-2).allowsHitTesting(false) }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if holdTask == nil { startHold() } }
            .onEnded { _ in stopHold() })
        .onAppear { t = player.isPlaying ? 1 : 0 }
        .onChange(of: player.isPlaying) { _, p in
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { t = p ? 1 : 0 }
            turns += 1
        }
    }

    private func startHold() {
        fired = false
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            ringOn = true; Haptics.select()
            withAnimation(.linear(duration: 0.42)) { hold = 1 }
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            fired = true
            player.toggleShuffle()
            burst += 1; comet += 1
            try? await Task.sleep(nanoseconds: 400_000_000)
            ringOn = false
            hold = 0
        }
    }
    private func stopHold() {
        if fired { holdTask = nil; return }              // the burst finishes by itself
        holdTask?.cancel(); holdTask = nil
        if ringOn { ringOn = false; withAnimation(.easeOut(duration: 0.2)) { hold = 0 } }
    }
}

struct PlayTurn { var angle: Double = 0; var scale: CGFloat = 1 }

/// The web player's play / pause path (24 × 24): two quads that move from the triangle's halves to the two bars.
struct PlayPauseShape: Shape {
    var t: CGFloat
    var animatableData: CGFloat { get { t } set { t = newValue } }
    private static let play: [[CGFloat]] = [[8, 5, 13.5, 8.5, 13.5, 15.5, 8, 19], [13.5, 8.5, 19, 12, 19, 12, 13.5, 15.5]]
    private static let pause: [[CGFloat]] = [[6, 5, 10, 5, 10, 19, 6, 19], [14, 5, 18, 5, 18, 19, 14, 19]]
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = r.width / 24
        for i in 0..<2 {
            let a = Self.play[i], b = Self.pause[i]
            let v = (0..<8).map { a[$0] + (b[$0] - a[$0]) * t }
            p.move(to: CGPoint(x: r.minX + v[0] * k, y: r.minY + v[1] * k))
            for j in stride(from: 2, to: 8, by: 2) { p.addLine(to: CGPoint(x: r.minX + v[j] * k, y: r.minY + v[j + 1] * k)) }
            p.closeSubpath()
        }
        return p
    }
}

/// A comet of light that runs once round a round button's rim (web: ringFire).
struct Comet: View {
    var trigger: Int
    var body: some View {
        Circle()
            .strokeBorder(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 205 / 360),
                                                  .init(color: Color(red: 0.78, green: 0.84, blue: 0.88).opacity(0.5), location: 285 / 360),
                                                  .init(color: .white.opacity(0.95), location: 348 / 360), .init(color: .white, location: 355 / 360),
                                                  .init(color: .clear, location: 1)], center: .center), lineWidth: 2)
            .shadow(color: .white.opacity(0.9), radius: 1)
            .keyframeAnimator(initialValue: CometState(), trigger: trigger) { v, k in v.rotationEffect(.degrees(k.angle)).opacity(k.opacity) } keyframes: { _ in
                KeyframeTrack(\.angle) { LinearKeyframe(-70, duration: 0.001); CubicKeyframe(395, duration: 1.0) }
                KeyframeTrack(\.opacity) { LinearKeyframe(0, duration: 0.001); LinearKeyframe(1, duration: 0.2); LinearKeyframe(0.9, duration: 0.52); LinearKeyframe(0, duration: 0.28) }
            }
    }
}
struct CometState { var angle: Double = -70; var opacity: Double = 0 }

/// The progress bar: drag the dot; it only seeks when you let go (seeking while dragging broke streaming on the web).
struct Scrubber: View {
    var height: CGFloat
    var thumb: CGFloat = 14
    /// The big player's motion (0…1): while it moves, the line bends like a carried string (web: bow).
    var bow: Double = 0
    private var player: Player { .shared }
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let d = max(player.duration, 0.001)
            let p = min(1, max(0, (player.scrubbing ?? player.time) / d))
            // the string: it sags in the middle and a soft ripple runs along it, strongest halfway, gone at either end
            let sn = sin(Double.pi * bow), env = bow > 0 && bow < 1 ? sn * sn : 0
            let A = -9 * env, Wr = 3 * env, ph = bow * 2.2
            let dy: (Double) -> CGFloat = { t in 4 * t * (1 - t) * (A + Wr * sin(2 * .pi * (1.3 * t - ph))) }
            ZStack(alignment: .leading) {
                if env > 0.0001 {
                    let w = g.size.width, mid = g.size.height / 2, r = height / 2
                    let line: (Double, Double) -> Path = { a, b in
                        Path { pth in
                            let n = max(1, Int((28 * (b - a)).rounded()))
                            for i in 0...n {
                                let t = a + (b - a) * Double(i) / Double(n)
                                let pt = CGPoint(x: min(w - r, max(r, w * t)), y: mid + dy(t))
                                if i == 0 { pth.move(to: pt) } else { pth.addLine(to: pt) }
                            }
                        }
                    }
                    line(0, 1).stroke(Color.w(0.15), style: StrokeStyle(lineWidth: height, lineCap: .round))
                    if p > 0.002 { line(0, p).stroke(Color.w(0.85), style: StrokeStyle(lineWidth: height, lineCap: .round)) }
                } else {
                    Capsule().fill(Color.w(0.15)).frame(height: height)
                    Capsule().fill(Color.w(0.85)).frame(width: max(0, g.size.width * p), height: height)
                }
                Circle().fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .scaleEffect(dragging ? 1.25 : 1)
                    .offset(x: g.size.width * p - thumb / 2, y: dy(p))
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { dragging = true; Haptics.select() }
                    player.scrubbing = min(1, max(0, v.location.x / g.size.width)) * player.duration
                }
                .onEnded { _ in
                    if let s = player.scrubbing { player.seek(to: s) }
                    player.scrubbing = nil; dragging = false
                })
            .animation(Theme.easeQ, value: dragging)
        }
        .frame(height: max(thumb, height) + 6)
    }
}

/// + Songs on the left, Queue · Library · Artists on the right (24 pt apart) with the sliding glass pill.
struct Footer: View {
    private var ui: UIState { .shared }
    @State private var frames: [DrawerTab: CGRect] = [:]
    @State private var pill = PillSim()

    var body: some View {
        HStack(spacing: 0) {
            Button { Haptics.light(); ui.importing = true } label: {
                Text("+ SONGS").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(Color.w(0.7))
                    .lineLimit(1).fixedSize()
                    .frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(PopStyle(deep: 0.88))
            Spacer()
            HStack(spacing: 24) {
                tab(.queue, "QUEUE")
                tab(.library, "LIBRARY")
                tab(.artists, "ARTISTS")
            }
            .background(alignment: .leading) { PillView(sim: pill) }
            .coordinateSpace(name: "tabs")
        }
        .padding(.horizontal, 10)
        .onChange(of: ui.tab, initial: true) { _, t in move(t) }
        .onChange(of: frames) { _, _ in move(ui.tab, jump: true) }
    }

    private func move(_ t: DrawerTab?, jump: Bool = false) {
        guard let t else { pill.hide(); return }
        guard let f = frames[t] else { return }
        let pad: CGFloat = 10.8                                             // web: min(11, max(5, gap * .45))
        pill.to(f.minX - pad, f.maxX + pad, jump: jump)
    }

    private func tab(_ t: DrawerTab, _ title: String) -> some View {
        let on = ui.tab == t
        return Button { ui.open(t) } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(on ? Color.white : Color.w(0.4))
                .shadow(color: on ? Color.w(0.3) : .clear, radius: 5)
                .lineLimit(1).fixedSize()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tabs")) } action: { frames[t] = $0 }
                .frame(height: 34)
                .contentShape(Rectangle().inset(by: -12))
                .animation(Theme.easeN, value: on)
        }
        .buttonStyle(PopStyle(deep: 0.88))
    }
}

/// The web player's Liquid Glass tab slider: the pill's two edges are separate springs. The leading edge is quick and a
/// little bouncy (k 640, damping .6), the trailing one slower (k 230, .92), so the pill stretches towards the new tab like
/// a drop, squashes a touch while stretched, then pulls itself together and ticks as it lands. It pops in (scale .55 → 1)
/// when the drawer opens and shrinks away when it closes.
@Observable
final class PillSim {
    var L: CGFloat = 0
    var R: CGFloat = 0
    var on = false
    var moving = false
    var speed: CGFloat = 0
    @ObservationIgnored private var vL: CGFloat = 0
    @ObservationIgnored private var vR: CGFloat = 0
    @ObservationIgnored private var tL: CGFloat = 0
    @ObservationIgnored private var tR: CGFloat = 0
    @ObservationIgnored private var dir: CGFloat = 0
    @ObservationIgnored private var landed = true
    @ObservationIgnored private var last: Date?

    var squash: CGFloat { 1 - min(0.22, max(0, (R - L) - (tR - tL)) / 150) }

    @MainActor func to(_ a: CGFloat, _ z: CGFloat, jump: Bool) {
        if !on || jump {
            L = a; R = z; tL = a; tR = z; vL = 0; vR = 0; moving = false
            if !on { withAnimation(Theme.easeN) { on = true } }
            return
        }
        if a == tL && z == tR { return }
        dir = (a + z - tL - tR) > 0 ? 1 : -1
        tL = a; tR = z; landed = false; last = nil; moving = true
    }
    @MainActor func hide() { withAnimation(Theme.easeN) { on = false } }

    @MainActor func step(_ now: Date) {
        guard moving else { return }
        let dt = min(0.034, last.map { now.timeIntervalSince($0) } ?? 0.016); last = now
        let kl: CGFloat = dir < 0 ? 640 : 230, kr: CGFloat = dir > 0 ? 640 : 230
        let zl: CGFloat = dir < 0 ? 0.6 : 0.92, zr: CGFloat = dir > 0 ? 0.6 : 0.92
        var t = 0.0
        while t < dt - 1e-6 {
            let h = CGFloat(min(0.004, dt - t))
            vL += (kl * (tL - L) - 2 * sqrt(kl) * zl * vL) * h; L += vL * h
            vR += (kr * (tR - R) - 2 * sqrt(kr) * zr * vR) * h; R += vR * h
            t += 0.004
        }
        speed = min(1, (abs(vL) + abs(vR)) / 1800)
        if !landed && (dir > 0 ? R >= tR : L <= tL) { landed = true; Haptics.select() }
        if abs(vL) + abs(vR) <= 2 && abs(tL - L) + abs(tR - R) <= 0.4 { L = tL; R = tR; vL = 0; vR = 0; speed = 0; moving = false }
    }
}

struct PillView: View {
    var sim: PillSim
    var body: some View {
        TimelineView(.animation(paused: !sim.moving)) { tl in
            TabPill(glow: sim.speed)
                .frame(width: max(0, sim.R - sim.L), height: 28)
                .scaleEffect(x: 1, y: sim.squash)
                .offset(x: sim.L)
                .onChange(of: tl.date) { _, d in sim.step(d) }
        }
        .opacity(sim.on ? 1 : 0)
        .scaleEffect(sim.on ? 1 : 0.55)
        .animation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.4), value: sim.on)
        .allowsHitTesting(false)
    }
}

/// A song's cover with its coloured glow behind it (a blurred copy of the art, as the web player's bloom).
struct CoverArt: View {
    var track: Track?
    var size: CGFloat
    var radius: CGFloat
    var glow = true
    /// The compact player's song-change motion (web: songOut / coverIn): the cover dips (250 ms) to 88 %, darker, a little
    /// towards the side you skipped from; the new artwork then comes in from the other side, bright, overshoots to 103.5 %
    /// and settles (400 ms ease).
    var motion = false
    var direction = 1
    @State private var shown: Track?
    @State private var dx: CGFloat = 0
    @State private var scale: CGFloat = 1
    @State private var bright: Double = 0
    @State private var job = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let t = motion ? shown : track
        ZStack {
            if glow, t != nil { CoverGlowBack(size: size) }
            ZStack {
                Color.black.opacity(0.22)
                CoverImage(path: t?.path, px: Int(size * 3), placeholder: AnyView(NotesPlaceholder()))
                    .frame(width: size, height: size)
                if glow { CoverGlass(path: t?.path, size: size, radius: radius) }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.stroke(.black.opacity(0.45), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 2.5 * size / 66, y: 2 * size / 66)
            .shadow(color: .black.opacity(0.32), radius: 9 * size / 66, y: 7 * size / 66)
            .brightness(bright)
            .scaleEffect(scale)
            .offset(x: dx)
        }
        .frame(width: size, height: size)
        .onAppear { shown = track }
        .onChange(of: track?.key) { _, _ in
            guard motion else { return }
            if shown == nil { shown = track; return }
            change()
        }
    }

    private func change() {
        job += 1
        let my = job, d = CGFloat(direction) * 22, same = shown?.path == track?.path
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)) { dx = -d * 0.5; scale = 0.88; bright = -0.2 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard my == job else { return }
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) {
                shown = track
                if !same { dx = d * 0.5; scale = 0.86 }
                bright = 0.22
            }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)) { dx = 0; scale = 1.035; bright = 0.05 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard my == job else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)) { scale = 1; bright = 0 }
        }
    }
}

struct NotesPlaceholder: View {
    var body: some View {
        ZStack {
            Color.w(0.06)
            Image(systemName: "music.note").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.w(0.35))
        }
    }
}

/// The glass pill under the open tab (web: .tab-pill).
struct TabPill: View {
    var glow: CGFloat = 0
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.w(0.2), .w(0.06)], startPoint: .top, endPoint: .bottom))
            .background(Capsule().fill(Color.w(0.05)))
            .background(Capsule().fill(.ultraThinMaterial).opacity(0.5))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.w(0.46), .w(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .top) {
                Capsule().fill(LinearGradient(colors: [.w(0.3), .w(0)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 11).padding(.horizontal, 7).padding(.top, 1)
            }
            .background(Capsule().fill(Color.w(glow * 0.07)))
            .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
            .shadow(color: Color(red: 200 / 255, green: 215 / 255, blue: 225 / 255).opacity(glow * 0.5), radius: glow * 8)
    }
}

/// One of the two layouts of the panel: hidden (and untouchable) when the motion says so.
struct XPLayer<C: View>: View {
    var big: Bool
    @ViewBuilder var content: C
    @Environment(\.xpPoses) private var poses
    var body: some View {
        let on = big ? poses.bigOn : poses.compactOn
        content
            .opacity(on ? 1 : 0)
            .allowsHitTesting(on && !poses.moving)
    }
}
