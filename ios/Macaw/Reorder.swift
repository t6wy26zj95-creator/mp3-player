import SwiftUI

/// Hold a song and move it to reorder (web attachReorder / beginDrag): the Queue, the rest of the album, a playlist.
/// One Reorder per list. The lifted row sits on a glass card with its cover glowing behind it, the others dim to 50 %
/// and step aside as it passes their middle; on release it glides into the gap and the list is rebuilt in the new order.
/// Held but never moved: the song's menu instead.
@MainActor @Observable
final class Reorder {
    var me: Int?                                   // the lifted row
    var cy: CGFloat = 0                            // how far it has moved
    var landing = false
    @ObservationIgnored var frames: [Int: CGRect] = [:]
    @ObservationIgnored var to = 0
    @ObservationIgnored var count = 0

    private func f(_ j: Int) -> CGRect { frames[j] ?? .zero }
    var H: CGFloat { me.map { f($0).height } ?? 0 }

    /// how far row j steps aside for the lifted one
    func shift(_ j: Int) -> CGFloat {
        guard let me, j != me else { return 0 }
        let top = f(me).minY + cy, bot = top + H
        if j < me && top < f(j).midY { return H }
        if j > me && bot > f(j).midY { return -H }
        return 0
    }

    func begin(_ i: Int, count n: Int) {
        count = n; to = i; cy = 0; landing = false
        UIState.shared.tileDragging = true
        Haptics.medium()
        withAnimation(Theme.easeN) { me = i }
    }

    func moved(_ dy: CGFloat) {
        guard let me, !landing, count > 0 else { return }
        let first = f(0), last = f(count - 1), mine = f(me)
        let lo = first.minY - mine.minY - 10, hi = last.maxY - mine.minY - mine.height + 10
        withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.95)) { cy = max(lo, min(hi, dy)) }
        var nt = me
        for j in 0..<count where j != me {
            let s = shift(j)
            if s > 0 { nt -= 1 } else if s < 0 { nt += 1 }
        }
        if nt != to { to = nt; Haptics.select() }
    }

    func end(still: () -> Void, drop: @escaping (Int, Int) -> Void) {
        guard let me else { return }
        UIState.shared.tileDragging = false
        if abs(cy) < 7 {                                                  // held but never moved: the menu
            withAnimation(Theme.easeN) { self.me = nil; cy = 0 }
            still(); return
        }
        var land: CGFloat = 0                                             // glide into the gap that opened for it
        if to > me { for j in (me + 1)...to { land += f(j).height } }
        else if to < me { for j in to..<me { land -= f(j).height } }
        Haptics.light()
        landing = true
        withAnimation(Theme.easeN) { cy = land }
        let from = me, dest = to
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            if dest != from { drop(from, dest) }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { self.me = nil; self.cy = 0; self.landing = false }
        }
    }
}

/// What a row in a reorderable list needs: its list, its place, and what to do when it lands somewhere else.
struct ReorderSpot {
    var r: Reorder
    var i: Int
    var count: Int
    var drop: (Int, Int) -> Void
}

/// The hold: with a list it starts a reorder (and a still hold opens the menu); without one it just opens the menu.
struct HoldToReorder: ViewModifier {
    var spot: ReorderSpot?
    var cover: String?
    var menu: () -> Void

    func body(content: Content) -> some View {
        if let spot {
            let r = spot.r, up = r.me == spot.i, busy = r.me != nil
            content
                .background { if up { LiftCard(cover: cover, landing: r.landing) } }
                .scaleEffect(up && !r.landing ? 1.03 : 1)
                .offset(y: up ? r.cy : r.shift(spot.i))
                .animation(up ? nil : Theme.easeN, value: r.shift(spot.i))
                .animation(Theme.easeN, value: busy)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                    if r.me == nil { r.frames[spot.i] = f }
                }
                .zIndex(up ? 5 : 0)
                .gesture(LongPressGesture(minimumDuration: 0.38, maximumDistance: 8)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { v in
                        guard case .second(true, let d) = v else { return }
                        if r.me == nil { r.begin(spot.i, count: spot.count) }
                        if let d, r.me == spot.i { r.moved(d.translation.height) }
                    }
                    .onEnded { _ in if r.me == spot.i { r.end(still: menu, drop: spot.drop) } })
        } else {
            content.onLongPressGesture(minimumDuration: 0.38) { menu() }
        }
    }
}

/// web .q-row.lifted: the glass card under the lifted row, and its cover's colour glowing behind (qglow / qglowOut)
private struct LiftCard: View {
    var cover: String?
    var landing: Bool
    @State private var glow: Double = 0
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        ZStack {
            Color.clear                                                   // the cover, held to the row's size (inset 6 / 18)
                .overlay { CoverImage(path: cover, px: 120, placeholder: AnyView(Color.w(0.2))) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.vertical, 6).padding(.horizontal, 18)
                .saturation(1.7).blur(radius: 18)
                .opacity(0.5 * glow)
                .scaleEffect(landing ? 0.9 : 0.8 + 0.2 * glow)
            shape.fill(Color(red: 19 / 255, green: 54 / 255, blue: 68 / 255).opacity(0.98))
                .overlay(shape.fill(LinearGradient(stops: [.init(color: .w(0.2), location: 0), .init(color: .w(0.07), location: 0.55),
                                                           .init(color: .w(0.04), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.w(0.4), .w(0.16), .w(0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .padding(-1)
                .shadow(color: .black.opacity(0.32), radius: 15, y: 14)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                .opacity(landing ? 0 : 1)
        }
        .animation(Theme.easeN, value: landing)
        .onAppear { withAnimation(Theme.easeN) { glow = 1 } }
        .onChange(of: landing) { _, l in if l { withAnimation(Theme.easeN) { glow = 0 } } }
        .allowsHitTesting(false)
    }
}
