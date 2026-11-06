import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The drawer under the footer: Queue, Library or Artists. It grows with what's in it, up to the room on screen.
struct DrawerView: View {
    var tab: DrawerTab
    var room: CGFloat
    @State private var contentHeight: CGFloat = 0
    @State private var backHeight: CGFloat = 0
    @State private var pos = ScrollPosition(edge: .top)
    private static let offsets = OffsetBox()
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
            .animation(Theme.ease.slowed)
        let outT = AnyTransition.modifier(active: SongSwap(dx: -d * 12, dy: d == 0 ? -4 : 0, fade: true, blur: 0), identity: SongSwap(dx: 0, dy: 0, fade: false, blur: 0))
            .animation(Theme.easeN.slowed)
        let back = backTitle
        VStack(spacing: 0) {
        // web: the Back button sits outside the scrolling list (#playlist-wrapper / #artist-wrapper), so it stays at the
        // top however far down you've scrolled
        ZStack(alignment: .topLeading) {
            if let back {
                BackButton(title: back)
                    .id(viewKey)
                    .transition(.asymmetric(insertion: inT, removal: outT))
            }
        }
        .padding(.horizontal, Theme.panelPad)
        .padding(.top, back == nil ? 0 : 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { backHeight = $0 }
        ScrollViewReader { sv in
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
            .padding(.top, back == nil ? 14 : 0)                                // web #view-host: padding-top 14px
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollDisabled(UIState.shared.tileDragging)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 40), max(40, room - (back == nil ? 0 : backHeight))))
        // web renderQueue(true): opening the Queue shows Now Playing at the top, the history scrolled away above it
        .scrollPosition($pos)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in Self.offsets.cur = y }
        // web: a page you open starts at its top (renderPlaylist + scrollTop = 0); Back, or coming back to a tab, finds the
        // page where you left it (albumOrigin.scroll, rememberTab)
        .onChange(of: viewKey) { old, new in
            Self.offsets.at[old] = Self.offsets.cur
            if tab == .queue { toNow(sv); return }                                  // web renderQueue(true)
            let y = ui.navDir > 0 ? 0 : (Self.offsets.at[new] ?? 0)
            if ui.navDir > 0 { Self.offsets.at[new] = nil }
            Self.offsets.cur = y
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { pos.scrollTo(y: y) }
            DispatchQueue.main.async { withTransaction(tr) { pos.scrollTo(y: y) } }      // again once the new page is laid out
        }
        .onAppear { if tab == .queue { toNow(sv) } }
        }
        }
        .anim(Theme.ease, value: contentHeight)                       // web: #view-host height, 400 ms ease
    }

    /// web renderQueue(true): Now Playing at the top, History above it. Done once the new page has been laid out.
    private func toNow(_ sv: ScrollViewProxy) {
        var tr = Transaction(); tr.disablesAnimations = true
        for d in [0.0, 0.05, 0.2, 0.45, 0.6] {                       // the drawer grows for 400 ms: again once it has
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { withTransaction(tr) { sv.scrollTo("q-now", anchor: .top) } }
        }
    }

    /// The page's Back label (nil on a tab's first page): the same words the pages used to show at their top.
    private var backTitle: String? {
        switch tab {
        case .queue: return nil
        case .library:
            switch ui.libraryPath.last {
            case nil: return nil
            case .album?, .playlist?, .allTracks?: return "Back to Library"
            default: return "Back"
            }
        case .artists:
            if ui.artistsPath.isEmpty { return nil }
            return ui.artistsPath.count <= 1 ? "Back to Artists" : "Back"
        }
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
    var spot: ReorderSpot? = nil                 // in a list you can reorder: hold and move
    var label: String? = nil                     // an album page's "4. Title" (the release's numbering)
    var sub: String? = nil                       // "Artist · Live"
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
    @State private var width: CGFloat = 0
    @State private var place = FrameBox()         // where the row is on screen (for the menu); kept out of SwiftUI's sight so scrolling doesn't redraw the row
    private var player: Player { .shared }

    struct Stage { var min: CGFloat; var f: CGFloat; var label: String; var icon: String; var tone: Color }
    static let next = Stage(min: 64, f: 0.2, label: "Play next", icon: SVGIcon.qNext, tone: Color(red: 88 / 255, green: 196 / 255, blue: 178 / 255))
    static let last = Stage(min: 170, f: 0.52, label: "Play last", icon: SVGIcon.qLast, tone: Color(red: 126 / 255, green: 146 / 255, blue: 1))
    static let remove = Stage(min: 90, f: 0.35, label: "Remove", icon: SVGIcon.trash, tone: Color(red: 1, green: 99 / 255, blue: 99 / 255))
    static let more = Stage(min: 64, f: 0.2, label: "More", icon: SVGIcon.more, tone: Color(red: 160 / 255, green: 170 / 255, blue: 190 / 255))

    private var isLifted: Bool { spot.map { $0.r.me == $0.i && !$0.r.landing } ?? false }

    private var stages: [Stage] {
        if dir > 0 { return [Self.more] }
        switch leftAction {
        case .queue: return [Self.next, Self.last]
        case .remove: return [Self.remove]
        case .none: return []
        }
    }
    private func at(_ st: Stage) -> CGFloat { max(st.min, st.f * width) }

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
                    .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: 6, y: 4)
                    .scaleEffect(isLifted ? 1.08 : 1)                                       // web .q-row.lifted .item-art
                    .anim(Theme.easeN, value: isLifted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label ?? ((number.map { "\($0). " } ?? "") + track.title))          // web: up to 2 lines, line-height 1.25
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                        .lineSpacing(13 * 1.25 - UIFont.systemFont(ofSize: 13, weight: .medium).lineHeight)
                    Text(sub ?? track.shownArtist).font(.system(size: 11)).foregroundStyle(Color.w(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(shape.fill(Color.w(active ? 0.12 : 0)))
            .overlay(shape.strokeBorder(Color.w(active ? 0.1 : 0), lineWidth: 1))
            .contentShape(shape)
            .opacity(dim ? 0.5 : 1)
            .offset(x: out ? -width : dir * d)
        }
        .clipShape(shape)
        // web .queue-container.dragging .q-row:not(.lifted): every other row dims while one is lifted
        .opacity(UIState.shared.tileDragging && !isLifted ? 0.5 : 1)
        .anim(Theme.easeN, value: UIState.shared.tileDragging)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { place.r = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !out { rowH = $0 } }
        .frame(height: out ? (gone ? 0 : rowH) : nil, alignment: .top)
        .opacity(gone ? 0 : 1)
        .clipped()
        .onTapGesture { Haptics.light(); tap() }
        .modifier(HoldToReorder(spot: spot, cover: track.path, menu: openMenu))
        .gesture(HorizontalPan(changed: moved, ended: { _, _ in released() }))
        .onAppear {                                                     // the build's screenshots: hold the first row mid-swipe
            if let x = TestScreens.swipe, number != nil, !TestScreens.swipeShown { TestScreens.swipeShown = true; moved(x) }
            else if case .queue = leftAction, Self.hintDue { hint() }
        }
    }

    /// web .sw-bg / .sw-lab: the strip behind the row, as wide as the row has slid, in the stage's colour
    private var strip: some View {
        let st = stages.isEmpty ? nil : stages[max(0, k - 1)]
        let left = dir < 0
        let label = HStack(spacing: 6) {
            if !left { SVGIcon(d: done != nil ? SVGIcon.check : st?.icon ?? "").fill(.white).frame(width: 18, height: 18) }
            Text(done ?? st?.label ?? "").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .opacity(done != nil || d >= labW - 2 ? 1 : 0).anim(Theme.easeQ, value: d >= labW - 2)
            if left { SVGIcon(d: done != nil ? SVGIcon.check : st?.icon ?? "").fill(.white).frame(width: 18, height: 18) }
        }
        .padding(.horizontal, 14)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labW = $0 }
        .opacity(k > 0 || done != nil ? 1 : min(0.5, d / 90))
        .modifier(KFEffect(p: pop, scale: KF(stops: [(0, 0.82), (0.6, 1.07), (1, 1)], each: .ease)))
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(k > 0 || done != nil ? (st?.tone ?? .white).opacity(0.34) : Color.w(0.07))
            .anim(Theme.easeQ, value: k)
            .overlay(alignment: left ? .trailing : .leading) { label }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: out ? width : d)
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

    /// web swipeHint: once ever, the first song you see in a list peeks left to show what's behind it
    @MainActor static var hintDue: Bool { Store.shared["hintSwipe"] != "1" && !hintTaken }
    @MainActor static var hintTaken = false
    private func hint() {
        Self.hintTaken = true
        Store.shared["hintSwipe"] = "1"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { dir = -1; k = 1 }
            withAnimation(Theme.ease) { d = 76 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { back() }
            AppModel.shared.toast("Swipe a song left to queue it, right for more")
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
        UIState.shared.menu = UIState.MenuState(kind: .song(track, inPlaylist: inPlaylist), anchor: place.r)
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
    @State private var rq = Reorder()            // your queue
    @State private var ru = Reorder()            // the rest of the album
    private var player: Player { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        content
            .onAppear {                                                         // the build's screenshots: a song held up mid-move
                guard TestScreens.lift else { return }
                TestScreens.lift = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ru.begin(0, count: min(30, player.contextUpcoming().count)); ru.moved(40) }
            }
    }

    @ViewBuilder private var content: some View {
        // a plain stack (at most 30 + your queue + 20 rows): every row exists, so the drawer can scroll to Now Playing
        VStack(alignment: .leading, spacing: 0) {
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
                    .id("q-now")                                  // web: the Queue opens scrolled to here (history above it)
                SongRow(track: cur, active: true, leftAction: .none) {}
                if !player.queue.isEmpty {
                    SectionLabel(text: "Queue · \(player.queue.count)", button: "Clear") { player.clearQueue() }
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { i, k in
                        if let t = model.byKey[k] {
                            SongRow(track: t, leftAction: .remove({ player.removeFromQueue(at: IndexSet(integer: i)) }),
                                    spot: ReorderSpot(r: rq, i: i, count: player.queue.count) { f, to in
                                        player.moveQueue(from: IndexSet(integer: f), to: to > f ? to + 1 : to) }) { player.playFromQueue(index: i) }
                        }
                    }
                }
                if let ctx {
                    let up = player.contextUpcoming()
                    let n = showAll ? up.count : min(up.count, 20)            // web CTX_ROWS
                    SectionLabel(text: "\(player.queue.isEmpty ? "Next" : "Then") from \(ctx.name)\(player.shuffle ? " · Shuffled" : "")")
                    ForEach(Array(up.prefix(n).enumerated()), id: \.offset) { i, k in
                        if let t = model.byKey[k] {
                            SongRow(track: t, leftAction: .remove({ player.removeUpcoming(k) }),
                                    spot: ReorderSpot(r: ru, i: i, count: n) { f, to in
                                        player.moveUpcoming(from: IndexSet(integer: f), to: to > f ? to + 1 : to) }) { player.playFromContext(k) }
                        }
                    }
                    if up.count > n {
                        // web .q-more.q-link
                        Button { showAll = true } label: {
                            Text("Show all \(up.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.6))
                                .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 4).contentShape(Rectangle())
                        }
                        .buttonStyle(PopStyle())
                    } else if !player.contextList().isEmpty {
                        note(player.repeatMode == .off ? (up.isEmpty ? "\(ctx.name) stops after this song" : "Then \(ctx.name) stops")
                             : (up.isEmpty ? "\(ctx.name) starts again from the top" : "Then \(ctx.name) starts again"))
                    }
                } else if player.queue.isEmpty {
                    empty("Nothing after this song. Swipe a song left in Library to queue it.")
                }
            } else {
                empty("Nothing playing yet.")
            }
        }
    }

    /// web .q-empty: 12 pt, 40 % white, centred, 14 pt above and below
    private func empty(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(Color.w(0.4)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 12)
    }

    /// web .q-more
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
            case .catalog(let c): CatalogPage(cat: c)
            }
        }
        // the slide between pages is done by DrawerView
    }
}

