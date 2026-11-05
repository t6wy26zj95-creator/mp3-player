import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(\.scenePhase) private var phase
    private var ui: UIState { .shared }
    private var model: AppModel { .shared }
    @State private var booted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if booted && model.loaded && model.tracks.isEmpty {
                    EmptyLibraryPanel()
                        .frame(maxWidth: min(Theme.panelMaxWidth, geo.size.width - 32))
                        .padding(.top, 24)
                } else if booted && model.loaded {
                    PlayerPanel(room: max(160, geo.size.height - 24 - 228 - 70 - 15))
                        .frame(maxWidth: min(Theme.panelMaxWidth, geo.size.width - 32))
                        .padding(.top, 24)
                } else {
                    LoadingPanel(text: model.readingText)
                        .frame(maxWidth: min(Theme.panelMaxWidth, geo.size.width - 32))
                        .padding(.top, 24)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { Haptics.light(); withAnimation(Theme.ease) { ui.settingsOpen.toggle() } } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.w(0.8))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(PopStyle())
                        .buttonGlass(classic: ui.classic)
                        .opacity(0.75)
                        .padding(.trailing, 20).padding(.bottom, 20)
                    }
                }
                .opacity(ui.expanded ? 0 : 1)

                // Settings: a floating card over the player (web: .set-ov + .floating-customizer), not a sheet
                if ui.settingsOpen {
                    Color(red: 3 / 255, green: 10 / 255, blue: 14 / 255).opacity(0.42)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Theme.ease) { ui.settingsOpen = false } }
                        .transition(.opacity.animation(Theme.easeN))
                        .zIndex(4)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        SettingsView(maxHeight: geo.size.height - 24) { withAnimation(Theme.ease) { ui.settingsOpen = false } }
                            .frame(width: min(420, geo.size.width - 24))
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(Theme.easeN).combined(with: .modifier(active: CardIn(on: false), identity: CardIn(on: true)).animation(Theme.ease)),
                        removal: .opacity.animation(Theme.easeN).combined(with: .modifier(active: CardIn(on: false), identity: CardIn(on: true)).animation(Theme.ease))))
                    .zIndex(5)
                }

                ToastView()
                    .zIndex(6)

                if let m = ui.menu { PopMenu(state: m).zIndex(10) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // behind everything and under the status bar, without making the layout itself taller than the screen
        .background { WallpaperView().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .tint(.white)
        .fileImporter(isPresented: Binding(get: { ui.importing }, set: { ui.importing = $0 }), allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { model.importFiles(urls) }
        }
        .alert(ui.prompt?.title ?? "", isPresented: Binding(get: { ui.prompt != nil }, set: { if !$0 { ui.prompt = nil } })) {
            TextField("Name", text: Binding(get: { ui.prompt?.text ?? "" }, set: { ui.prompt?.text = $0 }))
            Button("Cancel", role: .cancel) { ui.prompt = nil }
            Button(ui.prompt?.button ?? "OK") {
                if let p = ui.prompt { p.done(p.text) }
                ui.prompt = nil
            }
        }
        .onOpenURL { url in if url.isFileURL { model.importFiles([url]) } }
        .task {
            guard !booted else { return }
            await Boot.start()
            withAnimation(Theme.ease) { booted = true }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                Telegram.shared.becameActive()
                if booted { Task { await model.scan() } }
            case .background:
                Telegram.shared.wentToBackground()
                Player.shared.saveStateNow()
                Store.shared.saveNow()
                Task { await Sync.shared.push() }
            default: break
            }
        }
    }
}

enum Boot {
    @MainActor static func start() async {
        let t0 = Date()
        func mark(_ what: String) { NSLog("MacawBoot %@ %.2fs", what, Date().timeIntervalSince(t0)) }
        await Migration.runIfNeeded()
        mark("migration")
        AppModel.shared.loadArrangement()
        Telegram.shared.load()
        UIState.shared.classic = Store.shared["oldPanel"] == "1"
        UIState.shared.minimalLight = Store.shared["lightMin"] == "1"
        UIState.shared.dimGlass = Store.shared["glassDim"] == "1"
        UIState.shared.glassTest = Store.shared["glassTest"] ?? ""
        UIState.shared.coverFlow = Store.shared["libView"] == "flow"
        UIState.shared.blur = Double(Store.shared["wallpaperBlur"] ?? "") ?? 0
        // the build's screenshots: a detailed test wallpaper, where the glass's bending shows (launch argument -macawWall)
        if CommandLine.arguments.contains("-macawWall"),
           let d = try? Data(contentsOf: Library.shared.songsFolder.appendingPathComponent("test-wall.jpg")) { Wallpaper.saveCustom(d) }
        UIState.shared.reloadWallpaper()
        _ = Player.shared
        Glow.shared.start()
        mark("settings")
        await AppModel.shared.scan()
        mark("scan")
        Telegram.shared.start()
        if let i = CommandLine.arguments.firstIndex(of: "-macawScreen"), i + 1 < CommandLine.arguments.count {
            let name = CommandLine.arguments[i + 1]
            Task { try? await Task.sleep(nanoseconds: 300_000_000); await TestScreens.show(name) }   // after the app has shown
        }
    }
}

