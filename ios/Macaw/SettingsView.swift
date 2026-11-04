import SwiftUI
import PhotosUI

/// Settings, laid out as in the web player: Wallpaper · Library · Appearance (+ About).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var hiddenOpen = false
    private var ui: UIState { .shared }
    private var model: AppModel { .shared }
    private var tg: Telegram { .shared }
    static let effects: [(mode: String, name: String, sub: String?)] = [
        ("off", "None", "Your songs as they are"), ("gram", "Gramophone", nil), ("radio", "Old radio", nil), ("vinyl", "Vinyl", nil)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.w(0.85)).frame(width: 32, height: 32)
                }
                .buttonStyle(PopStyle())
                .buttonGlass(classic: ui.classic)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)

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
                                Text("Blur").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                                Spacer()
                                Text(ui.blur < 0.5 ? "Off" : "\(Int(ui.blur))").font(.system(size: 15)).foregroundStyle(Color.w(0.55))
                            }
                            Slider(value: Binding(get: { ui.blur }, set: { ui.setBlur($0.rounded()) }), in: 0...30)
                                .tint(Color.w(0.8))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }

                    header("Library")
                    group {
                        Button { withAnimation(Theme.easeN) { hiddenOpen.toggle() } } label: {
                            row {
                                Text("Hidden albums").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
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
                            Button { dismiss(); ui.importing = true } label: { pill("Add") }.buttonStyle(PopStyle())
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
                        divider
                        row {
                            label("Minimal light", "No coloured light behind the player, only the cover's own glow")
                            MacawSwitch(on: Binding(get: { ui.minimalLight }, set: { ui.setMinimalLight($0) }))
                        }
                    }

                    Text("MacawP3 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · native")
                        .font(.system(size: 11)).foregroundStyle(Color.w(0.35))
                        .frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground { SheetBackground(classic: ui.classic) }
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
        Text(t.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.7).foregroundStyle(Color.w(0.5))
            .padding(.leading, 6).padding(.top, 18).padding(.bottom, 8)
    }
    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) { c() }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.w(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.w(0.1), lineWidth: 1))
    }
    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 12) { c() }.padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 52)
    }
    private func label(_ t: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
            if let sub { Text(sub).font(.system(size: 12.5)).foregroundStyle(Color.w(0.55)).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func pill(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(Color.w(0.12)))
            .overlay(Capsule().strokeBorder(Color.w(0.2), lineWidth: 1))
    }
    private var divider: some View { Rectangle().fill(Color.w(0.08)).frame(height: 1).padding(.leading, 14) }
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
        Button { Haptics.light(); withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { on.toggle() } } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Theme.teal.opacity(0.55) : Color.w(0.12))
                    .overlay(Capsule().strokeBorder(on ? Color(red: 160 / 255, green: 240 / 255, blue: 225 / 255).opacity(0.5) : Color.w(0.15), lineWidth: 1))
                Circle().fill(LinearGradient(colors: [.white, Color(red: 0.89, green: 0.93, blue: 0.94)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22).shadow(color: .black.opacity(0.35), radius: 3, y: 2).padding(2)
            }
            .frame(width: 46, height: 26)
        }
        .buttonStyle(.plain)
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
            .scaleEffect(on ? 1 : 0.6)
            .animation(Theme.easeN, value: on)
            .frame(width: 22, height: 22)
            .onChange(of: busy, initial: true) { _, b in
                if b { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true } }
                else { withAnimation(.easeOut(duration: 0.2)) { dim = false } }
            }
    }
}
