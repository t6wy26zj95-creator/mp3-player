import SwiftUI

/// The one glass panel: the now-playing row, the controls, the footer (+ Songs, Queue · Library · Artists) and the drawer
/// under it. Tapping the cover (or pulling the row down) grows the same panel into the big player.
struct PlayerPanel: View {
    var room: CGFloat
    @Namespace private var ns
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
        VStack(spacing: 0) {
            if ui.expanded {
                BigPlayer(ns: ns, close: close)
            } else {
                CompactPlayer(ns: ns, open: open)
                    .padding(.horizontal, Theme.panelPad)
                    .padding(.top, Theme.panelPad)
                    .padding(.bottom, 16)
                if let tab = ui.tab {
                    Rectangle().fill(Color.w(0.1)).frame(height: 1)
                        .padding(.horizontal, Theme.panelPad)
                    DrawerView(tab: tab, room: room)
                        .padding(.bottom, Theme.panelPad - 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Color.clear.frame(height: Theme.panelPad)
                }
            }
        }
        .frame(maxWidth: .infinity)
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

    private func open() {
        Haptics.light()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { ui.expanded = true; ui.tab = nil }
    }
    private func close() {
        Haptics.light()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { ui.expanded = false; ui.lyricsScroll = 0; ui.lyricsOpen = false }
    }
}

// MARK: compact

struct CompactPlayer: View {
    var ns: Namespace.ID
    var open: () -> Void
    private var ui: UIState { .shared }
    private var player: Player { .shared }

    var body: some View {
        VStack(spacing: 16) {
            // now playing: cover (centred over the three buttons), title, artist ›
            HStack(alignment: .center, spacing: 16) {
                Button(action: open) {
                    CoverArt(track: player.current, size: 66, radius: 12, glow: !ui.minimalLight)
                        .matchedGeometryEffect(id: "art", in: ns)
                }
                .buttonStyle(PressStyle())
                .padding(.leading, 34)
                VStack(alignment: .leading, spacing: 2) {
                    SlidingTitle(text: player.current?.title ?? "", size: 17, direction: player.songDirection)
                        .matchedGeometryEffect(id: "title", in: ns, properties: .position)
                    HStack(spacing: 6) {
                        Button { if let a = player.current?.shownArtist { ui.showArtist(a) } } label: {
                            Text((player.current?.shownArtist ?? "") + " ›")
                                .font(.system(size: 13)).foregroundStyle(Color.w(0.6)).lineLimit(1)
                                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                        }
                        .buttonStyle(PressStyle())
                        if player.shuffle {
                            Image(systemName: "shuffle").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.teal)
                        }
                    }
                    .matchedGeometryEffect(id: "artist", in: ns, properties: .position)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 70)
            .contentShape(Rectangle())

            // controls: prev / play / next, time, bar, length
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TransportButton(kind: .prev, size: 34).matchedGeometryEffect(id: "prev", in: ns)
                    TransportButton(kind: .play, size: 34).matchedGeometryEffect(id: "play", in: ns)
                    TransportButton(kind: .next, size: 34).matchedGeometryEffect(id: "next", in: ns)
                }
                Text(formatTime(player.scrubbing ?? player.time))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.7))
                    .frame(minWidth: 24, alignment: .leading)
                Scrubber(height: 4)
                    .matchedGeometryEffect(id: "bar", in: ns)
                Text(formatTime(player.duration))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.w(0.7))
                    .frame(minWidth: 24, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Footer()
                .frame(height: 34)
        }
    }
}

/// The title: slides out and the new one in from the side you skipped to, as in the web player.
struct SlidingTitle: View {
    var text: String
    var size: CGFloat
    var direction: Int
    var center = false
    var body: some View {
        ZStack(alignment: center ? .center : .leading) {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2.5, y: 2)        // web: text-shadow 0 2px 5px rgba(0,0,0,.5)
                .lineLimit(1)
                .id(text)
                .transition(.asymmetric(insertion: .move(edge: direction >= 0 ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: direction >= 0 ? .leading : .trailing).combined(with: .opacity)))
        }
        .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
        .clipped()
        .animation(Theme.ease, value: text)
    }
}