/// Library grid: All Tracks, your playlists, then albums (web .albums-grid). Hold a tile to lift it and move it
/// (the others jiggle, each gets a hide badge, Done replaces the tabs); hold and let go without moving: its menu.
struct TileGrid: View {
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }
    @State private var keys: [String]? = nil              // the order while a tile is being moved
    @State private var lifted: String?
    @State private var grab: CGSize = .zero              // where the finger holds the tile, from its slot's corner
    @State private var finger: CGPoint = .zero
    @State private var start: CGPoint = .zero
    @State private var box = SlotBox()                    // each tile's slot on screen, out of SwiftUI's sight while scrolling
    @State private var slotTick = 0                      // …except while a tile is held, when the lifted one must follow its slot
    private var slots: [String: CGRect] { box.s }
    @State private var wasEditing = false
    @State private var pending = false
    @State private var going: Set<String> = []           // tiles shrinking away (hidden)
    @State private var jig: [String: Int] = [:]          // web --j: each tile's own jiggle phase

    var body: some View {
        // web .albums-grid: three equal columns, 14 pt apart, 10 pt of padding all round
        let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top), count: ui.land ? 5 : 3)   // web: five smaller covers a row on a phone on its side
        let byKey = Dictionary(model.tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let list = (keys ?? model.tiles.map(\.key)).compactMap { byKey[$0] }
        let _ = slotTick
        LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
            ForEach(list) { tile in
                let k = tile.key, up = lifted == k
                TileView(tile: tile, editing: ui.editing, lifted: up, j: jig[k] ?? 0, going: going.contains(k),
                         hold: ui.editing ? 0.14 : 0.42,
                         onLift: { p in lift(k, p) }, onMove: { s0, p in move(k, s0, p) }, onDrop: { f in drop(k, f) }, badge: { remove(tile) })
                    .offset(up ? liftOffset(k) : .zero)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.s[k] = $0; if lifted != nil { slotTick &+= 1 } }   // the slot, not the lifted tile
                    .zIndex(up ? 20 : 0)
            }
        }
        .padding(10)
        .coordinateSpace(name: "grid")
        .contentShape(Rectangle())
        .onTapGesture { if ui.editing { setEdit(false) } }                       // web: a tap on the empty grid ends editing
        .onAppear { for t in model.tiles where jig[t.key] == nil { jig[t.key] = Int.random(in: 0..<6) } }
        .onChange(of: model.tiles.map(\.key)) { _, ks in for k in ks where jig[k] == nil { jig[k] = Int.random(in: 0..<6) } }
        .onDisappear { setEdit(false) }
    }

    private func setEdit(_ on: Bool) { if ui.editing != on { withAnimation(Theme.easeN) { ui.editing = on } } }

    private func liftOffset(_ k: String) -> CGSize {
        guard let f = slots[k] else { return .zero }
        return CGSize(width: finger.x - grab.width - f.minX, height: finger.y - grab.height - f.minY)
    }

    /// web attachDrag: after the hold the tile lifts and follows the finger; over the middle of another tile they swap
    private func lift(_ k: String, _ at: CGPoint?) {
        guard lifted == nil else { return }
        wasEditing = ui.editing
        setEdit(true)
        let f = slots[k] ?? .zero
        let p = at ?? CGPoint(x: f.midX, y: f.midY)
        pending = at == nil
        start = p; finger = p
        grab = CGSize(width: p.x - f.minX, height: p.y - f.minY)
        keys = model.tiles.map(\.key)
        ui.tileDragging = true
        Haptics.light()
        withAnimation(Theme.easeN) { lifted = k }
    }

    private func move(_ k: String, _ s0: CGPoint, _ p: CGPoint) {
        guard lifted == k else { return }
        if pending, let f = slots[k] {                                           // the hold ended before the finger moved
            pending = false; start = s0; grab = CGSize(width: s0.x - f.minX, height: s0.y - f.minY)
        }
        withAnimation(.interactiveSpring(response: 0.12, dampingFraction: 0.9)) { finger = p }
        swapIfOver(k, p)
    }

    private func swapIfOver(_ k: String, _ p: CGPoint) {
        guard var ks = keys, let from = ks.firstIndex(of: k) else { return }
        // only the middle of a tile triggers a swap (no flapping)
        guard let hit = slots.first(where: { $0.key != k && ks.contains($0.key) && $0.value.insetBy(dx: $0.value.width * 0.2, dy: $0.value.height * 0.2).contains(p) }),
              let to = ks.firstIndex(of: hit.key), to != from else { return }
        Haptics.select()
        ks.remove(at: from); ks.insert(k, at: to)
        withAnimation(Theme.ease) { keys = ks }
    }

    private func drop(_ k: String, _ frame: CGRect) {
        guard lifted == k else { return }
        let moved = hypot(finger.x - start.x, finger.y - start.y) >= 10 || keys != model.tiles.map(\.key)
        if let ks = keys, ks != model.tiles.map(\.key) { model.saveTileOrder(ks) }
        withAnimation(Theme.easeN) { lifted = nil }
        ui.tileDragging = false
        keys = nil
        if !wasEditing && !moved {                                             // held and let go without moving: the tile's menu
            setEdit(false)
            if let t = model.tiles.first(where: { $0.key == k }) {
                Haptics.medium(); ui.menu = UIState.MenuState(kind: .tile(t), anchor: frame)
            }
        }
    }

    /// web del-badge: a playlist is deleted; an album shrinks away and is hidden
    private func remove(_ t: Tile) {
        Haptics.light()
        switch t {
        case .all: break
        case .playlist(let p): model.deletePlaylist(p.id)
        case .album(let a):
            withAnimation(Theme.easeN) { _ = going.insert(a.name) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(Theme.ease) { model.hideAlbum(a.name) }
                going.remove(a.name)
                if !model.tiles.contains(where: { if case .album = $0 { return true }; return false }) { setEdit(false) }
            }
        }
    }
}

