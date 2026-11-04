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
struct PanelGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var classic: Bool
    var interactive = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !classic {
            if GlassStyle.forced == "regular" {
                content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
            } else {
                let dim = GlassStyle.forced.map { $0 == "dim" } ?? UIState.shared.dimGlass
                content
                    // Apple's clear glass lifts a dark wallpaper by about 40 levels on a phone (the dock: about 15). This shade
                    // brings the panel back to the web player's darkness; Dim glass goes darker still.
                    .background(shape.fill(Color.black.opacity(dim ? 0.65 : 0.5)).animation(Theme.ease, value: dim))
                    .glassEffect(clear(), in: shape)
            }
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func clear() -> Glass {
        // Apple's clear glass (as in the iOS 26 dock): hardly frosted, the wallpaper stays sharp in the middle and is
        // bent and stretched at the rounded edges, with a thin bright rim
        interactive ? Glass.clear.interactive() : Glass.clear
    }
    #endif

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
    func makeBody(configuration: Configuration) -> some View {
        RoundButtonBody(label: configuration.label, pressed: configuration.isPressed, size: size, filled: filled, touchPoint: touchPoint)
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
