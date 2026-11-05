import SwiftUI
import PhotosUI

/// The small menu that opens next to a song or tile (web: .pl-pop): dark glass, 236 pt wide.
struct PopMenu: View {
    var state: UIState.MenuState
    @State private var shown = false
    private var ui: UIState { .shared }
    private var model: AppModel { .shared }
    private var player: Player { .shared }

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = 236
            let screen = geo.frame(in: .global)
            let a = state.anchor
            let x = min(max(12, a.maxX - w - 8 - screen.minX), geo.size.width - w - 12)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(shown ? 0.2 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                card
                    .frame(width: w)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardH = $0 }
                    .offset(x: x, y: topFor(a: a, screen: screen, h: geo.size.height))
                    .scaleEffect(shown ? 1 : 0.92, anchor: .topTrailing)
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear { withAnimation(Theme.easeN) { shown = true } }
    }

    @State private var cardH: CGFloat = 300
    private func topFor(a: CGRect, screen: CGRect, h: CGFloat) -> CGFloat {
        let below = a.maxY + 4 - screen.minY
        if below + cardH < h - 12 { return below }
        let above = a.minY - 4 - cardH - screen.minY
        return above >= 12 ? above : max(12, h - 12 - cardH)
    }

    private func close() {
        withAnimation(Theme.easeN) { shown = false }
        Task { try? await Task.sleep(nanoseconds: 220_000_000); if ui.menu?.id == state.id { ui.menu = nil } }
    }
    private func run(_ f: @escaping () -> Void) { close(); Haptics.light(); f() }

    @ViewBuilder private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.kind {
            case .song(let t, let inPl): songItems(t, inPl)
            case .tile(let tile): tileItems(tile)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255).opacity(0.86)))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.w(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 17, y: 14)
    }

    // MARK: a song

    @ViewBuilder private func songItems(_ t: Track, _ inPl: String?) -> some View {
        HStack(spacing: 10) {
            CoverImage(path: t.path, px: 120, placeholder: AnyView(Color.w(0.06)))
                .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
                Text(t.shownArtist).font(.system(size: 12)).foregroundStyle(Color.w(0.55)).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
        item("Play next", "text.line.first.and.arrowtriangle.forward") { player.enqueue(t, last: false) }
        item("Play last", "text.append") { player.enqueue(t, last: true) }
        sep
        if !model.playlists.isEmpty {
            Text("ADD TO PLAYLIST").font(.system(size: 11, weight: .semibold)).tracking(0.66).foregroundStyle(Color.w(0.5))
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
            ForEach(model.playlists) { p in
                let on = p.keys.contains(t.key)
                Button { Haptics.light(); model.toggle(t, in: p.id) } label: {
                    HStack(spacing: 10) {
                        Text(p.name).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        ZStack {
                            Circle().strokeBorder(on ? .white : Color.w(0.45), lineWidth: 1.5)
                                .background(Circle().fill(on ? .white : .clear))
                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255)) }
                        }
                        .frame(width: 20, height: 20)
                        .anim(Theme.easeN, value: on)
                    }
                    .padding(10).contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle())
            }
        }
        item("New playlist", "plus", dimmed: true) {
            ui.prompt = UIState.Prompt(title: "New playlist", text: "My playlist \(model.playlists.count + 1)", button: "Create") { name in
                let p = model.newPlaylist(name, keys: [t.key])
                model.toast("Added to “\(p.name)”")
            }
        }
        if let inPl {
            sep
            item("Remove from this playlist", "minus.circle", danger: true) { model.remove(t, from: inPl) }
        }
        sep
        item("Go to artist", "person") { ui.showArtist(t.shownArtist) }
    }

    // MARK: a tile

    @ViewBuilder private func tileItems(_ tile: Tile) -> some View {
        switch tile {
        case .all:
            item("Play", "play") { player.playAll(model.tracks, name: "Library", wholeLibrary: true) }
            sep
            item("Choose cover", "photo") { ui.coverPickFor = tile.key }
            if model.tileCovers[AppModel.allKey] != nil { item("Use the standard cover", "arrow.uturn.backward") { model.setTileCover(tile.key, jpeg: nil) } }
            item("Rename", "pencil") {
                ui.prompt = UIState.Prompt(title: "Rename", text: model.allName, button: "Rename") { model.renameAll($0) }
            }
        case .playlist(let p):
            item("Play", "play") { player.playAll(model.tracks(of: p), name: p.name) }
            sep
            item("Choose cover", "photo") { ui.coverPickFor = tile.key }
            if model.tileCovers["pl:" + p.id] != nil { item("Use the standard cover", "arrow.uturn.backward") { model.setTileCover(tile.key, jpeg: nil) } }
            item("Rename", "pencil") {
                ui.prompt = UIState.Prompt(title: "Rename playlist", text: p.name, button: "Rename") { model.renamePlaylist(p.id, $0) }
            }
            sep
            item("Delete playlist", "trash", danger: true) { model.deletePlaylist(p.id) }
        case .album(let a):
            item("Play", "play") { player.playAll(a.tracks, name: a.name) }
            item("Play next", "text.line.first.and.arrowtriangle.forward") { player.enqueueAll(a.tracks, last: false) }
            item("Play last", "text.append") { player.enqueueAll(a.tracks, last: true) }
            sep
            item("Choose cover", "photo") { ui.coverPickFor = tile.key }
            if model.tileCovers["a:" + a.name] != nil { item("Use the album's cover", "arrow.uturn.backward") { model.setTileCover(tile.key, jpeg: nil) } }
            item("Hide album", "eye.slash", danger: true) { model.hideAlbum(a.name) }
        }
    }

    // MARK: parts

    private var sep: some View {
        Rectangle().fill(Color.w(0.12)).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func item(_ title: String, _ icon: String, dimmed: Bool = false, danger: Bool = false, _ f: @escaping () -> Void) -> some View {
        let color = danger ? Color(red: 1, green: 0.54, blue: 0.54) : (dimmed ? Color.w(0.75) : .white)
        return Button { run(f) } label: {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 14)).foregroundStyle(color).lineLimit(1)
                Spacer()
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(danger ? color : Color.w(0.75)).frame(width: 18)
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.w(configuration.isPressed ? 0.1 : 0)))
    }
}

