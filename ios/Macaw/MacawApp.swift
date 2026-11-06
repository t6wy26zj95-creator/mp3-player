import SwiftUI
import AVFoundation

@main
struct MacawApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(CoverPicker())
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // "Playback": music keeps going with the screen locked, in the background and with the silent switch on.
        // The session only becomes active when a song plays, so opening the app doesn't stop other apps' music.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        application.beginReceivingRemoteControlEvents()
        return true
    }
}
