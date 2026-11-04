import SwiftUI

/// The big player: the panel grows, the cover grows in place (one cover, never two), with the title, artist · album ·
/// year, the bar with elapsed / remaining, Shuffle · Prev · Play · Next · Repeat and the Queue strip.
struct BigPlayer: View {
    var close: () -> Void
    @Environment(\.xpPoses) private var poses
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
        .onChange(of: player.currentKey, initial: true) { _, _ in Lyrics.shared.song() }
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

            CoverArt(track: player.current, size: 191, radius: poses.artRadius ?? 18, glow: !ui.minimalLight)
                .xp("b.art")
                .padding(.top, 10)
                .onTapGesture(perform: close)

            VStack(spacing: 5) {
                SlidingTitle(text: player.current?.title ?? "", size: 20, direction: player.songDirection, center: true, tag: "b.title")
                subtitle
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            VStack(spacing: 5) {
                Scrubber(height: 4).xp("b.bar")
                HStack {
                    Text(formatTime(player.scrubbing ?? player.time)).xp("b.cur")
                    Spacer()
                    Text("-" + formatTime(max(0, player.duration - (player.scrubbing ?? player.time)))).xp("b.left")
                }
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.6))
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            HStack(spacing: 0) {
                ToggleButton(system: "shuffle", on: player.shuffle) { player.toggleShuffle() }.xp("b.shuf")
                Spacer(minLength: 0)
                TransportButton(kind: .prev, size: 46).xp("b.prev")
                Spacer(minLength: 0)
                TransportButton(kind: .play, size: 60).xp("b.play")
                Spacer(minLength: 0)
                TransportButton(kind: .next, size: 46).xp("b.next")
                Spacer(minLength: 0)
                ToggleButton(system: player.repeatMode == .one ? "repeat.1" : "repeat", on: player.repeatMode != .off) { player.cycleRepeat() }.xp("b.rep")
            }
            .padding(.horizontal, 26)
            .frame(height: 60)
            .padding(.top, 12)

            UpNextStrip()
                .xp("b.strip")
                .padding(.top, 34)
                .padding(.bottom, 12)
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
    var system: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(on ? Theme.teal.opacity(0.95) : Color.w(0.55))
                    .contentTransition(.symbolEffect(.replace))
                Circle().fill(on ? Theme.teal : .clear).frame(width: 4, height: 4)
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
                .frame(height: 64)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripW = $0 }
                .onAppear { proxy.scrollTo("now", anchor: nowAnchor) }
                .onChange(of: player.currentKey) { _, _ in withAnimation(Theme.ease) { proxy.scrollTo("now", anchor: nowAnchor) } }
                .onChange(of: stripW) { _, _ in proxy.scrollTo("now", anchor: nowAnchor) }
            }
        }
    }

    private func card(_ c: Card) -> some View {
        let now: Bool = { if case .now = c.kind { return true }; return false }()
        let played: Bool = { if case .played = c.kind { return true }; return false }()
        let queued: Int? = { if case .queued(let i) = c.kind { return i }; return nil }()
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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.w(now ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.w(now ? 0.34 : 0.12), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if queued != nil { Circle().fill(Theme.teal).frame(width: 6, height: 6).padding(7) }
            }
            .opacity(played ? 0.45 : 1)
        }
        .buttonStyle(PressStyle())
        .contextMenu {
            Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(c.track, last: false) }
            if let i = queued {
                Button("Remove from queue", systemImage: "minus.circle", role: .destructive) { player.removeFromQueue(at: IndexSet(integer: i)) }
            } else if case .album = c.kind {
                Button("Remove from up next", systemImage: "minus.circle", role: .destructive) { player.removeUpcoming(c.track.key) }
            }
        }
    }
}
