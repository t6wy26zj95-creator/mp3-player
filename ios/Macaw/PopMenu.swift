import SwiftUI
import PhotosUI

/// The small menu that opens next to a song or tile (web: .pl-pop): dark glass, 236 pt wide.
struct PopMenu: View {
    var state: UIState.MenuState
    @State private var shown = false
    @State private var ask: Ask?
    @State private var askText = ""
    @FocusState private var askFocus: Bool
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
                Color.black.opacity(0.001)
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

    // MARK: a song (web songMenu)

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
        item("Play next", SVGIcon.qNext) { player.enqueue(t, last: false) }
        item("Play last", SVGIcon.qLast) { player.enqueue(t, last: true) }
        sep
        if !model.playlists.isEmpty {
            head("Add to playlist")
            ForEach(model.playlists) { p in
                let on = p.keys.contains(t.key)
                // web: ticks it in place, the menu stays open, no message
                Button { Haptics.select(); model.toggle(t, in: p.id) } label: {
                    HStack(spacing: 10) {
                        Text(p.name).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 0)
                        ZStack {
                            Circle().strokeBorder(on ? .white : Color.w(0.45), lineWidth: 1.5)
                                .background(Circle().fill(on ? .white : .clear))
                            SVGIcon(d: SVGIcon.check).fill(Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255))
                                .frame(width: 14, height: 14).opacity(on ? 1 : 0)
                        }
                        .frame(width: 20, height: 20)
                        .anim(Theme.easeN, value: on)
                    }
                    .padding(10).contentShape(Rectangle())
                }
                .buttonStyle(MenuRowStyle())
            }
        }
        if let a = ask {
            askRow(a)
        } else {
            item("New playlist", SVGIcon.add, dimmed: true, closes: false) {
                askText = ""
                ask = Ask(ph: "Playlist name", button: "Create") { name in
                    let p = model.newPlaylist(name, keys: [t.key])
                    Haptics.light(); close()
                    model.toast("Added to \(p.name)")
                }
            }
            if let inPl, let p = model.playlist(inPl), p.keys.contains(t.key) {
                item("Remove from \(p.name)", SVGIcon.trash, danger: true) {
                    model.remove(t, from: inPl)
                    model.toast("Removed from \(p.name)")
                }
            }
        }
    }

    // MARK: a tile (web tileMenu): All Tracks: cover, rename · playlist: cover, rename, delete · album: cover, hide

    @ViewBuilder private func tileItems(_ tile: Tile) -> some View {
        switch tile {
        case .all:
            head(model.allName)
            if let a = ask { askRow(a) } else {
                item("Choose cover", SVGIcon.photo) { ui.coverPickFor = tile.key }
                if model.tileCovers[AppModel.allKey] != nil { item("Use the standard cover", SVGIcon.undo) { model.setTileCover(tile.key, jpeg: nil) } }
                item("Rename", SVGIcon.edit, closes: false) {
                    askText = model.allName
                    ask = Ask(ph: "Name", button: "Save") { name in
                        if !name.isEmpty { model.renameAll(name == "All Tracks" ? "" : name) }
                        close()
                    }
                }
            }
        case .playlist(let p):
            head(p.name)
            if let a = ask { askRow(a) } else {
                item("Choose cover", SVGIcon.photo) { ui.coverPickFor = tile.key }
                if model.tileCovers["pl:" + p.id] != nil { item("Use the standard cover", SVGIcon.undo) { model.setTileCover(tile.key, jpeg: nil) } }
                item("Rename", SVGIcon.edit, closes: false) {
                    askText = p.name
                    ask = Ask(ph: "Name", button: "Save") { name in
                        if !name.isEmpty { model.renamePlaylist(p.id, name) }
                        close()
                    }
                }
                sep
                item("Delete playlist", SVGIcon.trash, danger: true) {
                    ui.confirm = UIState.Confirm(text: "Delete the playlist \"\(p.name)\"? The songs stay in your library.") { model.deletePlaylist(p.id) }
                }
            }
        case .album(let a):
            head(a.name)
            item("Choose cover", SVGIcon.photo) { ui.coverPickFor = tile.key }
            if model.tileCovers["a:" + a.name] != nil { item("Use the album's cover", SVGIcon.undo) { model.setTileCover(tile.key, jpeg: nil) } }
            sep
            item("Hide album", SVGIcon.trash, danger: true) { model.hideAlbum(a.name) }
        }
    }

    // MARK: parts

    struct Ask { var ph: String; var button: String; var done: (String) -> Void }

    private var sep: some View {
        Rectangle().fill(Color.w(0.12)).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
    }

    /// web .pl-h: 11 pt, bold, 0.06 em apart, capitals, half white
    private func head(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.66).foregroundStyle(Color.w(0.5)).lineLimit(1)
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
    }

    /// web .pl-row: the icon (18, 75 % white) first, then the name; danger rows are #ff8a8a
    private func item(_ title: String, _ icon: String, dimmed: Bool = false, danger: Bool = false, closes: Bool = true, _ f: @escaping () -> Void) -> some View {
        let color = danger ? Color(red: 1, green: 0x8a / 255, blue: 0x8a / 255) : (dimmed ? Color.w(0.75) : .white)
        return Button { if closes { run(f) } else { f() } } label: {
            HStack(spacing: 10) {
                SVGIcon(d: icon).fill(danger ? color : Color.w(0.75)).frame(width: 18, height: 18)
                Text(title).font(.system(size: 14)).foregroundStyle(color).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(10).contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }

    /// web ask(): a name field with its button in place of the menu's last rows (.pl-new)
    private func askRow(_ a: Ask) -> some View {
        let go = { a.done(askText.trimmingCharacters(in: .whitespaces)) }
        return HStack(spacing: 6) {
            TextField("", text: $askText, prompt: Text(a.ph).foregroundStyle(Color.w(0.4)))
                .font(.system(size: 16)).foregroundStyle(.white).tint(.white)
                .autocorrectionDisabled().submitLabel(.done)
                .focused($askFocus)
                .onSubmit(go)
                .onChange(of: askText) { _, v in if v.count > 40 { askText = String(v.prefix(40)) } }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.w(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.w(0.2), lineWidth: 1))
            Button(action: go) {
                Text(a.button).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255))
                    .padding(.horizontal, 12).frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(4)
        .onAppear { askFocus = true }
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
                        if let jpeg, let key { AppModel.shared.setTileCover(key, jpeg: jpeg); AppModel.shared.toast("Cover changed") }
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