/// Only for the build's screenshots (the simulator opens the app with -macawScreen <name>): puts the app on one screen.
enum TestScreens {
    @MainActor static var swipe: CGFloat?
    @MainActor static var swipeShown = false
    @MainActor static var lift = false
    @MainActor static func show(_ name: String) async {
        let ui = UIState.shared, model = AppModel.shared, player = Player.shared
        if player.current == nil, let t = model.tracks.first { player.start(model.tracks, at: t, name: "Library", wholeLibrary: true) }
        player.pause()
        try? await Task.sleep(nanoseconds: 600_000_000)
        switch name {
        case "queue": ui.open(.queue)
        case "library": ui.open(.library)
        case "flow": ui.coverFlow = true; ui.open(.library)
        case "lift": lift = true; ui.open(.queue)
        case "pull":                            // the big player held half way by a pull
            if XPMotion.shared.dragBegin() {
                try? await Task.sleep(nanoseconds: 400_000_000)
                XPMotion.shared.dragTo(150)
            }
        case "edit": ui.open(.library); try? await Task.sleep(nanoseconds: 500_000_000); ui.editing = true
        case "swipe1", "swipe2":                // an album's first song held mid-swipe: Play next, and further, Play last
            swipe = name == "swipe1" ? -110 : -230
            ui.open(.library)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let a = model.albums.first(where: { $0.tracks.contains { $0.num > 0 } }) ?? model.albums.first { ui.push(.album(a.name)) }
        case "artists": ui.open(.artists)
        case "big": XPMotion.shared.open()
        case "lyrics":
            XPMotion.shared.open()
            try? await Task.sleep(nanoseconds: 800_000_000)
            ui.lyricsScroll = ui.lyricsMax
        case "settings": ui.settingsOpen = true
        case "motion":                      // a fixed walk through the main motions, for the build's screen recording
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            await wait(2); player.next()
            await wait(2); player.previous(); player.previous()
            await wait(2); ui.open(.library)
            await wait(2); if let a = model.albums.first { ui.push(.album(a.name)) }
            await wait(2); ui.back()
            await wait(2); ui.open(.queue)
            await wait(2); ui.open(.artists)
            await wait(2); ui.open(.artists)
            await wait(2); XPMotion.shared.open()
            await wait(2.5); player.next()
            await wait(2); XPMotion.shared.close()
            await wait(2); XPMotion.shared.open()
            await wait(2); XPMotion.shared.close()
        default: break
        }
    }
}

/// The wallpaper behind everything: your photo (or the default), blurred by Settings > Blur, darkened a little on
/// bright photos so white text stays readable.
struct WallpaperView: View {
    private var ui: UIState { .shared }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.page, Color(red: 0x1d / 255, green: 0x4e / 255, blue: 0x5f / 255), Theme.page],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let img = ui.wallpaper {
                GeometryReader { g in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width + ui.blur * 4, height: g.size.height + ui.blur * 4)
                        .offset(x: -ui.blur * 2, y: -ui.blur * 2)
                        .blur(radius: ui.blur, opaque: true)
                        .clipped()
                }
                .transition(.opacity)
                .id(ui.wallpaperVersion)
            }
            Theme.scrim.opacity(0.18)
            // the web player's vignette: clear in the middle, darker towards the corners
            GeometryReader { g in
                let r = sqrt(g.size.width * g.size.width + g.size.height * g.size.height) / 2
                RadialGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.6), location: 1)],
                               center: .center, startRadius: 0, endRadius: r)
            }
            .allowsHitTesting(false)
        }
    }
}

struct ToastView: View {
    private var model: AppModel { .shared }
    var body: some View {
        VStack {
            Spacer()
            if let t = model.toastText {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.07, green: 0.11, blue: 0.14).opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.w(0.1), lineWidth: 1))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(t)
            }
        }
        .allowsHitTesting(false)
    }
}

struct LoadingPanel: View {
    var text: String?
    private var ui: UIState { .shared }
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(text ?? "Loading…").font(.system(size: 13)).foregroundStyle(Color.w(0.6))
        }
        .frame(maxWidth: .infinity).frame(height: 186)
        .panelGlass(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous), classic: ui.classic)
    }
}

/// No songs yet: "Tap to add your songs", as in the web player.
struct EmptyLibraryPanel: View {
    private var ui: UIState { .shared }
    var body: some View {
        Button { ui.importing = true } label: {
            VStack(spacing: 6) {
                Text("Tap to add your songs").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text("They stay in the app. You can also copy music into the MacawP3 folder in the Files app.")
                    .font(.system(size: 11)).foregroundStyle(Color.w(0.7)).multilineTextAlignment(.center)
            }
            .padding(Theme.panelPad + 8)
            .frame(maxWidth: .infinity).frame(minHeight: 186)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .panelGlass(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous), classic: ui.classic)
    }
}

/// The Settings card's way in and out: 18 pt lower and at 98 %, growing from its bottom edge.
struct CardIn: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(on ? 1 : 0.98, anchor: .bottom).offset(y: on ? 0 : 18)
    }
}
