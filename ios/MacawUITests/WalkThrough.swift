import XCTest

/// The build machine's walk through the whole app, the way a person would use it: every tab, page and button, with a
/// screenshot after each step (they're compared with the web player) and the app's speed meter logging how smooth
/// each part was (MacawPerf lines in the log). Steps that can't find their button are skipped, not failed, so one
/// missing control doesn't hide the rest of the walk.
final class WalkThrough: XCTestCase {
    var app: XCUIApplication!
    var n = 0
    var missed: [String] = []
    var forced: [String] = []

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-macawPerf", "-macawUITest"]
        app.launch()
        sleep(4)
    }

    func shot(_ name: String) {
        n += 1
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = String(format: "%02d-%@", n, name)
        a.lifetime = .keepAlways
        add(a)
        NSLog("MacawStep %@", a.name ?? name)
    }

    @discardableResult
    func tap(_ e: XCUIElement, _ what: String, wait: Double = 1.2) -> Bool {
        guard e.waitForExistence(timeout: 3) else { missed.append(what); NSLog("MacawMissed %@", what); return false }
        if e.isHittable { e.tap() } else {
            // covered as far as accessibility goes: tap where it is on screen, as a finger would
            let f = e.frame, w = app.frame
            guard f.width > 0, w.width > 0 else { missed.append(what); return false }
            forced.append(what); NSLog("MacawForced %@", what)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        }
        Thread.sleep(forTimeInterval: wait)
        return true
    }
    /// the element with this name that a finger can reach: the small and the big player both have a "next", "play" ...,
    /// and the hidden one's spot can be the open cover (tapping there folds the big player)
    func id(_ s: String) -> XCUIElement {
        let q = app.descendants(matching: .any).matching(identifier: s)
        if q.count > 1 { for i in 0..<q.count where q.element(boundBy: i).isHittable { return q.element(boundBy: i) } }
        return q.firstMatch
    }
    /// scrolls Settings until the control shows, then taps it
    func scrollTo(_ e: XCUIElement, _ what: String) -> Bool {
        for _ in 0..<6 where !(e.exists && e.isHittable) { drag(CGVector(dx: 0.5, dy: 0.75), CGVector(dx: 0.5, dy: 0.45)) }
        return tap(e, what)
    }
    func text(_ s: String) -> XCUIElement { app.staticTexts[s].firstMatch }
    func textContaining(_ s: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch }
    func button(containing s: String) -> XCUIElement { app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch }
    func drag(_ from: CGVector, _ to: CGVector, hold: Double = 0, speed: XCUIGestureVelocity = .default) {
        let a = app.coordinate(withNormalizedOffset: from), b = app.coordinate(withNormalizedOffset: to)
        a.press(forDuration: hold, thenDragTo: b, withVelocity: speed, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 1)
    }

    func testWalkThrough() {
        shot("home")

        // the small player
        tap(id("play"), "play"); shot("playing")
        tap(id("next"), "next"); shot("next")
        tap(id("prev"), "prev"); tap(id("prev"), "prev again"); shot("prev")
        tap(id("play"), "pause")
        id("play").press(forDuration: 1.0); Thread.sleep(forTimeInterval: 1); shot("hold-play-shuffle")
        id("play").press(forDuration: 1.0); Thread.sleep(forTimeInterval: 1)

        // Library
        tap(id("tab-library"), "Library tab"); shot("library")
        drag(CGVector(dx: 0.5, dy: 0.75), CGVector(dx: 0.5, dy: 0.4), speed: .fast); shot("library-scrolled")
        drag(CGVector(dx: 0.5, dy: 0.4), CGVector(dx: 0.5, dy: 0.8), speed: .fast)
        if tap(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Wish (30th")).firstMatch, "album tile") {
            shot("album")
            drag(CGVector(dx: 0.5, dy: 0.7), CGVector(dx: 0.5, dy: 0.45)); shot("album-scrolled")
            // swipe a song left (Play next), then right (its menu)
            let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open (Remastered")).firstMatch   // album rows read "4. Open (Remastered 2022)"
            if row.waitForExistence(timeout: 2) {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: -1.2, dy: 0.5)))
                Thread.sleep(forTimeInterval: 1); shot("swiped-play-next")
                row.press(forDuration: 0.8); Thread.sleep(forTimeInterval: 1); shot("song-menu")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); Thread.sleep(forTimeInterval: 1)
            } else { missed.append("song row") }
            tap(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open (Remastered")).firstMatch, "play a song"); shot("played-from-album")
            tap(button(containing: "Back"), "back to Library"); shot("library-again")
        }
        if tap(text("All Tracks"), "All Tracks") { shot("all-tracks"); tap(button(containing: "Back"), "back from All Tracks") }
        // hold a tile: rearrange mode
        let tile = text("Night Album")
        if tile.waitForExistence(timeout: 2) {
            tile.press(forDuration: 1.0); Thread.sleep(forTimeInterval: 1); shot("tile-menu-or-edit")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap(); Thread.sleep(forTimeInterval: 1)
            if button(containing: "Done").exists { button(containing: "Done").tap(); Thread.sleep(forTimeInterval: 1) }
        }

        // Queue
        tap(id("tab-queue"), "Queue tab"); shot("queue")
        drag(CGVector(dx: 0.5, dy: 0.7), CGVector(dx: 0.5, dy: 0.4), speed: .fast); shot("queue-scrolled")

        // Artists
        tap(id("tab-artists"), "Artists tab"); shot("artists")
        if tap(text("The Cure"), "artist tile", wait: 4) {
            shot("artist-page")
            drag(CGVector(dx: 0.5, dy: 0.75), CGVector(dx: 0.5, dy: 0.35), speed: .fast); shot("artist-scrolled")
            tap(button(containing: "Back"), "back to Artists")
        }
        tap(id("tab-artists"), "close drawer"); shot("drawer-closed")

        // tabs: drag along them
        if id("tab-queue").exists && id("tab-artists").exists {
            tap(id("tab-queue"), "Queue again")
            id("tab-queue").press(forDuration: 0.1, thenDragTo: id("tab-artists")); Thread.sleep(forTimeInterval: 1); shot("tab-drag")
            tap(id("tab-artists"), "close drawer again")
        }

        // the big player
        tap(id("cover"), "open big player", wait: 1.5); shot("big")
        tap(id("shuffle"), "shuffle"); tap(id("repeat"), "repeat"); shot("big-toggles")
        tap(id("repeat"), "repeat 2"); tap(id("repeat"), "repeat 3"); tap(id("shuffle"), "shuffle off")
        tap(id("next"), "big next"); shot("big-next")
        drag(CGVector(dx: 0.5, dy: 0.6), CGVector(dx: 0.5, dy: 0.2)); shot("big-lyrics-bubble")
        drag(CGVector(dx: 0.5, dy: 0.3), CGVector(dx: 0.5, dy: 0.8))
        tap(id("handle"), "close big player", wait: 1.5); shot("big-closed")
        // pull to open, pull to close
        drag(CGVector(dx: 0.3, dy: 0.12), CGVector(dx: 0.3, dy: 0.55)); shot("pulled-open")
        drag(CGVector(dx: 0.5, dy: 0.12), CGVector(dx: 0.5, dy: 0.02))
        if id("handle").exists { tap(id("handle"), "close after pull") }

        // the artist link under the title
        if tap(id("artistLink"), "artist link", wait: 3) { shot("artist-from-link"); tap(id("tab-artists"), "close artist") }

        // Settings
        tap(id("settings"), "Settings"); shot("settings")
        drag(CGVector(dx: 0.5, dy: 0.8), CGVector(dx: 0.5, dy: 0.25), speed: .fast); shot("settings-scrolled")
        drag(CGVector(dx: 0.5, dy: 0.8), CGVector(dx: 0.5, dy: 0.25), speed: .fast); shot("settings-bottom")
        tap(id("closeSettings"), "close Settings"); shot("settings-closed")

        // + Songs opens the Files picker
        if tap(id("addSongs"), "+ Songs", wait: 2) { shot("files-picker"); if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } }

        // a phone on its side: the Library grid (five a row), the big player (cover beside the controls), Cover Flow
        XCUIDevice.shared.orientation = .landscapeLeft; Thread.sleep(forTimeInterval: 2); shot("land-home")
        tap(id("tab-library"), "land Library"); shot("land-grid")
        tap(id("cover"), "land big player", wait: 1.5); shot("land-big")
        tap(id("handle"), "land close big", wait: 1.5)
        XCUIDevice.shared.orientation = .portrait; Thread.sleep(forTimeInterval: 1.5)
        tap(id("settings"), "Settings for Cover Flow")
        if scrollTo(id("flowSwitch"), "Cover Flow switch") {
            tap(id("closeSettings"), "close Settings 2")
            shot("flow")
            drag(CGVector(dx: 0.8, dy: 0.62), CGVector(dx: 0.2, dy: 0.62), speed: .fast); shot("flow-swiped")
            XCUIDevice.shared.orientation = .landscapeLeft; Thread.sleep(forTimeInterval: 2); shot("land-flow")
            XCUIDevice.shared.orientation = .portrait; Thread.sleep(forTimeInterval: 1.5)
        }

        NSLog("MacawMissedAll %@", missed.joined(separator: " | "))
        let a = XCTAttachment(string: "Missed: " + (missed.isEmpty ? "nothing" : missed.joined(separator: ", "))
                              + "\nTapped by position (not reachable for accessibility): " + (forced.isEmpty ? "nothing" : forced.joined(separator: ", ")))
        a.name = "missed"; a.lifetime = .keepAlways; add(a)
    }
}
