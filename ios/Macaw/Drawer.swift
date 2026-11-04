import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The drawer under the footer: Queue, Library or Artists. It grows with what's in it, up to the room on screen.
struct DrawerView: View {
    var tab: DrawerTab
    var room: CGFloat
    @State private var contentHeight: CGFloat = 0
    private var ui: UIState { .shared }

    /// What the drawer shows now: a new key = a new view, which slides in (web: showOnly / .v-in).
    private var viewKey: String {
        let path = tab == .artists ? ui.artistsPath : tab == .library ? ui.libraryPath : []
        return tab.rawValue + "/" + path.map { "\($0)" }.joined(separator: "/")
    }

    var body: some View {
        let d = CGFloat(ui.navDir)
        // web: the new view comes in 18 pt from the side you went (8 pt from below on a tab switch), 400 ms ease;
        // the old one fades out 12 pt the other way (4 pt up), 250 ms
        let inT = AnyTransition.modifier(active: SongSwap(dx: d * 18, dy: d == 0 ? 8 : 0, fade: true, blur: 0), identity: SongSwap(dx: 0, dy: 0, fade: false, blur: 0))
            .animation(Theme.ease)
        let outT = AnyTransition.modifier(active: SongSwap(dx: -d * 12, dy: d == 0 ? -4 : 0, fade: true, blur: 0), identity: SongSwap(dx: 0, dy: 0, fade: false, blur: 0))
            .animation(Theme.easeN)
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .top) {
                Group {
                    switch tab {
                    case .queue: QueueDrawer()
                    case .library: LibraryDrawer()
                    case .artists: ArtistsDrawer()
                    }
                }
                .id(viewKey)
                .transition(.asymmetric(insertion: inT, removal: outT))
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.top, 14)                                                  // web #view-host: padding-top 14px
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 40), room))
        .animation(Theme.ease, value: contentHeight)                       // web: #view-host height, 400 ms ease
    }
}

// MARK: rows

/// A song row (web: .playlist-item / .q-row): cover 30, title 13, artist 11. Swipe left: Play next (further: Play
/// last), or in the Queue: remove. Swipe right or hold: the song's menu.
struct SongRow: View {
    var track: Track
    var number: Int? = nil
    var active = false
    var dim = false
    var leftAction: LeftAction = .queue
    var inPlaylist: String? = nil
    var tap: () -> Void

    enum LeftAction { case queue, remove(() -> Void), none }

    // the swipe, as the web's attachSwipe: d = how far the row has slid, dir = which way, k = the stage reached
    @State private var d: CGFloat = 0
    @State private var dir: CGFloat = -1
    @State private var k = 0
    @State private var swiping = false
    @State private var done: String?             // the confirmation shown in the strip (Plays next / Added)
    @State private var pop: Double = 1           // the label's pop (web swpop), rest = 1
    @State private var labW: CGFloat = 0
    @State private var rowH: CGFloat = 0
    @State private var out = false               // Queue: the row leaving
    @State private var gone = false              // …and its gap closing
    @State private var frame: CGRect = .zero
    private var player: Player { .shared }

    struct Stage { var min: CGFloat; var f: CGFloat; var label: String; var icon: String; var tone: Color }
    static let next = Stage(min: 64, f: 0.2, label: "Play next", icon: SVGIcon.qNext, tone: Color(red: 88 / 255, green: 196 / 255, blue: 178 / 255))
    static let last = Stage(min: 170, f: 0.52, label: "Play last", icon: SVGIcon.qLast, tone: Color(red: 126 / 255, green: 146 / 255, blue: 1))
    static let remove = Stage(min: 90, f: 0.35, label: "Remove", icon: SVGIcon.trash, tone: Color(red: 1, green: 99 / 255, blue: 99 / 255))
    static let more = Stage(min: 64, f: 0.2, label: "More", icon: SVGIcon.more, tone: Color(red: 160 / 255, green: 170 / 255, blue: 190 / 255))

