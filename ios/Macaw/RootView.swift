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
                        .padding(.top, 8)
                } else if booted && model.loaded {
                    PlayerPanel(room: max(160, geo.size.height - 8 - 228 - 70))
                        .frame(maxWidth: min(Theme.panelMaxWidth, geo.size.width - 32))
                        .padding(.top, 8)
                } else {
                    LoadingPanel(text: model.readingText)
                        .frame(maxWidth: min(Theme.panelMaxWidth, geo.size.width - 32))
                        .padding(.top, 8)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { Haptics.light(); ui.settingsOpen = true } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.w(0.85))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(PressStyle())
                        .buttonGlass(classic: ui.classic)
                        .padding(.trailing, 5).padding(.bottom, 2)
                    }
                }
                .opacity(ui.expanded ? 0 : 1)

                ToastView()

                if let m = ui.menu { PopMenu(state: m).zIndex(10) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // behind everything and under the status bar, without making the layout itself taller than the screen
        .background { WallpaperView().ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .tint(.white)
        .sheet(isPresented: Binding(get: { ui.settingsOpen }, set: { ui.settingsOpen = $0 })) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
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
        await Migration.runIfNeeded()
        AppModel.shared.loadArrangement()
        Telegram.shared.load()
        UIState.shared.classic = Store.shared["oldPanel"] == "1"
        UIState.shared.minimalLight = Store.shared["lightMin"] == "1"
        UIState.shared.blur = Double(Store.shared["wallpaperBlur"] ?? "") ?? 0
        UIState.shared.reloadWallpaper()
        _ = Player.shared
        await AppModel.shared.scan()
        Telegram.shared.start()
        if let i = CommandLine.arguments.firstIndex(of: "-macawScreen"), i + 1 < CommandLine.arguments.count {
            await TestScreens.show(CommandLine.arguments[i + 1])
        }
    }
}

/// Only for the build's screenshots (the simulator opens the app with -macawScreen <name>): puts the app on one screen.
enum TestScreens {
    @MainActor static func show(_ name: String) async {
        let ui = UIState.shared, model = AppModel.shared, player = Player.shared
        if player.current == nil, let t = model.tracks.first { player.start(model.tracks, at: t, name: "Library", wholeLibrary: true) }
        player.pause()
        try? await Task.sleep(nanoseconds: 600_000_000)
        switch name {
        case "queue": ui.open(.queue)
        case "library": ui.open(.library)
        case "artists": ui.open(.artists)
        case "big": ui.expanded = true
        case "lyrics":
            ui.expanded = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            ui.lyricsScroll = ui.lyricsMax
        case "settings": ui.settingsOpen = true
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