struct TransportButton: View {
    enum Kind { case prev, play, next }
    var kind: Kind
    var size: CGFloat
    @State private var held = false
    private var player: Player { .shared }
    var body: some View {
        Button {
            if held { held = false; return }                               // that was a hold (shuffle), not a tap
            Haptics.light()
            switch kind { case .prev: player.previous(); case .play: player.toggle(); case .next: player.next() }
        } label: {
            ZStack {
                switch kind {
                case .prev: Image(systemName: "backward.end.fill")
                case .next: Image(systemName: "forward.end.fill")
                case .play:
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: player.isPlaying ? 0 : size * 0.025)
                }
            }
            .font(.system(size: kind == .play ? size * 0.34 : size * 0.3, weight: .bold))
            .foregroundStyle(.white)
        }
        .buttonStyle(RoundButtonStyle(size: size))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
            if kind == .play { held = true; player.toggleShuffle() }       // hold Play = shuffle, as in the web player
        })
    }
}

/// The progress bar: drag the dot; it only seeks when you let go (seeking while dragging broke streaming on the web).
struct Scrubber: View {
    var height: CGFloat
    var thumb: CGFloat = 14
    private var player: Player { .shared }
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let d = max(player.duration, 0.001)
            let p = min(1, max(0, (player.scrubbing ?? player.time) / d))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.w(0.15)).frame(height: height)
                Capsule().fill(Color.w(0.85)).frame(width: max(0, g.size.width * p), height: height)
                Circle().fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .scaleEffect(dragging ? 1.25 : 1)
                    .offset(x: g.size.width * p - thumb / 2)
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

/// + Songs on the left, Queue · Library · Artists on the right with the sliding pill.
struct Footer: View {
    @Namespace private var pillNS
    private var ui: UIState { .shared }

    var body: some View {
        HStack(spacing: 0) {
            Button { Haptics.light(); ui.importing = true } label: {
                Text("+ SONGS").font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(Color.w(0.7))
                    .lineLimit(1).fixedSize()
                    .frame(height: 34).contentShape(Rectangle())
            }
            .buttonStyle(PopStyle(deep: 0.88))
            Spacer()
            HStack(spacing: 4) {
                tab(.queue, "QUEUE")
                tab(.library, "LIBRARY")
                tab(.artists, "ARTISTS")
            }
        }
        .padding(.horizontal, 10)
    }

    private func tab(_ t: DrawerTab, _ title: String) -> some View {
        let on = ui.tab == t
        return Button { ui.open(t) } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(on ? Color.white : Color.w(0.4))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10)
                .shadow(color: on ? Color.w(0.3) : .clear, radius: 5)
                .frame(height: 28)
                .background {
                    if on {
                        TabPill().matchedGeometryEffect(id: "pill", in: pillNS)
                    }
                }
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PopStyle(deep: 0.88))
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: ui.tab)
    }
}

/// A song's cover with its coloured glow behind it (a blurred copy of the art, as the web player's bloom).
struct CoverArt: View {
    var track: Track?
    var size: CGFloat
    var radius: CGFloat
    var glow = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if glow, let t = track {
                CoverImage(path: t.path, px: 120, placeholder: AnyView(Color.clear))
                    .frame(width: size, height: size)
                    .blur(radius: size * 0.28)
                    .opacity(0.75)
                    .scaleEffect(1.18)
                    .allowsHitTesting(false)
            }
            CoverImage(path: track?.path, px: Int(size * 3), placeholder: AnyView(NotesPlaceholder()))
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.w(0.35), .w(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: size * 0.12, y: size * 0.06)
                .id(track?.path)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .frame(width: size, height: size)
        .animation(Theme.ease, value: track?.path)
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
            .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
    }
}
