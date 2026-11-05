import SwiftUI

/// Sizes and colours copied from the web player (index.html), so the app looks the same.
enum Theme {
    static let page = Color(red: 0x0b / 255, green: 0x1d / 255, blue: 0x24 / 255)
    static let teal = Color(red: 88 / 255, green: 196 / 255, blue: 178 / 255)        // swipe "Play next", ticks
    static let panelRadius: CGFloat = 36
    static let panelPad: CGFloat = 21
    static let panelMaxWidth: CGFloat = 580
    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.4)         // --ease / --t-s
    static let easeN = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)       // --t-n
    static let easePop = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.4)   // --ease-pop over --t-s
    static let easeQ = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)       // --t-q
    static let scrim = Color(red: 6 / 255, green: 18 / 255, blue: 26 / 255)
}

extension Color {
    static func w(_ a: Double) -> Color { Color.white.opacity(a) }
}

/// Which of Apple's glasses the panel uses: clear, or clear with a light shade behind it (Settings > Dim glass).
/// The build's screenshots can force one with the launch argument -macawGlass regular | dim | clear.
enum GlassStyle {
    static let forced: String? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-macawGlass"), i + 1 < a.count { return a[i + 1] }
        return nil
    }()
}

/// The panel's glass. On iOS 26 and later it is Apple's real Liquid Glass (it bends and lights what's behind it);
/// before that, or with Classic panel on, the frosted glass the web player used.
/// The build's screenshots can force a look with -macawGlass: dim, regular, gtNN / gbNN (Apple's tint / black behind
/// at NN %), clear, tint, dim-top (older looks), or web (the web player's own lens, Glass.metal, for comparison).
struct PanelGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var classic: Bool
    var interactive = false

    func body(content: Content) -> some View {
        if classic { frosted(content) }
        else if GlassStyle.forced == "web" {
            content
                .background { WebGlass(dim: false) }
                .overlay { GlassRim().allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.3), radius: 25, y: 20)
                .shadow(color: .black.opacity(0.15), radius: 7.5, y: 4)
        } else { apple(content) }
    }

    @ViewBuilder private func apple(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let f = GlassStyle.forced
            if f == "regular" {
                content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
            } else if let f, f.hasPrefix("gt"), let n = Double(f.dropFirst(2)) {
                // Apple's own tint: darkens the glass itself instead of a sheet over it (gt20 = 20 % black)
                content.glassEffect(Glass.clear.tint(Color.black.opacity(n / 100)), in: shape)
            } else if let f, f.hasPrefix("gb"), let n = Double(f.dropFirst(2)) {
                // Apple's own recipe for clear glass: a see-through black BEHIND the glass (Glass.clear docs), so the glass
                // bends a dimmed wallpaper and its rim and light stay crisp on top (gb30 = 30 % black)
                content
                    .glassEffect(interactive ? Glass.clear.interactive() : Glass.clear, in: shape)
                    .background(shape.fill(Color.black.opacity(n / 100)))
            } else if let f, f.hasPrefix("sub"), let n = Double(f.dropFirst(3)) {
                // test: the 30 % black behind, plus a layer under the text that subtracts the glass's grey lift evenly
                // (plus-darker: result = glass − n %), so dark stays dark while the rim and its light stay bright
                content
                    .background(shape.fill(Color(white: 1 - n / 100)).blendMode(.plusDarker))
                    .glassEffect(interactive ? Glass.clear.interactive() : Glass.clear, in: shape)
                    .background(shape.fill(Color.black.opacity(0.3)))
            } else if let f, f == "clear" || f == "tint" || f == "dim-top" {
                // older looks, for comparison screenshots only: nothing, a light tint, or the dark layer on top
                let under: Color = f == "clear" ? .clear
                    : f == "tint" ? Color(red: 6 / 255, green: 18 / 255, blue: 26 / 255).opacity(0.1)
                    : Color.black.opacity(0.5)
                content
                    .background(shape.fill(under))
                    .glassEffect(interactive ? Glass.clear.interactive() : Glass.clear, in: shape)
            } else {
                // the panel: Apple's clear glass over a see-through black BEHIND it, as Apple's docs advise for clear glass.
                // Tuned on the phone with Settings > Glass lab: black behind (+15 with Dim glass), the grey the glass adds
                // taken out evenly (plus-darker: result = glass − n %), Apple's own black tint, clear or regular glass.
                let u = UIState.shared, dim = f.map { $0 == "dim" } ?? u.dimGlass
                let behind = min(0.9, (u.glassBehind + (dim ? 15 : 0)) / 100), sub = u.glassSub / 100
                let base = u.glassRegular ? Glass.regular : Glass.clear
                let tinted = u.glassTint > 0 ? base.tint(Color.black.opacity(u.glassTint / 100)) : base
                content
                    .background(shape.fill(Color(white: 1 - sub)).blendMode(.plusDarker).opacity(sub > 0 ? 1 : 0))
                    .glassEffect(interactive ? tinted.interactive() : tinted, in: shape)
                    .environment(\.colorScheme, u.glassLight ? .light : .dark)
                    .background(shape.fill(Color.black.opacity(behind)).animation(Theme.ease, value: dim))
            }
        } else { frosted(content) }
        #else
        frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Theme.scrim.opacity(0.13)))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.w(0.4), .w(0.12), .w(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 25, y: 20)
                    .shadow(color: .black.opacity(0.15), radius: 7.5, y: 4)
            }
    }
}

