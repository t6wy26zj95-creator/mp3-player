import SwiftUI

/// The one glass panel: the now-playing row, the controls, the footer (+ Songs, Queue · Library · Artists) and the drawer
/// under it. Tapping the cover (or pulling the row down) grows the same panel into the big player.
struct PlayerPanel: View {
    var room: CGFloat
    @State private var pull: CGFloat = 0
    @State private var driving = false              // the pull is moving the big player open / closed
    @State private var pullBase: CGFloat = 0
    @State private var pullDead = false             // this touch was decided: not a pull
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
                            // web: under the drawer come the panel's 16 pt gap and its 20 pt padding (measured on the
                            // web screenshots: 15 pt more than before)
                            DrawerView(tab: tab, room: room)
                                .padding(.bottom, Theme.panelPad - 6 + 15)
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
                    if !ui.expanded && !driving && pull == 0 && player.scrubbing == nil && !(ui.tab != nil && v.startLocation.y > (ui.landFlow ? 60 : 228)) {
                        leanTo(v.translation)
                    } else if leaning { release() }
                    guard hypot(v.translation.width, v.translation.height) > 9 || scrollFrom != nil || driving else { return }
                    if scrollFrom == nil && !driving && !pullDead {
                        guard abs(v.translation.height) > abs(v.translation.width), player.scrubbing == nil, !ui.lyricsOpen else { return }
                        // open: the handle and the cover fold it back; anywhere else scrolls down to the lyrics bubble
                        if ui.expanded && (v.startLocation.y + ui.lyricsScroll) >= foldZone { scrollFrom = ui.lyricsScroll }
                    }
                    if let from = scrollFrom {
                        let m = ui.lyricsMax, s = from - v.translation.height
                        ui.lyricsScroll = s < 0 ? -rub(-s) : s > m ? m + rub(s - m) : s
                        return
                    }
                    // the pull opens (or folds) the player under the finger: decided once, from the first few points
                    if driving { motion.dragTo(Double(v.translation.height - pullBase)); return }
                    if pullDead { return }
                    let dx = v.translation.width, dy = v.translation.height
                    if !ui.expanded && !ui.landFlow && v.startLocation.y < 130 {
                        // opening needs a clearly downward start (steeper than ~35° from vertical)
                        if dy > 0 && dy > abs(dx) * 1.4, motion.dragBegin() { driving = true; pullBase = dy; release() } else { pullDead = true }
                    } else if ui.expanded && !ui.lyricsOpen && v.startLocation.y < foldZone {
                        if abs(dy) > abs(dx) * 1.1, motion.dragBegin() { driving = true; pullBase = dy } else { pullDead = true }
                    } else { pullDead = true }
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
                    _ = dy; _ = fling
                    pullDead = false
                    if driving { driving = false; motion.dragEnd(Double(v.velocity.height)) }
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
          // web html.cf-land: on its side with Cover Flow open, the player rows step aside and only the tabs stay
          if !ui.landFlow {
            // now playing: cover (centred over the three buttons), title, artist ›
            HStack(alignment: .center, spacing: 16) {
                Button(action: open) {
                    CoverArt(track: player.current, size: 66, radius: 12, glow: !ui.minimalLight, motion: true, direction: player.songDirection)
                        .xp("c.art")
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("cover")
                .padding(.leading, 34)
                VStack(alignment: .leading, spacing: 2) {
                    SlidingTitle(text: player.current?.title ?? "", size: 17, direction: player.songDirection, tag: "c.title", spark: true)
                    HStack(spacing: 6) {
                        Button { if let a = player.current?.shownArtist { ui.showArtist(a) } } label: {
                            Text((player.current?.shownArtist ?? "") + " ›")
                                .font(.system(size: 13)).foregroundStyle(Color.w(0.6)).lineLimit(1)
                                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("artistLink")
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
                TimeText(kind: .elapsed)
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
          }

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
    /// The compact title glows now and then (web: the title spark).
    var spark = false
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2.5, y: 2)        // web: text-shadow 0 2px 5px rgba(0,0,0,.5)
            .lineLimit(1)
            .overlay(alignment: .leading) { if spark { TitleGlint(text: text, size: size) } }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if spark { Glow.shared.titleW = $0 } }
            .songSwap(text, direction: direction, center: center)
            .xp(tag)
            .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
    }
}

/// The title spark: no object travels across, the letters themselves glow. A copy of the title, its letters filled with
/// a soft 84 pt band of light, with a white and cover-coloured halo; the band slides across while it fades in and out
/// (web .title-glint + sparkFire: 1.3–2.1 s, cubic-bezier(.45,0,.3,1), opacity 0 → .85 → 1 → .8 → 0 at 0/.2/.5/.78/1).
struct TitleGlint: View {
    var text: String
    var size: CGFloat
    @State private var p: Double = 1                       // rest = 1 (invisible)
    @State private var b: Double = 0.7
    @State private var w: CGFloat = 0
    private var g: Glow { .shared }
    var body: some View {
        GlintBand(p: p, b: b, w: w)
            .mask(alignment: .leading) {
                Text(text).font(.system(size: size, weight: .semibold)).lineLimit(1)
            }
            .shadow(color: .white.opacity(0.9), radius: 0.75)
            .shadow(color: g.c1.color.opacity(0.75), radius: 3)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w = $0 }
            .onChange(of: g.sparkN) { _, _ in
                b = g.sparkB
                replay($p, duration: g.sparkD)
            }
            .onChange(of: text) { _, _ in                      // web: a new title stops the spark
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { p = 1 }
            }
    }
}

private struct GlintBand: View, Animatable {
    var p: Double
    var b: Double
    var w: CGFloat
    var animatableData: Double { get { p } set { p = newValue } }
    var body: some View {
        let e = Bezier(0.45, 0, 0.3, 1), B: Double = 84, x0 = -B * 0.8, x1 = Double(min(w, Glow.shared.titleW > 0 ? Glow.shared.titleW : w)) - B * 0.2
        let x = KF(stops: [(0, x0), (1, x1)], whole: e).at(p)
        let o = KF(stops: [(0, 0), (0.2, 0.85), (0.5, 1), (0.78, 0.8), (1, 0)], whole: e).at(p) * (0.55 + 0.45 * b)
        LinearGradient(stops: [.init(color: .w(0), location: 0), .init(color: .w(0.35), location: 0.25), .init(color: .w(0.9), location: 0.45),
                               .init(color: .white, location: 0.5), .init(color: .w(0.9), location: 0.55), .init(color: .w(0.35), location: 0.75),
                               .init(color: .w(0), location: 1)], startPoint: .leading, endPoint: .trailing)
            .frame(width: B)
            .offset(x: x)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .opacity(o)
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
    @State private var nudge: Double = 1                // rest = 1
    private var player: Player { .shared }
    var body: some View {
        let d: Double = next ? 1 : -1
        Button {
            Haptics.light(); replay($nudge, duration: 0.4)
            if next { player.next() } else { player.previous() }
        } label: {
            // the web's own icon: 14 px in the small player, 20 px in the big one
            SVGIcon(d: next ? SVGIcon.next : SVGIcon.prev).fill(.white)
                .frame(width: size >= 44 ? 20 : 14, height: size >= 44 ? 20 : 14)
                // web nudge: 0 → 4 px the way it points (30 %) → 1 px back (65 %) → 0, 400 ms ease
                .modifier(KFEffect(p: nudge, dx: KF(stops: [(0, 0), (0.3, d * 4), (0.65, -d), (1, 0)], whole: .ease)))
        }
        .buttonStyle(RoundButtonStyle(size: size, touchPoint: true))
        .accessibilityIdentifier(next ? "next" : "prev")
        .modifier(Breath(index: next ? 2 : 0, amount: 0.035))
    }
}

/// Play / pause: one shape whose two pieces glide from the triangle's halves to the two bars (with a little overshoot),
/// the icon turning in as it changes. Hold it for shuffle: after 140 ms a ring appears and fills; full (560 ms) =
/// shuffle toggles, the ring bursts outwards and a comet of light runs round the rim. Let go early and it runs back.
struct PlayButton: View {
    var size: CGFloat
    @State private var t: CGFloat = 0                   // 0 = play triangle, 1 = pause bars
    @State private var turn: Double = 1                  // the little turn as it flips (rest = 1)
    @State private var turnFrom: Double = 14
    @State private var hold: CGFloat = 0
    @State private var ringOn = false
    @State private var burst: Double = 1                 // the ring bursting outwards (rest = 1)
    @State private var comet: Double = 1                 // the comet round the rim (rest = 1)
    @State private var cometB: Double = 1
    @State private var fired = false
    @State private var holdTask: Task<Void, Never>?
    private var player: Player { .shared }
    private var icon: CGFloat { size >= 56 ? 26 : size == 34 ? 14 : size * 0.41 }   // web: 14 px small, 26 px big

