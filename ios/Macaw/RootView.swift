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
                    // web fitRoom: the lists get the height left under the player (a phone on its side: much less;
                    // on its side with Cover Flow open, only the tabs sit above the row, and the panel spans the screen)
                    let lf = ui.landFlow
                    let room = lf ? max(110, geo.size.height - 12 - 24 - 34 - 10 - 15 - 12)
                                  : max(ui.land ? 110 : 160, geo.size.height - 24 - 228 - 70 - 15)
                    PlayerPanel(room: room)
                        .frame(maxWidth: lf ? geo.size.width - 32 : min(Theme.panelMaxWidth, geo.size.width - 32))
                        .background(alignment: .top) { DrawerWarmUp().frame(height: room) }
                        .padding(.top, lf ? 12 : ui.land ? 12 : 24)
                        .onChange(of: room, initial: true) { _, r in if ui.room != r { ui.room = r } }
                        .onChange(of: geo.size, initial: true) { _, s in
                            // web layout() on its side: S = max(110, min(panel × .4, 300, room under the top - 44))
                            let a = (max(110, min(min(Theme.panelMaxWidth, s.width - 32) * 0.4, 300, s.height - 12 - 14 - 44))).rounded()
                            if ui.landArt != a { ui.landArt = a }
                        }
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
                        .accessibilityIdentifier("settings")
                        .opacity(0.75)
                        .padding(.trailing, 20).padding(.bottom, 20)
                    }
                }
                .opacity(ui.expanded ? 0 : 1)

                // Settings: a floating card over the player (web: .set-ov + .floating-customizer), not a sheet
                if ui.settingsOpen {
                    Color(red: 3 / 255, green: 10 / 255, blue: 14 / 255).opacity(ui.glassPeek ? 0 : 0.42)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Theme.ease) { ui.settingsOpen = false } }
                        .transition(.opacity.animation(Theme.easeN.slowed))
                        .zIndex(4)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        SettingsView(maxHeight: geo.size.height - 24) { withAnimation(Theme.ease) { ui.settingsOpen = false } }
                            .frame(width: min(420, geo.size.width - 24))
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(Theme.easeN.slowed).combined(with: .modifier(active: CardIn(on: false), identity: CardIn(on: true)).animation(Theme.ease.slowed)),
                        removal: .opacity.animation(Theme.easeN.slowed).combined(with: .modifier(active: CardIn(on: false), identity: CardIn(on: true)).animation(Theme.ease.slowed))))
                    .zIndex(5)
                }

                ToastView()
                    .zIndex(6)

                if let m = ui.menu { PopMenu(state: m).zIndex(10) }

                if PerfMeter.shared.shown {
                    PerfHUD().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 16).padding(.top, 2).zIndex(20)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size, initial: true) { _, s in
                let l = s.width > s.height && s.height < 560
                if ui.land != l { withAnimation(Theme.ease) { ui.land = l } }
            }
        }
        // behind everything and under the status bar, without making the layout itself taller than the screen
        .background { WallpaperView().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        // the slow-motion recording: every animation that passes through here runs N times slower
        .transaction { t in if TestScreens.slow > 1, let a = t.animation { t.animation = a.speed(1 / TestScreens.slow) } }
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
        // web: confirm() before a playlist is deleted
        .alert(ui.confirm?.text ?? "", isPresented: Binding(get: { ui.confirm != nil }, set: { if !$0 { ui.confirm = nil } })) {
            Button("Cancel", role: .cancel) { ui.confirm = nil }
            Button("OK") { ui.confirm?.ok(); ui.confirm = nil }
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
        let st = Store.shared, u = UIState.shared
        // the glass Nick picked on his phone with the Glass lab (5 Nov): nothing extra behind it, 4 % of the grey taken
        // out, Apple's own tint at 14 % black
        u.glassBehind = 0; u.glassSub = TestScreens.sub ?? 4; u.glassTint = 14; u.glassRegular = false; u.glassLight = false
        // the speed meter: the build's walk-through logs it (-macawPerf), Settings > Speed meter shows it
        let perfLog = CommandLine.arguments.contains("-macawPerf")
        PerfMeter.shared.shown = st["perfHUD"] == "1"
        if perfLog || PerfMeter.shared.shown { PerfMeter.shared.start(log: perfLog) }
        UIState.shared.coverFlow = Store.shared["libView"] == "flow"
        UIState.shared.blur = Double(Store.shared["wallpaperBlur"] ?? "") ?? 0
        // the build's screenshots: a detailed test wallpaper, where the glass's bending shows (launch argument -macawWall)
        if CommandLine.arguments.contains("-macawWall"),
           let d = try? Data(contentsOf: Library.shared.songsFolder.appendingPathComponent("test-wall.jpg")) { Wallpaper.saveCustom(d) }
        else if CommandLine.arguments.contains("-macawScreen") { Wallpaper.clearCustom() }   // the other screenshots: the default wallpaper
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
        if CommandLine.arguments.contains("-macawUITest") {                   // the build's walk-through: a song ready, paused
            Task { try? await Task.sleep(nanoseconds: 300_000_000); await TestScreens.show("ready") }
        }
    }
}

