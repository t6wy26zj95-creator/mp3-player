import SwiftUI

/// Choose cover, after the photo is picked: move and zoom it in a square frame (web cropImage): drag to move, pinch or the
/// slider to zoom (1–4×), the picture always fills the frame; Use saves the square as up to 400 × 400 JPEG.
struct CoverCrop: View {
    var image: UIImage
    var done: (Data?) -> Void
    @State private var z: CGFloat = 1
    @State private var x: CGFloat = 0
    @State private var y: CGFloat = 0
    @State private var dragFrom: CGPoint?
    @State private var pinchFrom: (z: CGFloat, x: CGFloat, y: CGFloat)?
    @State private var shown = false

    private let S: CGFloat = 300
    private var base: CGFloat { max(S / max(1, image.size.width), S / max(1, image.size.height)) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).background(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { close(nil) }
            VStack(spacing: 0) {
                Text("Move and zoom").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.w(0.7)).padding(.bottom, 12)
                frame
                HStack(spacing: 10) {
                    Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Color.w(0.55))
                    MacawSlider(value: Binding(get: { Double(z) }, set: { zoom(to: CGFloat($0), at: CGPoint(x: S / 2, y: S / 2)) }), range: 1...4)
                    Image(systemName: "photo").font(.system(size: 19)).foregroundStyle(Color.w(0.55))
                }
                .padding(.top, 14).padding(.horizontal, 2).padding(.bottom, 4)
                HStack(spacing: 8) {
                    Button { close(nil) } label: { label("Cancel", ok: false) }.buttonStyle(PopStyle())
                    Button { close(render()) } label: { label("Use", ok: true) }.buttonStyle(PopStyle())
                }
                .padding(.top, 12)
            }
            .padding(16)
            .frame(width: min(340, UIScreen.main.bounds.width - 32))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255).opacity(0.86)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.w(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 18)
            .scaleEffect(shown ? 1 : 0.95)
        }
        .opacity(shown ? 1 : 0)
        .onAppear { clamp(); withAnimation(Theme.easeN) { shown = true } }
    }

    private var frame: some View {
        let k = base * z
        return Image(uiImage: image).resizable()
            .frame(width: image.size.width * k, height: image.size.height * k)
            .offset(x: x, y: y)
            .frame(width: S, height: S, alignment: .topLeading)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.w(0.2), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f = dragFrom ?? CGPoint(x: x, y: y)
                    if dragFrom == nil { dragFrom = f }
                    x = f.x + v.translation.width; y = f.y + v.translation.height; clamp()
                }
                .onEnded { _ in dragFrom = nil })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in
                    let p = pinchFrom ?? (z, x, y)
                    if pinchFrom == nil { pinchFrom = p }
                    let a = CGPoint(x: v.startAnchor.x * S, y: v.startAnchor.y * S)
                    let nz = max(1, min(4, p.z * v.magnification)), f = nz / p.z
                    z = nz; x = a.x - (a.x - p.x) * f; y = a.y - (a.y - p.y) * f; clamp()
                }
                .onEnded { _ in pinchFrom = nil })
    }

    private func label(_ t: String, ok: Bool) -> some View {
        Text(t).font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ok ? Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255) : .white)
            .frame(maxWidth: .infinity).padding(11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ok ? Color.white : Color.w(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ok ? Color.white : Color.w(0.18), lineWidth: 1))
    }

    private func zoom(to nz0: CGFloat, at c: CGPoint) {
        let nz = max(1, min(4, nz0)), f = nz / z
        x = c.x - (c.x - x) * f; y = c.y - (c.y - y) * f; z = nz; clamp()
    }

    /// the picture always fills the frame
    private func clamp() {
        let w = image.size.width * base * z, h = image.size.height * base * z
        x = min(0, max(S - w, x)); y = min(0, max(S - h, y))
    }

    private func render() -> Data? {
        let k = base * z, side = max(64, min(400, (S / k).rounded()))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { _ in
            let q = side / S
            image.draw(in: CGRect(x: x * q, y: y * q, width: image.size.width * k * q, height: image.size.height * k * q))
        }
        return img.jpegData(compressionQuality: 0.86)
    }

    private func close(_ data: Data?) {
        withAnimation(Theme.easeN) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { done(data) }
    }
}