    private var stages: [Stage] {
        if dir > 0 { return [Self.more] }
        switch leftAction {
        case .queue: return [Self.next, Self.last]
        case .remove: return [Self.remove]
        case .none: return []
        }
    }
    private func at(_ st: Stage) -> CGFloat { max(st.min, st.f * frame.width) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if d > 0 || out { strip }
            HStack(spacing: 10) {
                CoverImage(path: track.path, px: 120, placeholder: AnyView(Color.w(0.05)))
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(1)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.w(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text((number.map { "\($0). " } ?? "") + track.title)                      // web: up to 2 lines, line-height 1.25
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                        .lineSpacing(13 * 1.25 - UIFont.systemFont(ofSize: 13, weight: .medium).lineHeight)
                    Text(track.shownArtist).font(.system(size: 11)).foregroundStyle(Color.w(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(shape.fill(Color.w(active ? 0.12 : 0)))
            .overlay(shape.strokeBorder(Color.w(active ? 0.1 : 0), lineWidth: 1))
            .contentShape(shape)
            .opacity(dim ? 0.5 : 1)
            .offset(x: out ? -frame.width : dir * d)
        }
        .clipShape(shape)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !out { rowH = $0 } }
        .frame(height: out ? (gone ? 0 : rowH) : nil, alignment: .top)
        .opacity(gone ? 0 : 1)
        .clipped()
        .onTapGesture { Haptics.light(); tap() }
        .onLongPressGesture(minimumDuration: 0.38) { openMenu() }
        .gesture(HorizontalPan(changed: moved, ended: { _, _ in released() }))
    }

    /// web .sw-bg / .sw-lab: the strip behind the row, as wide as the row has slid, in the stage's colour
    private var strip: some View {
        let st = stages.isEmpty ? nil : stages[max(0, k - 1)]
        let left = dir < 0
        let label = HStack(spacing: 6) {
            if !left { SVGIcon(d: done != nil ? SVGIcon.check : st?.icon ?? "").fill(.white).frame(width: 18, height: 18) }
            Text(done ?? st?.label ?? "").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .opacity(done != nil || d >= labW - 2 ? 1 : 0).animation(Theme.easeQ, value: d >= labW - 2)
            if left { SVGIcon(d: done != nil ? SVGIcon.check : st?.icon ?? "").fill(.white).frame(width: 18, height: 18) }
        }
        .padding(.horizontal, 14)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labW = $0 }
        .opacity(k > 0 || done != nil ? 1 : min(0.5, d / 90))
        .modifier(KFEffect(p: pop, scale: KF(stops: [(0, 0.82), (0.6, 1.07), (1, 1)], each: .ease)))
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(k > 0 || done != nil ? (st?.tone ?? .white).opacity(0.34) : Color.w(0.07))
            .animation(Theme.easeQ, value: k)
            .overlay(alignment: left ? .trailing : .leading) { label }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: out ? frame.width : d)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left ? .trailing : .leading)
    }

    private func moved(_ t: CGFloat) {
        if out { return }
        if !swiping {
            swiping = true; done = nil
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { dir = t < 0 ? -1 : 1; k = 0 }
        }
        let st = stages
        guard let lastStage = st.last else { d = 0; return }
        var x = max(0, dir > 0 ? t : -t)
        let lim = at(lastStage) + 70
        if x > lim { x = lim + (x - lim) * 0.3 }
        var nk = 0
        for (i, s) in st.enumerated() where x >= at(s) - (k > i ? 12 : 0) { nk = i + 1 }
        if nk != k {
            Haptics.select()
            k = nk
            if nk > 0 { replay($pop, duration: 0.25) }
        }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { d = x }
    }

    private func released() {
        guard swiping else { return }
        swiping = false
        guard k > 0 else { back(); return }
        Haptics.light()
        if dir > 0 { back(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { openMenu() }; return }
        switch leftAction {
        case .queue:                                                   // web swDone: the strip confirms, then the row springs back
            player.enqueue(track, last: k == 2)
            done = k == 2 ? "Added" : "Plays next"
            replay($pop, duration: 0.25)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { back() }
        case .remove(let f):                                           // web swOut: the row leaves and the gap closes
            withAnimation(Theme.easeN) { out = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(Theme.easeN) { gone = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                f()
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { out = false; gone = false; d = 0; k = 0 }
            }
        case .none: back()
        }
    }

    /// web swBack: the row springs back into place (the strip keeps its colour on the way)
    private func back() {
        withAnimation(Theme.ease) { d = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            if !swiping { var tr = Transaction(); tr.disablesAnimations = true; withTransaction(tr) { k = 0; done = nil } }
        }
    }

    private func openMenu() {
        Haptics.medium()
        UIState.shared.menu = UIState.MenuState(kind: .song(track, inPlaylist: inPlaylist), anchor: frame)
    }
}

/// A horizontal drag that only starts when the finger moves sideways, so the list still scrolls.
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        let t = g.translation(in: g.view).x
        switch g.state {
        case .changed: changed(t)
        case .ended, .cancelled, .failed: ended(t, g.velocity(in: g.view).x)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return false }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y) * 1.4
        }
    }
}

