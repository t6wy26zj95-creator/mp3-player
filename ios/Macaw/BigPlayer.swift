import SwiftUI

/// The big player: the panel grows, the cover grows in place (one cover, never two), with the title, artist · album ·
/// year, the bar with elapsed / remaining, Shuffle · Prev · Play · Next · Repeat and the Queue strip.
struct BigPlayer: View {
    var close: () -> Void
    @Environment(\.xpPoses) private var poses
    @State private var meta: Double = 1                   // the song-change motion of the title block (rest = 1)
    @State private var bump: Double = 1                   // ... and of the cover
    @State private var metaDir = 1
    private var ui: UIState { .shared }
    private var player: Player { .shared }

    var body: some View {
        ZStack(alignment: .top) {
            home
                .overlay(alignment: .bottom) {
                    // under the panel's bottom edge until the player is scrolled up
                    LyricsBubble(open: openLyrics)
                        .padding(.horizontal, 16)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ui.lyricsMax = $0 + 4 + 18 }
                        .alignmentGuide(.bottom) { d in d[.top] - 4 }
                        .opacity(ui.lyricsScroll > 0.5 ? 1 : 0)
                        .xp("b.lyr")
                }
                .offset(y: -ui.lyricsScroll)
                .opacity(ui.lyricsOpen ? 0 : 1)
                .allowsHitTesting(!ui.lyricsOpen)
            if ui.lyricsOpen {
                LyricsPage(close: closeLyrics)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .offset(y: 12)),
                                            removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .bottom))))
            }
        }
        .onChange(of: player.currentKey, initial: true) { old, _ in
            Lyrics.shared.song()
            guard old != nil, XPMotion.shared.phase == .big, player.isPlaying else { return }
            metaDir = player.songDirection
            replay($meta, duration: 0.4); replay($bump, duration: 0.4)
        }
        .onChange(of: ui.lyricsScroll > 0.5) { _, on in if on { Lyrics.shared.retryIfFailed() } }
        .onDisappear { ui.lyricsScroll = 0; ui.lyricsOpen = false }
    }

    private func openLyrics() {
        guard !ui.lyricsOpen else { return }
        Haptics.light()
        withAnimation(Theme.ease) { ui.lyricsOpen = true }
    }
    private func closeLyrics() {
        Haptics.light()
        withAnimation(Theme.ease) { ui.lyricsOpen = false }
    }

    private var home: some View {
        VStack(spacing: 0) {
            Button(action: close) {
                Capsule().fill(Color.w(0.3)).frame(width: 36, height: 5)
                    .frame(width: 72, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .xp("b.handle")
            .padding(.top, 6)

            CoverArt(track: player.current, size: 191, radius: poses.artRadius ?? 18, glow: !ui.minimalLight, bump: bump)
                .xp("b.art")
                .padding(.top, 10)
                .onTapGesture(perform: close)

            // web .xp-meta: on a song change it comes in 26 pt from the side you skipped to (8 pt from below when picked)
            // while the cover springs; nothing slides out
            VStack(spacing: 5) {
                BigTitle(text: player.current?.title ?? "", tag: "b.title")
                subtitle
            }
            .modifier(KFEffect(p: meta, dx: KF(stops: [(0, Double(metaDir) * 26), (1, 0)], whole: .ease),
                               dy: KF(stops: [(0, metaDir == 0 ? 8 : 0), (1, 0)], whole: .ease),
                               opacity: KF(stops: [(0, 0), (1, 1)], whole: .ease)))
            .padding(.horizontal, 22)
            .padding(.top, 22)

            // measured against the web screenshot at the same scale: bar 24 pt under the artist line, times 9 pt under the bar
            VStack(spacing: 2) {
                Scrubber(height: 4, bow: poses.moving ? poses.p : 0).xp("b.bar")
                HStack {
                    TimeText(kind: .elapsed).xp("b.cur")
                    Spacer()
                    TimeText(kind: .left).xp("b.left")
                }
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.6))
            }
            .padding(.horizontal, 22)
            .padding(.top, 18.5)

            HStack(spacing: 0) {
                ToggleButton(d: SVGIcon.shuffle, on: player.shuffle) { player.toggleShuffle() }.xp("b.shuf")
                Spacer(minLength: 0)
                TransportButton(kind: .prev, size: 46).xp("b.prev")
                Spacer(minLength: 0)
                TransportButton(kind: .play, size: 60).xp("b.play")
                Spacer(minLength: 0)
                TransportButton(kind: .next, size: 46).xp("b.next")
                Spacer(minLength: 0)
                ToggleButton(d: player.repeatMode == .one ? SVGIcon.repeatOne : SVGIcon.repeatAll, on: player.repeatMode != .off) { player.cycleRepeat() }.xp("b.rep")
            }
            .padding(.horizontal, 26)
            .frame(height: 60)
            .padding(.top, 12.5)

            UpNextStrip()
                .xp("b.strip")
                .padding(.top, 40)
                .padding(.bottom, 18)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: some View {
        let t = player.current
        let rest = [t?.album ?? "", t?.year ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        // while it opens, album · year (and the sound effect) write themselves in letter by letter (web: letters()),
        // the artist starts as dim as the small line, and the small line's " ›" rides along and fades
        let tail = rest.isEmpty ? "" : " · " + rest, fx = Retro.shared.mode != "off" ? " · " + Retro.shared.label : ""
        let n = tail.count + fx.count, K = 3.0, e = poses.extra
        func op(_ i: Int) -> Double { max(0, min(1, (e * Double(n) + e * K - Double(i)) / K)) }
        func letters(_ s: String, from i0: Int, _ color: Color) -> Text {
            if e >= 1 { return Text(s).foregroundColor(color) }
            return s.enumerated().reduce(Text("")) { acc, x in acc + Text(String(x.element)).foregroundColor(color.opacity(op(i0 + x.offset))) }
        }
        let gold = Color(red: 232 / 255, green: 196 / 255, blue: 140 / 255)
        return HStack(spacing: 0) {
            Button { if let a = t?.shownArtist { ui.showArtist(a) } } label: {
                Text(t?.shownArtist ?? "").foregroundStyle(Color.w(e >= 1 ? 0.85 : 0.6 + 0.25 * e))
                    .overlay(alignment: .trailing) {
                        if poses.chev > 0.001 {
                            Text(" ›").foregroundStyle(Color.w(0.85)).fixedSize()
                                .alignmentGuide(.trailing) { d in d[.leading] }
                                .opacity(poses.chev * 0.5)
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .xp("b.artistName")
            if !tail.isEmpty || !fx.isEmpty { letters(tail, from: 0, Color.w(0.55)) + letters(fx, from: tail.count, gold) }
        }
        .font(.system(size: 13.5))
        .lineLimit(1)
        .xp("b.artist")
        .frame(maxWidth: .infinity)
    }
}

/// Shuffle / Repeat: no ring, lit (with a dot under it) when on.
struct ToggleButton: View {
    var d: String
    var on: Bool
    var action: () -> Void
    // web .xp-tog: a 20 px icon in a 40 px button, rgba(255,255,255,.55) → rgb(120,222,202) when on, with a 4 px dot
    // 3 px above the bottom fading in (250 ms)
    private static let lit = Color(red: 120 / 255, green: 222 / 255, blue: 202 / 255)
    var body: some View {
        Button(action: action) {
            SVGIcon(d: d).fill(on ? Self.lit : Color.w(0.55))
                .frame(width: 20, height: 20)
                .animation(Theme.easeN, value: on)
                .frame(width: 40, height: 40)
                .overlay(alignment: .bottom) {
                    Circle().fill(on ? Self.lit : Color.w(0.55)).frame(width: 4, height: 4)
                        .padding(.bottom, 3)
                        .opacity(on ? 1 : 0)
                        .animation(Theme.easeN, value: on)
                }
        }
        .buttonStyle(RoundButtonStyle(size: 40, filled: false))
    }
}

/// QUEUE ... See all, then a row of cards: what you heard (grey), now playing (lit), your queue (teal dot), the album.
struct UpNextStrip: View {
    @State private var stripW: CGFloat = 0
    /// The playing card sits 20 pt in from the panel's edge, like the web player (not flush against it).
    private var nowAnchor: UnitPoint { UnitPoint(x: stripW > 158 ? 20 / (stripW - 138) : 0, y: 0.5) }
    private var ui: UIState { .shared }
    private var player: Player { .shared }
    private var model: AppModel { .shared }

    private struct Card: Identifiable {
        let id: String
        let track: Track
        let kind: Kind
        enum Kind { case played, now, queued(Int), album }
    }

    private var cards: [Card] {
        var out: [Card] = []
        for (i, h) in player.history.suffix(3).enumerated() {
            if let t = model.byKey[h.key] { out.append(Card(id: "h\(i)", track: t, kind: .played)) }
        }
        if let c = player.current { out.append(Card(id: "now", track: c, kind: .now)) }
        for (i, k) in player.queue.enumerated() { if let t = model.byKey[k] { out.append(Card(id: "q\(i)", track: t, kind: .queued(i))) } }
        for k in player.contextUpcoming().prefix(40) { if let t = model.byKey[k] { out.append(Card(id: "c" + k, track: t, kind: .album)) } }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("QUEUE").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5))
                Spacer()
                Button("See all") {
                    XPMotion.shared.close { ui.open(.queue) }
                }
                .font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.7))
                .buttonStyle(PopStyle())
            }
            .padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(cards) { c in card(c).id(c.id) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollDisabled(lifted != nil && liftHeld)
                .frame(height: 64)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripW = $0 }
                .onAppear { proxy.scrollTo("now", anchor: nowAnchor) }
                .onChange(of: player.currentKey) { _, _ in withAnimation(Theme.ease) { proxy.scrollTo("now", anchor: nowAnchor) } }
                .onChange(of: stripW) { _, _ in proxy.scrollTo("now", anchor: nowAnchor) }
            }
        }
    }

    // web liftCard / flickCard: hold a card and move it sideways to reorder (within your queue, or within the album), or
    // pull it up past the line (it turns red) and let go to remove it
    @State private var lifted: String?
    @State private var cx: CGFloat = 0
    @State private var cy: CGFloat = 0
    @State private var armed = false
    @State private var leaving: String?             // the card lifting away before the queue changes
    @State private var to = 0
    @State private var landing = false
    private let step: CGFloat = 138 + 8

    /// a card's group (queue or album), its place in it and the group's size
    private func spot(_ c: Card, _ all: [Card]) -> (g: Int, i: Int, n: Int)? {
        switch c.kind {
        case .queued(let i): return (0, i, player.queue.count)
        case .album:
            let al = all.filter { if case .album = $0.kind { return true }; return false }
            guard let i = al.firstIndex(where: { $0.id == c.id }) else { return nil }
            return (1, i, al.count)
        default: return nil
        }
    }

    /// how far another card of the lifted one's group steps aside
    private func shift(_ c: Card, _ all: [Card]) -> CGFloat {
        guard let lid = lifted, lid != c.id, !armed, let me = all.first(where: { $0.id == lid }),
              let a = spot(me, all), let b = spot(c, all), a.g == b.g else { return 0 }
        let L = CGFloat(a.i) * step + cx, R = L + 138, mid = CGFloat(b.i) * step + 69
        if b.i < a.i && L < mid { return step }
        if b.i > a.i && R > mid { return -step }
        return 0
    }

    private func liftMoved(_ c: Card, _ all: [Card], _ t: CGSize) {
        guard let a = spot(c, all), !landing else { return }
        if lifted == nil { Haptics.medium(); withAnimation(Theme.easeN) { lifted = c.id }; to = a.i }
        let up = min(0, t.height), arm = up < -36
        if arm != armed { armed = arm; Haptics.select() }
        let lo = -CGFloat(a.i) * step - 6, hi = CGFloat(a.n - 1 - a.i) * step + 6
        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.95)) {
            cx = max(lo, min(hi, t.width)); cy = arm ? up * 0.7 : up * 0.25
        }
        var nt = a.i
        for o in all where o.id != c.id { let s = shift(o, all); if s > 0 { nt -= 1 } else if s < 0 { nt += 1 } }
        if nt != to { to = nt; Haptics.select() }
    }

    private func liftEnded(_ c: Card, _ all: [Card]) {
        guard lifted == c.id, let a = spot(c, all) else { return }
        if armed { remove(c); return }
        let land = CGFloat(to - a.i) * step
        Haptics.light()
        landing = true
        withAnimation(Theme.easeN) { cx = land; cy = 0 }
        let from = a.i, dest = to
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            if dest != from {
                let ix = IndexSet(integer: from), t = dest > from ? dest + 1 : dest
                if a.g == 0 { player.moveQueue(from: ix, to: t) } else { player.moveUpcoming(from: ix, to: t) }
            }
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { lifted = nil; cx = 0; cy = 0; landing = false }
        }
    }

    /// web flickCard: the card follows the finger up (a little down), shrinks and fades; past 30 pt it turns red
    private func flickMoved(_ c: Card, _ dy: CGFloat) {
        guard spot(c, cards) != nil, lifted == nil || lifted == c.id else { return }
        if lifted == nil { lifted = c.id }
        let d = dy < 0 ? dy : dy * 0.2, arm = d < -30
        if arm != armed { armed = arm; Haptics.select() }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { cx = 0; cy = d }
    }
    private func flickEnded(_ c: Card) {
        guard lifted == c.id else { return }
        if armed { remove(c); return }
        withAnimation(Theme.easeN) { cy = 0; armed = false } completion: { if !armed { lifted = nil } }
    }

    /// web removeCard: the card lifts away, the gap closes, then the queue changes
    private func remove(_ c: Card) {
        Haptics.light()
        withAnimation(Theme.easeQ) { leaving = c.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(Theme.easeN) {
                switch c.kind {
                case .queued(let i): player.removeFromQueue(at: IndexSet(integer: i))
                case .album: player.removeUpcoming(c.track.key)
                default: break
                }
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { lifted = nil; cx = 0; cy = 0; armed = false; leaving = nil }
            }
        }
    }

    private func card(_ c: Card) -> some View {
        let all = cards
        let now: Bool = { if case .now = c.kind { return true }; return false }()
        let played: Bool = { if case .played = c.kind { return true }; return false }()
        let queued: Int? = { if case .queued(let i) = c.kind { return i }; return nil }()
        let up = lifted == c.id, rm = up && armed, gone = leaving == c.id
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let lift = up && liftHeld && !landing
        return Button {
            Haptics.light()
            if let i = queued { player.playFromQueue(index: i) }
            else if case .album = c.kind { player.playFromContext(c.track.key) }
        } label: {
            HStack(spacing: 8) {
                CoverImage(path: c.track.path, px: 120, placeholder: AnyView(NotesPlaceholder()))
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.track.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    Text(c.track.shownArtist).font(.system(size: 10.5)).foregroundStyle(Color.w(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(7)
            .frame(width: 138, height: 52)
            .background {
                if rm { shape.fill(Color(red: 1, green: 99 / 255, blue: 99 / 255).opacity(0.42)) }
                else if lift {                                               // web .xp-card.lifted
                    shape.fill(Color(red: 19 / 255, green: 54 / 255, blue: 68 / 255).opacity(0.96))
                        .overlay(shape.fill(LinearGradient(colors: [.w(0.2), .w(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: .black.opacity(0.35), radius: 13, y: 12)
                } else { shape.fill(Color.w(now ? 0.16 : 0.08)) }
            }
            .overlay(shape.strokeBorder(rm ? Color(red: 1, green: 150 / 255, blue: 150 / 255).opacity(0.55) : Color.w(lift ? 0.3 : now ? 0.34 : 0.12), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if queued != nil { Circle().fill(Theme.teal).frame(width: 6, height: 6).padding(7) }
            }
            .opacity(played ? 0.45 : 1)
        }
        .buttonStyle(PressStyle())
        .scaleEffect(gone ? 0.9 : lift ? 1.06 : up && !liftHeld ? 1 - min(0.08, -min(0, cy) / 500) : 1)
        .offset(x: up ? cx : shift(c, all), y: gone ? -34 : up ? cy : 0)
        .opacity(cardOpacity(gone: gone, up: up))
        .animation(Theme.easeN, value: shift(c, all))
        .zIndex(up ? 5 : 0)
        .gesture(HoldPan(began: { p in
            guard spot(c, all) != nil else { return }
            liftStart = p; liftHeld = true
            liftMoved(c, all, .zero)
        }, changed: { p in
            if liftHeld { liftMoved(c, all, CGSize(width: p.x - liftStart.x, height: p.y - liftStart.y)) }
        }, ended: { if liftHeld { liftEnded(c, all); liftHeld = false } }))
        .gesture(VerticalPan(changed: { dy in if !liftHeld { flickMoved(c, dy) } }, ended: { if !liftHeld { flickEnded(c) } }))
    }
    @State private var liftStart: CGPoint = .zero
    @State private var liftHeld = false              // lifted by a hold (reorder), not by a flick

    private func cardOpacity(gone: Bool, up: Bool) -> Double {
        if gone { return 0 }
        if up && !liftHeld { return max(0.45, 1 + Double(min(0, cy)) / 120) }       // pulled up: it fades
        if lifted != nil && liftHeld && !up && !landing { return 0.55 }             // web .xp-strip.dragging
        return 1
    }
}

/// A pull up on a card that only starts when the finger goes clearly up, so the strip still scrolls sideways.
struct VerticalPan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer(); g.delegate = context.coordinator; return g
    }
    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        switch g.state {
        case .changed: changed(g.translation(in: g.view).y)
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return false }
            let v = p.velocity(in: p.view)
            return v.y < 0 && abs(v.y) > abs(v.x) * 1.3
        }
    }
}

/// The big title (web .xp-title): 20 pt, up to 2 lines, balanced; a name that needs a 3rd line drops to 17 pt (fitTitle).
struct BigTitle: View {
    var text: String
    var tag: String
    @State private var w: CGFloat = 300
    private func lines(_ size: CGFloat) -> Int {
        let f = UIFont.systemFont(ofSize: size, weight: .semibold)
        let r = (text as NSString).boundingRect(with: CGSize(width: max(1, w), height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin], attributes: [.font: f], context: nil)
        return Int((r.height / f.lineHeight).rounded())
    }
    var body: some View {
        let size: CGFloat = lines(20) > 2 ? 17 : 20
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .lineSpacing(size * 1.25 - UIFont.systemFont(ofSize: size, weight: .semibold).lineHeight)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 2)           // web: text-shadow 0 2px 6px rgba(0,0,0,.45)
            .xp(tag)                                                         // the morph measures the text itself
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w = $0 }
    }
}
