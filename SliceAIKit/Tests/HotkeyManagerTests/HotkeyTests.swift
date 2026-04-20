import XCTest
@testable import HotkeyManager

final class HotkeyTests: XCTestCase {

    func test_parseOptionSpace() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.keyCode, 49)    // space keycode
        XCTAssertEqual(hk.modifiers, .option)
    }

    func test_parseCmdShiftSpace() throws {
        let hk = try Hotkey.parse("cmd+shift+space")
        XCTAssertEqual(hk.keyCode, 49)
        XCTAssertTrue(hk.modifiers.contains(.command))
        XCTAssertTrue(hk.modifiers.contains(.shift))
    }

    func test_parseCaseInsensitive() throws {
        let hk = try Hotkey.parse("CMD+Space")
        XCTAssertTrue(hk.modifiers.contains(.command))
    }

    func test_parseInvalid_throws() {
        XCTAssertThrowsError(try Hotkey.parse("cmd+nothing"))
        XCTAssertThrowsError(try Hotkey.parse(""))
    }

    func test_descriptionRoundTrip() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.description, "option+space")
    }
}
