import XCTest

/// Real touches on the real app, in the Simulator. The app runs in test mode: dry run (nothing goes to the PS5 or
/// the TV), a made-up pairing kept in memory and three counters on screen that the test reads.
///
/// What this cannot prove is that a hardware keyboard is ignored: the Simulator's `typeKey` does not arrive at
/// the app as a key press, so it is typed here only to show that nothing runs. The proof for keys is the app's
/// own self-test (`-ps5-selftest-input`, see Guard/InputSelfTest.swift) and, on the phone, a Bluetooth keyboard.
final class TouchOnlyTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ps5-uitest"]
        app.launch()
        return app
    }

    private func count(_ app: XCUIApplication, _ id: String) -> Int {
        Int(app.staticTexts[id].label.split(separator: "=").last ?? "") ?? -1
    }

    func testTouchBecomesCommandsAndTypedKeysDoNot() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["probe.ps5"].waitForExistence(timeout: 15), "o app não abriu a tela do controle")
        XCTAssertTrue(app.staticTexts["✕"].isHittable, "tela do controle coberta (pareamento de teste?)")

        let ps5Before = count(app, "probe.ps5"), tvBefore = count(app, "probe.tv")

        // The same 26 keys as the Mac self-test, each pressed and released.
        let keys: [String] = [
            XCUIKeyboardKey.upArrow.rawValue, XCUIKeyboardKey.downArrow.rawValue,
            XCUIKeyboardKey.leftArrow.rawValue, XCUIKeyboardKey.rightArrow.rawValue,
            XCUIKeyboardKey.return.rawValue, XCUIKeyboardKey.enter.rawValue, XCUIKeyboardKey.space.rawValue,
            XCUIKeyboardKey.escape.rawValue, XCUIKeyboardKey.delete.rawValue, XCUIKeyboardKey.forwardDelete.rawValue,
            XCUIKeyboardKey.tab.rawValue,
            "s", "t", "h", "o", "c", "p", "[", "]", ",", ".", "=", "-", "m", "1", "0",
        ]
        XCTAssertEqual(keys.count, 26)
        for key in keys { app.typeKey(key, modifierFlags: []) }
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(count(app, "probe.ps5"), ps5Before, "um comando do PS5 passou durante as teclas")
        XCTAssertEqual(count(app, "probe.tv"), tvBefore, "um comando da TV passou durante as teclas")

        // Real touches must go through, one command per tap.
        app.staticTexts["✕"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(count(app, "probe.ps5"), ps5Before + 1, "o toque no ✕ não virou exatamente um comando")
        app.staticTexts["▲"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(count(app, "probe.ps5"), ps5Before + 2, "o toque no ▲ não virou exatamente um comando")
    }
}
