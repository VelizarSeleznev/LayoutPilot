import CoreGraphics
@testable import LayoutPilotCore
import XCTest

final class KeyboardEventTextMapTests: XCTestCase {
    func testSplitFollowedByRussianWordWithStaleRussianEventText() throws {
        let us = try XCTUnwrap(KeyboardEventTextMap.load(sourceID: "com.apple.keylayout.US"))
        // Actual keys for сделать, after ыздше -> split switched the active layout to US.
        let keys: [Int64] = [8, 37, 17, 40, 3, 45, 46]
        let token = zip(keys, "сделать").map {
            us.text(keyCode: $0.0, flags: [], fallback: String($0.1))!
        }.joined()
        XCTAssertEqual(token, "cltkfnm")
        let store = SmartInputLearningStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("learning.json"))
        let service = SmartInputService(learningStore: store)
        XCTAssertEqual(service.checkBilingualConversion(for: token,
            sourceLayoutID: us.sourceID)?.replacement, "сделать")
    }

    func testReverseSwitchAndModifiers() throws {
        let ru = try XCTUnwrap(KeyboardEventTextMap.load(sourceID: "com.apple.keylayout.RussianWin"))
        XCTAssertEqual(ru.text(keyCode: 8, flags: [], fallback: "c"), "с")
        XCTAssertEqual(ru.text(keyCode: 8, flags: .maskShift, fallback: "C"), "С")
        XCTAssertEqual(ru.text(keyCode: 8, flags: .maskAlphaShift, fallback: "C"), "С")
        XCTAssertEqual(ru.text(keyCode: 49, flags: [], fallback: " "), " ")
        for modifier: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate] {
            XCTAssertEqual(ru.text(keyCode: 8, flags: modifier, fallback: "c"), "c")
        }
        XCTAssertEqual(ru.text(keyCode: 8, flags: [], fallback: "pasted text"), "pasted text")
        XCTAssertNil(KeyboardEventTextMap.load(sourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"))
    }
}