/// Only for the build's screenshots (the simulator opens the app with -macawScreen <name>): puts the app on one screen.
enum TestScreens {
    @MainActor static var swipe: CGFloat?
    @MainActor static var swipeShown = false
    @MainActor static var lift = false
    /// The build's slow-motion recording (-macawSlow N): every motion N times slower, so each step can be compared
    /// frame by frame with the web player's.
    @MainActor static let slow: Double = motionSlow
    /// -macawSub N: the grey taken out of the glass, for comparison recordings
    @MainActor static let sub: Double? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-macawSub"), i + 1 < a.count { return Double(a[i + 1]) }
        return nil
    }()
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
        case "playing": player.play()          // the cover's light, glow and glass while a song plays (recorded)
        case "artistpage", "catalog":       // an artist's page (their albums you don't have greyed), then one of those albums
            ui.open(.artists)
            try? await Task.sleep(nanoseconds: 500_000_000)
            ui.push(.artist("The Cure"))
            if name == "catalog" {
                for _ in 0..<40 where ArtistInfo.shared.get("The Cure")?.albums?.isEmpty ?? true { try? await Task.sleep(nanoseconds: 300_000_000) }
                if let all = ArtistInfo.shared.get("The Cure")?.albums, let a = all.first(where: { $0.title.lowercased().contains("disintegration") }) ?? all.first {
                    ui.push(.catalog(CatRef(id: a.id, title: a.title, artist: "The Cure", cover: a.cover, year: a.year)))
                }
            }
        case "big": XPMotion.shared.open()
        case "lyrics":
            XPMotion.shared.open()
            try? await Task.sleep(nanoseconds: 800_000_000)
            ui.lyricsScroll = ui.lyricsMax
        case "settings": ui.settingsOpen = true
        case "slowmotion":                  // the main motions, slowed (with -macawSlow N), one after another
            let k = slow
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * k * 1_000_000_000)) }
            NSLog("MacawSlow start")
            await wait(1); player.next()
            await wait(1); ui.open(.library)
            await wait(1); if let a = model.albums.first { ui.push(.album(a.name)) }
            await wait(1); ui.back()
            await wait(1); ui.open(.queue)
            await wait(1); ui.open(.queue)
            await wait(1); XPMotion.shared.open()
            await wait(1.2); XPMotion.shared.close()
            await wait(1.2)
            // the drawer opened a second time, then once more without the grey taken out (is the white flash the plus-darker layer?)
            NSLog("MacawSlow again"); ui.open(.library)
            await wait(1); ui.open(.library)
            await wait(1); NSLog("MacawSlow sub0"); ui.glassSub = 0; ui.open(.library)
            await wait(1); ui.open(.library)
            await wait(1)
        case "firstopen":                   // the Library's first open after launch, slowed (is the glass white?)
            let k = slow
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * k * 1_000_000_000)) }
            await wait(0.4); ui.open(.library)
            await wait(0.8); ui.open(.library)
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

/// web TILT.apply: the wallpaper drifts 6 pt against the tilt (scaled 4 % so its edges never show).
struct WallTilt: ViewModifier {
    private var g: Glow { .shared }
    func body(content: Content) -> some View {
        let on = g.tx != 0 || g.ty != 0
        content.scaleEffect(on ? 1.04 : 1).offset(x: -6 * g.tx, y: -6 * g.ty)
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
                        .modifier(WallTilt())
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
    @State private var pressed = false
    var body: some View {
        // web .drop-zone inside the panel: a dashed 16 pt box, 30 pt padding, 14 pt text at 60 % white, the line under it
        // 11 pt at 70 % of that; pressed: lighter, the border and text brighter
        let box = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button { Haptics.light(); ui.importing = true } label: {
            VStack(spacing: 2) {
                Text("Tap to add your songs").font(.system(size: 14))
                Text("They stay in the app. You can also copy music into the MacawP3 folder in the Files app.")
                    .font(.system(size: 11)).opacity(0.7)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.w(pressed ? 1 : 0.6))
            .padding(30)
            .frame(maxWidth: .infinity)
            .background(box.fill(Color.w(pressed ? 0.08 : 0.02)))
            .overlay(box.strokeBorder(Color.w(pressed ? 0.4 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(box)
        }
        .buttonStyle(PressReport(pressed: $pressed))
        .padding(Theme.panelPad)
        .panelGlass(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous), classic: ui.classic)
    }
}

/// A button style that only reports whether it's held (the look is drawn by the label itself).
struct PressReport: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, v in pressed = v }
    }
}

/// The Settings card's way in and out: 18 pt lower and at 98 %, growing from its bottom edge.
struct CardIn: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(on ? 1 : 0.98, anchor: .bottom).offset(y: on ? 0 : 18)
    }
}
