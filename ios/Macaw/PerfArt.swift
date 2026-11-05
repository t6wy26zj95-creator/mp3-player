import SwiftUI
import UIKit

/// Pictures drawn once and reused, for looks that are costly to draw live in every tile of a grid: a soft shadow
/// (each live one needs its own off-screen pass, every frame the grid moves or fades) and the tiles' glass rim (a
/// circular gradient the phone shades on the CPU). Switching tabs used to redraw dozens of each per frame.
@MainActor
enum PerfArt {
    private static var cache: [String: UIImage] = [:]
    private static var order: [String] = []

    static func image(_ key: String, scale: CGFloat = 3, make: () -> AnyView) -> UIImage? {
        if let im = cache[key] { return im }
        let r = ImageRenderer(content: make())
        r.scale = scale
        guard let im = r.uiImage else { return nil }
        cache[key] = im; order.append(key)
        if order.count > 80 { cache[order.removeFirst()] = nil }
        return im
    }
}

/// A soft drop shadow under a tile, from a cached picture (same look as `.shadow(color: .black.opacity(o), radius: r, y: y)`).
struct SoftShadow: ViewModifier {
    var radius: CGFloat
    var y: CGFloat
    var opacity: Double
    var circle = false
    var corner: CGFloat = 12
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { s in
                if abs(s.width - size.width) > 0.5 || abs(s.height - size.height) > 0.5 { size = s }
            }
            .background {
                if size.width > 1, let im = art {
                    let pad = radius * 3
                    Image(uiImage: im).resizable()
                        .frame(width: size.width + 2 * pad, height: size.height + 2 * pad)
                        .offset(y: y)
                        .opacity(opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private var art: UIImage? {
        let w = size.width.rounded(), h = size.height.rounded(), pad = radius * 3, r = radius, c = corner, round = circle
        return PerfArt.image("sh|\(w)|\(h)|\(r)|\(c)|\(round)", scale: 1) {
            AnyView(Group {
                if round { Circle().fill(.black) } else { RoundedRectangle(cornerRadius: c, style: .continuous).fill(.black) }
            }
            .frame(width: w, height: h)
            .blur(radius: r)
            .padding(pad))
        }
    }
}

extension View {
    func softShadow(radius: CGFloat, y: CGFloat, opacity: Double, circle: Bool = false, corner: CGFloat = 12) -> some View {
        modifier(SoftShadow(radius: radius, y: y, opacity: opacity, circle: circle, corner: corner))
    }
}
