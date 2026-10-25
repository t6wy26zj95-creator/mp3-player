import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // "Playback": music keeps going with the screen locked, in the background and with the silent switch on.
        // The session is only made active by the player when a song actually plays, so opening the app
        // doesn't stop music from other apps.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let player = PlayerViewController()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = PlayerViewController.pageColor
        window.rootViewController = player
        window.makeKeyAndVisible()
        self.window = window
        open(connectionOptions.urlContexts)
    }

    // A song shared to the app ("Open in Macaw" / the share sheet).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        open(URLContexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        let urls = contexts.map(\.url).filter(\.isFileURL)
        if !urls.isEmpty { player.importSongs(urls) }
    }
}