    var body: some View {
        Button {
            if fired { fired = false; return }
            Haptics.light(); player.toggle()
        } label: {
            PlayPauseShape(t: t)
                .fill(.white)
                .frame(width: icon, height: icon)
                // web: rotate(±14deg) scale(.72) → none, 400 ms cubic-bezier(.22,1.35,.36,1)
                .modifier(KFEffect(p: turn, scale: KF(stops: [(0, 0.72), (1, 1)], whole: Bezier(0.22, 1.35, 0.36, 1)),
                                   angle: KF(stops: [(0, turnFrom), (1, 0)], whole: Bezier(0.22, 1.35, 0.36, 1))))
        }
        .buttonStyle(RoundButtonStyle(size: size, touchPoint: true, onPress: { p in if p { if holdTask == nil { startHold() } } else { stopHold() } }))
        .accessibilityIdentifier("play")
        .modifier(Breath(index: 1, amount: 0.06))
        .overlay {
            ZStack {
                Circle().stroke(Color.w(0.16), lineWidth: 2.3)
                Circle().trim(from: 0, to: hold).stroke(.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .padding(-5 + 1.15)
            .opacity(ringOn ? 1 : 0)
            .allowsHitTesting(false)
        }
        .overlay {                                       // web holdBurst: the full ring, scale 1 → 1.45 and fading, 400 ms ease
            Circle().stroke(.white, lineWidth: 2.3)
                .padding(-5 + 1.15)
                .modifier(KFEffect(p: burst, scale: KF(stops: [(0, 1), (1, 1.45)], whole: .ease), opacity: KF(stops: [(0, 1), (1, 0)], whole: .ease)))
                .allowsHitTesting(false)
        }
        .overlay { Comet(p: comet, bright: cometB).padding(-2).allowsHitTesting(false) }
        .onChange(of: Glow.shared.cometN) { _, _ in                // after the title spark (web: ringFire(b), 1.5 s)
            guard size < 38 else { return }                           // the compact player's Play only
            cometB = Glow.shared.cometB
            replay($comet, duration: 1.5)
        }
        .onAppear { t = player.isPlaying ? 1 : 0 }
        .onChange(of: player.isPlaying) { _, p in
            withAnimation(.playMorph) { t = p ? 1 : 0 }
            turnFrom = p ? -14 : 14
            replay($turn, duration: 0.4)
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
            ringOn = false
            cometB = 1
            replay($burst, duration: 0.4); replay($comet, duration: 1.0)
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

/// A comet of light that runs once round a round button's rim (web: ringFire): rotate −70° → 395°, opacity 0 → .2: full
/// → .72: 90 % → 0, all on cubic-bezier(.45,0,.3,1). p = 1 is at rest (invisible).
struct Comet: View {
    var p: Double
    var bright: Double = 1                               // web: o = .5 + .5 × brightness
    var body: some View {
        let o = 0.5 + 0.5 * bright, e = Bezier(0.45, 0, 0.3, 1), lc = Glow.shared.c1.color
        ZStack {
            // .pb-comet: the conic tail on a 2 px rim, tinted with the cover's colour
            Circle()
                .strokeBorder(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 205 / 360),
                                                      .init(color: lc.opacity(0.5), location: 285 / 360),
                                                      .init(color: .white.opacity(0.95), location: 348 / 360), .init(color: .white, location: 355 / 360),
                                                      .init(color: .clear, location: 1)], center: .center), lineWidth: 2)
            // .pb-face: a soft highlight on the face, near the top
            GeometryReader { g in
                EllipticalGradient(colors: [.w(0.26), .w(0)], center: UnitPoint(x: 0.46, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.72)
                    .frame(width: g.size.width * 1.2, height: g.size.height)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
                    .clipShape(Circle())
            }
            .padding(3)
        }
        // web: drop-shadow(0 0 2px white .9) drop-shadow(0 0 6px cover colour .9)
        .shadow(color: .white.opacity(0.9), radius: 1)
        .shadow(color: lc.opacity(0.9), radius: 3)
        .modifier(KFEffect(p: p, angle: KF(stops: [(0, -70), (1, 395)], whole: e),
                           opacity: KF(stops: [(0, 0), (0.2, o), (0.72, o * 0.9), (1, 0)], whole: e)))
    }
}

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
            let dy: (Double) -> CGFloat = { t in CGFloat(4 * t * (1 - t) * (A + Wr * sin(2 * Double.pi * (1.3 * t - ph)))) }
            ZStack(alignment: .leading) {
                if env > 0.0001 {
                    let w = g.size.width, mid = g.size.height / 2, r = height / 2
                    let line: (Double, Double) -> Path = { a, b in
                        Path { pth in
                            let n = max(1, Int((28 * (b - a)).rounded()))
                            for i in 0...n {
                                let t = a + (b - a) * Double(i) / Double(n)
                                let pt = CGPoint(x: min(w - r, max(r, w * CGFloat(t))), y: mid + dy(t))
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
    @State private var drag: TabDrag?
    @State private var eatTap = false
    private let order: [DrawerTab] = [.queue, .library, .artists]
    private let pad: CGFloat = 10.8                                         // web: min(11, max(5, gap * .45))

    /// Drag the open tab's pill sideways to switch tabs (web: like an iOS segmented control).
    private struct TabDrag { var start: DrawerTab; var off: CGFloat; var on = false; var hot: DrawerTab }

    var body: some View {
        HStack(spacing: 0) {
            Button { Haptics.light(); ui.importing = true } label: {
                Text("+ SONGS").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(Color.w(0.7))
                    .lineLimit(1).fixedSize()
                    .frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(PopStyle(deep: 0.88))
            .accessibilityIdentifier("addSongs")
            Spacer()
            HStack(spacing: 24) {
                tab(.queue, "QUEUE")
                tab(.library, "LIBRARY")
                tab(.artists, "ARTISTS")
            }
            .background(alignment: .leading) { PillView(sim: pill) }
            .coordinateSpace(name: "tabs")
            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tabs"))
                .onChanged { v in dragMoved(v) }
                .onEnded { _ in dragEnded() })
            // web .player-footer.edit: while rearranging the Library the tabs step aside for Done
            .opacity(ui.editing ? 0 : 1).offset(y: ui.editing ? 4 : 0)
            .allowsHitTesting(!ui.editing)
            .animation(Theme.easeN, value: ui.editing)
            .overlay(alignment: .trailing) { DoneButton(on: ui.editing) }
        }
        .padding(.horizontal, 10)
        .onChange(of: ui.tab, initial: true) { _, t in move(t) }
        .onChange(of: frames) { _, _ in move(ui.tab, jump: true) }
    }

    private func move(_ t: DrawerTab?, jump: Bool = false, quiet: Bool = false) {
        guard let t else { pill.hide(); return }
        guard let f = frames[t] else { return }
        pill.to(f.minX - pad, f.maxX + pad, jump: jump, quiet: quiet)
    }

    private func centre(_ t: DrawerTab) -> CGFloat { frames[t]?.midX ?? 0 }
    private func width(_ t: DrawerTab) -> CGFloat { (frames[t]?.width ?? 0) + pad * 2 }

    private func dragMoved(_ v: DragGesture.Value) {
        if drag == nil {
            guard let cur = ui.tab, let f = frames[cur], f.insetBy(dx: -12, dy: -12).contains(v.startLocation) else { return }
            drag = TabDrag(start: cur, off: v.startLocation.x - f.midX, hot: cur)
        }
        guard var d = drag else { return }
        if !d.on {
            if abs(v.translation.width) < 6 { return }
            d.on = true; eatTap = true
            withAnimation(Theme.easePop) { pill.held = true }
        }
        // the pill follows the finger, its width blending between the tabs it passes; past the ends it gives a little
        let lo = centre(order[0]), hi = centre(order[order.count - 1])
        var p = v.location.x - d.off
        if p < lo { p = lo - min(14, (lo - p) * 0.25) } else if p > hi { p = hi + min(14, (p - hi) * 0.25) }
        var i = 0
        while i < order.count - 2 && p > centre(order[i + 1]) { i += 1 }
        let a = order[i], b = order[i + 1]
        let t = max(0, min(1, (p - centre(a)) / max(1, centre(b) - centre(a))))
        let w = width(a) + (width(b) - width(a)) * t
        pill.hold(p - w / 2, p + w / 2)
        let near = order.min { abs(centre($0) - p) < abs(centre($1) - p) } ?? d.hot
        if near != d.hot { d.hot = near; Haptics.select() }
        drag = d
    }

    private func dragEnded() {
        guard let d = drag else { return }
        drag = nil
        guard d.on else { return }
        withAnimation(Theme.easePop) { pill.held = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { eatTap = false }   // the tap that ends a drag isn't a tap
        if d.hot != d.start { ui.open(d.hot) }
        move(d.hot, quiet: true)                                          // springs from where the finger left it
    }

    private func tab(_ t: DrawerTab, _ title: String) -> some View {
        let on = ui.tab == t
        // while dragging: the open tab dims and the tab under the pill lights up (web: .dragging .active / .hot)
        let lit = drag?.on == true ? drag?.hot == t : on
        return Button { if !eatTap { ui.open(t) } } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(lit ? Color.white : Color.w(0.4))
                .shadow(color: lit ? Color.w(0.3) : .clear, radius: 5)
                .lineLimit(1).fixedSize()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tabs")) } action: { frames[t] = $0 }
                .frame(height: 34)
                .contentShape(Rectangle().inset(by: -12))
                .animation(Theme.easeN, value: lit)
        }
        .buttonStyle(PopStyle(deep: 0.88))
        .accessibilityIdentifier("tab-\(t)")
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
    var held = false                                                       // lifted under the finger (scale 1.1)
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

    @MainActor func to(_ a: CGFloat, _ z: CGFloat, jump: Bool, quiet: Bool = false) {
        if !on || jump {
            L = a; R = z; tL = a; tR = z; vL = 0; vR = 0; moving = false
            if !on { withAnimation(Theme.easeN) { on = true } }
            return
        }
        if a == tL && z == tR { return }
        dir = (a + z - tL - tR) > 0 ? 1 : -1
        tL = a; tR = z; landed = quiet; last = nil; moving = true
    }
    /// The finger places the pill directly.
    @MainActor func hold(_ a: CGFloat, _ z: CGFloat) {
        L = a; R = z; tL = a; tR = z; vL = 0; vR = 0; speed = 0; moving = false; last = nil
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
        .animation(Theme.easeN, value: sim.on)                               // web: opacity var(--t-n) var(--ease)
        .scaleEffect(sim.on ? (sim.held ? 1.1 : 1) : 0.55)
        .animation(Theme.easePop, value: sim.on)                             //      scale var(--t-s) var(--ease-pop)
        .animation(Theme.easePop, value: sim.held)
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
    /// The big player's song change (web XP.onSong): 0 → 1 springs the cover from 93 %, darker, past full size, brighter.
    var bump: Double = 1
    @State private var shown: Track?
    @State private var dip: Double = 0                  // 0…1: the dip before the new artwork
    @State private var arrive: Double = 1               // the new artwork coming in (rest = 1)
    @State private var fromDx: Double = 0
    @State private var fromScale: Double = 0.88
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
            .modifier(CoverMotion(arrive: arrive, dip: dip, bump: bump, d: Double(direction) * 22, fromDx: fromDx, fromScale: fromScale, shape: shape))
        }
        .frame(width: size, height: size)
        .onAppear { shown = track }
        .onChange(of: track?.key) { _, _ in
            guard motion else { return }
            if shown == nil { shown = track; return }
            change()
        }
    }

    // web songOut / coverArrived / coverIn
    private func change() {
        job += 1
        let my = job, d = Double(direction) * 22, same = shown?.path == track?.path
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.25)) { dip = 1 }           // dips: 250 ms
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)                                 // the web waits ≥ 170 ms for the dip
            guard my == job else { return }
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) {
                shown = track
                // same artwork: it springs back from where it dipped; new artwork arrives from the other side
                fromDx = same ? -d * 0.5 : d * 0.5
                fromScale = same ? 0.88 : 0.86
                dip = 0
            }
            replay($arrive, duration: 0.4)
            Glow.shared.flare = 1
        }
    }
}

/// The compact cover's song-change pose. Dip (web: translateX(−dx/2) scale(.88) brightness(.72)); arrive (web, 400 ms
/// ease: from → scale(1.035) brightness(1.08) at 50 % → rest, starting at brightness(1.35)).
struct CoverMotion<S: Shape>: ViewModifier, Animatable {
    var arrive: Double
    var dip: Double
    var bump: Double
    var d: Double
    var fromDx: Double
    var fromScale: Double
    var shape: S
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(arrive, AnimatablePair(dip, bump)) }
        set { arrive = newValue.first; dip = newValue.second.first; bump = newValue.second.second }
    }
    func body(content: Content) -> some View {
        let x = KF(stops: [(0, fromDx), (0.5, 0), (1, 0)], whole: .ease).at(arrive)
        let s0 = KF(stops: [(0, fromScale), (0.5, 1.035), (1, 1)], whole: .ease).at(arrive)
        let b0 = KF(stops: [(0, 1.35), (0.5, 1.08), (1, 1)], whole: .ease).at(arrive)
        // big player: scale(.93) brightness(.8) → scale(1.015) brightness(1.08) at 55 % → rest, 400 ms ease
        let s = s0 * KF(stops: [(0, 0.93), (0.55, 1.015), (1, 1)], whole: .ease).at(bump)
        let b = b0 * KF(stops: [(0, 0.8), (0.55, 1.08), (1, 1)], whole: .ease).at(bump)
        let dx = x + (-d * 0.5 - x) * dip, sc = s + (0.88 - s) * dip, br = b + (0.72 - b) * dip
        content
            .modifier(CSSBrightness(x: br, shape: shape))
            .scaleEffect(sc)
            .offset(x: dx)
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

/// web .done-btn: a glass pill, 30 pt tall, that ends rearranging the Library
struct DoneButton: View {
    var on: Bool
    var body: some View {
        Button { Haptics.light(); withAnimation(Theme.easeN) { UIState.shared.editing = false } } label: {
            Text("DONE").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.white)
                .padding(.horizontal, 18).frame(height: 30)
                .background {
                    Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.w(0.14)))
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.w(0.4), .w(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                }
        }
        .buttonStyle(PopStyle())
        .opacity(on ? 1 : 0)
        .scaleEffect(on ? 1 : 0.92).offset(y: on ? 0 : -4)
        .animation(Theme.easeN.delay(on ? 0.06 : 0), value: on)
        .allowsHitTesting(on)
    }
}

/// The playing time on its own, so only this little label redraws as the song plays (not the whole player).
struct TimeText: View {
    enum Kind { case elapsed, left }
    var kind: Kind
    private var player: Player { .shared }
    var body: some View {
        let t = player.scrubbing ?? player.time
        Text(kind == .elapsed ? formatTime(t) : "-" + formatTime(max(0, player.duration - t)))
    }
}
