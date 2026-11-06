import SwiftUI

/// Library as one row of album covers (Settings > Cover Flow; off by default), as on the web (COVER FLOW in index.html).
/// Swipe and the row glides on and settles on an album; tap the middle one to open it, a side one to bring it to the
/// middle; hold one for its menu. Under the row: the album's name and artist. All Tracks and your playlists come first,
/// then the albums by artist (oldest first within an artist). Positions are in slots: cover i sits at slot i, c is the
/// slot in the middle; a glide is a Hermite curve that starts at the finger's speed and lands with none.
struct CoverFlow: View {
    @State private var sim = FlowSim()
    @State private var stageW: CGFloat = 360
    private var model: AppModel { .shared }
    private var ui: UIState { .shared }

    struct Item: Identifiable {
        var id: String { tile.key }
        var tile: Tile
        var name: String
        var sub: String
        var cover: String?            // a song with artwork
        var custom: String?           // a cover you picked
        var icon: String
    }

    private var items: [Item] {
        var special: [Item] = [], albums: [(Item, String, Int)] = []
        for t in model.tiles {
            let custom = model.tileCovers[model.coverKey(t.key)]
            switch t {
            case .all:
                let n = model.tracks.count
                special.append(Item(tile: t, name: model.allName, sub: "\(n) song\(n == 1 ? "" : "s")", custom: custom, icon: "folder.fill"))
            case .playlist(let p):
                let n = p.keys.count
                special.append(Item(tile: t, name: p.name, sub: "\(n) song\(n == 1 ? "" : "s")", custom: custom, icon: "music.note.list"))
            case .album(let a):
                let y = Int(a.year) ?? 0
                albums.append((Item(tile: t, name: a.name, sub: [a.artist, y > 0 ? "\(y)" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                    cover: a.coverPath, custom: custom, icon: "music.note"), a.artist, y))
            }
        }
        func sortName(_ s: String) -> String {
            let f = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return f.hasPrefix("the ") ? String(f.dropFirst(4)) : f
        }
        albums.sort { x, y in
            let ax = sortName(x.1).isEmpty ? "~" : sortName(x.1), ay = sortName(y.1).isEmpty ? "~" : sortName(y.1)
            if ax != ay { return ax.localizedStandardCompare(ay) == .orderedAscending }
            if x.2 != y.2 { return (x.2 == 0 ? 10000 : x.2) < (y.2 == 0 ? 10000 : y.2) }
            return x.0.name.localizedStandardCompare(y.0.name) == .orderedAscending
        }
        return special + albums.map(\.0)
    }

    var body: some View {
        let list = items
        let land = ui.landFlow
        // web measure(): the row's width sets the size; a short screen keeps the covers small enough to fit
        let W = (max(64, min(land ? 260 : 150, max(96, stageW * (land ? 0.3 : 0.34)), (ui.room - 72) / 1.3))).rounded()
        let CG = W * 0.66, SP = W * 0.3, ft: CGFloat = 0.1
        VStack(spacing: 0) {
            TimelineView(.animation(paused: !sim.moving)) { tl in
                ZStack {
                    if list.isEmpty {
                        Text("No albums yet").font(.system(size: 13)).foregroundStyle(Color.w(0.5))
                    }
                    let R = Double((stageW / 2 - CG) / SP) + 2.5
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, it in
                        let d = Double(i) - sim.c, a = abs(d)
                        if a <= R {
                            let t = min(a, 1), sg: Double = d < 0 ? -1 : 1, far = max(0, a - 1)
                            let x = sg * (t * Double(CG) + far * Double(SP)), z = -t * Double(W) * 0.6 - far * 3, r = -sg * t * 60
                            let P = Double(W) * 4, k = P / (P - z)                      // CSS perspective: 4 × the cover size
                            cover(it, W: W, shade: min(0.5, t * 0.26 + far * 0.05))
                                .rotation3DEffect(.degrees(r), axis: (0, 1, 0), anchor: .center, perspective: 0.25)
                                .scaleEffect(CGFloat(k))
                                .offset(x: CGFloat(x * k), y: W * ft)
                                .zIndex(1000 - (a * 10).rounded())
                                .onTapGesture { tap(i, it) }
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    Haptics.medium()
                                    if abs(Double(i) - sim.c) > 0.3 { sim.glide(to: Double(i), vel: 0, T: 0.26) }
                                    ui.menu = UIState.MenuState(kind: .tile(it.tile), anchor: .zero)
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: tl.date) { _, now in sim.step(now, count: list.count) }
            }
            .frame(height: W * (ft + 1.2))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageW = $0 }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.13),
                                         .init(color: .black, location: 0.87), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .gesture(DragGesture(minimumDistance: 7)
                .onChanged { v in sim.drag(v, spx: Double(CG + SP) / 2, count: list.count) }
                .onEnded { _ in sim.release(count: list.count) })
            .padding(.horizontal, -Theme.panelPad)                                  // web: margin 0 -20px, to the panel's edges

            // web .cf-cap
            let cur = list.isEmpty ? nil : list[max(0, min(list.count - 1, Int(sim.c.rounded())))]
            VStack(spacing: 2) {
                Text(cur?.name ?? "").font(.system(size: land ? 16 : 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(cur?.sub ?? "").font(.system(size: land ? 13 : 12)).foregroundStyle(Color.w(0.55)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .top)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 2)
        .onAppear { sim.start(at: startIndex(list)) }
        .onChange(of: Int(sim.c.rounded())) { _, _ in if sim.moving { sim.tick() } }
    }

    private func startIndex(_ list: [Item]) -> Double {
        if let k = sim.atKey, let i = list.firstIndex(where: { $0.id == k }) { return Double(i) }
        if let cur = Player.shared.current, let i = list.firstIndex(where: { if case .album(let a) = $0.tile { return a.name == cur.albumName } else { return false } }) { return Double(i) }
        return Double(list.firstIndex { if case .album = $0.tile { return true } else { return false } } ?? 0)
    }

    private func tap(_ i: Int, _ it: Item) {
        if abs(Double(i) - sim.c) < 0.3 {
            Haptics.light()
            sim.atKey = it.id
            switch it.tile {
            case .all: ui.push(.allTracks)
            case .playlist(let p): ui.push(.playlist(p.id))
            case .album(let a): ui.push(.album(a.name))
            }
        } else { Haptics.select(); sim.glide(to: Double(i), vel: 0, T: nil) }
    }

    private func cover(_ it: Item, W: CGFloat, shade: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            Color(red: 0x2b / 255, green: 0x30 / 255, blue: 0x38 / 255)
            if it.custom != nil || it.cover != nil {
                CoverImage(path: it.cover, dataURL: it.custom, px: Int(W * 3), placeholder: AnyView(icon(it)))
            } else { icon(it) }
            // a little gloss (web .cf-sl::after), and the side covers sit in the shade (::before)
            LinearGradient(stops: [.init(color: .w(0.14), location: 0), .init(color: .w(0), location: 0.42)],
                           startPoint: UnitPoint(x: 0.1, y: 0.2), endPoint: UnitPoint(x: 0.9, y: 0.8))
            Color.black.opacity(shade)
        }
        .frame(width: W, height: W)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.w(0.16), lineWidth: 0.5))
    }