/// Choose cover: pick a photo; the middle square becomes the tile's 400×400 cover.
struct CoverPicker: ViewModifier {
    @State private var item: PhotosPickerItem?
    @State private var picked: UIImage?
    @State private var key: String?
    private var ui: UIState { .shared }
    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: Binding(get: { ui.coverPickFor != nil && picked == nil }, set: { if !$0 && item == nil && picked == nil { ui.coverPickFor = nil } }),
                          selection: $item, matching: .images)
            .onChange(of: item) { _, it in
                guard let it, let k = ui.coverPickFor else { return }
                Task {
                    if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        // big photos are scaled down first (the crop never needs more than a few times 400 px)
                        let m = max(img.size.width, img.size.height), s = min(1, 1600 / max(1, m))
                        let small = s < 1 ? UIGraphicsImageRenderer(size: CGSize(width: img.size.width * s, height: img.size.height * s)).image { _ in
                            img.draw(in: CGRect(x: 0, y: 0, width: img.size.width * s, height: img.size.height * s)) } : img
                        key = k; picked = small
                    } else { AppModel.shared.toast("That picture couldn't be opened"); ui.coverPickFor = nil }
                    item = nil
                }
            }
            .overlay {
                if let picked {
                    CoverCrop(image: picked) { jpeg in
                        if let jpeg, let key { AppModel.shared.setTileCover(key, jpeg: jpeg) }
                        self.picked = nil; key = nil; ui.coverPickFor = nil
                    }
                    .zIndex(30)
                }
            }
    }
}

func squareJPEG(_ img: UIImage, side: CGFloat, quality: CGFloat = 0.86) -> Data? {
    let s = min(img.size.width, img.size.height)
    guard s > 0 else { return nil }
    let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
    let out = r.image { _ in
        let k = side / s
        img.draw(in: CGRect(x: -(img.size.width - s) / 2 * k, y: -(img.size.height - s) / 2 * k, width: img.size.width * k, height: img.size.height * k))
    }
    return out.jpegData(compressionQuality: quality)
}
