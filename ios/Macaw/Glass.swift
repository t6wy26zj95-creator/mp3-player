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

/// The panel's glass. On iOS 26 and later it is Apple's real Liquid Glass (it bends and lights what's behind it);
/// before that, or with Classic panel on, the frosted glass the web player used.
struct PanelGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var classic: Bool
    var interactive = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !classic {
            content.glassEffect(glass(), in: shape)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func glass() -> Glass {
        // Apple's standard glass, untinted: it bends and lights the wallpaper at its edges and adapts to what's behind it
        interactive ? Glass.regular.interactive() : Glass.regular
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

/// The round player buttons (white 10% fill, faint rim), as in the web player.
struct RoundButtonStyle: ButtonStyle {
    var size: CGFloat
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(Circle().fill(Color.w(filled ? (configuration.isPressed ? 0.2 : 0.1) : (configuration.isPressed ? 0.1 : 0))))
            .overlay(Circle().strokeBorder(Color.w(filled ? 0.15 : 0), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.easeQ, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Buttons that dim a little while pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1).animation(Theme.easeQ, value: configuration.isPressed)
    }
}
