import SwiftUI
import PhotosUI

/// Settings, laid out as in the web player: Wallpaper · Library · Appearance (+ About).
struct SettingsView: View {
    var maxHeight: CGFloat
    var close: () -> Void
    @State private var contentH: CGFloat = 600
    @State private var photo: PhotosPickerItem?
    @State private var hiddenOpen = false
    private var ui: UIState { .shared }
    private var model: AppModel { .shared }
    private var tg: Telegram { .shared }
    static let effects: [(mode: String, name: String, sub: String?)] = [
        ("off", "None", "Your songs as they are"), ("gram", "Gramophone", nil), ("radio", "Old radio", nil), ("vinyl", "Vinyl", nil)]

    var body: some View {
        VStack(spacing: 0) {
            // web: .set-head (16 14 6 20), h2 17 px semibold, the close button a 30 px circle
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold)).tracking(-0.2).foregroundStyle(.white)
                Spacer()
                Button { Haptics.light(); close() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.w(0.8))
                        .frame(width: 30, height: 30).background(Circle().fill(Color.w(0.12)))
                }
                .buttonStyle(PopStyle())
            }
            .padding(.leading, 20).padding(.trailing, 14).padding(.top, 16).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header("Wallpaper")
                    group {
                        row {
                            ZStack {
                                if let w = ui.wallpaper { Image(uiImage: w).resizable().scaledToFill() } else { Color.w(0.1) }
                            }
                            .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            label("Wallpaper", Wallpaper.hasCustom ? "Your photo" : "Default")
                            PhotosPicker(selection: $photo, matching: .images) { pill("Change") }
                        }
                        if Wallpaper.hasCustom {
                            divider
                            Button {
                                Wallpaper.clearCustom(); ui.reloadWallpaper()
                            } label: {
                                Text("Use the default wallpaper").font(.system(size: 15)).foregroundStyle(Theme.teal)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 14)
                            }
                            .buttonStyle(PressStyle())
                        }
                        divider
                        VStack(spacing: 10) {
                            HStack {
                                Text("Blur").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                Spacer()
                                Text(ui.blur < 0.5 ? "Off" : "\(Int(ui.blur))").font(.system(size: 15)).foregroundStyle(Color.w(0.55))
                            }
                            MacawSlider(value: Binding(get: { ui.blur }, set: { ui.setBlur($0.rounded()) }), range: 0...30)
                        }
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
                    }

                    header("Library")
                    group {
                        row {
                            label("Cover Flow", "Albums in one row that you flip through, instead of the grid")
                            MacawSwitch(on: Binding(get: { ui.coverFlow }, set: { ui.setCoverFlow($0) }))
                        }
                        divider
                        Button { withAnimation(Theme.easeN) { hiddenOpen.toggle() } } label: {
                            row {
                                Text("Hidden albums").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                Spacer()
                                Text(model.hidden.isEmpty ? "None" : "\(model.hidden.count)").font(.system(size: 15)).foregroundStyle(Color.w(0.55))
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.w(0.55))
                                    .rotationEffect(.degrees(hiddenOpen ? 180 : 0))
                            }
                        }
                        .buttonStyle(PressStyle())
                        if hiddenOpen {
                            ForEach(model.hidden, id: \.self) { name in
                                divider
                                row {
                                    Text(name).font(.system(size: 14)).foregroundStyle(Color.w(0.85)).lineLimit(1)
                                    Spacer()
                                    Button { model.unhideAlbum(name) } label: { pill("Show") }.buttonStyle(PopStyle())
                                }
                            }
                        }
                        divider
                        row {
                            label("Telegram", tg.statusLine)
                            Button { Haptics.light(); Task { await tg.linkOrUnlink() } } label: { pill(tg.key.isEmpty ? "Link" : "Unlink") }
                                .buttonStyle(PopStyle())
                        }
                        divider
                        row {
                            label("Songs", "\(model.tracks.count) in the app. You can also copy music into the MacawP3 folder in the Files app")
                            Button { close(); ui.importing = true } label: { pill("Add") }.buttonStyle(PopStyle())
                        }
                    }

                    header("Sound effect")
                    group {
                        ForEach(Array(SettingsView.effects.enumerated()), id: \.offset) { i, e in
                            if i > 0 { divider }
                            Button { Retro.shared.set(e.mode) } label: {
                                row {
                                    label(e.name, e.sub)
                                    EffectTick(on: Retro.shared.mode == e.mode, busy: Retro.shared.busy && Retro.shared.mode == e.mode)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }

                    header("Appearance")
                    group {
                        row {
                            label("Classic panel", "Plain frosted glass instead of Liquid Glass")
                            MacawSwitch(on: Binding(get: { ui.classic }, set: { ui.setClassic($0) }))
                        }
                        if !ui.classic {
                            divider
                            row {
                                label("Dim glass", "A light shade behind the glass, so text stays easy to read on bright wallpapers")
                                MacawSwitch(on: Binding(get: { ui.dimGlass }, set: { ui.setDimGlass($0) }))
                            }
                            divider
                            divider
                            // temporary: tune Apple's glass on the phone itself (hold a slider and Settings fades away)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Glass lab").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                    Spacer()
                                    Button("Reset") { Haptics.light(); ui.setGlassLab(behind: 30, sub: 0, tint: 0, regular: false) }
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.teal)
                                }
                                Text("Hold a slider and this card fades so you can see the player. Send Claude the numbers you like.")
                                    .font(.system(size: 12)).foregroundStyle(Color.w(0.55)).fixedSize(horizontal: false, vertical: true)
                                labSlider("Dark behind the glass", ui.glassBehind, 0...80) { ui.setGlassLab(behind: $0) }
                                labSlider("Take out the grey", ui.glassSub, 0...40) { ui.setGlassLab(sub: $0) }
                                labSlider("Apple's tint", ui.glassTint, 0...80) { ui.setGlassLab(tint: $0) }
                                HStack {
                                    Text("Frosted (regular) glass").font(.system(size: 13)).foregroundStyle(Color.w(0.8))
                                    Spacer()
                                    MacawSwitch(on: Binding(get: { ui.glassRegular }, set: { ui.setGlassLab(regular: $0) }))
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                        divider
                        row {
                            label("Minimal light", "No coloured light behind the player, only the cover's own glow")
                            MacawSwitch(on: Binding(get: { ui.minimalLight }, set: { ui.setMinimalLight($0) }))
                        }
                    }

                    Text("MacawP3 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · native")
                        .font(.system(size: 11)).foregroundStyle(Color.w(0.35))
                        .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 4)
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: max(100, min(contentH, maxHeight - 52)))
        }
        // web: .floating-customizer: 28 px corners, frosted (blur 30, saturate 160 %) under a dark tint, a lighter top edge
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(red: 10 / 255, green: 24 / 255, blue: 32 / 255).opacity(0.72)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.w(0.34), .w(0.14), .w(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .shadow(color: .black.opacity(0.45), radius: 30, y: 24)
        .opacity(UIState.shared.glassPeek ? 0.1 : 1)             // Glass lab: a slider is held, the player shows through
        .preferredColorScheme(.dark)
        .onChange(of: photo) { _, it in
            guard let it else { return }
            Task {
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    let scale = min(1, 1600 / max(img.size.width, img.size.height))
                    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                    let f = UIGraphicsImageRendererFormat(); f.scale = 1
                    let out = UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                    if let j = out.jpegData(compressionQuality: 0.85) { Wallpaper.saveCustom(j); ui.reloadWallpaper() }
                }
                photo = nil
            }
        }
    }

    // MARK: parts (web: .set-h, .set-group, .set-row, .set-pill)

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Color.w(0.55))
            .padding(.horizontal, 6).padding(.top, 14).padding(.bottom, 6)
    }
    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) { c() }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.w(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.w(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 12) { c() }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 50)
    }
    private func labSlider(_ t: String, _ v: Double, _ r: ClosedRange<Double>, _ set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(t).font(.system(size: 13)).foregroundStyle(Color.w(0.8))
                Spacer()
                Text("\(Int(v)) %").font(.system(size: 13).monospacedDigit()).foregroundStyle(Color.w(0.55))
            }
            MacawSlider(value: Binding(get: { v }, set: { set($0.rounded()) }), range: r, editing: { on in
                withAnimation(Theme.easeN) { UIState.shared.glassPeek = on }
            })
        }
    }
    private func label(_ t: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
            if let sub { Text(sub).font(.system(size: 12)).foregroundStyle(Color.w(0.55)).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func pill(_ t: String) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(Color.w(0.12)))
            .overlay(Capsule().strokeBorder(Color.w(0.2), lineWidth: 1))
    }
    private var divider: some View { Rectangle().fill(Color.w(0.08)).frame(height: 1) }
}