/// web .q-sec: 11 pt caps, 26 pt tall, 12 pt of room above (2 pt for the first one) and 4 pt below.
struct SectionLabel: View {
    var text: String
    var button: String? = nil
    var first = false
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5)).lineLimit(1)
            Spacer(minLength: 0)
            if let button, let action {
                Button(button, action: action).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.65))
                    .padding(.vertical, 4).buttonStyle(PopStyle())
            }
        }
        .frame(minHeight: 26)
        .padding(.horizontal, 12)
        .padding(.top, first ? 2 : 12).padding(.bottom, 4)
    }
}

struct BackButton: View {
    var title: String
    var body: some View {
        Button { Haptics.light(); UIState.shared.back() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left").font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.w(0.6))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Queue

struct QueueDrawer: View {
    @State private var showAll = false
    private var player: Player { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let cur = player.current {
                let hist = Array(player.history.suffix(30))
                if !hist.isEmpty {
                    SectionLabel(text: "History", button: "Clear", first: true) { player.clearHistory() }
                    ForEach(Array(hist.enumerated()), id: \.offset) { i, h in
                        if let t = model.byKey[h.key] {
                            SongRow(track: t, dim: true, leftAction: .remove({ player.removeHistory(at: player.history.count - hist.count + i) })) {
                                player.replay(t)
                            }
                        }
                    }
                }
                let ctx = player.context
                SectionLabel(text: player.nowFrom == .context && ctx != nil ? "Playing from \(ctx!.name)" : "Now Playing", first: hist.isEmpty)
                SongRow(track: cur, active: true, leftAction: .none) {}
                if !player.queue.isEmpty {
                    SectionLabel(text: "Queue · \(player.queue.count)", button: "Clear") { player.clearQueue() }
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { i, k in
                        if let t = model.byKey[k] {
                            SongRow(track: t, leftAction: .remove({ player.removeFromQueue(at: IndexSet(integer: i)) })) { player.playFromQueue(index: i) }
                        }
                    }
                }
                if let ctx {
                    let up = player.contextUpcoming()
                    let n = showAll ? up.count : min(up.count, 30)
                    SectionLabel(text: "\(player.queue.isEmpty ? "Next" : "Then") from \(ctx.name)\(player.shuffle ? " · Shuffled" : "")")
                    ForEach(Array(up.prefix(n).enumerated()), id: \.offset) { _, k in
                        if let t = model.byKey[k] {
                            SongRow(track: t, leftAction: .remove({ player.removeUpcoming(k) })) { player.playFromContext(k) }
                        }
                    }
                    if up.count > n {
                        Button("Show all \(up.count)") { showAll = true }
                            .font(.system(size: 11)).foregroundStyle(Color.w(0.55)).frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 4)
                    } else if !player.contextList().isEmpty {
                        note(player.repeatMode == .off ? (up.isEmpty ? "\(ctx.name) stops after this song" : "Then \(ctx.name) stops")
                             : (up.isEmpty ? "\(ctx.name) starts again from the top" : "Then \(ctx.name) starts again"))
                    }
                } else if player.queue.isEmpty {
                    note("Nothing after this song. Swipe a song left in Library to queue it.")
                }
            } else {
                note("Nothing playing yet.")
            }
        }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(Color.w(0.4)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 4)
    }
}

// MARK: Library

struct LibraryDrawer: View {
    private var ui: UIState { .shared }
    var body: some View {
        Group {
            switch ui.libraryPath.last {
            case nil: if ui.coverFlow { CoverFlow() } else { TileGrid() }
            case .album(let name): AlbumPage(name: name, back: "Back to Library")
            case .playlist(let id): PlaylistPage(id: id)
            case .allTracks: AllTracksPage()
            case .artist(let name): ArtistPage(name: name)
            }
        }
        // the slide between pages is done by DrawerView
    }
}

/// Library grid: All Tracks, your playlists, then albums (90 pt tiles, as in the web player). Hold for the tile's menu,
/// or hold and move to rearrange.
struct TileGrid: View {
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }
    var body: some View {
        // web .albums-grid: three equal columns, 14 pt apart, 10 pt of padding all round
        let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: 3)
        LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
            ForEach(model.tiles) { tile in
                TileView(tile: tile)
            }
        }
        .padding(10)
    }
}