struct TileView: View {
    var tile: Tile
    var editing = false
    var lifted = false
    var j = 0
    var going = false
    var hold: Double = 0.42
    var onLift: (CGPoint?) -> Void = { _ in }
    var onMove: (CGPoint, CGPoint) -> Void = { _, _ in }
    var onDrop: (CGRect) -> Void = { _ in }
    var badge: () -> Void = {}
    @State private var spot = FrameBox()
    private var pressed: Bool { false }
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 8) {
                // web .album-card: the cover with the glass edge (::before rim, ::after light), shadow 0 8px 15px .3;
                // pressed, the cover (not the name) dips to 96 % (250 ms); lifted, 108 % with a deep shadow
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { cover }
                    .clipShape(shape)
                    .overlay { TileGlass(shape: shape) }
                    .softShadow(radius: lifted ? 17 : 7.5, y: lifted ? 20 : 8, opacity: lifted ? 0.55 : 0.3)
                    .modifier(Jiggle(on: editing && !lifted, j: j))
                    .overlay(alignment: .topLeading) { if case .all = tile {} else { DelBadge(on: editing && !lifted, j: j, action: badge) } }
                    .scaleEffect(lifted ? 1.08 : pressed ? 0.96 : 1)
                    .anim(Theme.easeN, value: pressed)
                    .anim(Theme.easeN, value: lifted)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
        }
        .scaleEffect(going ? 0.7 : 1).opacity(going ? 0 : 1)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { spot.r = $0 }
        .onTapGesture {
            if editing { return }                                               // web: while editing, a tap does nothing
            Haptics.light()
            switch tile {
            case .all: ui.push(.allTracks)
            case .playlist(let p): ui.push(.playlist(p.id))
            case .album(let a): ui.push(.album(a.name))
            }
        }
        .gesture(HoldPan(duration: hold, began: { p in
            onLift(p)
        }, changed: { p in
            onMove(p, p)
        }, ended: { onDrop(spot.r) }))
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
    @State private var side: CGSize = .zero
    private var g: Glow { .shared }
    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { s in
                if abs(s.width - side.width) > 0.5 || abs(s.height - side.height) > 0.5 { side = s }
            }
            .overlay {
                // drawn once per size and cover colours, then reused by every tile (the live version shaded its
                // circular rim on the CPU for each tile, every time a grid appeared or faded)
                if side.width > 1, let im = art { Image(uiImage: im).resizable() }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var art: UIImage? {
        let w = side.width.rounded(), h = side.height.rounded(), c1 = g.c1, c2 = g.c2, sh = shape
        let key = "tg|\(w)|\(h)|\(ObjectIdentifier(S.self).hashValue)|\(Int(c1.r)),\(Int(c1.g)),\(Int(c1.b))|\(Int(c2.r)),\(Int(c2.g)),\(Int(c2.b))"
        return PerfArt.image(key) { AnyView(TileGlassLive(shape: sh, lc: c1.color, lc2: c2.color).frame(width: w, height: h)) }
    }
}