struct SheetBackground: View {
    var classic: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color(red: 15 / 255, green: 23 / 255, blue: 30 / 255).opacity(0.72)
        }
        .ignoresSafeArea()
    }
}

/// The web player's switch: teal when on, the knob slides.
struct MacawSwitch: View {
    @Binding var on: Bool
    var body: some View {
        Button { Haptics.light(); on.toggle() } label: { EmptyView() }
            .buttonStyle(SwitchLook(on: on))
    }
}

/// web .switch: 46 × 28, 1 px rim; the knob (22 px, 2 px in from the inside of the rim) slides 18 px with the small
/// overshoot (400 ms ease-pop) and stretches to 27 px while pressed (250 ms), sliding back 5 px when on.
private struct SwitchLook: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        ZStack(alignment: .topLeading) {
            Capsule().fill(on ? Theme.teal.opacity(0.55) : Color.w(0.1))
                .overlay(Capsule().strokeBorder(on ? Color(red: 160 / 255, green: 240 / 255, blue: 225 / 255).opacity(0.5) : Color.w(0.2), lineWidth: 1))
                .animation(Theme.easeN, value: on)
            Capsule().fill(LinearGradient(colors: [.white, Color(red: 0xe3 / 255, green: 0xec / 255, blue: 0xf0 / 255)], startPoint: .top, endPoint: .bottom))
                .frame(width: p ? 27 : 22, height: 22)
                .animation(Theme.easeN, value: p)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                .offset(x: 3 + (on ? (p ? 13 : 18) : 0), y: 3)
                .animation(Theme.easePop, value: on)
                .animation(Theme.easePop, value: p)
        }
        .frame(width: 46, height: 28)
        .contentShape(Capsule())
    }
}