struct TileView: View {
    var tile: Tile
    @State private var frame: CGRect = .zero
    @State private var pressed = false
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 8) {
                // web .album-card: the cover with the glass edge (::before rim, ::after light), shadow 0 8px 15px .3;
                // pressed, the cover (not the name) dips to 96 % (250 ms)
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { cover }
                    .clipShape(shape)
                    .overlay { TileGlass(shape: shape) }
                    .shadow(color: .black.opacity(0.3), radius: 7.5, y: 8)
                    .scaleEffect(pressed ? 0.96 : 1)
                    .animation(Theme.easeN, value: pressed)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onTapGesture {
            Haptics.light()
            switch tile {
            case .all: ui.push(.allTracks)
            case .playlist(let p): ui.push(.playlist(p.id))
            case .album(let a): ui.push(.album(a.name))
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.medium(); ui.menu = UIState.MenuState(kind: .tile(tile), anchor: frame)
        } onPressingChanged: { pressed = $0 }
    }

    private var title: String {
        switch tile {
        case .all: return model.allName
        case .playlist(let p): return p.name
        case .album(let a): return a.name
        }
    }

    @ViewBuilder private var cover: some View {
        let custom = model.tileCovers[model.coverKey(tile.key)]
        switch tile {
        case .all:
            CoverImage(path: nil, dataURL: custom, px: 300, placeholder: AnyView(IconTile(system: "folder.fill")))
        case .playlist:
            CoverImage(path: nil, dataURL: custom, px: 300, placeholder: AnyView(IconTile(system: "music.note.list")))
        case .album(let a):
            if let custom { CoverImage(path: nil, dataURL: custom, px: 300, placeholder: AnyView(IconTile(system: "music.note"))) }
            else { CoverImage(path: a.coverPath, px: 300, placeholder: AnyView(IconTile(system: "music.note"))) }
        }
    }
}

/// The glass edge every cover in a grid gets (web .album-card::before / ::after): a crisp 1 pt rim that catches the
/// light top-left, tinted by the playing cover's colours, a soft highlight and a little thickness.
struct TileGlass<S: InsettableShape>: View {
    var shape: S
    private var g: Glow { .shared }
    var body: some View {
        let lc = g.c1.color, lc2 = g.c2.color
        ZStack {
            // ::after: radial-gradient(70% 60% at 25% 12%, white .1 → 0 at 60%), linear-gradient(168deg, white .05 → 0 at 45%)
            EllipticalGradient(colors: [.w(0.1), .w(0)], center: UnitPoint(x: 0.25, y: 0.12), startRadiusFraction: 0, endRadiusFraction: 0.6 * 0.7)
            LinearGradient(stops: [.init(color: .w(0.05), location: 0), .init(color: .w(0), location: 0.45)],
                           startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 0.6, y: 1))
            // the thickness: inset 0 -12px 16px -14px black .5 (bottom), inset 0 11px 14px -14px white .35 (top)
            VStack(spacing: 0) {
                LinearGradient(colors: [.w(0.16), .w(0)], startPoint: .top, endPoint: .bottom).frame(height: 7)
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.22)], startPoint: .top, endPoint: .bottom).frame(height: 8)
            }
            // ::before: the conic rim (CSS: from -40deg, 0deg at the top)
            shape.strokeBorder(AngularGradient(stops: [
                .init(color: .w(0.42), location: 0), .init(color: lc.opacity(0.22), location: 35 / 360.0),
                .init(color: .w(0.1), location: 90 / 360.0), .init(color: .w(0.06), location: 180 / 360.0),
                .init(color: lc2.opacity(0.14), location: 200 / 360.0), .init(color: .w(0.08), location: 260 / 360.0),
                .init(color: lc.opacity(0.22), location: 325 / 360.0), .init(color: .w(0.42), location: 1)],
                center: .center, startAngle: .degrees(-130), endAngle: .degrees(230)), lineWidth: 1)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