/// The tile glass itself (drawn into TileGlass's cached picture).
private struct TileGlassLive<S: InsettableShape>: View {
    var shape: S
    var lc: Color
    var lc2: Color
    var body: some View {
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
    var icon: String                                     // web: the list icon for All Tracks, the note otherwise
    var remote: String? = nil                            // an album on an artist's page: its cover from Deezer
    var enabled = true                                   // web .alb-play[disabled]: nothing of yours to play
    var play: () -> Void
    static let note = "M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"
    static let list = "M4 6h16v2H4zm0 5h16v2H4zm0 5h10v2H4z"
    var body: some View {
        // web .alb-head: 56 pt art (1 pt border inside, radius 10), 15 pt name up to 2 lines, 12 pt line 3 pt under it,
        // a 36 pt round Play with a 15 pt triangle
        let ph = AnyView(ZStack { Color.w(0.06); SVGIcon(d: icon).fill(Color.w(0.45)).frame(width: 22, height: 22) })
        HStack(spacing: 12) {
            Group {
                if let remote, let u = URL(string: remote) {
                    AsyncImage(url: u) { r in if let img = r.image { img.resizable().scaledToFill() } else { Color.w(0.06) } }
                } else {
                    CoverImage(path: coverPath, dataURL: coverData, px: 200, placeholder: ph)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.w(0.12), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(2).lineSpacing(1)
                Text(sub).font(.system(size: 12)).foregroundStyle(Color.w(0.55)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { Haptics.light(); play() }) {
                SVGIcon(d: "M8 5v14l11-7z").fill(.white).frame(width: 15, height: 15).offset(x: 2)
            }
            .buttonStyle(RoundButtonStyle(size: 36))
            .opacity(enabled ? 1 : 0.35)
            .allowsHitTesting(enabled)
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 10)
    }

    /// web albumHead: the album's artist when there's one (its main name), "Various artists" when there are several
    static func who(_ own: [Track]) -> String {
        var seen: [String] = []
        for t in own {
            let a = Artists.main(t.albumArtist.isEmpty ? t.artist : t.albumArtist)
            if !a.isEmpty && a != "Unknown Artist" && !seen.contains(a) { seen.append(a) }
        }
        return seen.count == 1 ? seen[0] : seen.isEmpty ? "" : "Various artists"
    }
    static func count(_ n: Int) -> String { n == 1 ? "1 song" : "\(n) songs" }
}

struct AlbumPage: View {
    var name: String
    var back: String
    private var model: AppModel { .shared }
    private var player: Player { .shared }
    var body: some View {
        let R = Releases.shared
        VStack(spacing: 0) {
            if let a = model.album(named: name) {
                let entries = R.albumEntries(name)
                let own = entries.compactMap(\.track)
                let list = R.editions(name), view = R.edView(name)
                // web albumHead: an album with editions shows the year of the one shown (Mixed: the original)
                let ed = list.map { view ?? $0[0] }
                let year = (ed.map(\.year).flatMap { Int($0) }) ?? (own.compactMap { Int($0.year) }.max() ?? 0)
                let sub = [ListHeader.who(own), year > 0 ? "\(year)" : "", ListHeader.count(own.count)].filter { !$0.isEmpty }.joined(separator: " · ")
                ListHeader(title: a.name, sub: sub, coverPath: a.coverPath, coverData: model.tileCovers[model.coverKey(a.name)], icon: ListHeader.note, enabled: !own.isEmpty) {
                    if !own.isEmpty { player.playAll(own, name: a.name) }
                }
                if let list, list.count > 1 { EditionSwitch(name: name, list: list, view: view) }
                EntryRows(entries: entries, context: own, name: a.name, cover: .path(a.coverPath, model.tileCovers[model.coverKey(a.name)]),
                          ask: AskCtx(artist: Artists.main(a.artist), album: a.name), albumName: name)
            } else {
                Text("This album isn't on this phone any more.").font(.system(size: 12)).foregroundStyle(Color.w(0.5)).padding()
            }
        }
    }
}

/// An album on an artist's page: its songs from Deezer, the ones you don't have in grey (web openCatalogAlbum).
struct CatalogPage: View {
    var cat: CatRef
    @State private var list: [RelTrack]?
    @State private var failed = false
    private var player: Player { .shared }
    var body: some View {
        let R = Releases.shared
        let entries = R.catEntries(cat, own: nil, list: list)
        let own = entries.compactMap(\.track)
        VStack(spacing: 0) {
            let sub = [cat.artist, cat.year, ListHeader.count(own.count)].filter { !$0.isEmpty }.joined(separator: " · ")
            ListHeader(title: cat.title, sub: sub, coverPath: nil, coverData: nil, icon: ListHeader.note, remote: cat.cover, enabled: !own.isEmpty) {
                if !own.isEmpty { player.playAll(own, name: cat.title) }
            }
            if list == nil {
                Text(failed ? "Couldn\u{2019}t load this album\u{2019}s songs." : "Loading tracks\u{2026}")
                    .font(.system(size: 12)).foregroundStyle(Color.w(0.45)).frame(maxWidth: .infinity).padding(16)
            } else {
                if R.resolving && own.isEmpty {
                    Text("Checking your library\u{2026}").font(.system(size: 12)).foregroundStyle(Color.w(0.45)).padding(.horizontal, 12).padding(.vertical, 6)
                }
                EntryRows(entries: entries, context: own, name: cat.title, cover: .url(cat.cover),
                          ask: AskCtx(artist: cat.artist, album: R.ownedAlbum(cat.id) ?? cat.title), albumName: nil)
            }
        }
        .task(id: cat.id) {
            list = await R.trackList(cat.id)
            failed = list == nil
        }
    }
}

/// The catalog album's header: its cover from Deezer, name, artist · year · songs, Play (web .alb-head).
struct RemoteCover: View {
    var url: String?
    var body: some View {
        if let u = url.flatMap(URL.init(string:)) {
            AsyncImage(url: u) { ph in if let img = ph.image { img.resizable().scaledToFill() } else { Color.w(0.06) } }
        } else { IconTile(system: "music.note", size: 20) }
    }
}

/// Who and which album the grey songs belong to (web albumCtx).
struct AskCtx { var artist: String; var album: String }

enum RowCover { case path(String?, String?), url(String?) }

/// Mixed · Original · Deluxe Edition… under an album's name (web .ed-sw).
struct EditionSwitch: View {
    var name: String
    var list: [Edition]
    var view: Edition?
    var body: some View {
        let R = Releases.shared
        let items = [("mix", "Mixed")] + list.enumerated().map { ("\($0.element.id)", R.edLabel($0.element, $0.offset, list)) }
        let on = view.map { "\($0.id)" } ?? "mix"
        ScrollViewReader { sv in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.0) { item in
                        let id = item.0, label = item.1
                        Button { if id != on { withAnimation(Theme.easeN) { R.pickEdition(name, id) } } } label: {
                            Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(id == on ? Color(white: 0.07) : Color.w(0.75))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(id == on ? Color.w(0.88) : Color.w(0.06)))
                                .overlay(Capsule().strokeBorder(id == on ? Color.clear : Color.w(0.14), lineWidth: 1))
                        }
                        .buttonStyle(PopStyle())
                        .id(id)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
            }
            .onAppear { sv.scrollTo(on, anchor: .leading) }
        }
    }
}

/// An album page's rows: your songs (they play), the ones you don't have in grey with a + (opens your bot's chat with the
/// song typed in), disc / edition headings, and "Show N more from other editions" (web renderPlaylist).
struct EntryRows: View {
    var entries: [AlbumEntry]
    var context: [Track]
    var name: String
    var cover: RowCover
    var ask: AskCtx
    var albumName: String?
    private var player: Player { .shared }
    var body: some View {
        let multi = Set(entries.filter { $0.disc < 50 }.map { max(1, $0.disc) }).count > 1
        let canAsk = !Telegram.shared.key.isEmpty
        LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                let hd = head(e, multi), prev = i > 0 ? lastHead(i, multi) : nil
                if let hd, !hd.isEmpty, hd != prev {
                    Text(hd.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                }
                if let more = e.more {
                    Button { if let n = albumName { withAnimation(Theme.ease) { Releases.shared.toggleOpen(n) } } } label: {
                        Text(more < 0 ? "Hide the songs you don\u{2019}t have" : "Show \(more) more from other editions")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.w(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.w(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(PopStyle())
                    .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
                } else if let t = e.track {
                    let v = Editions.verOf(e.title)
                    SongRow(track: t, active: player.currentKey == t.key, label: (e.num > 0 ? "\(e.num). " : "") + e.title,
                            sub: t.shownArtist + (v.isEmpty ? "" : " · " + v)) {
                        player.start(context, at: t, name: name)
                    }
                } else {
                    GreyRow(label: (e.num > 0 ? "\(e.num). " : "") + e.title, cover: cover,
                            ask: canAsk ? { Telegram.shared.askBot(artist: ask.artist, title: e.want.isEmpty ? e.title : e.want) } : nil)
                }
            }
        }
    }
    /// web headOf
    private func head(_ e: AlbumEntry, _ multi: Bool) -> String? {
        if let h = e.head { return h }
        if e.disc >= 99 { return "Also in your files" }
        if e.disc == 97 { return "Extra copies" }
        if e.disc >= 50 { return "" }
        return multi ? "Disc \(max(1, e.disc))" : ""
    }
    /// The heading shown last before row i ("Show more" rows don't change it).
    private func lastHead(_ i: Int, _ multi: Bool) -> String? {
        var j = i - 1
        while j >= 0 { if entries[j].more == nil { return head(entries[j], multi) }; j -= 1 }
        return nil
    }
}

/// A song that isn't in your library: faded cover and text, "🔒 Not in your library", and a + (web .playlist-item.missing).
struct GreyRow: View {
    var label: String
    var cover: RowCover
    var ask: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    switch cover {
                    case .path(let p, let d): CoverImage(path: p, dataURL: d, px: 120, placeholder: AnyView(Color.w(0.05)))
                    case .url(let u): RemoteCover(url: u)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.w(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                        .lineSpacing(13 * 1.25 - UIFont.systemFont(ofSize: 13, weight: .medium).lineHeight)
                    Text("\u{1F512} Not in your library").font(.system(size: 11)).foregroundStyle(Color.w(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(0.35)
            if let ask {
                Button { Haptics.light(); ask() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.w(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.w(0.07)))
                        .overlay(Circle().strokeBorder(Color.w(0.2), lineWidth: 1))
                }
                .buttonStyle(PopStyle())
                .accessibilityLabel("Get this song")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

struct PlaylistPage: View {
    var id: String
    @State private var rp = Reorder()
    private var model: AppModel { .shared }
    private var player: Player { .shared }
    var body: some View {
        VStack(spacing: 0) {
            if let p = model.playlist(id) {
                let ts = model.tracks(of: p)
                ListHeader(title: p.name, sub: "Playlist · " + ListHeader.count(ts.count), coverPath: ts.first?.path,
                           coverData: model.tileCovers["pl:" + p.id], icon: ListHeader.note, enabled: !ts.isEmpty) {
                    player.playAll(ts, name: p.name)
                }
                if ts.isEmpty {
                    Text("No songs here yet. Hold a song in Library, or swipe it right, to add it.")       // web .artist-note
                        .font(.system(size: 12)).foregroundStyle(Color.w(0.45)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(16)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(ts.enumerated()), id: \.element.id) { i, t in
                        SongRow(track: t, active: player.currentKey == t.key, inPlaylist: p.id,
                                spot: ReorderSpot(r: rp, i: i, count: ts.count) { f, to in
                                    model.movePlaylistSongs(p.id, from: IndexSet(integer: f), to: to > f ? to + 1 : to) }) { player.start(ts, at: t, name: p.name) }
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
            ListHeader(title: "All Tracks", sub: ListHeader.count(model.tracks.count), coverPath: nil,
                       coverData: nil, icon: ListHeader.list, enabled: !model.tracks.isEmpty) {
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

/// web @keyframes jig: ±0.9° back and forth every .34 s (ease-in-out, alternate), each tile at its own phase
struct Jiggle: ViewModifier {
    var on: Bool
    var j: Int
    func body(content: Content) -> some View {
        if on {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate / 0.34 + Double(j) * 0.13 / 0.34
                let c = floor(t), f0 = t - c, f = Int(c) % 2 == 0 ? f0 : 1 - f0
                content.rotationEffect(.degrees(-0.9 + 1.8 * Bezier(0.42, 0, 0.58, 1)(f)))
            }
        } else { content }
    }
}

/// web .del-badge: a small glass circle with a minus at the tile's corner, in one after another (22 ms apart)
struct DelBadge: View {
    var on: Bool
    var j: Int
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial).overlay(Circle().fill(Color.w(0.2)))
                    .overlay(Circle().strokeBorder(Color.w(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 10, height: 2)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(PopStyle())
        .offset(x: -7, y: -7)
        .scaleEffect(on ? 1 : 0.3)
        .opacity(on ? 1 : 0)
        .anim(Theme.ease.delay(on ? Double(j) * 0.022 : 0), value: on)
        .allowsHitTesting(on)
        .accessibilityLabel("Hide")
    }
}

/// A place to keep a view's position on screen without redrawing it each time it moves (it moves on every scroll frame).
final class FrameBox { var r: CGRect = .zero }
final class SlotBox { var s: [String: CGRect] = [:] }
/// Where each drawer page was scrolled to (web: every view keeps its own scrollTop), out of SwiftUI's sight.
final class OffsetBox { var cur: CGFloat = 0; var at: [String: CGFloat] = [:] }

/// The drawer's pages drawn once, unseen, soon after launch, so the first time one opens its pictures (tile glass,
/// shadows) and views already exist. Without it the first open of the Library hitched and its first frames were lost.
struct DrawerWarmUp: View {
    @State private var on = false
    private var ui: UIState { .shared }
    var body: some View {
        ZStack(alignment: .top) {
            if on {
                ZStack(alignment: .top) {
                    LibraryDrawer()
                    QueueDrawer()
                    ArtistsDrawer()
                }
                .padding(.horizontal, Theme.panelPad)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)              // after the app has shown and settled
            guard ui.tab == nil else { return }
            on = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            on = false
        }
    }
}