    private func icon(_ it: Item) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0x46 / 255, green: 0x50 / 255, blue: 0x5f / 255), Color(red: 0x23 / 255, green: 0x28 / 255, blue: 0x31 / 255)],
                           startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1))
            GeometryReader { g in
                Image(systemName: it.icon).resizable().scaledToFit().foregroundStyle(Color.w(0.5))
                    .frame(width: g.size.width * 0.38, height: g.size.height * 0.38)
                    .position(x: g.size.width / 2, y: g.size.height / 2)
            }
        }
    }
}

/// The row's motion (web: c, v, glide, drag; step / glideTo / release).
@MainActor @Observable
final class FlowSim {
    var c: Double = 0
    var moving = false
    @ObservationIgnored var atKey: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var g: (p0: Double, p1: Double, m0: Double, T: Double, t0: Date)?
    @ObservationIgnored private var d: (c0: Double, s: [(Date, Double)])?
    @ObservationIgnored private var lastTick = Date.distantPast

    func start(at i: Double) { if !started { started = true; c = i } }

    func tick() {
        let now = Date()
        if now.timeIntervalSince(lastTick) > 0.045 { lastTick = now; Haptics.select() }   // a click per album going past
    }

    func step(_ now: Date, count: Int) {
        guard let g, d == nil else { return }
        let u = min(1, now.timeIntervalSince(g.t0) / g.T), u2 = u * u, u3 = u2 * u
        c = (2 * u3 - 3 * u2 + 1) * g.p0 + (u3 - 2 * u2 + u) * g.m0 + (-2 * u3 + 3 * u2) * g.p1
        if u >= 1 { c = g.p1; self.g = nil; moving = false }
    }

    /// vel in slots / s; T in seconds (picked from the distance and speed when nil)
    func glide(to p1: Double, vel: Double, T: Double?) {
        let D = p1 - c
        if abs(D) < 0.001 && abs(vel) < 0.05 { c = p1; g = nil; moving = d != nil; return }
        let t = T ?? (vel * D > 0 ? min(1.1, max(0.26, 2.4 * abs(D) / abs(vel))) : 0.3 + 0.07 * min(8, sqrt(abs(D)) * 2))
        var m0 = vel * t
        if m0 * D > 0 && abs(m0) > 2.6 * abs(D) { m0 = 2.6 * D }                    // never overshoot the album it lands on
        g = (c, p1, m0, t, Date()); moving = true
    }

    func drag(_ v: DragGesture.Value, spx: Double, count: Int) {
        guard count > 0 else { return }
        if d == nil { g = nil; d = (c, []); moving = true }
        guard var dd = d else { return }
        let lo = 0.0, hi = Double(count - 1)
        var x = dd.c0 - Double(v.translation.width) / spx
        if x < lo { x = lo - (lo - x) * 0.35 } else if x > hi { x = hi + (x - hi) * 0.35 }   // the ends give a little
        c = x
        let now = Date()
        dd.s.append((now, c))
        while dd.s.count > 2 && now.timeIntervalSince(dd.s[0].0) > 0.11 { dd.s.removeFirst() }
        d = dd
    }

    func release(count: Int) {
        guard let dd = d, count > 0 else { d = nil; return }
        d = nil
        let now = Date()
        var vel = 0.0
        if let a = dd.s.first, let b = dd.s.last, now.timeIntervalSince(b.0) <= 0.09 {     // a finger that stopped throws nothing
            vel = (c - a.1) / max(0.016, now.timeIntervalSince(a.0))
        }
        vel = max(-60, min(60, vel))
        let target = max(0, min(Double(count - 1), (c + vel * 0.3).rounded()))
        glide(to: target, vel: vel, T: nil)
    }
}