struct IconTile: View {
    var system: String
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            Color.w(0.05)
            Image(systemName: system).font(.system(size: size, weight: .regular)).foregroundStyle(Color.w(0.4))   // web: 40 px icon, white .4
        }
    }
}

/// An album, playlist or All Tracks opened: header (cover, name, artist · year · songs, Play) and its songs.
struct ListHeader: View {
    var title: String
    var sub: String
    var coverPath: String?
    var coverData: String?
    var icon: String
    var play: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(path: coverPath, dataURL: coverData, px: 200, placeholder: AnyView(IconTile(system: icon, size: 20)))
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.w(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                Text(sub).font(.system(size: 12)).foregroundStyle(Color.w(0.55)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { Haptics.light(); play() }) {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).offset(x: 1)
            }
            .buttonStyle(RoundButtonStyle(size: 36))
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
    }
}

struct AlbumPage: View {
    var name: String
    var back: String
    private var model: AppModel { .shared }
    private var player: Player { .shared }
    var body: some View {
        VStack(spacing: 0) {
            BackButton(title: back)
            if let a = model.album(named: name) {
                let sub = [a.artist, a.year, "\(a.tracks.count) song\(a.tracks.count == 1 ? "" : "s")"].filter { !$0.isEmpty }.joined(separator: " · ")
                ListHeader(title: a.name, sub: sub, coverPath: a.coverPath, coverData: model.tileCovers[model.coverKey(a.name)], icon: "music.note") {
                    player.playAll(a.tracks, name: a.name)
                }
                LazyVStack(spacing: 0) {
                    ForEach(a.tracks) { t in
                        SongRow(track: t, number: t.num > 0 ? t.num : nil, active: player.currentKey == t.key) {
                            player.start(a.tracks, at: t, name: a.name)
                        }
                    }
                }
            } else {
                Text("This album isn't on this phone any more.").font(.system(size: 12)).foregroundStyle(Color.w(0.5)).padding()
            }
        }
    }
}

struct PlaylistPage: View {
    var id: String
    private var model: AppModel { .shared }
    private var player: Player { .shared }
    var body: some View {
        VStack(spacing: 0) {
            BackButton(title: "Back to Library")
            if let p = model.playlist(id) {
                let ts = model.tracks(of: p)
                ListHeader(title: p.name, sub: "\(ts.count) song\(ts.count == 1 ? "" : "s")", coverPath: ts.first?.path,
                           coverData: model.tileCovers["pl:" + p.id], icon: "music.note.list") {
                    player.playAll(ts, name: p.name)
                }
                if ts.isEmpty {
                    Text("Swipe a song right (or hold it) and tick this playlist to add it.")
                        .font(.system(size: 11)).foregroundStyle(Color.w(0.4)).multilineTextAlignment(.center).padding(.vertical, 10)
                }
                LazyVStack(spacing: 0) {
                    ForEach(ts) { t in
                        SongRow(track: t, active: player.currentKey == t.key, inPlaylist: p.id) { player.start(ts, at: t, name: p.name) }
                    }
                }
            }
        }
    }
}

struct AllTracksPage: View {
    @State private var search = ""
    private var model: AppModel { .shared }
    private var player: Player { .shared }
    var body: some View {
        VStack(spacing: 0) {
            BackButton(title: "Back to Library")
            ListHeader(title: model.allName, sub: "\(model.tracks.count) songs", coverPath: nil,
                       coverData: model.tileCovers[AppModel.allKey], icon: "folder.fill") {
                player.playAll(model.tracks, name: "Library", wholeLibrary: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.w(0.45))
                TextField("", text: $search, prompt: Text("Search your songs").foregroundStyle(Color.w(0.4)))
                    .font(.system(size: 13)).foregroundStyle(.white).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(Color.w(0.07)))
            .padding(.horizontal, 4).padding(.bottom, 8)
            let list = filtered
            LazyVStack(spacing: 0) {
                ForEach(list) { t in
                    SongRow(track: t, active: player.currentKey == t.key) {
                        if search.isEmpty { player.start(model.tracks, at: t, name: "Library", wholeLibrary: true) }
                        else { player.start(list, at: t, name: "Search") }
                    }
                }
            }
        }
    }
    private var filtered: [Track] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.tracks }
        return model.tracks.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) || $0.album.lowercased().contains(q) }
    }
}
