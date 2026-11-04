import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The drawer under the footer: Queue, Library or Artists. It grows with what's in it, up to the room on screen.
struct DrawerView: View {
    var tab: DrawerTab
    var room: CGFloat
    @State private var contentHeight: CGFloat = 0
    private var ui: UIState { .shared }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch tab {
                case .queue: QueueDrawer()
                case .library: LibraryDrawer()
                case .artists: ArtistsDrawer()
                }
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 40), room))
        .animation(Theme.easeN, value: contentHeight)
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

    @State private var dx: CGFloat = 0
    @State private var frame: CGRect = .zero
    private var player: Player { .shared }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            if dx < 0 { swipeBack(shape) }
            HStack(spacing: 10) {
                CoverImage(path: track.path, px: 120, placeholder: AnyView(Color.w(0.05)))
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(1)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.w(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text((number.map { "\($0). " } ?? "") + track.title)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Text(track.shownArtist).font(.system(size: 11)).foregroundStyle(Color.w(0.5)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(shape.fill(Color.w(active ? 0.12 : 0)))
            .overlay(shape.strokeBorder(Color.w(active ? 0.1 : 0), lineWidth: 1))
            .contentShape(shape)
            .opacity(dim ? 0.5 : 1)
            .offset(x: dx)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onTapGesture { Haptics.light(); tap() }
        .onLongPressGesture(minimumDuration: 0.38) { openMenu() }
        .gesture(HorizontalPan(changed: { t in
            var x = t
            if case .none = leftAction, x < 0 { x = 0 }
            dx = x < 0 ? x : min(x, 90) * 0.8
        }, ended: { t, v in
            let x = t + v * 0.08
            if x < -60 {
                switch leftAction {
                case .queue: player.enqueue(track, last: x < -170)
                case .remove(let f): f()
                case .none: break
                }
                Haptics.light()
            } else if x > 60 { openMenu() }
            withAnimation(Theme.ease) { dx = 0 }
        }))
    }

    private func swipeBack(_ shape: RoundedRectangle) -> some View {
        let isRemove: Bool = { if case .remove = leftAction { return true }; return false }()
        let label = isRemove ? "Remove" : (dx < -170 ? "Play last" : "Play next")
        return shape.fill(isRemove ? Color(red: 1, green: 0.42, blue: 0.42).opacity(0.3) : Theme.teal.opacity(0.34))
            .overlay(alignment: .trailing) {
                HStack(spacing: 6) {
                    Image(systemName: isRemove ? "minus.circle" : (dx < -170 ? "text.append" : "text.line.first.and.arrowtriangle.forward"))
                    Text(label)
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.trailing, 14)
                .animation(Theme.easeQ, value: label)
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

struct SectionLabel: View {
    var text: String
    var button: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.5)).lineLimit(1)
            Spacer()
            if let button, let action {
                Button(button, action: action).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.7)).buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10).padding(.bottom, 8)
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
        .buttonStyle(PressStyle())
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
                    SectionLabel(text: "History", button: "Clear") { player.clearHistory() }
                    ForEach(Array(hist.enumerated()), id: \.offset) { i, h in
                        if let t = model.byKey[h.key] {
                            SongRow(track: t, dim: true, leftAction: .remove({ player.removeHistory(at: player.history.count - hist.count + i) })) {
                                player.replay(t)
                            }
                        }
                    }
                }
                let ctx = player.context
                SectionLabel(text: player.nowFrom == .context && ctx != nil ? "Playing from \(ctx!.name)" : "Now Playing")
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
            case nil: TileGrid()
            case .album(let name): AlbumPage(name: name, back: "Back to Library")
            case .playlist(let id): PlaylistPage(id: id)
            case .allTracks: AllTracksPage()
            case .artist(let name): ArtistPage(name: name)
            }
        }
        .transition(.opacity)
        .id(ui.libraryPath.last)
    }
}

/// Library grid: All Tracks, your playlists, then albums (90 pt tiles, as in the web player). Hold for the tile's menu,
/// or hold and move to rearrange.
struct TileGrid: View {
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 90, maximum: 90), spacing: 14, alignment: .top)]
        LazyVGrid(columns: cols, alignment: .center, spacing: 14) {
            ForEach(model.tiles) { tile in
                TileView(tile: tile)
            }
        }
        .padding(.vertical, 4)
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
                cover
                    .frame(width: 90, height: 90)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.w(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.w(0.8)).lineLimit(1)
                    .frame(width: 90)
        }
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(Theme.easeQ, value: pressed)
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

struct IconTile: View {
    var system: String
    var body: some View {
        ZStack {
            Color.w(0.05)
            Image(systemName: system).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.w(0.45))
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
            CoverImage(path: coverPath, dataURL: coverData, px: 200, placeholder: AnyView(IconTile(system: icon)))
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