/// The wallpaper behind the panel, through the web player's lens (Glass.metal).
struct WebGlass: View {
    var dim: Bool
    private let m: CGFloat = 16                            // room round the panel for the rim to bend in what's outside it

    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global), screen = UIScreen.main.bounds
            let R = min(Theme.panelRadius, f.width / 2, f.height / 2)
            // the light from the top left (web: -.55, -.83, normalised)
            let L = CGPoint(x: -0.55 / 0.9957, y: -0.83 / 0.9957)
            WallpaperView()
                .frame(width: screen.width, height: screen.height)
                .offset(x: -f.minX + m, y: -f.minY + m)
                .frame(width: f.width + 2 * m, height: f.height + 2 * m, alignment: .topLeading)
                .clipped()
                .blur(radius: 2.2, opaque: true)                // web: GLASS_BLUR 2 × 1.1
                .layerEffect(ShaderLibrary.webGlass(.float2(f.size), .float(m), .float(R), .float(16), .float(12),
                                                    .float2(L), .float(dim ? 0.3 : 0.1)),
                             maxSampleOffset: CGSize(width: m, height: m))
                .padding(-m)
                .clipShape(RoundedRectangle(cornerRadius: R, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}

/// web .bubble-svg: the rim (a white gradient line, brightest at the top) and four faint inner strokes
struct GlassRim: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        ZStack {
            ForEach([16.0, 11, 7, 3.5], id: \.self) { w in
                shape.stroke(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white.opacity(0.45), location: 0.55),
                                                    .init(color: .white.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom),
                             lineWidth: w).opacity(0.013)
            }
            .clipShape(shape)
            shape.stroke(LinearGradient(stops: [.init(color: .w(0.5), location: 0), .init(color: .w(0.12), location: 0.3),
                                                .init(color: .w(0.07), location: 0.8), .init(color: .w(0.26), location: 1)],
                                        startPoint: .top, endPoint: UnitPoint(x: 0.2, y: 1)), lineWidth: 0.9)
        }
    }
}

/// Small round glass buttons (the gear, the Settings close button).
struct ButtonGlass: ViewModifier {
    var classic: Bool
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !classic {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(.ultraThinMaterial).overlay(Circle().strokeBorder(Color.w(0.15), lineWidth: 1)))
        }
        #else
        content.background(Circle().fill(.ultraThinMaterial).overlay(Circle().strokeBorder(Color.w(0.15), lineWidth: 1)))
        #endif
    }
}

extension View {
    func panelGlass<S: InsettableShape>(_ shape: S, classic: Bool, interactive: Bool = false) -> some View {
        modifier(PanelGlass(shape: shape, classic: classic, interactive: interactive))
    }
    func buttonGlass(classic: Bool) -> some View { modifier(ButtonGlass(classic: classic)) }
}