/// The tick of the chosen sound effect; it pulses while the song is being made to sound old.
struct EffectTick: View {
    var on: Bool
    var busy: Bool
    @State private var dim = false
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 120 / 255, green: 222 / 255, blue: 202 / 255))
            .opacity(on ? (busy && dim ? 0.35 : 1) : 0)
            .animation(Theme.easeN, value: on)
            .scaleEffect(on ? 1 : 0.6)
            .animation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.25), value: on)     // web: transform var(--t-n) var(--ease-pop)
            .frame(width: 22, height: 22)
            .onChange(of: busy, initial: true) { _, b in
                if b { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true } }
                else { withAnimation(.easeOut(duration: 0.2)) { dim = false } }
            }
    }
}

/// The web player's range input: a 4 px track, white up to the value, and a 22 px white knob.
struct MacawSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var editing: ((Bool) -> Void)? = nil
    @State private var held = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, f = (value - range.lowerBound) / (range.upperBound - range.lowerBound), x = 11 + (w - 22) * f
            ZStack(alignment: .leading) {
                Capsule().fill(Color.w(0.18)).frame(height: 4)
                Capsule().fill(.white).frame(width: max(0, x), height: 4)
                Circle().fill(.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .offset(x: x - 11)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let t = max(0, min(1, (v.location.x - 11) / max(1, w - 22)))
                value = range.lowerBound + t * (range.upperBound - range.lowerBound)
                if !held { held = true; editing?(true) }
            }.onEnded { _ in held = false; editing?(false) })
        }
        .frame(height: 28)
    }
}