/// The web player's springy press (pressDown / pressUp in index.html): the control sinks under the finger
/// (150 ms, cubic-bezier(.3,0,.4,1)) and, on release, springs back past its size before settling
/// (400 ms: deep → big at 36 % → .982 at 66 % → 1.005 at 86 % → 1).
struct SpringPress: ViewModifier {
    var pressed: Bool
    var deep: CGFloat
    var big: CGFloat
    @State private var down = false
    @State private var up: Double = 1                    // the release spring (rest = 1)

    func body(content: Content) -> some View {
        let e = Bezier(0.25, 0.7, 0.4, 1)
        content
            .scaleEffect(down ? deep : 1)
            .modifier(KFEffect(p: up, scale: KF(stops: [(0, Double(deep)), (0.36, Double(big)), (0.66, 0.982), (0.86, 1.005), (1, 1)], each: e)))
            .onChange(of: pressed) { _, p in
                if p {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { up = 1 }
                    withAnimation(.timingCurve(0.3, 0, 0.4, 1, duration: 0.15)) { down = true }
                } else {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { down = false }
                    replay($up, duration: 0.4)
                }
            }
    }
}

/// The round player buttons (white 10% fill, faint rim, soft shadow), with the springy press (.86 → 1.08)
/// and the glass lighting up a little while pressed.
struct RoundButtonStyle: ButtonStyle {
    var size: CGFloat
    var filled = true
    /// Light up exactly where the finger lands. Off for buttons inside scrolling lists (a touch-tracking gesture there
    /// would hold up the scroll); those light up from the middle.
    var touchPoint = false
    /// told when the finger goes down and comes up (Play's hold-to-restart ring), without a second gesture on the button
    var onPress: ((Bool) -> Void)? = nil
    func makeBody(configuration: Configuration) -> some View {
        RoundButtonBody(label: configuration.label, pressed: configuration.isPressed, size: size, filled: filled, touchPoint: touchPoint)
            .onChange(of: configuration.isPressed) { _, p in onPress?(p) }
    }
}

/// The round button itself. Where the finger lands, the glass lights up (web: .player-btn.pressed, a white radial
/// light at the touch point, 40 %, in over 60 ms and fading out over 400 ms after release).
private struct RoundButtonBody<L: View>: View {
    var label: L
    var pressed: Bool
    var size: CGFloat
    var filled: Bool
    var touchPoint: Bool
    @State private var at = UnitPoint.center
    @State private var hl: Double = 0

    var body: some View {
        let far = hypot(max(at.x, 1 - at.x), max(at.y, 1 - at.y)) * size      // CSS: circle … farthest-corner
        label
            .frame(width: size, height: size)
            .background {
                ZStack {
                    Circle().fill(Color.w(filled ? (pressed ? 0.16 : 0.1) : (pressed ? 0.08 : 0)))
                        .animation(Theme.easeN, value: pressed)
                    if filled {
                        Circle().fill(RadialGradient(colors: [.w(0.4 * hl), .w(0)], center: at, startRadius: 0, endRadius: far * 0.72))
                    }
                }
            }
            .overlay(Circle().strokeBorder(Color.w(filled ? 0.15 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(filled ? 0.2 : 0), radius: 2.5, y: 2)
            .contentShape(Circle())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in
                at = UnitPoint(x: v.startLocation.x / size, y: v.startLocation.y / size)
            }, isEnabled: touchPoint)
            .onChange(of: pressed) { _, p in
                if p { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.06)) { hl = 1 } }
                else { withAnimation(Theme.ease) { hl = 0 } }
            }
            .modifier(SpringPress(pressed: pressed, deep: 0.86, big: 1.08))
    }
}

/// Small controls (gear, pills, back, close, tabs): the springy press (.94 → 1.045, tabs .88).
struct PopStyle: ButtonStyle {
    var deep: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(SpringPress(pressed: configuration.isPressed, deep: deep, big: 1.045))
    }
}

/// Text links and rows: they dim a little while pressed (no size change, as in the web player).
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1).animation(Theme.easeQ, value: configuration.isPressed)
    }
}

/// Library and artist tiles: the picture dips to 96 % while pressed (web: .album-card:active).
struct TileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(Theme.easeN, value: configuration.isPressed)
    }
}
